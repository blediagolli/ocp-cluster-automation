#!/bin/bash
set -uo pipefail

# Helm Template Tests for openshift-provisioning chart
# Validates template rendering across all 4 platform types and conditional features.
#
# Usage: ./template-test.sh
# Requirements: helm 3.x

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); }

render() {
  helm template test-cluster "$CHART_DIR" --values "$1" 2>&1
}

count_kind() {
  local n
  n=$(echo "$1" | grep -c "^kind: $2") || true
  echo "$n"
}

has_kind() {
  echo "$1" | grep -q "^kind: $2"
}

has_string() {
  echo "$1" | grep -qF "$2"
}

# Verify helm is available
if ! command -v helm &>/dev/null; then
  echo "ERROR: helm not found in PATH"
  exit 1
fi

# Create temp dir for test values
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ============================================================================
# Test values files
# ============================================================================

cat > "$TMPDIR/provision-disabled.yaml" <<'EOF'
provision:
  include: false
cluster:
  name: test-disabled
  platform: vsphere
EOF

cat > "$TMPDIR/vsphere.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-vsphere
  baseDomain: lab.example.com
  platform: vsphere
  environment: dev
  clusterSet: default
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    fake-key
    -----END OPENSSH PRIVATE KEY-----
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: dev
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 3
vsphere:
  vcenter: vcenter.lab.example.com
  username: admin
  password: secret
  datacenter: DC1
  datastore: DS1
  cluster: Cluster1
  folder: /DC1/vm/ocp
  network: VM Network
  cacertificate: |
    -----BEGIN CERTIFICATE-----
    fake-cert
    -----END CERTIFICATE-----
  apiVIP: 10.0.0.10
  ingressVIP: 10.0.0.11
  masters:
    cpus: 8
    coresPerSocket: 4
    memoryMB: 32768
    diskGB: 120
  workers:
    cpus: 4
    coresPerSocket: 2
    memoryMB: 16384
    diskGB: 120
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

cat > "$TMPDIR/aws.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-aws
  baseDomain: cloud.example.com
  platform: aws
  environment: prod
  clusterSet: production
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    fake-key
    -----END OPENSSH PRIVATE KEY-----
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 3
aws:
  accessKeyID: AKIAIOSFODNN7EXAMPLE
  secretAccessKey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  region: us-east-1
  masters:
    instanceType: m5.xlarge
    zones:
      - us-east-1a
      - us-east-1b
      - us-east-1c
    rootVolume:
      size: 120
      type: gp3
  workers:
    instanceType: m5.xlarge
    zones:
      - us-east-1a
      - us-east-1b
      - us-east-1c
    rootVolume:
      size: 120
      type: gp3
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

# The serviceAccountJSON here is deliberately awkward: embedded double quotes
# and a private_key carrying literal \n sequences. secret-gcp-creds.yaml runs
# the whole file through `quote` rather than a block scalar, and this fixture
# is the only thing in the suite that would catch that going wrong.
cat > "$TMPDIR/gcp.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-gcp
  baseDomain: cloud.example.com
  platform: gcp
  environment: prod
  clusterSet: production
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    fake-key
    -----END OPENSSH PRIVATE KEY-----
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 3
gcp:
  serviceAccountJSON: |
    {
      "type": "service_account",
      "project_id": "test-project",
      "private_key": "-----BEGIN PRIVATE KEY-----\nFAKEKEY\n-----END PRIVATE KEY-----\n",
      "client_email": "installer@test-project.iam.gserviceaccount.com"
    }
  projectID: test-project
  region: us-central1
  masters:
    machineType: n2-standard-4
    zones:
      - us-central1-a
      - us-central1-b
      - us-central1-c
    osDisk:
      diskType: pd-ssd
      diskSizeGB: 128
  workers:
    machineType: n2-standard-4
    zones:
      - us-central1-a
      - us-central1-b
      - us-central1-c
    osDisk:
      diskType: pd-ssd
      diskSizeGB: 128
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
EOF

# Single node. gcp.workers.machineType is deliberately a size that appears
# nowhere else, so Test 18 can assert worker sizing never reaches
# install-config for a pool that is never created.
cat > "$TMPDIR/gcp-sno.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-gcp-sno
  baseDomain: cloud.example.com
  platform: gcp
  environment: dev
  clusterSet: default
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    fake-key
    -----END OPENSSH PRIVATE KEY-----
  pullSecret: '{"auths":{}}'
  fips: false
masters:
  count: 1
workers:
  count: 0
gcp:
  projectID: test-project
  region: us-central1
  masters:
    machineType: n2-standard-8
    zones:
      - us-central1-a
    osDisk:
      diskType: pd-ssd
      diskSizeGB: 200
  workers:
    machineType: n2-standard-16
    zones: []
    osDisk:
      diskType: pd-ssd
      diskSizeGB: 128
EOF

# Azure. Zones are written here as bare YAML integers on purpose -- that is
# the spelling a reader reaches for, it parses as []int against a []string
# field, and the chart is supposed to quote it back into strings. Test 20
# asserts that; written as "1" the fixture would pass no matter what the
# template did.
cat > "$TMPDIR/azure.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-azure
  baseDomain: cloud.example.com
  platform: azure
  environment: prod
  clusterSet: production
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    fake-key
    -----END OPENSSH PRIVATE KEY-----
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 3
azure:
  servicePrincipalJSON: |
    {
      "subscriptionId": "00000000-0000-0000-0000-000000000001",
      "tenantId": "00000000-0000-0000-0000-000000000002",
      "clientId": "00000000-0000-0000-0000-000000000003",
      "clientSecret": "fake\"secret\\with-escapes"
    }
  baseDomainResourceGroupName: test-dns-rg
  region: eastus
  cloudName: ""
  credentialsMode: ""
  outboundType: ""
  networkResourceGroupName: ""
  virtualNetwork: ""
  controlPlaneSubnet: ""
  computeSubnet: ""
  masters:
    vmSize: Standard_D4s_v3
    zones:
      - 1
      - 2
      - 3
    osDisk:
      diskType: Premium_LRS
      diskSizeGB: 128
  workers:
    vmSize: Standard_D4s_v3
    zones:
      - 1
      - 2
      - 3
    osDisk:
      diskType: Premium_LRS
      diskSizeGB: 128
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
EOF

# Azure into a pre-existing vnet, with workers. The names here are unique
# strings so Test 22 can count where each one lands: the vnet trio and
# outboundType have to reach the MachinePool as well as install-config,
# because Hive does not read install-config for them and its own defaults
# (${infraID}-vnet, ${infraID}-worker-subnet) name resources a BYO-vnet
# install never creates.
sed -e 's|^  networkResourceGroupName: ""|  networkResourceGroupName: byo-net-rg|' \
    -e 's|^  virtualNetwork: ""|  virtualNetwork: byo-vnet|' \
    -e 's|^  controlPlaneSubnet: ""|  controlPlaneSubnet: byo-cp-subnet|' \
    -e 's|^  computeSubnet: ""|  computeSubnet: byo-compute-subnet|' \
    -e 's|^  outboundType: ""|  outboundType: UserDefinedRouting|' \
    -e 's|^  name: test-azure|  name: test-azure-vnet|' \
    "$TMPDIR/azure.yaml" > "$TMPDIR/azure-vnet.yaml"

# Single node on Azure. azure.workers.vmSize is a size that appears nowhere
# else, so Test 21 can assert worker sizing never reaches install-config.
cat > "$TMPDIR/azure-sno.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-azure-sno
  baseDomain: cloud.example.com
  platform: azure
  environment: dev
  clusterSet: default
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    fake-key
    -----END OPENSSH PRIVATE KEY-----
  pullSecret: '{"auths":{}}'
  fips: false
masters:
  count: 1
workers:
  count: 0
azure:
  baseDomainResourceGroupName: test-dns-rg
  region: eastus
  cloudName: ""
  credentialsMode: ""
  outboundType: ""
  networkResourceGroupName: ""
  virtualNetwork: ""
  controlPlaneSubnet: ""
  computeSubnet: ""
  masters:
    vmSize: Standard_D8s_v3
    zones:
      - "1"
    osDisk:
      diskType: Premium_LRS
      diskSizeGB: 200
  workers:
    vmSize: Standard_D64s_v3
    zones: []
    osDisk:
      diskType: Premium_LRS
      diskSizeGB: 128
EOF

cat > "$TMPDIR/unknown-platform.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-unknown
  baseDomain: cloud.example.com
  # Deliberately not the name of a real cloud. This fixture used to say
  # `azure`, which stopped testing anything the moment Azure was added as a
  # supported platform -- the render started succeeding and the assertion
  # below would have been the only thing to notice. A platform that will
  # never be implemented keeps the test honest.
  platform: nosuchcloud
  environment: dev
  clusterSet: default
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
masters:
  count: 3
workers:
  count: 3
EOF

cat > "$TMPDIR/baremetal.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-bm
  baseDomain: dc.example.com
  platform: baremetal
  environment: prod
  clusterSet: datacenter
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 0
baremetal:
  apiVIPs:
    - 10.206.220.10
  ingressVIPs:
    - 10.206.220.11
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0
  bmc:
    username: admin
    password: password
  hosts:
    - name: host001
      role: master
      bootMACAddress: "b4:96:91:e9:48:e4"
      bmcAddress: "idrac-virtualmedia+https://10.0.0.1/redfish/v1/Systems/System.Embedded.1"
      bmcInsecure: true
    - name: host002
      role: master
      bootMACAddress: "b4:96:91:e9:48:e5"
      bmcAddress: "idrac-virtualmedia+https://10.0.0.2/redfish/v1/Systems/System.Embedded.1"
    - name: host003
      role: master
      bootMACAddress: "b4:96:91:e9:48:e6"
      bmcAddress: "idrac-virtualmedia+https://10.0.0.3/redfish/v1/Systems/System.Embedded.1"
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

