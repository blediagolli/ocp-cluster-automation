"""Sushy EC2 Emulator — Redfish API server backed by AWS EC2.

Exposes a Redfish-compatible API that Metal3/Ironic can use as a BMC
endpoint. Each EC2 instance appears as a Redfish ComputerSystem.

Usage:
    python app.py                      # runs on port 8000
    FLASK_PORT=9000 python app.py      # custom port
"""

import json
import logging
import os

from flask import Flask, jsonify, request, abort

from ec2_driver import EC2Driver

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(name)s %(levelname)s %(message)s',
)
LOG = logging.getLogger('sushy-ec2')

app = Flask(__name__)
driver = EC2Driver()


# ── Redfish Service Root ──

@app.route('/redfish/v1/')
@app.route('/redfish/v1')
def service_root():
    return jsonify({
        '@odata.type': '#ServiceRoot.v1_0_0.ServiceRoot',
        'Id': 'RootService',
        'Name': 'Sushy EC2 Emulator',
        'RedfishVersion': '1.0.0',
        'UUID': 'sushy-ec2-emulator',
        'Systems': {'@odata.id': '/redfish/v1/Systems'},
        'Managers': {'@odata.id': '/redfish/v1/Managers'},
    })


# ── Systems collection ──

@app.route('/redfish/v1/Systems/')
@app.route('/redfish/v1/Systems')
def systems_collection():
    systems = driver.get_systems()
    members = [{'@odata.id': f'/redfish/v1/Systems/{s}'} for s in systems]
    return jsonify({
        '@odata.type': '#ComputerSystemCollection.ComputerSystemCollection',
        'Name': 'Computer System Collection',
        'Members@odata.count': len(members),
        'Members': members,
    })


@app.route('/redfish/v1/Systems/<identity>')
def get_system(identity):
    try:
        system = driver.get_system(identity)
    except Exception as e:
        LOG.error('Failed to get system %s: %s', identity, e)
        abort(404)

    return jsonify({
        '@odata.type': '#ComputerSystem.v1_1_0.ComputerSystem',
        'Id': system['Id'],
        'Name': system['Name'],
        'UUID': system['UUID'],
        'Manufacturer': system.get('Manufacturer', 'AWS'),
        'Model': system.get('Model', ''),
        'SerialNumber': system.get('SerialNumber', ''),
        'PowerState': system['PowerState'],
        'Status': system.get('Status', {'State': 'Enabled'}),
        'Boot': system.get('Boot', {}),
        'ProcessorSummary': system.get('ProcessorSummary', {}),
        'MemorySummary': system.get('MemorySummary', {}),
        'EthernetInterfaces': {
            '@odata.id': f'/redfish/v1/Systems/{identity}/EthernetInterfaces'
        },
        'VirtualMedia': {
            '@odata.id': f'/redfish/v1/Systems/{identity}/VirtualMedia'
        },
        'Actions': {
            '#ComputerSystem.Reset': {
                'target': f'/redfish/v1/Systems/{identity}/Actions/ComputerSystem.Reset',
                'ResetType@Redfish.AllowableValues': [
                    'On', 'ForceOff', 'GracefulShutdown',
                    'GracefulRestart', 'ForceRestart', 'ForceOn',
                ],
            }
        },
    })


# ── Power actions ──

@app.route('/redfish/v1/Systems/<identity>/Actions/ComputerSystem.Reset',
           methods=['POST'])
def system_reset(identity):
    body = request.get_json(force=True)
    reset_type = body.get('ResetType', 'On')
    LOG.info('Reset %s: %s', identity, reset_type)

    try:
        driver.set_power_state(identity, reset_type)
    except Exception as e:
        LOG.error('Power action failed on %s: %s', identity, e)
        abort(500)

    return '', 204


# ── Boot settings ──

@app.route('/redfish/v1/Systems/<identity>', methods=['PATCH'])
def patch_system(identity):
    body = request.get_json(force=True)
    boot = body.get('Boot', {})

    if 'BootSourceOverrideTarget' in boot:
        driver.set_boot_device(identity, boot['BootSourceOverrideTarget'])
    if 'BootSourceOverrideMode' in boot:
        driver.set_boot_mode(identity, boot['BootSourceOverrideMode'])

    return '', 204


# ── Virtual media ──

@app.route('/redfish/v1/Systems/<identity>/VirtualMedia/')
@app.route('/redfish/v1/Systems/<identity>/VirtualMedia')
def virtual_media_collection(identity):
    media = driver.get_virtual_media(identity)
    members = [
        {'@odata.id': f'/redfish/v1/Systems/{identity}/VirtualMedia/{m["Id"]}'}
        for m in media
    ]
    return jsonify({
        '@odata.type': '#VirtualMediaCollection.VirtualMediaCollection',
        'Name': 'Virtual Media Collection',
        'Members@odata.count': len(members),
        'Members': members,
    })


