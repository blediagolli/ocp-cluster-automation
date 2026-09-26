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
