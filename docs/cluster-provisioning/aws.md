# AWS (IPI)

Standard IPI provisioning on AWS. Hive creates EC2 instances, VPCs, Route53 records, and runs the OpenShift installer.

## provision.yaml

```yaml
provision:
  include: true

cluster:
  name: example-cluster
  baseDomain: example.com
  platform: aws
  environment: dev
  clusterSet: default
  imageSetRef: img4.22.13-x86-64-appsub
  networkType: OVNKubernetes
  sshPublicKey: "ssh-ed25519 AAAA..."

fleet:
  operatorClusterType: dev
  operatorProfile: ocp-4.22

masters:
  count: 3

workers:
  count: 3

aws:
  region: us-east-2
  masters:
    instanceType: m5.xlarge
    zones: []                # empty = let installer pick AZs
    rootVolume:
      size: 120
      type: gp3
  workers:
    instanceType: m5.xlarge
    zones: []
    rootVolume:
      size: 120
      type: gp3
```

### Availability zones

To pin masters or workers to specific AZs:

```yaml
aws:
  masters:
    zones:
      - us-east-2a
      - us-east-2b
      - us-east-2c
```

When `zones` is empty, the installer picks AZs automatically.

## Single-node OpenShift

One master, no workers. `masters.count: 1` is the whole switch — see
[cluster topology](README.md#cluster-topology) for what the chart does with
it and for the compact (3/0) variant.

```yaml
provision:
  include: true

cluster:
  name: sno-dev
  baseDomain: example.com
  platform: aws
  environment: dev
  clusterSet: default
  imageSetRef: img4.22.13-x86-64-appsub
  networkType: OVNKubernetes
  sshPublicKey: "ssh-ed25519 AAAAYOUR_SSH_PUBLIC_KEY sno-dev-cluster"

fleet:
  operatorClusterType: dev
  operatorProfile: ocp-4.22

masters:
  count: 1

workers:
  count: 0

aws:
  region: us-east-2
  masters:
    instanceType: m5.2xlarge     # 8 vCPU / 32 GiB — the SNO floor
    zones:
      - us-east-2a               # a single-node cluster lives in one AZ
    rootVolume:
      size: 200
      type: gp3
  workers:                       # never instantiated; keys are read anyway
    instanceType: m5.2xlarge
    zones: []
    rootVolume:
      size: 120
      type: gp3
```

The default `m5.xlarge` is 4 vCPU / 16 GiB — half the memory a single node
needs, since it is running the control plane and the workload on one
instance. Pin `aws.masters.zones` to a single AZ: it keeps the node in the
same place across a reinstall, and the chart echoes those zones onto the
compute pool, which is what stops the installer subnetting every AZ in the
region and allocating an Elastic IP per NAT gateway. Leave it empty and a
one-node cluster costs three EIPs instead of one.

Hive still creates a temporary bootstrap instance, so the install briefly
runs two EC2 instances. `bootstrapInPlace` is for ISO-based single-node
installs on `platform: none`, not for AWS.

### What differs from a 3/3 cluster

- No MachinePool — nothing to scale, and a zero-replica pool would leave Hive
  reconciling empty MachineSets.
- `compute[0].platform` carries the master zones and nothing else, rather
  than the full AWS worker block. The installer validates instance types and
  volume sizes it is given even for a pool it will never create, so a stale
  worker type can fail the install — but the zones have to stay, because the
  machine pools are what bound the AZs the VPC spans. An unbounded compute
  pool subnets every AZ in the region and hangs a NAT gateway, and therefore
  an Elastic IP, off each one: three EIPs for a one-node cluster, against a
  default regional quota of five.
Day-2 charts are a separate decision. Start a new single-node cluster with
`platformCharts: []` and `operatorCharts: []`, provision it, confirm it is
healthy, then add charts one at a time — every chart lands on the same node
as the control plane, so a bad one degrades the cluster rather than one
worker of several. Three to think twice about:

- `machine-health-checks`: remediation on a one-node cluster means rebooting
  the cluster to fix the cluster.
- `etcd-defrag`: a single-member etcd defrags with the API server offline, so
  the scheduled job is an outage.
- `odf`: wants three nodes and its own dedicated capacity. `lvm`
  thin-provisions the node's own disk instead.

## Resources generated

| Resource | Purpose |
|---|---|
| Namespace | Cluster namespace on the hub |
| ClusterDeployment | Hive cluster definition with `platform.aws` |
| MachinePool | Worker node pool (instance type, zones, volume config) |
| ManagedCluster | ACM registration |
| KlusterletAddonConfig | ACM addon config |
| Secret (`*-aws-creds`) | AWS access key and secret key |
| Secret (`*-install-config`) | Generated install-config.yaml |
| Secret (`*-pull-secret`) | Container registry pull secret |
| Secret (`*-ssh-private-key`) | SSH key for node access |

## How it works

1. ArgoCD syncs the provisioning chart, creating the resources above
2. Hive creates a provisioning pod that runs the OpenShift installer
3. The installer creates a VPC, subnets, security groups, Route53 records, EC2 instances, and ELBs
4. OpenShift is installed on the EC2 instances
5. Hive marks the ClusterDeployment as installed
6. ACM imports the cluster via ManagedCluster

## Custom manifests

For day-0 customizations (NTP, kernel args, custom MachineConfigs), use the `customManifests` block. These are injected into the install via a ConfigMap referenced by the ClusterDeployment's `manifestsConfigMapRef`. See [cross-platform features](README.md#custom-manifests-ipi-only).

## Prerequisites

- AWS credentials with permissions for: EC2, VPC, Route53, ELB, S3, IAM
- A Route53 hosted zone for the base domain
- ClusterImageSet matching `imageSetRef`

## Troubleshooting

1. Check ClusterDeployment status and conditions:
   ```bash
   oc get clusterdeployment <name> -n <name> -o yaml
   ```

2. Check the provisioning pod logs:
   ```bash
   oc logs -n <name> -l hive.openshift.io/cluster-deployment-name=<name>
   ```

3. Common issues:
   - **InstallError**: check AWS credentials permissions
   - **DNSNotReady**: verify Route53 hosted zone exists and credentials can manage it
   - **InfrastructureLimitExceeded**: check EC2 instance limits in the target region