cat > "$TMPDIR/none.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-none
  baseDomain: edge.example.com
  platform: none
  environment: prod
  clusterSet: edge
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 0
none:
  apiVIPs: []
  ingressVIPs: []
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0
  bmc:
    username: admin
    password: password
  hosts:
    - name: edge001
      role: master
      bootMACAddress: "02:ff:dc:94:79:5f"
      bmcAddress: "redfish-virtualmedia+https://sushy:8000/redfish/v1/Systems/i-0abc"
    - name: edge002
      role: master
      bootMACAddress: "02:ff:dc:94:79:60"
      bmcAddress: "redfish-virtualmedia+https://sushy:8000/redfish/v1/Systems/i-0def"
    - name: edge003
      role: master
      bootMACAddress: "02:ff:dc:94:79:61"
      bmcAddress: "redfish-virtualmedia+https://sushy:8000/redfish/v1/Systems/i-0ghi"
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

cat > "$TMPDIR/baremetal-opts.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-bm-opts
  baseDomain: dc.example.com
  platform: baremetal
  environment: prod
  clusterSet: datacenter
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 0
baremetal:
  apiVIPs:
    - 10.206.220.10
  ingressVIPs:
    - 10.206.220.11
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0
  bmc:
    username: admin
    password: password
  hosts:
    - name: host001
      role: master
      bootMACAddress: "b4:96:91:e9:48:e4"
      bmcAddress: "idrac-virtualmedia+https://10.0.0.1/redfish/v1/Systems/System.Embedded.1"
      nmstate:
        config:
          interfaces:
            - name: ens1f0
              type: ethernet
              state: up
              ipv4:
                enabled: true
                address:
                  - ip: 10.206.220.2
                    prefix-length: 24
                dhcp: false
        interfaces:
          - name: ens1f0
            macAddress: "b4:96:91:e9:48:e4"
proxy:
  enabled: true
  httpProxy: "http://proxy.internal:3128"
  httpsProxy: "http://proxy.internal:3128"
  noProxy: ".internal,.cluster.local"
ntp:
  enabled: true
  sources:
    - ntp1.internal
    - ntp2.internal
ignitionConfigOverride:
  enabled: true
  config: '{"ignition":{"version":"3.1.0"}}'
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork:
    - cidr: 10.206.220.0/24
EOF

cat > "$TMPDIR/baremetal-govc.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-bm-govc
  baseDomain: dc.example.com
  platform: baremetal
  environment: prod
  clusterSet: datacenter
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 0
baremetal:
  apiVIPs:
    - 10.206.220.10
  ingressVIPs:
    - 10.206.220.11
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0
  bmc:
    username: admin
    password: password
  hosts: []
vsphereControlPlane:
  enabled: true
  automation: govc
  simulator:
    enabled: false
    image: "ghcr.io/vmware/govmomi/vcsim:latest"
  govcVersion: "v0.46.2"
  images:
    govc: "quay.io/openshift/origin-cli:latest"
    ansible: "quay.io/ansible/ansible-runner:latest"
  vcenter: vcsa.lab.example.com
  username: admin@vsphere.local
  password: secret
  insecure: true
  datacenter: DC1
  datastore: DS1
  cluster: Cluster1
  network: VM-Net
  folder: /DC1/vm
  resourcePool: /DC1/host/Cluster1/Resources
  masters:
    count: 3
    cpus: 4
    memoryMB: 16384
    diskGB: 120
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

cat > "$TMPDIR/baremetal-ansible.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-bm-ansible
  baseDomain: dc.example.com
  platform: baremetal
  environment: prod
  clusterSet: datacenter
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 0
baremetal:
  apiVIPs:
    - 10.206.220.10
  ingressVIPs:
    - 10.206.220.11
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0
  bmc:
    username: admin
    password: password
  hosts: []
vsphereControlPlane:
  enabled: true
  automation: ansible
  simulator:
    enabled: false
    image: "ghcr.io/vmware/govmomi/vcsim:latest"
  images:
    govc: "quay.io/openshift/origin-cli:latest"
    ansible: "quay.io/ansible/ansible-runner:latest"
  vcenter: vcsa.lab.example.com
  username: admin@vsphere.local
  password: secret
  insecure: true
  datacenter: DC1
  datastore: DS1
  cluster: Cluster1
  network: VM-Net
  folder: /DC1/vm
  resourcePool: /DC1/host/Cluster1/Resources
  masters:
    count: 3
    cpus: 4
    memoryMB: 16384
    diskGB: 120
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

cat > "$TMPDIR/baremetal-govc-sim.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-sim
  baseDomain: dc.example.com
  platform: baremetal
  environment: dev
  clusterSet: datacenter
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: dev
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 0
baremetal:
  apiVIPs:
    - 10.206.220.10
  ingressVIPs:
    - 10.206.220.11
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0
  bmc:
    username: admin
    password: password
  hosts: []
vsphereControlPlane:
  enabled: true
  automation: govc
  simulator:
    enabled: true
    image: "ghcr.io/vmware/govmomi/vcsim:latest"
  govcVersion: "v0.46.2"
  images:
    govc: "quay.io/openshift/origin-cli:latest"
    ansible: "quay.io/ansible/ansible-runner:latest"
  vcenter: vcsa.real.example.com
  username: admin@vsphere.local
  password: secret
  insecure: true
  datacenter: DC1
  datastore: DS1
  cluster: Cluster1
  network: VM-Net
  folder: /DC1/vm
  resourcePool: /DC1/host/Cluster1/Resources
  masters:
    count: 3
    cpus: 4
    memoryMB: 16384
    diskGB: 120
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

cat > "$TMPDIR/mixed-dual-infraenv.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-mixed
  baseDomain: dc.example.com
  platform: baremetal
  environment: prod
  clusterSet: datacenter
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  pullSecret: '{"auths":{}}'
  fips: false
fleet:
  operatorClusterType: prod
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 2
baremetal:
  apiVIPs:
    - 10.206.220.10
  ingressVIPs:
    - 10.206.220.11
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 2
  bmc:
    username: admin
    password: password
  hosts:
    - name: worker001
      role: worker
      bootMACAddress: "b4:96:91:e9:49:01"
      bmcAddress: "idrac-virtualmedia+https://10.0.1.1/redfish/v1/Systems/System.Embedded.1"
      nmstate:
        config:
          interfaces:
            - name: ens1f0
              type: ethernet
              state: up
              ipv4:
                enabled: true
                address:
                  - ip: 10.206.220.50
                    prefix-length: 24
                dhcp: false
        interfaces:
          - name: ens1f0
            macAddress: "b4:96:91:e9:49:01"
    - name: worker002
      role: worker
      bootMACAddress: "b4:96:91:e9:49:02"
      bmcAddress: "idrac-virtualmedia+https://10.0.1.2/redfish/v1/Systems/System.Embedded.1"
vsphereControlPlane:
  enabled: true
  automation: govc
  simulator:
    enabled: false
    image: "ghcr.io/vmware/govmomi/vcsim:latest"
  govcVersion: "v0.46.2"
  images:
    govc: "quay.io/openshift/origin-cli:latest"
    ansible: "quay.io/ansible/ansible-runner:latest"
  vcenter: vcsa.lab.example.com
  username: admin@vsphere.local
  password: secret
  insecure: true
  datacenter: DC1
  datastore: DS1
  cluster: Cluster1
  network: VM-Net
  folder: /DC1/vm
  resourcePool: /DC1/host/Cluster1/Resources
  masters:
    count: 3
    cpus: 4
    memoryMB: 16384
    diskGB: 120
proxy:
  enabled: false
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: false
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

cat > "$TMPDIR/vsphere-opts.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-vs-opts
  baseDomain: lab.example.com
  platform: vsphere
  environment: dev
  clusterSet: default
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    fake-key
    -----END OPENSSH PRIVATE KEY-----
  pullSecret: '{"auths":{}}'
  fips: true
  additionalTrustBundle: |
    -----BEGIN CERTIFICATE-----
    fake-cert
    -----END CERTIFICATE-----
fleet:
  operatorClusterType: dev
  operatorProfile: ocp-4.22
masters:
  count: 3
workers:
  count: 3
vsphere:
  vcenter: vcenter.lab.example.com
  username: admin
  password: secret
  datacenter: DC1
  datastore: DS1
  cluster: Cluster1
  folder: /DC1/vm/ocp
  network: VM Network
  cacertificate: |
    -----BEGIN CERTIFICATE-----
    fake-cert
    -----END CERTIFICATE-----
  apiVIP: 10.0.0.10
  ingressVIP: 10.0.0.11
  masters:
    cpus: 8
    coresPerSocket: 4
    memoryMB: 32768
    diskGB: 120
  workers:
    cpus: 4
    coresPerSocket: 2
    memoryMB: 16384
    diskGB: 120
proxy:
  enabled: true
  httpProxy: "http://proxy.internal:3128"
  httpsProxy: "http://proxy.internal:3128"
  noProxy: ".internal,.cluster.local"
ntp:
  enabled: false
ignitionConfigOverride:
  enabled: false
