"""Sushy-tools EC2 driver.

Maps Redfish BMC operations to AWS EC2 API calls via boto3, allowing
Metal3 BareMetalHost resources to manage EC2 instances as if they
were bare-metal servers with Redfish BMCs.

Environment variables:
    AWS_REGION              - EC2 region (default: us-east-2)
    AWS_ACCESS_KEY_ID       - AWS credentials
    AWS_SECRET_ACCESS_KEY   - AWS credentials
    SUSHY_EC2_BOOT_AMI      - RHCOS AMI ID to boot from on virtual media insert
    SUSHY_EC2_IGNITION_URL  - URL to fetch discovery ignition config (InfraEnv API)
    SUSHY_EC2_CONFIG        - Path to instance config JSON (optional)
"""

import json
import logging
import os
import ssl
import threading
import time
import urllib.request

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger(__name__)

POWER_STATE_MAP = {
    'pending': 'On',
    'running': 'On',
    'shutting-down': 'Off',
    'terminated': 'Off',
    'stopping': 'Off',
    'stopped': 'Off',
}


class EC2Driver:
    """Sushy-tools driver that manages EC2 instances via the AWS API."""

    PERMANENT_CACHE = {}
    _reimage_lock = threading.Lock()
    _reimage_threads = {}

    def __init__(self, config=None):
        region = os.environ.get('AWS_REGION', 'us-east-2')
        self._ec2 = boto3.client('ec2', region_name=region)
        self._config = self._load_config()
        self._boot_ami = os.environ.get('SUSHY_EC2_BOOT_AMI', '')
        self._ignition_url = os.environ.get('SUSHY_EC2_IGNITION_URL', '')

    @staticmethod
    def _load_config():
        config_path = os.environ.get('SUSHY_EC2_CONFIG', '')
        if config_path and os.path.exists(config_path):
            with open(config_path) as f:
                return json.load(f)
        return {}

    def _instance_id(self, identity):
        if identity.startswith('i-'):
            return identity
        for iid, cfg in self._config.get('instances', {}).items():
            if cfg.get('uuid') == identity:
                return iid
        return identity

    def _describe_instance(self, identity):
        instance_id = self._instance_id(identity)
        resp = self._ec2.describe_instances(InstanceIds=[instance_id])
        return resp['Reservations'][0]['Instances'][0]

    def _fetch_discovery_ignition(self):
        """Fetch discovery ignition and build a minimal version for EC2 user-data.

        Extracts only what agent.service needs (pull secret, agent-fix script)
        and drops the CA cert (public CA is trusted) to fit within EC2's 16KB
        user-data limit.
        """
        if not self._ignition_url:
            return None

        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        try:
            req = urllib.request.Request(self._ignition_url)
            resp = urllib.request.urlopen(req, context=ctx, timeout=30)
            ign = json.loads(resp.read())
        except Exception:
            LOG.exception('Failed to fetch discovery ignition')
            return None

        keep_files = {
            '/usr/local/bin/agent-fix-bz1964591',
            '/root/.docker/config.json',
        }
        files = [
            f for f in ign.get('storage', {}).get('files', [])
            if f['path'] in keep_files
        ]

        agent_unit = None
        for unit in ign.get('systemd', {}).get('units', []):
            if unit['name'] == 'agent.service':
                agent_unit = dict(unit)
                agent_unit['enabled'] = True
                contents = agent_unit.get('contents', '')
                contents = contents.replace(
                    '--insecure=false  --cacert /etc/assisted-service/service-ca-cert.crt',
                    '--insecure=false',
                )
                agent_unit['contents'] = contents
                break

        if not agent_unit:
            LOG.error('agent.service not found in discovery ignition')
            return None

        firstboot_unit = {
            'name': 'restore-firstboot.service',
            'enabled': True,
            'contents': (
                '[Unit]\n'
                'Description=Recreate ignition firstboot flag for installed OS\n'
                'DefaultDependencies=no\n'
                'Before=reboot.target halt.target poweroff.target kexec.target\n'
                '[Service]\n'
                'Type=oneshot\n'
                'ExecStart=/usr/bin/touch /boot/ignition.firstboot\n'
                '[Install]\n'
                'WantedBy=reboot.target halt.target poweroff.target kexec.target\n'
            ),
        }

        passwd = ign.get('passwd', {})

        minimal = {
            'ignition': {'version': '3.2.0'},
            'storage': {'files': files},
            'systemd': {'units': [agent_unit, firstboot_unit]},
        }
        if passwd:
            minimal['passwd'] = passwd

        raw = json.dumps(minimal, separators=(',', ':'))
        LOG.info('Minimal ignition: %d bytes', len(raw))
        return raw

    # ── System discovery ──

    def get_driver(self, identity):
        return 'Ec2'

    def get_systems(self):
        if self._config.get('instances'):
            return list(self._config['instances'].keys())

        resp = self._ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name',
                 'Values': ['pending', 'running', 'stopping', 'stopped']},
                {'Name': 'tag-key',
                 'Values': ['sushy-managed']},
            ]
        )
        instances = []
        for reservation in resp['Reservations']:
            for inst in reservation['Instances']:
                instances.append(inst['InstanceId'])
        return instances

    def get_system(self, identity):
        inst = self._describe_instance(identity)
        instance_id = inst['InstanceId']
        name = instance_id
        for tag in inst.get('Tags', []):
            if tag['Key'] == 'Name':
                name = tag['Value']
                break

        return {
            'Id': instance_id,
            'Name': name,
            'UUID': instance_id,
            'Manufacturer': 'Amazon Web Services',
            'Model': inst['InstanceType'],
            'SerialNumber': instance_id,
            'PowerState': POWER_STATE_MAP.get(
                inst['State']['Name'], 'Off'),
            'Status': {'State': 'Enabled'},
            'ProcessorSummary': {
                'Count': inst.get('CpuOptions', {}).get('CoreCount', 0),
            },
            'MemorySummary': {
                'TotalSystemMemoryGiB': 0,
            },
            'Boot': {
                'BootSourceOverrideEnabled': 'Continuous',
                'BootSourceOverrideTarget': self.PERMANENT_CACHE.get(
                    instance_id, {}).get('boot_device', 'Hdd'),
                'BootSourceOverrideMode': 'UEFI',
            },
        }

    # ── Power management ──

    def get_power_state(self, identity):
        inst = self._describe_instance(identity)
        return POWER_STATE_MAP.get(inst['State']['Name'], 'Off')

    def set_power_state(self, identity, state):
        instance_id = self._instance_id(identity)
        LOG.info('Setting power state of %s to %s', instance_id, state)

        if state in ('On', 'ForceOn'):
            cache = self.PERMANENT_CACHE.get(instance_id, {})
            if (cache.get('boot_device') == 'Cd'
                    and cache.get('virtual_media_inserted')
                    and self._boot_ami
                    and not cache.get('reimage_done')):
                self._reimage_and_start(instance_id)
            else:
                self._ec2.start_instances(InstanceIds=[instance_id])
        elif state in ('ForceOff', 'GracefulShutdown'):
            self._ec2.stop_instances(InstanceIds=[instance_id])
        elif state in ('ForceRestart', 'GracefulRestart'):
            self._ec2.reboot_instances(InstanceIds=[instance_id])
        elif state == 'Nmi':
            self._ec2.reboot_instances(InstanceIds=[instance_id])
        else:
            raise Exception(f'Unsupported power state: {state}')

    REIMAGE_COOLDOWN = 300

    def _reimage_and_start(self, instance_id):
        """Swap root volume to boot from RHCOS AMI, then start."""
        with self._reimage_lock:
            existing = self._reimage_threads.get(instance_id)
            if existing and existing.is_alive():
                LOG.info('Reimage already in progress for %s', instance_id)
                return

            last = self.PERMANENT_CACHE.get(instance_id, {}).get('last_reimaged', 0)
            if time.time() - last < self.REIMAGE_COOLDOWN:
                LOG.info('Reimage cooldown active for %s, just starting', instance_id)
                try:
                    self._ec2.start_instances(InstanceIds=[instance_id])
                except ClientError:
                    pass
                return

        thread = threading.Thread(
            target=self._do_reimage,
            args=(instance_id,),
            daemon=True,
        )
        with self._reimage_lock:
            self._reimage_threads[instance_id] = thread
        thread.start()

    def _do_reimage(self, instance_id):
        try:
            LOG.info('Re-imaging %s with RHCOS AMI %s', instance_id, self._boot_ami)

            inst = self._describe_instance(instance_id)
            if inst['State']['Name'] in ('running', 'pending'):
                self._ec2.stop_instances(InstanceIds=[instance_id])
                waiter = self._ec2.get_waiter('instance_stopped')
                waiter.wait(InstanceIds=[instance_id])
                inst = self._describe_instance(instance_id)

            if inst['State']['Name'] != 'stopped':
                LOG.info('Waiting for instance to stop...')
                waiter = self._ec2.get_waiter('instance_stopped')
                waiter.wait(InstanceIds=[instance_id])

            ignition = self._fetch_discovery_ignition()
            if ignition:
                LOG.info('Setting discovery ignition as user-data on %s', instance_id)
                self._ec2.modify_instance_attribute(
                    InstanceId=instance_id,
                    UserData={'Value': ignition},
                )
            else:
                LOG.warning('No ignition URL configured, booting without user-data')

            ami_info = self._ec2.describe_images(ImageIds=[self._boot_ami])
            snapshot_id = ami_info['Images'][0]['BlockDeviceMappings'][0][
                'Ebs']['SnapshotId']

            root_device = inst['RootDeviceName']
            current_volumes = [
                m for m in inst.get('BlockDeviceMappings', [])
                if m['DeviceName'] == root_device
            ]
            if current_volumes:
                old_vol_id = current_volumes[0]['Ebs']['VolumeId']
                LOG.info('Detaching old root volume %s', old_vol_id)
                self._ec2.detach_volume(
                    VolumeId=old_vol_id, InstanceId=instance_id, Force=True)
                waiter = self._ec2.get_waiter('volume_available')
                waiter.wait(VolumeIds=[old_vol_id])
                self._ec2.delete_volume(VolumeId=old_vol_id)

            az = inst['Placement']['AvailabilityZone']
            new_vol = self._ec2.create_volume(
                SnapshotId=snapshot_id,
                AvailabilityZone=az,
                VolumeType='gp3',
                Size=120,
                TagSpecifications=[{
                    'ResourceType': 'volume',
                    'Tags': [
                        {'Key': 'sushy-managed', 'Value': 'true'},
                        {'Key': 'Name',
                         'Value': f'{instance_id}-discovery-root'},
                    ],
                }],
            )
            new_vol_id = new_vol['VolumeId']
            waiter = self._ec2.get_waiter('volume_available')
            waiter.wait(VolumeIds=[new_vol_id])

            LOG.info('Attaching new root volume %s', new_vol_id)
            self._ec2.attach_volume(
                VolumeId=new_vol_id,
                InstanceId=instance_id,
                Device=root_device,
            )

            LOG.info('Starting instance %s with RHCOS root volume', instance_id)
            self._ec2.start_instances(InstanceIds=[instance_id])
            self.PERMANENT_CACHE.setdefault(instance_id, {})
            self.PERMANENT_CACHE[instance_id]['last_reimaged'] = time.time()
            self.PERMANENT_CACHE[instance_id]['boot_device'] = 'Hdd'
            self.PERMANENT_CACHE[instance_id]['virtual_media_inserted'] = False
            self.PERMANENT_CACHE[instance_id]['reimage_done'] = True
            LOG.info('Reimage complete for %s', instance_id)

        except Exception:
            LOG.exception('Reimage failed for %s', instance_id)

    # ── Boot device ──

    def get_boot_device(self, identity):
        instance_id = self._instance_id(identity)
        return self.PERMANENT_CACHE.get(instance_id, {}).get('boot_device', 'Hdd')

    def set_boot_device(self, identity, boot_source):
        instance_id = self._instance_id(identity)
        LOG.info('Set boot device %s -> %s', instance_id, boot_source)
        self.PERMANENT_CACHE.setdefault(instance_id, {})
        self.PERMANENT_CACHE[instance_id]['boot_device'] = boot_source

    def get_boot_mode(self, identity):
        return 'UEFI'

    def set_boot_mode(self, identity, boot_mode):
        LOG.info('Boot mode set to %s (EC2 always uses UEFI/BIOS per AMI)',
                 boot_mode)

    # ── Virtual media ──

    def get_virtual_media(self, identity):
        instance_id = self._instance_id(identity)
        cached = self.PERMANENT_CACHE.get(instance_id, {})
        inserted = cached.get('virtual_media_inserted', False)
        image = cached.get('virtual_media_image', '')

        return [
            {
                'Id': 'Cd',
                'Name': 'Virtual CD',
                'MediaTypes': ['CD', 'DVD'],
                'Inserted': inserted,
                'Image': image if inserted else '',
                'WriteProtected': True,
            },
            {
                'Id': 'Floppy',
                'Name': 'Virtual Floppy',
                'MediaTypes': ['Floppy'],
                'Inserted': False,
                'Image': '',
                'WriteProtected': True,
            },
        ]

    def insert_virtual_media(self, identity, device, image_url):
        """Insert virtual media — records the image URL immediately.

        No ISO-to-AMI conversion. The pre-built SUSHY_EC2_BOOT_AMI is
        used on next power-on with boot device = Cd.
        """
        instance_id = self._instance_id(identity)
        LOG.info('Insert virtual media on %s: %s (device: %s)',
                 instance_id, image_url, device)

        self.PERMANENT_CACHE.setdefault(instance_id, {})
        self.PERMANENT_CACHE[instance_id]['virtual_media_inserted'] = True
        self.PERMANENT_CACHE[instance_id]['virtual_media_image'] = image_url

    def eject_virtual_media(self, identity, device):
        instance_id = self._instance_id(identity)
        LOG.info('Eject virtual media from %s', instance_id)
        self.PERMANENT_CACHE.setdefault(instance_id, {})
        self.PERMANENT_CACHE[instance_id]['virtual_media_inserted'] = False
        self.PERMANENT_CACHE[instance_id]['virtual_media_image'] = ''

    # ── BIOS / Secure Boot (stubs) ──

    def get_secure_boot(self, identity):
        return False

    def set_secure_boot(self, identity, secure):
        LOG.info('Secure boot %s (no-op on EC2)', secure)

    def get_nics(self, identity):
        inst = self._describe_instance(identity)
        nics = []
        for iface in inst.get('NetworkInterfaces', []):
            nics.append({
                'Id': iface['NetworkInterfaceId'],
                'MAC': iface['MacAddress'],
                'SpeedMbps': 10000,
            })
        return nics

    def get_processors(self, identity):
        inst = self._describe_instance(identity)
        cpu = inst.get('CpuOptions', {})
        return [{
            'Id': 'CPU0',
            'TotalCores': cpu.get('CoreCount', 0),
            'TotalThreads': cpu.get('ThreadsPerCore', 0)
                            * cpu.get('CoreCount', 0),
            'MaxSpeedMHz': 0,
            'Model': inst.get('InstanceType', 'unknown'),
        }]

    def get_total_memory(self, identity):
        return 0

    def get_bios(self, identity):
        return []

    def set_bios(self, identity, attributes):
        LOG.info('BIOS settings update (no-op on EC2)')
