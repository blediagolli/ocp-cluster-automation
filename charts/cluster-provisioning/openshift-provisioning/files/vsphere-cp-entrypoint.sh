#!/bin/bash
set -euo pipefail

echo "=== vSphere Control Plane Automation (Ansible) ==="

echo "--- Installing dependencies ---"
pip install --quiet --disable-pip-version-check pyvmomi kubernetes jmespath

echo "--- Installing Ansible collections ---"
ansible-galaxy collection install -r /scripts/requirements.yml --force

echo "--- Running playbook ---"
ansible-playbook /scripts/playbook.yml -v

echo "=== Automation complete ==="