customManifests:
  enabled: true
  data:
    99-chrony-masters.yaml: |
      apiVersion: machineconfiguration.openshift.io/v1
      kind: MachineConfig
      metadata:
        name: 99-chrony-masters
imageContentSources:
  enabled: false
networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork: []
EOF

# ============================================================================
echo "=== Helm Template Tests: openshift-provisioning ==="
echo ""

# ============================================================================
echo "--- Test 1: provision.include=false renders nothing ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/provision-disabled.yaml")
if [ -z "$(echo "$OUTPUT" | grep "^kind:")" ]; then
  pass "No resources rendered when provision.include=false"
else
  fail "Resources rendered when provision.include=false: $(echo "$OUTPUT" | grep "^kind:" | sort -u | tr '\n' ', ')"
fi

# ============================================================================
echo ""
echo "--- Test 2: vSphere platform (IPI) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/vsphere.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for vsphere: $OUTPUT"
else
  pass "vsphere template renders successfully"

  # Common resources (all platforms)
  for KIND in Namespace ClusterDeployment KlusterletAddonConfig ManagedCluster ManagedClusterInfo; do
    if has_kind "$OUTPUT" "$KIND"; then
      pass "vsphere: $KIND present"
    else
      fail "vsphere: $KIND missing"
    fi
  done

  # IPI-only resources
  if has_kind "$OUTPUT" "MachinePool"; then
    pass "vsphere: MachinePool present (IPI)"
  else
    fail "vsphere: MachinePool missing (IPI)"
  fi

  # Agent-only resources must NOT exist
  for KIND in AgentClusterInstall InfraEnv BareMetalHost; do
    if has_kind "$OUTPUT" "$KIND"; then
      fail "vsphere: $KIND present (should be agent-only)"
    else
      pass "vsphere: $KIND absent (correct, agent-only)"
    fi
  done

  # Platform-specific secrets
  if has_string "$OUTPUT" "test-vsphere-vsphere-certs"; then
    pass "vsphere: vsphere-certs secret present"
  else
    fail "vsphere: vsphere-certs secret missing"
  fi
  if has_string "$OUTPUT" "test-vsphere-vsphere-creds"; then
    pass "vsphere: vsphere-creds secret present"
  else
    fail "vsphere: vsphere-creds secret missing"
  fi
  if has_string "$OUTPUT" "test-vsphere-install-config"; then
    pass "vsphere: install-config secret present"
  else
    fail "vsphere: install-config secret missing"
  fi
  if has_string "$OUTPUT" "test-vsphere-ssh-private-key"; then
    pass "vsphere: ssh-private-key secret present"
  else
    fail "vsphere: ssh-private-key secret missing"
  fi

  # AWS secret must NOT exist
  if has_string "$OUTPUT" "aws-creds"; then
    fail "vsphere: aws-creds secret present (should be aws-only)"
  else
    pass "vsphere: aws-creds secret absent (correct)"
  fi

  # Labels
  if has_string "$OUTPUT" "cloud: vSphere"; then
    pass "vsphere: cloud label = vSphere"
  else
    fail "vsphere: cloud label incorrect"
  fi
  if has_string "$OUTPUT" "hive.openshift.io/cluster-platform: vsphere"; then
    pass "vsphere: platform label = vsphere"
  else
    fail "vsphere: platform label incorrect"
  fi

  # ClusterDeployment should have installAttemptsLimit (IPI), not installed: false
  if has_string "$OUTPUT" "installAttemptsLimit: 1"; then
    pass "vsphere: ClusterDeployment has installAttemptsLimit"
  else
    fail "vsphere: ClusterDeployment missing installAttemptsLimit"
  fi
  if echo "$OUTPUT" | grep -A2 "kind: ClusterDeployment" | grep -q "installed: false" 2>/dev/null; then
    fail "vsphere: ClusterDeployment has installed: false (should be IPI)"
  else
    pass "vsphere: ClusterDeployment does not have installed: false"
  fi

  # Platform block
  if has_string "$OUTPUT" "vCenter: vcenter.lab.example.com"; then
    pass "vsphere: vCenter in install-config"
  else
    fail "vsphere: vCenter missing from install-config"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 3: AWS platform (IPI) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/aws.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for aws: $OUTPUT"
else
  pass "aws template renders successfully"

  # Common resources
  for KIND in Namespace ClusterDeployment KlusterletAddonConfig ManagedCluster ManagedClusterInfo; do
    if has_kind "$OUTPUT" "$KIND"; then
      pass "aws: $KIND present"
    else
      fail "aws: $KIND missing"
    fi
  done

  # IPI-only
  if has_kind "$OUTPUT" "MachinePool"; then
    pass "aws: MachinePool present (IPI)"
  else
    fail "aws: MachinePool missing (IPI)"
  fi

  # Agent-only must NOT exist
  for KIND in AgentClusterInstall InfraEnv BareMetalHost; do
    if has_kind "$OUTPUT" "$KIND"; then
      fail "aws: $KIND present (should be agent-only)"
    else
      pass "aws: $KIND absent (correct, agent-only)"
    fi
  done

  # AWS-specific
  if has_string "$OUTPUT" "test-aws-aws-creds"; then
    pass "aws: aws-creds secret present"
  else
    fail "aws: aws-creds secret missing"
  fi
  if has_string "$OUTPUT" "region: us-east-1"; then
    pass "aws: region in ClusterDeployment"
  else
    fail "aws: region missing from ClusterDeployment"
  fi

  # vSphere secrets must NOT exist
  if has_string "$OUTPUT" "vsphere-certs"; then
    fail "aws: vsphere-certs secret present (should be vsphere-only)"
  else
    pass "aws: vsphere-certs absent (correct)"
  fi
  if has_string "$OUTPUT" "vsphere-creds"; then
    fail "aws: vsphere-creds secret present (should be vsphere-only)"
  else
    pass "aws: vsphere-creds absent (correct)"
  fi

  # Labels
  if has_string "$OUTPUT" "cloud: Amazon"; then
    pass "aws: cloud label = Amazon"
  else
    fail "aws: cloud label incorrect"
  fi
  if has_string "$OUTPUT" "hive.openshift.io/cluster-platform: aws"; then
    pass "aws: platform label = aws"
  else
    fail "aws: platform label incorrect"
  fi

  # MachinePool should have AWS config
  if has_string "$OUTPUT" "type: m5.xlarge"; then
    pass "aws: MachinePool has instanceType"
  else
    fail "aws: MachinePool missing instanceType"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 4: Bare Metal platform (Agent-based) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/baremetal.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for baremetal: $OUTPUT"
else
  pass "baremetal template renders successfully"

  # Common resources
  for KIND in Namespace ClusterDeployment KlusterletAddonConfig ManagedCluster ManagedClusterInfo; do
    if has_kind "$OUTPUT" "$KIND"; then
      pass "baremetal: $KIND present"
    else
      fail "baremetal: $KIND missing"
    fi
  done

  # Agent-only resources
  for KIND in AgentClusterInstall InfraEnv BareMetalHost; do
    if has_kind "$OUTPUT" "$KIND"; then
      pass "baremetal: $KIND present (agent)"
    else
      fail "baremetal: $KIND missing (agent)"
    fi
  done

  # IPI-only must NOT exist
  if has_kind "$OUTPUT" "MachinePool"; then
    fail "baremetal: MachinePool present (should be IPI-only)"
  else
    pass "baremetal: MachinePool absent (correct)"
  fi

  # 3 BareMetalHosts
  BMH_COUNT=$(count_kind "$OUTPUT" "BareMetalHost")
  if [ "$BMH_COUNT" -eq 3 ]; then
    pass "baremetal: 3 BareMetalHosts rendered"
  else
    fail "baremetal: expected 3 BareMetalHosts, got $BMH_COUNT"
  fi

  # BMC credentials (3 secrets, one per host)
  BMC_CRED_COUNT=$(echo "$OUTPUT" | grep -c "bmc-credentials" || echo 0)
  if [ "$BMC_CRED_COUNT" -ge 3 ]; then
    pass "baremetal: BMC credential secrets rendered"
  else
    fail "baremetal: expected BMC credential secrets for each host, got $BMC_CRED_COUNT references"
  fi

  # Labels
  if has_string "$OUTPUT" "cloud: BareMetal"; then
    pass "baremetal: cloud label = BareMetal"
  else
    fail "baremetal: cloud label incorrect"
  fi
  if has_string "$OUTPUT" "hive.openshift.io/cluster-platform: agent-baremetal"; then
    pass "baremetal: platform label = agent-baremetal (Hive-normalized)"
  else
    fail "baremetal: platform label should be agent-baremetal"
  fi

  # ClusterDeployment should have installed: false and agentBareMetal platform
  if has_string "$OUTPUT" "installed: false"; then
    pass "baremetal: ClusterDeployment has installed: false"
  else
    fail "baremetal: ClusterDeployment missing installed: false"
  fi
  if has_string "$OUTPUT" "agentBareMetal:"; then
    pass "baremetal: ClusterDeployment uses agentBareMetal platform"
  else
    fail "baremetal: ClusterDeployment missing agentBareMetal platform"
  fi

  # AgentClusterInstall should NOT have userManagedNetworking (baremetal != none)
  if has_string "$OUTPUT" "userManagedNetworking: true"; then
    fail "baremetal: AgentClusterInstall has userManagedNetworking (should be none-only)"
  else
    pass "baremetal: AgentClusterInstall does not have userManagedNetworking"
  fi

  # AgentClusterInstall should have VIPs
  if has_string "$OUTPUT" "apiVIPs:"; then
    pass "baremetal: AgentClusterInstall has apiVIPs"
  else
    fail "baremetal: AgentClusterInstall missing apiVIPs"
  fi

  # IPI secrets must NOT exist
  if has_string "$OUTPUT" "test-bm-install-config"; then
    fail "baremetal: install-config secret present (should be IPI-only)"
  else
    pass "baremetal: install-config absent (correct)"
  fi
  if has_string "$OUTPUT" "ssh-private-key"; then
    fail "baremetal: ssh-private-key secret present (should be IPI-only)"
  else
    pass "baremetal: ssh-private-key absent (correct)"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 5: Platform None (Agent-based) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/none.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for none: $OUTPUT"
