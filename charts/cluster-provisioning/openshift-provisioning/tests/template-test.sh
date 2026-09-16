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
  echo "$1" | grep -c "^kind: $2" || echo 0
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