@app.route('/redfish/v1/Systems/<identity>/VirtualMedia/<device>')
def get_virtual_media(identity, device):
    media_list = driver.get_virtual_media(identity)
    media = next((m for m in media_list if m['Id'] == device), None)
    if not media:
        abort(404)

    return jsonify({
        '@odata.type': '#VirtualMedia.v1_2_0.VirtualMedia',
        'Id': media['Id'],
        'Name': media['Name'],
        'MediaTypes': media['MediaTypes'],
        'Inserted': media['Inserted'],
        'Image': media['Image'],
        'WriteProtected': media['WriteProtected'],
        'Actions': {
            '#VirtualMedia.InsertMedia': {
                'target': f'/redfish/v1/Systems/{identity}/VirtualMedia/{device}/Actions/VirtualMedia.InsertMedia',
            },
            '#VirtualMedia.EjectMedia': {
                'target': f'/redfish/v1/Systems/{identity}/VirtualMedia/{device}/Actions/VirtualMedia.EjectMedia',
            },
        },
    })


@app.route('/redfish/v1/Systems/<identity>/VirtualMedia/<device>/Actions/VirtualMedia.InsertMedia',
           methods=['POST'])
def insert_media(identity, device):
    body = request.get_json(force=True)
    image = body.get('Image', '')
    LOG.info('Insert media on %s/%s: %s', identity, device, image)

    try:
        driver.insert_virtual_media(identity, device, image)
    except Exception as e:
        LOG.error('Insert media failed: %s', e)
        abort(500)

    return '', 204


@app.route('/redfish/v1/Systems/<identity>/VirtualMedia/<device>/Actions/VirtualMedia.EjectMedia',
           methods=['POST'])
def eject_media(identity, device):
    LOG.info('Eject media on %s/%s', identity, device)
    driver.eject_virtual_media(identity, device)
    return '', 204


# ── Ethernet interfaces ──

@app.route('/redfish/v1/Systems/<identity>/EthernetInterfaces/')
@app.route('/redfish/v1/Systems/<identity>/EthernetInterfaces')
def ethernet_collection(identity):
    nics = driver.get_nics(identity)
    members = [
        {'@odata.id': f'/redfish/v1/Systems/{identity}/EthernetInterfaces/{n["Id"]}'}
        for n in nics
    ]
    return jsonify({
        '@odata.type': '#EthernetInterfaceCollection.EthernetInterfaceCollection',
        'Name': 'Ethernet Interface Collection',
        'Members@odata.count': len(members),
        'Members': members,
    })


@app.route('/redfish/v1/Systems/<identity>/EthernetInterfaces/<nic_id>')
def get_ethernet(identity, nic_id):
    nics = driver.get_nics(identity)
    nic = next((n for n in nics if n['Id'] == nic_id), None)
    if not nic:
        abort(404)

    return jsonify({
        '@odata.type': '#EthernetInterface.v1_1_0.EthernetInterface',
        'Id': nic['Id'],
        'MACAddress': nic['MAC'],
        'SpeedMbps': nic.get('SpeedMbps', 10000),
        'Status': {'State': 'Enabled'},
    })


# ── Managers (stub for Metal3 compatibility) ──

@app.route('/redfish/v1/Managers/')
@app.route('/redfish/v1/Managers')
def managers_collection():
    return jsonify({
        '@odata.type': '#ManagerCollection.ManagerCollection',
        'Name': 'Manager Collection',
        'Members@odata.count': 1,
        'Members': [{'@odata.id': '/redfish/v1/Managers/BMC'}],
    })


@app.route('/redfish/v1/Managers/BMC')
def get_manager():
    return jsonify({
        '@odata.type': '#Manager.v1_0_0.Manager',
        'Id': 'BMC',
        'Name': 'Sushy EC2 Emulator BMC',
        'ManagerType': 'BMC',
        'FirmwareVersion': '1.0.0',
        'Status': {'State': 'Enabled'},
        'VirtualMedia': {'@odata.id': '/redfish/v1/Managers/BMC/VirtualMedia'},
    })


# ── Health check ──

@app.route('/healthz')
def healthz():
    return jsonify({'status': 'ok'})


if __name__ == '__main__':
    port = int(os.environ.get('FLASK_PORT', 8000))
    LOG.info('Starting Sushy EC2 Emulator on port %d', port)
    app.run(host='0.0.0.0', port=port)