else
  pass "none template renders successfully"

  # Common resources
  for KIND in Namespace ClusterDeployment KlusterletAddonConfig ManagedCluster ManagedClusterInfo; do
    if has_kind "$OUTPUT" "$KIND"; then
      pass "none: $KIND present"
    else
      fail "none: $KIND missing"
    fi
  done

  # Agent-only resources
  for KIND in AgentClusterInstall InfraEnv BareMetalHost; do
    if has_kind "$OUTPUT" "$KIND"; then
      pass "none: $KIND present (agent)"
    else
      fail "none: $KIND missing (agent)"
    fi
  done

  # IPI-only must NOT exist
  if has_kind "$OUTPUT" "MachinePool"; then
    fail "none: MachinePool present (should be IPI-only)"
  else
    pass "none: MachinePool absent (correct)"
  fi

  # Labels
  if has_string "$OUTPUT" "cloud: Other"; then
    pass "none: cloud label = Other"
  else
    fail "none: cloud label incorrect"
  fi
  if has_string "$OUTPUT" "hive.openshift.io/cluster-platform: agent-baremetal"; then
    pass "none: platform label = agent-baremetal (Hive-normalized)"
  else
    fail "none: platform label should be agent-baremetal"
  fi

  # AgentClusterInstall SHOULD have userManagedNetworking
  if has_string "$OUTPUT" "userManagedNetworking: true"; then
    pass "none: AgentClusterInstall has userManagedNetworking"
  else
    fail "none: AgentClusterInstall missing userManagedNetworking"
  fi

  # AgentClusterInstall should NOT have VIPs (empty lists)
  if has_string "$OUTPUT" "apiVIPs:"; then
    fail "none: AgentClusterInstall has apiVIPs (should be empty for none)"
  else
    pass "none: AgentClusterInstall has no apiVIPs (correct for none)"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 6: Optional features — agent-based (NTP, proxy, ignition, NMState, machineNetwork) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/baremetal-opts.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for baremetal-opts: $OUTPUT"
else
  pass "baremetal with options renders successfully"

  # NTP in InfraEnv
  if has_string "$OUTPUT" "additionalNTPSources:"; then
    pass "opts: InfraEnv has NTP sources"
  else
    fail "opts: InfraEnv missing NTP sources"
  fi
  if has_string "$OUTPUT" "ntp1.internal"; then
    pass "opts: NTP source values present"
  else
    fail "opts: NTP source values missing"
  fi

  # Proxy in InfraEnv and AgentClusterInstall
  PROXY_COUNT=$(echo "$OUTPUT" | grep -c "httpProxy:" || echo 0)
  if [ "$PROXY_COUNT" -ge 2 ]; then
    pass "opts: proxy configured in both InfraEnv and AgentClusterInstall"
  else
    fail "opts: proxy should appear in InfraEnv + AgentClusterInstall, found $PROXY_COUNT"
  fi

  # Ignition override in InfraEnv
  if has_string "$OUTPUT" "ignitionConfigOverride:"; then
    pass "opts: InfraEnv has ignitionConfigOverride"
  else
    fail "opts: InfraEnv missing ignitionConfigOverride"
  fi

  # NMState
  if has_kind "$OUTPUT" "NMStateConfig"; then
    pass "opts: NMStateConfig rendered for host with nmstate"
  else
    fail "opts: NMStateConfig missing for host with nmstate"
  fi

  # machineNetwork in AgentClusterInstall
  if has_string "$OUTPUT" "machineNetwork:"; then
    pass "opts: AgentClusterInstall has machineNetwork"
  else
    fail "opts: AgentClusterInstall missing machineNetwork"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 7: Optional features — IPI (custom manifests, proxy, FIPS, trustBundle) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/vsphere-opts.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for vsphere-opts: $OUTPUT"
else
  pass "vsphere with options renders successfully"

  # Custom manifests ConfigMap
  if has_kind "$OUTPUT" "ConfigMap"; then
    pass "opts-ipi: custom manifests ConfigMap rendered"
  else
    fail "opts-ipi: custom manifests ConfigMap missing"
  fi
  if has_string "$OUTPUT" "test-vs-opts-custom-manifests"; then
    pass "opts-ipi: custom manifests ConfigMap named correctly"
  else
    fail "opts-ipi: custom manifests ConfigMap name incorrect"
  fi

  # ClusterDeployment should reference custom-manifests (not image-content-sources)
  if has_string "$OUTPUT" "name: test-vs-opts-custom-manifests"; then
    pass "opts-ipi: ClusterDeployment references custom-manifests"
  else
    fail "opts-ipi: ClusterDeployment should reference custom-manifests"
  fi

  # Proxy in install-config
  if has_string "$OUTPUT" "proxy.internal:3128"; then
    pass "opts-ipi: proxy in install-config"
  else
    fail "opts-ipi: proxy missing from install-config"
  fi

  # FIPS in install-config
  if has_string "$OUTPUT" "fips: true"; then
    pass "opts-ipi: FIPS enabled in install-config"
  else
    fail "opts-ipi: FIPS missing from install-config"
  fi

  # Additional trust bundle in install-config
  if has_string "$OUTPUT" "additionalTrustBundle:"; then
    pass "opts-ipi: additionalTrustBundle in install-config"
  else
    fail "opts-ipi: additionalTrustBundle missing from install-config"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 8: Sync wave ordering ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/baremetal.yaml")
check_wave() {
  local resource="$1" expected="$2"
  local wave
  wave=$(echo "$OUTPUT" | grep -A20 "kind: $resource" | grep "sync-wave" | head -1 | grep -o '"[0-9]*"' | tr -d '"')
  if [ "$wave" = "$expected" ]; then
    pass "sync-wave: $resource = $wave"
  else
    fail "sync-wave: $resource = ${wave:-none} (expected $expected)"
  fi
}
check_wave Namespace 0
check_wave ClusterDeployment 2
check_wave AgentClusterInstall 3
check_wave InfraEnv 4
check_wave KlusterletAddonConfig 5
check_wave BareMetalHost 7
check_wave ManagedCluster 8
check_wave ManagedClusterInfo 9

# ============================================================================
echo ""
echo "--- Test 9: InfraEnv does NOT contain agentLabelSelector ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/baremetal.yaml")
if echo "$OUTPUT" | grep -q "agentLabelSelector"; then
  fail "InfraEnv still contains agentLabelSelector (should be managed by controller)"
else
  pass "InfraEnv does not contain agentLabelSelector"
fi

# ============================================================================
echo ""
echo "--- Test 10: Namespace annotations ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/vsphere.yaml")
if has_string "$OUTPUT" "openshift.io/display-name: test-vsphere"; then
  pass "Namespace has display-name annotation"
else
  fail "Namespace missing display-name annotation"
fi
if has_string "$OUTPUT" "cluster.open-cluster-management.io/managedCluster: test-vsphere"; then
  pass "Namespace has managedCluster annotation"
else
  fail "Namespace missing managedCluster annotation"
fi

