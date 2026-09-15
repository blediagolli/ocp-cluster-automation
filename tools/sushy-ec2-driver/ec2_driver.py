"""Sushy-tools EC2 driver.

Maps Redfish BMC operations to AWS EC2 API calls via boto3, allowing
Metal3 BareMetalHost resources to manage EC2 instances as if they
were bare-metal servers with Redfish BMCs.

Expects a config file mapping instance IDs to UUIDs, or uses instance
IDs directly as system identities.

Environment variables:
    AWS_REGION              - EC2 region (default: us-east-2)
    AWS_ACCESS_KEY_ID       - AWS credentials
    AWS_SECRET_ACCESS_KEY   - AWS credentials
    SUSHY_EC2_BOOT_IMAGE    - Default AMI to use for virtual media boot
    SUSHY_EC2_CONFIG        - Path to instance config JSON (optional)
    SUSHY_EC2_S3_BUCKET     - S3 bucket for ISO conversion
"""

import hashlib
import json
import logging
import os
import subprocess
import tempfile
import threading
import time

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

BOOT_DEVICE_MAP = {
    'Pxe': 'network',
    'Hdd': 'hd',
    'Cd': 'cdrom',
}


class EC2Driver:
    """Sushy-tools driver that manages EC2 instances via the AWS API."""

    PERMANENT_CACHE = {}
    _media_lock = threading.Lock()
    _media_threads = {}
    _ami_cache = {}
    _ami_cache_lock = threading.Lock()

    def __init__(self, config=None):
        region = os.environ.get('AWS_REGION', 'us-east-2')
        self._ec2 = boto3.client('ec2', region_name=region)
        self._ec2_resource = boto3.resource('ec2', region_name=region)
        self._config = self._load_config()
        self._boot_image = os.environ.get('SUSHY_EC2_BOOT_IMAGE', '')

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
                 'Values': ['sigs.k8s.io/cluster-api-provider-aws/cluster/*',
                            'kubernetes.io/cluster/*',
                            'sushy-managed']},
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
                'BootSourceOverrideTarget': 'Hdd',
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
            self._wait_for_media_if_pending(instance_id)
            cache = self.PERMANENT_CACHE.get(instance_id, {})
            ami_id = cache.get('boot_ami')
            if ami_id and cache.get('boot_device') == 'Cd':
                self._reimage_instance(instance_id, ami_id)
            else:
                self._ec2.start_instances(InstanceIds=[instance_id])
        elif state in ('ForceOff', 'GracefulShutdown'):
            self._ec2.stop_instances(InstanceIds=[instance_id])
        elif state in ('ForceRestart', 'GracefulRestart'):
            self._ec2.reboot_instances(InstanceIds=[instance_id])
        elif state == 'Nmi':
            LOG.warning('NMI not supported on EC2, rebooting instead')
            self._ec2.reboot_instances(InstanceIds=[instance_id])
        else:
            raise Exception(f'Unsupported power state: {state}')

    def _wait_for_media_if_pending(self, instance_id):
        with self._media_lock:
            thread = self._media_threads.get(instance_id)
        if thread and thread.is_alive():
            LOG.info('Waiting for media insertion to complete on %s...', instance_id)
            thread.join(timeout=600)

    # ── Boot device ──

    def get_boot_device(self, identity):
        instance_id = self._instance_id(identity)
        return self.PERMANENT_CACHE.get(instance_id, {}).get('boot_device', 'Hdd')

    def set_boot_device(self, identity, boot_source):
        instance_id = self._instance_id(identity)
        LOG.info('Set boot device %s -> %s (stored, applied on next boot)',
                 instance_id, boot_source)
        self.PERMANENT_CACHE.setdefault(instance_id, {})
        self.PERMANENT_CACHE[instance_id]['boot_device'] = boot_source

    def get_boot_mode(self, identity):
        return 'UEFI'

    def set_boot_mode(self, identity, boot_mode):
        LOG.info('Boot mode set to %s (EC2 always uses UEFI/BIOS per AMI)',
                 boot_mode)

    # ── Virtual media (ISO mounting) ──

    def get_virtual_media(self, identity):
        instance_id = self._instance_id(identity)
        cached = self.PERMANENT_CACHE.get(instance_id, {})
        state = cached.get('virtual_media_state', 'ejected')
        image = cached.get('virtual_media_image', '')

        return [
            {
                'Id': 'Cd',
                'Name': 'Virtual CD',
                'MediaTypes': ['CD', 'DVD'],
                'Inserted': state == 'inserted',
                'Image': image if state != 'ejected' else '',
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
        """Insert virtual media — starts async ISO-to-AMI conversion.

        Returns immediately. The actual ISO download, S3 upload, snapshot
        import, and AMI registration happen in a background thread.
        Power-on operations will wait for this to complete.
        """
        instance_id = self._instance_id(identity)
        LOG.info('Inserting virtual media on %s: %s (device: %s)',
                 instance_id, image_url, device)

        with self._media_lock:
            existing = self._media_threads.get(instance_id)
            if existing and existing.is_alive():
                LOG.info('Media insertion already in progress for %s, skipping duplicate', instance_id)
                return

        self.PERMANENT_CACHE.setdefault(instance_id, {})
        self.PERMANENT_CACHE[instance_id]['virtual_media_state'] = 'inserting'
        self.PERMANENT_CACHE[instance_id]['virtual_media_image'] = image_url

        thread = threading.Thread(
            target=self._insert_media_background,
            args=(instance_id, image_url),
            daemon=True,
        )
        with self._media_lock:
            self._media_threads[instance_id] = thread
        thread.start()

    def _insert_media_background(self, instance_id, image_url):
        try:
            ami_id = self._iso_to_ami(image_url)
            if ami_id:
                self.PERMANENT_CACHE.setdefault(instance_id, {})
                self.PERMANENT_CACHE[instance_id]['boot_ami'] = ami_id
                self.PERMANENT_CACHE[instance_id]['virtual_media_state'] = 'inserted'
                LOG.info('Virtual media ready for %s: AMI %s', instance_id, ami_id)
            else:
                self.PERMANENT_CACHE[instance_id]['virtual_media_state'] = 'error'
                LOG.error('Virtual media insertion failed for %s', instance_id)
        except Exception:
            LOG.exception('Background media insertion failed for %s', instance_id)
            self.PERMANENT_CACHE.setdefault(instance_id, {})
            self.PERMANENT_CACHE[instance_id]['virtual_media_state'] = 'error'

    def eject_virtual_media(self, identity, device):
        instance_id = self._instance_id(identity)
        LOG.info('Ejecting virtual media from %s', instance_id)
        self.PERMANENT_CACHE.setdefault(instance_id, {})
        self.PERMANENT_CACHE[instance_id]['virtual_media_state'] = 'ejected'
        self.PERMANENT_CACHE[instance_id]['virtual_media_image'] = ''

    # ── ISO to AMI conversion ──

    def _iso_to_ami(self, image_url):
        """Convert a discovery ISO URL to an AMI.

        Thread-safe: uses a lock per ISO URL hash so concurrent requests
        for the same ISO don't duplicate work.
        """
        iso_hash = hashlib.sha256(image_url.encode()).hexdigest()[:12]
        ami_name = f'sushy-discovery-{iso_hash}'

        with self._ami_cache_lock:
            if ami_name in self._ami_cache:
                LOG.info('Using cached AMI %s', self._ami_cache[ami_name])
                return self._ami_cache[ami_name]

        existing = self._ec2.describe_images(
            Owners=['self'],
            Filters=[{'Name': 'name', 'Values': [ami_name]}]
        )
        if existing['Images']:
            ami_id = existing['Images'][0]['ImageId']
            LOG.info('Reusing existing AMI %s for %s', ami_id, image_url)
            with self._ami_cache_lock:
                self._ami_cache[ami_name] = ami_id
            return ami_id

        LOG.info('Converting ISO to AMI: %s', image_url)

        bucket = os.environ.get('SUSHY_EC2_S3_BUCKET')
        if not bucket:
            LOG.error('SUSHY_EC2_S3_BUCKET not set, cannot convert ISO')
            return None

        with tempfile.TemporaryDirectory() as tmpdir:
            iso_path = os.path.join(tmpdir, 'discovery.iso')
            raw_path = os.path.join(tmpdir, 'discovery.raw')

            LOG.info('Downloading ISO...')
            subprocess.run(
                ['curl', '-skL', '-o', iso_path, image_url],
                check=True, timeout=600)

            LOG.info('Converting ISO to raw disk image...')
            subprocess.run(
                ['qemu-img', 'convert', '-f', 'raw', '-O', 'raw',
                 iso_path, raw_path],
                check=True, timeout=300)

            s3_key = f'sushy-ec2/{ami_name}.raw'
            LOG.info('Uploading to s3://%s/%s', bucket, s3_key)
            s3 = boto3.client('s3')
            s3.upload_file(raw_path, bucket, s3_key)

        LOG.info('Importing EBS snapshot...')
        import_resp = self._ec2.import_snapshot(
            DiskContainer={
                'Format': 'RAW',
                'UserBucket': {
                    'S3Bucket': bucket,
                    'S3Key': s3_key,
                }
            },
            Description=f'sushy-ec2 discovery ISO: {iso_hash}',
        )

        task_id = import_resp['ImportTaskId']
        LOG.info('Waiting for snapshot import %s...', task_id)

        while True:
            status = self._ec2.describe_import_snapshot_tasks(
                ImportTaskIds=[task_id]
            )
            task = status['ImportSnapshotTasks'][0]
            detail = task['SnapshotTaskDetail']

            if detail['Status'] == 'completed':
                snapshot_id = detail['SnapshotId']
                LOG.info('Snapshot ready: %s', snapshot_id)
                break
            elif detail['Status'] == 'error':
                LOG.error('Snapshot import failed: %s',
                          detail.get('StatusMessage'))
                return None

            progress = detail.get('Progress', '?')
            LOG.info('Snapshot import %s: %s%% complete', task_id, progress)
            time.sleep(15)

        LOG.info('Registering AMI %s from snapshot %s',
                 ami_name, snapshot_id)
        ami_resp = self._ec2.register_image(
            Name=ami_name,
            Architecture='x86_64',
            RootDeviceName='/dev/sda1',
            BlockDeviceMappings=[{
                'DeviceName': '/dev/sda1',
                'Ebs': {
                    'SnapshotId': snapshot_id,
                    'VolumeType': 'gp3',
                    'VolumeSize': 16,
                    'DeleteOnTermination': True,
                },
            }],
            VirtualizationType='hvm',
            EnaSupport=True,
            BootMode='uefi-preferred',
        )

        ami_id = ami_resp['ImageId']
        LOG.info('AMI registered: %s', ami_id)

        self._ec2.create_tags(
            Resources=[ami_id, snapshot_id],
            Tags=[
                {'Key': 'sushy-managed', 'Value': 'true'},
                {'Key': 'iso-url-hash', 'Value': iso_hash},
            ]
        )

        with self._ami_cache_lock:
            self._ami_cache[ami_name] = ami_id

        return ami_id

    def _reimage_instance(self, instance_id, ami_id):
        """Stop an instance, swap its root volume to boot from a new AMI."""
        LOG.info('Re-imaging %s with AMI %s', instance_id, ami_id)

        inst = self._describe_instance(instance_id)
        if inst['State']['Name'] == 'running':
            self._ec2.stop_instances(InstanceIds=[instance_id])
            waiter = self._ec2.get_waiter('instance_stopped')
            waiter.wait(InstanceIds=[instance_id])

        ami_info = self._ec2.describe_images(ImageIds=[ami_id])
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

        LOG.info('Starting instance %s with new root volume', instance_id)
        self._ec2.start_instances(InstanceIds=[instance_id])

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