# ============================================================================
echo ""
echo "--- Test 11: vSphere control plane automation — govc mode ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/baremetal-govc.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for baremetal-govc: $OUTPUT"
else
  pass "baremetal with govc automation renders successfully"

  # RBAC resources
  if has_string "$OUTPUT" "test-bm-govc-vsphere-cp"; then
    pass "govc: ServiceAccount name correct"
  else
    fail "govc: ServiceAccount name incorrect"
  fi
  if echo "$OUTPUT" | grep -A5 "kind: Role" | grep -q "test-bm-govc-vsphere-cp"; then
    pass "govc: Role present"
  else
    fail "govc: Role missing"
  fi
  if has_kind "$OUTPUT" "RoleBinding"; then
    pass "govc: RoleBinding present"
  else
    fail "govc: RoleBinding missing"
  fi

  # RBAC sync-wave = 6
  SA_WAVE=$(echo "$OUTPUT" | grep -A5 "kind: ServiceAccount" | grep "sync-wave" | head -1 | grep -o '"[0-9]*"' | tr -d '"')
  if [ "$SA_WAVE" = "6" ]; then
    pass "govc: RBAC sync-wave = 6"
  else
    fail "govc: RBAC sync-wave = ${SA_WAVE:-none} (expected 6)"
  fi

  # Secret
  if has_string "$OUTPUT" "test-bm-govc-vsphere-cp-creds"; then
    pass "govc: vCenter credentials secret present"
  else
    fail "govc: vCenter credentials secret missing"
  fi
  if has_string "$OUTPUT" "username: admin@vsphere.local"; then
    pass "govc: secret has correct username"
  else
    fail "govc: secret username incorrect"
  fi

  # ConfigMap (govc script)
  if has_string "$OUTPUT" "test-bm-govc-vsphere-cp-govc"; then
    pass "govc: govc ConfigMap present"
  else
    fail "govc: govc ConfigMap missing"
  fi
  if has_string "$OUTPUT" "govc.sh:"; then
    pass "govc: govc.sh key in ConfigMap"
  else
    fail "govc: govc.sh key missing from ConfigMap"
  fi

  # ConfigMap sync-wave = 7
  CM_WAVE=$(echo "$OUTPUT" | grep -A5 "test-bm-govc-vsphere-cp-govc" | grep "sync-wave" | head -1 | grep -o '"[0-9]*"' | tr -d '"')
  if [ "$CM_WAVE" = "7" ]; then
    pass "govc: ConfigMap sync-wave = 7"
  else
    fail "govc: ConfigMap sync-wave = ${CM_WAVE:-none} (expected 7)"
  fi

  # Ansible ConfigMap must NOT exist
  if has_string "$OUTPUT" "vsphere-cp-ansible"; then
    fail "govc: ansible ConfigMap present (should be govc-only)"
  else
    pass "govc: ansible ConfigMap absent (correct)"
  fi

  # Job
  if has_kind "$OUTPUT" "Job"; then
    pass "govc: Job present"
  else
    fail "govc: Job missing"
  fi

  # Job sync-wave = 9
  JOB_WAVE=$(echo "$OUTPUT" | grep -A5 "kind: Job" | grep "sync-wave" | head -1 | grep -o '"[0-9]*"' | tr -d '"')
  if [ "$JOB_WAVE" = "9" ]; then
    pass "govc: Job sync-wave = 9"
  else
    fail "govc: Job sync-wave = ${JOB_WAVE:-none} (expected 9)"
  fi

  # Job Replace=true sync option
  if has_string "$OUTPUT" "Replace=true"; then
    pass "govc: Job has Replace=true sync option"
  else
    fail "govc: Job missing Replace=true sync option"
  fi

  # Job env vars
  if has_string "$OUTPUT" "GOVC_VERSION"; then
    pass "govc: Job has GOVC_VERSION env var"
  else
    fail "govc: Job missing GOVC_VERSION env var"
  fi
  if has_string "$OUTPUT" 'value: "vcsa.lab.example.com"'; then
    pass "govc: Job has correct VCENTER value"
  else
    fail "govc: Job VCENTER value incorrect"
  fi

  # Job uses secretKeyRef for credentials
  if has_string "$OUTPUT" "secretKeyRef:"; then
    pass "govc: Job uses secretKeyRef for credentials"
  else
    fail "govc: Job should use secretKeyRef for credentials"
  fi

  # Job image
  if has_string "$OUTPUT" "quay.io/openshift/origin-cli:latest"; then
    pass "govc: Job uses correct image"
  else
    fail "govc: Job image incorrect"
  fi

  # Job serviceAccountName
  if has_string "$OUTPUT" "serviceAccountName: test-bm-govc-vsphere-cp"; then
    pass "govc: Job uses correct ServiceAccount"
  else
    fail "govc: Job ServiceAccount incorrect"
  fi

  # Job backoffLimit and activeDeadlineSeconds
  if has_string "$OUTPUT" "backoffLimit: 2"; then
    pass "govc: Job has backoffLimit: 2"
  else
    fail "govc: Job missing backoffLimit"
  fi
  if has_string "$OUTPUT" "activeDeadlineSeconds: 7200"; then
    pass "govc: Job has activeDeadlineSeconds: 7200"
  else
    fail "govc: Job missing activeDeadlineSeconds"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 12: vSphere control plane automation — ansible mode ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/baremetal-ansible.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for baremetal-ansible: $OUTPUT"
else
  pass "baremetal with ansible automation renders successfully"

  # RBAC (shared with govc)
  if has_string "$OUTPUT" "test-bm-ansible-vsphere-cp"; then
    pass "ansible: ServiceAccount present"
  else
    fail "ansible: ServiceAccount missing"
  fi

  # Secret (shared with govc)
  if has_string "$OUTPUT" "test-bm-ansible-vsphere-cp-creds"; then
    pass "ansible: vCenter credentials secret present"
  else
    fail "ansible: vCenter credentials secret missing"
  fi

  # ConfigMap (ansible scripts)
  if has_string "$OUTPUT" "test-bm-ansible-vsphere-cp-ansible"; then
    pass "ansible: ansible ConfigMap present"
  else
    fail "ansible: ansible ConfigMap missing"
  fi
  if has_string "$OUTPUT" "entrypoint.sh:"; then
    pass "ansible: entrypoint.sh key in ConfigMap"
  else
    fail "ansible: entrypoint.sh key missing from ConfigMap"
  fi
  if has_string "$OUTPUT" "playbook.yml:"; then
    pass "ansible: playbook.yml key in ConfigMap"
  else
    fail "ansible: playbook.yml key missing from ConfigMap"
  fi
  if has_string "$OUTPUT" "requirements.yml:"; then
    pass "ansible: requirements.yml key in ConfigMap"
  else
    fail "ansible: requirements.yml key missing from ConfigMap"
  fi

  # govc ConfigMap must NOT exist
  if has_string "$OUTPUT" "vsphere-cp-govc"; then
    fail "ansible: govc ConfigMap present (should be ansible-only)"
  else
    pass "ansible: govc ConfigMap absent (correct)"
  fi

  # Job
  if has_kind "$OUTPUT" "Job"; then
    pass "ansible: Job present"
  else
    fail "ansible: Job missing"
  fi

  # Job image
  if has_string "$OUTPUT" "quay.io/ansible/ansible-runner:latest"; then
    pass "ansible: Job uses correct image"
  else
    fail "ansible: Job image incorrect"
  fi

  # Job should NOT have GOVC_VERSION
  if has_string "$OUTPUT" "GOVC_VERSION"; then
    fail "ansible: Job has GOVC_VERSION (should be govc-only)"
  else
    pass "ansible: Job does not have GOVC_VERSION (correct)"
  fi

  # Job command
  if has_string "$OUTPUT" "/scripts/entrypoint.sh"; then
    pass "ansible: Job runs entrypoint.sh"
  else
    fail "ansible: Job should run entrypoint.sh"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 13: vSphere CP excluded when disabled or on non-agent platforms ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/baremetal.yaml")
if has_string "$OUTPUT" "vsphere-cp"; then
  fail "excluded: vsphere-cp resources appear when vsphereControlPlane.enabled=false (default)"
else
  pass "excluded: no vsphere-cp resources when disabled (default)"
fi

OUTPUT=$(render "$TMPDIR/vsphere.yaml")
if has_string "$OUTPUT" "vsphere-cp"; then
  fail "excluded: vsphere-cp resources appear on IPI vsphere platform"
else
  pass "excluded: no vsphere-cp resources on IPI vsphere platform"
fi

OUTPUT=$(render "$TMPDIR/aws.yaml")
if has_string "$OUTPUT" "vsphere-cp"; then
  fail "excluded: vsphere-cp resources appear on AWS platform"
else
  pass "excluded: no vsphere-cp resources on AWS platform"
fi

OUTPUT=$(render "$TMPDIR/azure.yaml")
if has_string "$OUTPUT" "vsphere-cp"; then
  fail "excluded: vsphere-cp resources appear on Azure platform"
else
  pass "excluded: no vsphere-cp resources on Azure platform"
fi

OUTPUT=$(render "$TMPDIR/gcp.yaml")
if has_string "$OUTPUT" "vsphere-cp"; then
  fail "excluded: vsphere-cp resources appear on GCP platform"
else
  pass "excluded: no vsphere-cp resources on GCP platform"
fi
if has_kind "$OUTPUT" "Job"; then
  fail "excluded: a Job appears on GCP platform"
else
  pass "excluded: no Job on GCP platform"
fi

# ============================================================================
echo ""
echo "--- Test 14: vSphere control plane — simulator mode ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/baremetal-govc-sim.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for simulator mode: $OUTPUT"
else
  pass "simulator mode renders successfully"

  # vcsim Deployment present
  if has_kind "$OUTPUT" "Deployment"; then
    pass "simulator: vcsim Deployment present"
  else
    fail "simulator: vcsim Deployment missing"
  fi

  # vcsim Service present
  if has_kind "$OUTPUT" "Service"; then
    pass "simulator: vcsim Service present"
  else
    fail "simulator: vcsim Service missing"
  fi

  # vcsim image
  if has_string "$OUTPUT" "ghcr.io/vmware/govmomi/vcsim:latest"; then
    pass "simulator: vcsim image correct"
  else
    fail "simulator: vcsim image incorrect"
  fi

  # vcsim Deployment sync-wave = 7
  VCSIM_WAVE=$(echo "$OUTPUT" | grep -B10 "kind: Deployment" | grep "sync-wave" | head -1 | grep -o '"[0-9]*"' | tr -d '"')
  if [ "$VCSIM_WAVE" = "7" ]; then
    pass "simulator: vcsim Deployment sync-wave = 7"
  else
    fail "simulator: vcsim Deployment sync-wave = ${VCSIM_WAVE:-none} (expected 7)"
  fi

  # Job VCENTER points at vcsim service, NOT real vcenter
  if has_string "$OUTPUT" 'value: "test-sim-vcsim"'; then
    pass "simulator: Job VCENTER points to vcsim service"
  else
    fail "simulator: Job VCENTER should point to test-sim-vcsim"
  fi
  if has_string "$OUTPUT" "vcsa.real.example.com"; then
    fail "simulator: real vCenter URL leaked into output"
  else
    pass "simulator: real vCenter URL not in output"
  fi

  # vcsim Deployment selector labels
  if has_string "$OUTPUT" "app: test-sim-vcsim"; then
    pass "simulator: vcsim Deployment has correct selector label"
  else
    fail "simulator: vcsim Deployment selector label incorrect"
  fi

  # Service targets port 443
  if has_string "$OUTPUT" "port: 443"; then
    pass "simulator: Service exposes port 443"
  else
    fail "simulator: Service should expose port 443"
  fi

  # RBAC and Job still present alongside vcsim
  if has_kind "$OUTPUT" "Job"; then
    pass "simulator: automation Job still present"
  else
    fail "simulator: automation Job missing"
  fi
  if has_kind "$OUTPUT" "RoleBinding"; then
    pass "simulator: RBAC still present"
  else
    fail "simulator: RBAC missing"
  fi
fi

# Verify simulator resources absent when simulator.enabled=false
OUTPUT=$(render "$TMPDIR/baremetal-govc.yaml")
if has_kind "$OUTPUT" "Deployment"; then
  fail "simulator: Deployment present when simulator.enabled=false"
else
  pass "simulator: no Deployment when simulator.enabled=false"
fi
if echo "$OUTPUT" | grep -qx "kind: Service"; then
  fail "simulator: Service present when simulator.enabled=false"
else
  pass "simulator: no Service when simulator.enabled=false"
fi
if has_string "$OUTPUT" 'value: "vcsa.lab.example.com"'; then
  pass "simulator: Job uses real vCenter when simulator off"
else
  fail "simulator: Job should use real vCenter when simulator off"
fi

# ============================================================================
echo ""
echo "--- Test 15: Dual InfraEnv for mixed clusters ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/mixed-dual-infraenv.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for mixed-dual-infraenv: $OUTPUT"
else
  pass "mixed cluster with dual InfraEnv renders successfully"

  # Two InfraEnv resources
  INFRAENV_COUNT=$(count_kind "$OUTPUT" "InfraEnv")
  if [ "$INFRAENV_COUNT" -eq 2 ]; then
    pass "dual-infraenv: exactly 2 InfraEnv resources rendered"
  else
    fail "dual-infraenv: expected 2 InfraEnv, got $INFRAENV_COUNT"
  fi

  # CP InfraEnv name
  if has_string "$OUTPUT" "name: test-mixed-cp"; then
    pass "dual-infraenv: CP InfraEnv named test-mixed-cp"
  else
    fail "dual-infraenv: CP InfraEnv name missing"
  fi

  # Workers InfraEnv name
  if has_string "$OUTPUT" "name: test-mixed-workers"; then
    pass "dual-infraenv: workers InfraEnv named test-mixed-workers"
  else
    fail "dual-infraenv: workers InfraEnv name missing"
  fi

  # CP InfraEnv label selector
  if has_string "$OUTPUT" "infraenv: test-mixed-cp"; then
    pass "dual-infraenv: CP InfraEnv has correct label selector"
  else
    fail "dual-infraenv: CP InfraEnv label selector incorrect"
  fi

  # Workers InfraEnv label selector
  if has_string "$OUTPUT" "infraenv: test-mixed-workers"; then
    pass "dual-infraenv: workers InfraEnv has correct label selector"
  else
    fail "dual-infraenv: workers InfraEnv label selector incorrect"
  fi

  # BareMetalHost uses workers InfraEnv
  if echo "$OUTPUT" | grep -A2 "infraenvs.agent-install.openshift.io" | grep -q "test-mixed-workers"; then
    pass "dual-infraenv: BareMetalHost bound to workers InfraEnv"
  else
    fail "dual-infraenv: BareMetalHost should be bound to workers InfraEnv"
  fi

  # NMStateConfig uses workers label
  if echo "$OUTPUT" | grep -B2 -A15 "kind: NMStateConfig" | grep -q "infraenv: test-mixed-workers"; then
    pass "dual-infraenv: NMStateConfig has infraenv workers label"
  else
    fail "dual-infraenv: NMStateConfig should have infraenv workers label"
  fi

  # INFRAENV_NAME env var in govc Job
  if has_string "$OUTPUT" "INFRAENV_NAME"; then
    pass "dual-infraenv: Job has INFRAENV_NAME env var"
  else
    fail "dual-infraenv: Job missing INFRAENV_NAME env var"
  fi
  if has_string "$OUTPUT" 'value: "test-mixed-cp"'; then
    pass "dual-infraenv: INFRAENV_NAME set to test-mixed-cp"
  else
    fail "dual-infraenv: INFRAENV_NAME should be test-mixed-cp"
  fi

  # InfraEnv should not use single-mode cluster-name label selector
  if echo "$OUTPUT" | grep -B2 -A15 "kind: InfraEnv" | grep -q "cluster-name: test-mixed"; then
    fail "dual-infraenv: InfraEnv uses cluster-name label (should use infraenv labels)"
  else
    pass "dual-infraenv: InfraEnv uses infraenv labels, not cluster-name"
  fi
fi

# Verify standard mode still produces single InfraEnv
OUTPUT=$(render "$TMPDIR/baremetal.yaml")
INFRAENV_COUNT=$(count_kind "$OUTPUT" "InfraEnv")
if [ "$INFRAENV_COUNT" -eq 1 ]; then
  pass "standard-mode: single InfraEnv when vsphereControlPlane disabled"
else
  fail "standard-mode: expected 1 InfraEnv, got $INFRAENV_COUNT"
fi
if has_string "$OUTPUT" "cluster-name: test-bm"; then
  pass "standard-mode: InfraEnv uses cluster-name label selector"
else
  fail "standard-mode: InfraEnv should use cluster-name label selector"
fi

# ============================================================================
echo ""
echo "--- Test 16: Single-node OpenShift (AWS) ---"
# ============================================================================
cat > "$TMPDIR/sno.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-sno
  baseDomain: cloud.example.com
  platform: aws
  environment: dev
  clusterSet: default
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
  pullSecret: '{"auths":{}}'
masters:
  count: 1
workers:
  count: 0
aws:
  accessKeyID: AKIAIOSFODNN7EXAMPLE
  secretAccessKey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  region: us-east-2
  masters:
    instanceType: m5.2xlarge
    zones:
      - us-east-2a
    rootVolume:
      size: 200
      type: gp3
  workers:
    instanceType: m5.4xlarge
    zones: []
    rootVolume:
      size: 120
      type: gp3
EOF

OUTPUT=$(render "$TMPDIR/sno.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for sno: $OUTPUT"
else
  pass "sno template renders successfully"

  if has_kind "$OUTPUT" "ClusterDeployment"; then
    pass "sno: ClusterDeployment present"
  else
    fail "sno: ClusterDeployment missing"
  fi

  # The point of the topology: one control plane replica, no compute, and no
  # worker pool for Hive to reconcile into empty MachineSets.
  if has_string "$OUTPUT" "replicas: 1"; then
    pass "sno: controlPlane replicas = 1"
  else
    fail "sno: controlPlane replicas != 1"
  fi
  if has_string "$OUTPUT" "replicas: 0"; then
    pass "sno: compute replicas = 0"
  else
    fail "sno: compute replicas != 0"
  fi
  if has_kind "$OUTPUT" "MachinePool"; then
    fail "sno: MachinePool present (no workers means no pool)"
  else
    pass "sno: MachinePool absent (correct, workers.count is 0)"
  fi
  # The compute pool keeps the master zones even with no machines in it. It
  # is what bounds the AZs the VPC spans, and an unbounded one subnets every
  # AZ in the region and burns an Elastic IP per NAT gateway.
  if has_string "$OUTPUT" "platform: {}"; then
    fail "sno: compute platform is empty (VPC would span every AZ in the region)"
  else
    pass "sno: compute pool constrains zones rather than rendering platform: {}"
  fi
  if [ "$(echo "$OUTPUT" | grep -c "us-east-2a")" -ge 2 ]; then
    pass "sno: compute pool echoes the master zones"
  else
    fail "sno: compute pool missing the master zones"
  fi

  # Worker sizing must not reach install-config — the installer validates
  # instance types it is given even for a pool it will never create.
  if has_string "$OUTPUT" "type: m5.2xlarge"; then
    pass "sno: master instanceType present"
  else
    fail "sno: master instanceType missing"
  fi
  if has_string "$OUTPUT" "m5.4xlarge"; then
    fail "sno: worker instanceType reached install-config"
  else
    pass "sno: worker instanceType absent (pool is never created)"
  fi
fi

# A single master with workers alongside it is not a topology. Caught at
# render rather than hours later inside a Hive provisioning pod.
cat > "$TMPDIR/sno-invalid.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-sno-invalid
  baseDomain: cloud.example.com
  platform: aws
  environment: dev
  clusterSet: default
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
masters:
  count: 1
workers:
  count: 3
EOF

OUTPUT=$(render "$TMPDIR/sno-invalid.yaml")
if [ $? -eq 0 ]; then
  fail "sno: 1 master with 3 workers rendered (should be rejected)"
elif echo "$OUTPUT" | grep -q "requires workers.count: 0"; then
  pass "sno: 1 master with workers rejected with a topology error"
else
  fail "sno: rejected, but not with the topology error: $OUTPUT"
fi

# Compact: 3 masters, 0 workers. Same no-pool handling, still a valid cluster.
cat > "$TMPDIR/compact.yaml" <<'EOF'
provision:
  include: true
cluster:
  name: test-compact
  baseDomain: cloud.example.com
  platform: aws
  environment: dev
  clusterSet: default
  imageSetRef: img4.16.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: ssh-rsa AAAA...
masters:
  count: 3
workers:
  count: 0
aws:
  region: us-east-2
  masters:
    instanceType: m5.2xlarge
    zones: []
    rootVolume:
      size: 200
      type: gp3
  workers:
    instanceType: m5.xlarge
    zones: []
    rootVolume:
      size: 120
      type: gp3
EOF

OUTPUT=$(render "$TMPDIR/compact.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for compact: $OUTPUT"
else
  pass "compact template renders successfully"
  if has_kind "$OUTPUT" "MachinePool"; then
    fail "compact: MachinePool present (no workers means no pool)"
  else
    pass "compact: MachinePool absent (correct, workers.count is 0)"
  fi
  if has_string "$OUTPUT" "replicas: 3"; then
    pass "compact: controlPlane replicas = 3"
  else
    fail "compact: controlPlane replicas != 3"
  fi
  # masters.zones is empty here, so there is nothing to echo and the compute
  # pool falls back to platform: {} — the installer picks the AZs.
  if has_string "$OUTPUT" "platform: {}"; then
    pass "compact: compute platform empty when master zones are unset"
  else
    fail "compact: compute platform should be {} when master zones are unset"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 17: GCP platform (IPI) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/gcp.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for gcp: $OUTPUT"
else
  pass "gcp template renders successfully"

  # Common resources
  for KIND in Namespace ClusterDeployment KlusterletAddonConfig ManagedCluster ManagedClusterInfo; do
    if has_kind "$OUTPUT" "$KIND"; then
      pass "gcp: $KIND present"
    else
      fail "gcp: $KIND missing"
    fi
  done

  # IPI-only
  if has_kind "$OUTPUT" "MachinePool"; then
    pass "gcp: MachinePool present (IPI)"
  else
    fail "gcp: MachinePool missing (IPI)"
  fi
  for NAME in test-gcp-install-config test-gcp-ssh-private-key; do
    if has_string "$OUTPUT" "$NAME"; then
      pass "gcp: $NAME present (IPI)"
    else
      fail "gcp: $NAME missing (IPI)"
    fi
  done

  # Agent-only must NOT exist
  for KIND in AgentClusterInstall InfraEnv BareMetalHost; do
    if has_kind "$OUTPUT" "$KIND"; then
      fail "gcp: $KIND present (should be agent-only)"
    else
      pass "gcp: $KIND absent (correct, agent-only)"
    fi
  done

  # Until GCP was a known platform, isIPI and isAgent both answered false and
  # clusterdeployment.yaml's bare `else` handed a GCP cluster an agentBareMetal
  # platform plus a clusterInstallRef to an AgentClusterInstall nothing
  # rendered — alongside the IPI installAttemptsLimit. Hive accepts that
  # object, so the cluster provisioned into nothing and said so nowhere. These
  # two are the regression test for it.
  if has_string "$OUTPUT" "agentBareMetal"; then
    fail "gcp: agentBareMetal present — GCP fell through to the agent branch"
  else
    pass "gcp: agentBareMetal absent"
  fi
  if has_string "$OUTPUT" "clusterInstallRef"; then
    fail "gcp: clusterInstallRef present — GCP fell through to the agent branch"
  else
    pass "gcp: clusterInstallRef absent"
  fi

  # GCP-specific
  if has_string "$OUTPUT" "test-gcp-gcp-creds"; then
    pass "gcp: gcp-creds secret present"
  else
    fail "gcp: gcp-creds secret missing"
  fi
  if has_string "$OUTPUT" "osServiceAccount.json:"; then
    pass "gcp: creds secret uses the osServiceAccount.json key Hive reads"
  else
    fail "gcp: osServiceAccount.json key missing"
  fi
  # The key file is rendered through `quote`, so it is one double-quoted
  # scalar beginning with an escaped brace. A refactor to a block scalar
  # would still be valid YAML and would still carry the JSON, which is why
  # this asserts the shape rather than the content.
  if echo "$OUTPUT" | grep -qF 'osServiceAccount.json: "{'; then
    pass "gcp: key file rendered as a single-line quoted scalar"
  else
    fail "gcp: key file is not a single-line quoted scalar"
  fi
  if has_string "$OUTPUT" "region: us-central1"; then
    pass "gcp: region present"
  else
    fail "gcp: region missing"
  fi
  if has_string "$OUTPUT" "projectID: test-project"; then
    pass "gcp: install-config projectID present"
  else
    fail "gcp: install-config projectID missing"
  fi
  if has_string "$OUTPUT" "cloud: Google"; then
    pass "gcp: cloud label is Google"
  else
    fail "gcp: cloud label is not Google"
  fi
  if has_string "$OUTPUT" "hive.openshift.io/cluster-platform: gcp"; then
    pass "gcp: cluster-platform label is gcp"
  else
    fail "gcp: cluster-platform label is not gcp"
  fi
  if has_string "$OUTPUT" "type: n2-standard-4" && has_string "$OUTPUT" "diskType: pd-ssd"; then
    pass "gcp: machine type and disk type present"
  else
    fail "gcp: machine type or disk type missing"
  fi
  # credentialsMode is unset in the fixture, so nothing should be emitted —
  # an empty one would make the Cloud Credential Operator do nothing at all.
  if has_string "$OUTPUT" "credentialsMode"; then
    fail "gcp: credentialsMode emitted when unset"
  else
    pass "gcp: credentialsMode absent when unset"
  fi

  # Other platforms' credentials must not appear
  for NAME in aws-creds vsphere-creds vsphere-certs; do
    if has_string "$OUTPUT" "$NAME"; then
      fail "gcp: $NAME present (wrong platform)"
    else
      pass "gcp: $NAME absent (correct)"
    fi
  done
fi

# ============================================================================
echo ""
echo "--- Test 18: Single-node OpenShift (GCP) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/gcp-sno.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for gcp-sno: $OUTPUT"
else
  pass "gcp-sno template renders successfully"

  if has_kind "$OUTPUT" "MachinePool"; then
    fail "gcp-sno: MachinePool present (workers.count is 0)"
  else
    pass "gcp-sno: MachinePool absent (correct, workers.count is 0)"
  fi
  if has_string "$OUTPUT" "replicas: 1"; then
    pass "gcp-sno: controlPlane replicas = 1"
  else
    fail "gcp-sno: controlPlane replicas != 1"
  fi
  if has_string "$OUTPUT" "replicas: 0"; then
    pass "gcp-sno: compute replicas = 0"
  else
    fail "gcp-sno: compute replicas != 0"
  fi

  # The deliberate inverse of Test 16. On AWS the empty compute pool keeps the
  # master zones, because machine pools are what bound the AZs the VPC spans
  # and an unbounded pool costs an Elastic IP per AZ. GCP subnets are regional
  # and Cloud NAT is one regional resource, so zones buy nothing there and
  # would only get validated against the region. GCP gets platform: {}.
  if has_string "$OUTPUT" "platform: {}"; then
    pass "gcp-sno: compute pool is platform: {} (zones buy nothing on GCP)"
  else
    fail "gcp-sno: compute pool should be platform: {} on GCP"
  fi
  ZONE_HITS=$(echo "$OUTPUT" | grep -c "us-central1-a") || true
  if [ "$ZONE_HITS" -eq 1 ]; then
    pass "gcp-sno: master zone appears once, not echoed into the compute pool"
  else
    fail "gcp-sno: master zone appears ${ZONE_HITS} times, expected 1"
  fi
  if has_string "$OUTPUT" "n2-standard-16"; then
    fail "gcp-sno: worker machineType reached install-config for a pool that is never created"
  else
    pass "gcp-sno: worker machineType absent (pool is never created)"
  fi
  if has_string "$OUTPUT" "n2-standard-8"; then
    pass "gcp-sno: master machineType present"
  else
    fail "gcp-sno: master machineType missing"
  fi
  if has_string "$OUTPUT" "region: us-central1"; then
    pass "gcp-sno: ClusterDeployment still carries the GCP region"
  else
    fail "gcp-sno: ClusterDeployment region missing"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 19: unknown platform is rejected ---"
# ============================================================================
# cluster.platform is free text out of provision.yaml. Before validatePlatform
# a typo rendered a ClusterDeployment that Hive accepted and never installed,
# so the only signal was silence. It has to fail the render instead.
OUTPUT=$(render "$TMPDIR/unknown-platform.yaml")
if [ $? -eq 0 ]; then
  fail "unknown platform: render succeeded, expected a failure"
else
  pass "unknown platform: render fails"
  if has_string "$OUTPUT" "expected aws, azure, gcp, vsphere, baremetal or none"; then
    pass "unknown platform: error names the platforms that are valid"
  else
    fail "unknown platform: error does not name the valid platforms: $OUTPUT"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 20: Azure platform (IPI) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/azure.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for azure: $OUTPUT"
else
  pass "azure template renders successfully"

  # Common resources
  for KIND in Namespace ClusterDeployment KlusterletAddonConfig ManagedCluster ManagedClusterInfo; do
    if has_kind "$OUTPUT" "$KIND"; then
      pass "azure: $KIND present"
    else
      fail "azure: $KIND missing"
    fi
  done

  # IPI-only
  if has_kind "$OUTPUT" "MachinePool"; then
    pass "azure: MachinePool present (IPI)"
  else
    fail "azure: MachinePool missing (IPI)"
  fi
  for NAME in test-azure-install-config test-azure-ssh-private-key; do
    if has_string "$OUTPUT" "$NAME"; then
      pass "azure: $NAME present (IPI)"
    else
      fail "azure: $NAME missing (IPI)"
    fi
  done

  # Agent-only must NOT exist — the same fall-through that caught GCP.
  for KIND in AgentClusterInstall InfraEnv BareMetalHost; do
    if has_kind "$OUTPUT" "$KIND"; then
      fail "azure: $KIND present (should be agent-only)"
    else
      pass "azure: $KIND absent (correct, agent-only)"
    fi
  done
  if has_string "$OUTPUT" "agentBareMetal"; then
    fail "azure: agentBareMetal present — Azure fell through to the agent branch"
  else
    pass "azure: agentBareMetal absent"
  fi
  if has_string "$OUTPUT" "clusterInstallRef"; then
    fail "azure: clusterInstallRef present — Azure fell through to the agent branch"
  else
    pass "azure: clusterInstallRef absent"
  fi

  # Azure-specific
  if has_string "$OUTPUT" "test-azure-azure-creds"; then
    pass "azure: azure-creds secret present"
  else
    fail "azure: azure-creds secret missing"
  fi
  if has_string "$OUTPUT" "osServicePrincipal.json:"; then
    pass "azure: creds secret uses the osServicePrincipal.json key Hive reads"
  else
    fail "azure: osServicePrincipal.json key missing"
  fi
  if echo "$OUTPUT" | grep -qF 'osServicePrincipal.json: "{'; then
    pass "azure: service principal rendered as a single-line quoted scalar"
  else
    fail "azure: service principal is not a single-line quoted scalar"
  fi
  if has_string "$OUTPUT" "cloud: Azure"; then
    pass "azure: cloud label is Azure"
  else
    fail "azure: cloud label is not Azure"
  fi
  if has_string "$OUTPUT" "hive.openshift.io/cluster-platform: azure"; then
    pass "azure: cluster-platform label is azure"
  else
    fail "azure: cluster-platform label is not azure"
  fi
  if has_string "$OUTPUT" "type: Standard_D4s_v3" && has_string "$OUTPUT" "diskType: Premium_LRS"; then
    pass "azure: vmSize and disk type present"
  else
    fail "azure: vmSize or disk type missing"
  fi

  # The inverse of GCP's projectID, and the reason the two branches look
  # inconsistent on purpose. baseDomainResourceGroupName has to reach both
  # install-config and the ClusterDeployment: Hive does not parse it out of
  # install-config, and without its own copy it reconciles DNS against
  # nothing and reports DNSNotReady on a cluster that installed fine.
  RG_HITS=$(echo "$OUTPUT" | grep -c "baseDomainResourceGroupName: test-dns-rg") || true
  if [ "$RG_HITS" -eq 2 ]; then
    pass "azure: baseDomainResourceGroupName in both install-config and ClusterDeployment"
  else
    fail "azure: baseDomainResourceGroupName appears ${RG_HITS} times, expected 2"
  fi

  # The fixture writes zones as bare YAML integers, which is how anyone
  # transcribing Azure's docs would write them. The field is []string, so
  # the template has to quote them back or the installer rejects the pool.
  if echo "$OUTPUT" | grep -qE '^\s+- "1"$'; then
    pass "azure: zones rendered as quoted strings"
  else
    fail "azure: zones are not quoted strings"
  fi
  if echo "$OUTPUT" | grep -qE '^\s+- 1$'; then
    fail "azure: an unquoted integer zone reached the output"
  else
    pass "azure: no unquoted integer zones"
  fi

  # Three optional fields, all unset in the fixture. Emitting any of them
  # empty is worse than omitting it: an empty credentialsMode stops the
  # Cloud Credential Operator, an empty outboundType is not a valid enum.
  for FIELD in cloudName credentialsMode outboundType; do
    if has_string "$OUTPUT" "$FIELD"; then
      fail "azure: $FIELD emitted when unset"
    else
      pass "azure: $FIELD absent when unset"
    fi
  done

  # Other platforms' credentials must not appear
  for NAME in aws-creds gcp-creds vsphere-creds vsphere-certs; do
    if has_string "$OUTPUT" "$NAME"; then
      fail "azure: $NAME present (wrong platform)"
    else
      pass "azure: $NAME absent (correct)"
    fi
  done
fi

# ============================================================================
echo ""
echo "--- Test 21: Single-node OpenShift (Azure) ---"
# ============================================================================
OUTPUT=$(render "$TMPDIR/azure-sno.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for azure-sno: $OUTPUT"
else
  pass "azure-sno template renders successfully"

  if has_kind "$OUTPUT" "MachinePool"; then
    fail "azure-sno: MachinePool present (workers.count is 0)"
  else
    pass "azure-sno: MachinePool absent (correct, workers.count is 0)"
  fi
  if has_string "$OUTPUT" "replicas: 1"; then
    pass "azure-sno: controlPlane replicas = 1"
  else
    fail "azure-sno: controlPlane replicas != 1"
  fi
  if has_string "$OUTPUT" "replicas: 0"; then
    pass "azure-sno: compute replicas = 0"
  else
    fail "azure-sno: compute replicas != 0"
  fi

  # Azure sits with GCP, not AWS: a vnet and its subnets are regional, and
  # outbound is one load balancer per cluster rather than one per zone, so
  # echoing master zones into an empty compute pool buys nothing.
  if has_string "$OUTPUT" "platform: {}"; then
    pass "azure-sno: compute pool is platform: {} (zones buy nothing on Azure)"
  else
    fail "azure-sno: compute pool should be platform: {} on Azure"
  fi
  ZONE_HITS=$(echo "$OUTPUT" | grep -cE '^\s+- "1"$') || true
  if [ "$ZONE_HITS" -eq 1 ]; then
    pass "azure-sno: master zone appears once, not echoed into the compute pool"
  else
    fail "azure-sno: master zone appears ${ZONE_HITS} times, expected 1"
  fi
  if has_string "$OUTPUT" "Standard_D64s_v3"; then
    fail "azure-sno: worker vmSize reached install-config for a pool that is never created"
  else
    pass "azure-sno: worker vmSize absent (pool is never created)"
  fi
  if has_string "$OUTPUT" "Standard_D8s_v3"; then
    pass "azure-sno: master vmSize present"
  else
    fail "azure-sno: master vmSize missing"
  fi
  if has_string "$OUTPUT" "region: eastus"; then
    pass "azure-sno: ClusterDeployment still carries the Azure region"
  else
    fail "azure-sno: ClusterDeployment region missing"
  fi
fi

# ============================================================================
echo ""
echo "--- Test 22: Azure into a pre-existing vnet ---"
# ============================================================================
# The failure this guards against installs clean and breaks later. Hive's
# MachinePool defaults virtualNetwork to ${infraID}-vnet and computeSubnet to
# ${infraID}-worker-subnet -- names a BYO-vnet install never creates -- and it
# does not fall back to install-config. So the installer places the initial
# workers correctly and the cluster comes up healthy, then the first time the
# pool is scaled or a worker is replaced, Hive generates MachineSets pointed
# at a vnet that does not exist.
OUTPUT=$(render "$TMPDIR/azure-vnet.yaml")
if [ $? -ne 0 ]; then
  fail "helm template failed for azure-vnet: $OUTPUT"
else
  pass "azure-vnet template renders successfully"

  # Each value has to land in both install-config and the MachinePool, so the
  # count is the assertion -- "present" would pass with only one of the two.
  for PAIR in "virtualNetwork: byo-vnet" "networkResourceGroupName: byo-net-rg" \
              "computeSubnet: byo-compute-subnet" "outboundType: UserDefinedRouting"; do
    N=$(echo "$OUTPUT" | grep -cF "$PAIR") || true
    if [ "$N" -eq 2 ]; then
      pass "azure-vnet: ${PAIR%%:*} reaches install-config and the MachinePool"
    else
      fail "azure-vnet: ${PAIR%%:*} appears $N time(s), expected 2 (install-config + MachinePool)"
    fi
  done

  # controlPlaneSubnet is the deliberate exception: a worker pool has no
  # control-plane subnet, and Hive's MachinePool has no such field.
  N=$(echo "$OUTPUT" | grep -cF "controlPlaneSubnet: byo-cp-subnet") || true
  if [ "$N" -eq 1 ]; then
    pass "azure-vnet: controlPlaneSubnet stays in install-config only"
  else
    fail "azure-vnet: controlPlaneSubnet appears $N time(s), expected 1"
  fi

  # Naming a vnet without the group or the compute subnet must fail the
  # render rather than silently half-configuring the pool.
  for OMIT in networkResourceGroupName computeSubnet; do
    sed "s|^  ${OMIT}: byo-[a-z-]*|  ${OMIT}: \"\"|" \
      "$TMPDIR/azure-vnet.yaml" > "$TMPDIR/azure-vnet-partial.yaml"
    if render "$TMPDIR/azure-vnet-partial.yaml" >/dev/null 2>&1; then
      fail "azure-vnet: omitting $OMIT alongside virtualNetwork rendered anyway"
    else
      pass "azure-vnet: omitting $OMIT alongside virtualNetwork fails the render"
    fi
  done
fi

# ============================================================================
# Results
# ============================================================================
echo ""
echo "=== Results ==="
echo "  ${PASSED}/${TOTAL} passed, ${FAILED} failed"
if [ "${FAILED}" -eq 0 ]; then
  echo "  TEMPLATE TEST PASSED"
  exit 0
else
  echo "  TEMPLATE TEST FAILED"
  exit 1
fi
