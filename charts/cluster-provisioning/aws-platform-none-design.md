# OpenShift on AWS with Platform None (Agent-Based Install)

## Overview

Deploy OpenShift on AWS EC2 instances using the agent-based installer instead
of AWS IPI. The cluster has no cloud provider integration — infrastructure
(VPC, LBs, DNS, storage) is provisioned and managed independently.

The recommended approach uses **sushy-emulator with a custom EC2 driver** to
expose a Redfish BMC API for EC2 instances. This lets the full
`BareMetalHost` workflow run unchanged — the same chart templates, the same
Metal3 flow, the same agent-based install — just backed by EC2 instead of
physical hardware.

## Why

- Test baremetal/agent-based workflows without physical hardware
- Simulate disconnected or air-gapped environments on AWS
- Avoid cloud provider lock-in (no AWS-specific operators)
- Full control over networking, load balancing, and storage
- Match production patterns where clusters run on bare metal

## Architecture

```
                   Route53
                  ┌───────────────────────────┐
                  │ api.cluster.example.com    │──► NLB (TCP 6443)
                  │ *.apps.cluster.example.com │──► NLB (TCP 443/80)
                  └───────────────────────────┘

                        VPC (10.0.0.0/16)
         ┌──────────────────┬──────────────────┐
         │   Subnet AZ-a    │   Subnet AZ-b    │
         │                  │                  │
         │  ┌────────────┐  │  ┌────────────┐  │
         │  │  master-0   │  │  │  master-1   │  │
         │  │  m5.xlarge  │  │  │  m5.xlarge  │  │
         │  └────────────┘  │  └────────────┘  │
         │                  │                  │
         │  ┌────────────┐  │  ┌────────────┐  │
         │  │  master-2   │  │  │  worker-0   │  │
         │  │  m5.xlarge  │  │  │  m5.xlarge  │  │
         │  └────────────┘  │  └────────────┘  │
         └──────────────────┴──────────────────┘
                ▲                     ▲
                │  Redfish API        │
                │  (power/media)      │
         ┌──────────────────────────────────────┐
         │         Hub Cluster (ACM)            │
         │                                      │
         │  ┌──────────────────────────────┐    │
         │  │  sushy-emulator (EC2 driver) │    │
         │  │  Redfish → EC2 API           │    │
         │  └──────────────┬───────────────┘    │
         │                 │                    │
         │  BareMetalHost ─┘ (BMC address)      │
         │  InfraEnv ──► Discovery ISO          │
         │  AgentClusterInstall                 │
         │  ClusterDeployment (platform: none)  │
         │  Agents (auto-registered)            │
         └──────────────────────────────────────┘
```

## AWS Infrastructure (Pre-provisioned)

These resources must exist before the agent-based install begins. Provisioned
via Terraform, CloudFormation, or manually.

### Networking

| Resource | Details |
|----------|---------|
| VPC | Single VPC, e.g. `10.0.0.0/16` |
| Subnets | 1-3 private subnets (one per AZ for HA) |
| Security Groups | Allow 6443 (API), 22623 (MCS), 443/80 (ingress), 9000-9999 (node ports), all inter-node traffic |
| Internet Gateway | For public subnets (if not disconnected) |
| NAT Gateway | For private subnets needing outbound access |

### Load Balancers

| LB | Targets | Ports |
|----|---------|-------|
| API NLB | master-0, master-1, master-2 | TCP 6443, TCP 22623 |
| Ingress NLB | worker-0, worker-1, worker-2 (or masters if compact) | TCP 443, TCP 80 |

### DNS (Route53)

| Record | Type | Target |
|--------|------|--------|
| `api.<cluster>.<domain>` | A/ALIAS | API NLB |
| `api-int.<cluster>.<domain>` | A/ALIAS | API NLB (internal) |
| `*.apps.<cluster>.<domain>` | A/ALIAS | Ingress NLB |

### EC2 Instances

| Role | Count | Type | Storage | Notes |
|------|-------|------|---------|-------|
| Master | 3 | m5.xlarge | 120 GB gp3 | Can also run workloads in compact (3-node) |
| Worker | 0-N | m5.xlarge | 120 GB gp3 | Optional, 0 for compact cluster |

## BMC Emulation with Sushy (Recommended)

The key challenge with agent-based installs on AWS is that EC2 instances lack
a BMC (Baseboard Management Controller). Without a BMC, `BareMetalHost`
resources cannot manage power or boot media — breaking the standard Metal3
workflow.

**sushy-emulator** solves this by providing a Redfish API that translates BMC
operations into EC2 API calls. A custom EC2 driver maps each Redfish action to
its AWS equivalent:

### Redfish-to-EC2 Operation Mapping

| Redfish Operation | EC2 API Call | Notes |
|---|---|---|
| Power On | `ec2:StartInstances` | Starts a stopped instance |
| Power Off (graceful) | `ec2:StopInstances` | Graceful shutdown via ACPI |
| Power Off (force) | `ec2:StopInstances (Force=True)` | Immediate stop |
| Reset | `ec2:RebootInstances` | Hard reboot |
| Get Power State | `ec2:DescribeInstances` | Maps `running`→`On`, `stopped`→`Off` |
| Insert Virtual Media | Attach EBS from ISO snapshot | Creates volume from snapshot, attaches to instance |
| Eject Virtual Media | Detach EBS volume | Detaches and optionally deletes the volume |
| Set Boot Source Override | Modify user-data / stop+start | Sets boot order to attached media |
| Get System Info | `ec2:DescribeInstances` | Returns instance type, state, IDs |

### How It Works

1. **sushy-emulator** runs as a Deployment in the hub cluster (one per
   cluster namespace, or a shared instance)
2. It is configured with AWS credentials and a mapping of Redfish system UUIDs
   to EC2 instance IDs
3. Each `BareMetalHost` resource points to the emulator via its BMC address:

   ```
   redfish-virtualmedia+https://sushy-ec2.<namespace>.svc:8000/redfish/v1/Systems/<instance-id>
   ```

4. When Metal3 (the bare metal operator on the hub) needs to power on a host
   or attach the discovery ISO, it sends standard Redfish requests to the
   emulator
5. The emulator translates those into EC2 API calls (start instance, attach
   EBS volume from ISO snapshot, etc.)
6. The EC2 instance boots from the discovery ISO, the agent registers with the
   hub, and the standard agent-based install proceeds

### BMC Address Format

Each `BareMetalHost` uses this address format:

```
redfish-virtualmedia+https://sushy-ec2.<namespace>.svc:8000/redfish/v1/Systems/<instance-id>
```

For example:

```yaml
# In baremetal.hosts values:
- name: master-0
  role: master
  bootMACAddress: "0a:1b:2c:3d:4e:01"
  bmcAddress: "redfish-virtualmedia+https://sushy-ec2.aws-none-test.svc:8000/redfish/v1/Systems/i-0f73a7c7762c67aa9"
  bmcUsername: "admin"        # passed to sushy, used for basic auth
  bmcPassword: "password"     # passed to sushy, used for basic auth
```

### sushy-emulator Deployment

The emulator runs as a pod in the cluster namespace on the hub:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sushy-ec2
  namespace: <cluster-namespace>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sushy-ec2
  template:
    spec:
      containers:
        - name: sushy-emulator
          image: <custom-sushy-ec2-image>
          ports:
            - containerPort: 8000
          env:
            - name: AWS_REGION
              value: us-east-2
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: <cluster>-aws-creds
                  key: aws_access_key_id
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: <cluster>-aws-creds
                  key: aws_secret_access_key
            - name: SUSHY_EC2_ISO_SNAPSHOT_ID
              value: <snap-id-of-discovery-iso>
          volumeMounts:
            - name: config
              mountPath: /etc/sushy
      volumes:
        - name: config
          configMap:
            name: sushy-ec2-config
---
apiVersion: v1
kind: Service
metadata:
  name: sushy-ec2
  namespace: <cluster-namespace>
spec:
  selector:
    app: sushy-ec2
  ports:
    - port: 8000
      targetPort: 8000
```

### Advantages Over Direct ISO Boot

| Aspect | Direct ISO/AMI Boot | Sushy BMC Emulation |
|--------|---------------------|---------------------|
| BareMetalHost resources | Not used | **Used** (full Metal3 flow) |
| NMStateConfig | Not used | **Used** (if needed) |
| BMC credentials in chart | Not used | **Used** (standard pattern) |
| Power management | Manual EC2 start/stop | **Automatic** via Metal3 |
| ISO attachment | Manual AMI conversion | **Automatic** via virtual media |
| Day-2 node replacement | Manual | **Metal3-driven** (create BMH → auto-provision) |
| Chart template reuse | Partial | **Full** (identical to physical bare metal) |
| Matches production flow | No | **Yes** |

## Boot Process (Fallback — Without Sushy)

If sushy-emulator is not deployed, EC2 instances must be booted manually from
the discovery ISO. This path skips `BareMetalHost` resources entirely.

### Option A: Custom AMI from Discovery ISO

1. Hub creates `InfraEnv` → generates discovery ISO URL
2. Download the ISO
3. Convert ISO to AMI using `aws ec2 import-snapshot` + `register-image`
4. Launch EC2 instances from the custom AMI
5. Agents boot, auto-register with the hub
6. Install proceeds

```bash
# Download discovery ISO from InfraEnv
ISO_URL=$(oc get infraenv <cluster> -n <cluster> -o jsonpath='{.status.isoDownloadURL}')
curl -o discovery.iso "$ISO_URL"

# Upload to S3
aws s3 cp discovery.iso s3://<bucket>/discovery.iso

# Import as snapshot
aws ec2 import-snapshot \
  --disk-container "Format=RAW,Url=s3://<bucket>/discovery.iso"

# Register as AMI
aws ec2 register-image \
  --name "discovery-<cluster>" \
  --root-device-name /dev/sda1 \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={SnapshotId=<snap-id>}"

# Launch instances from AMI
aws ec2 run-instances --image-id <ami-id> --instance-type m5.xlarge ...
```

### Option B: iPXE Boot

1. Configure EC2 instances to boot via iPXE
2. iPXE chain-loads the discovery ISO kernel/initrd
3. Requires a TFTP/HTTP server accessible from the VPC
4. More complex setup, but avoids AMI conversion

### Option C: Manual Attach ISO

1. Upload ISO as a secondary EBS volume
2. Boot instance from the ISO volume
3. Simplest for testing, doesn't scale

## Install Flow on the Hub

### With Sushy (Recommended)

```
1.  Create namespace             ← Helm chart
2.  Create ClusterDeployment     ← Helm chart (platform: none, installed: false)
3.  Create AgentClusterInstall   ← Helm chart (with VIPs from NLBs)
4.  Create InfraEnv              ← Helm chart (generates discovery ISO)
5.  Create pull-secret           ← Helm chart
6.  Create BareMetalHost(s)      ← Helm chart (BMC → sushy-ec2 service)
7.  Create BMC credential(s)     ← Helm chart (per-host secrets)
    --- pre-provisioned (Terraform) ---
8.  AWS infra exists             ← Terraform (VPC, LBs, DNS, SGs, EC2 instances in stopped state)
9.  Deploy sushy-emulator        ← Helm chart or Terraform (with ISO snapshot ID)
    --- automatic from here ---
10. Metal3 powers on hosts       ← BareMetalHost → sushy → ec2:StartInstances
11. Metal3 attaches ISO          ← BareMetalHost → sushy → EBS attach from snapshot
12. Instances boot from ISO      ← Discovery agent starts
13. Agents register with hub     ← Automatic (agents phone home)
14. Agents approved              ← Automatic (label match) or manual
15. Install begins               ← AgentClusterInstall drives the install
16. Bootstrap complete           ← Control plane is up
17. Workers join                 ← Workers approved and join
18. Install complete             ← ClusterDeployment status: Installed
```

### Without Sushy (Fallback)

```
1.  Create namespace             ← Helm chart
2.  Create ClusterDeployment     ← Helm chart (platform: none, installed: false)
3.  Create AgentClusterInstall   ← Helm chart (with VIPs from NLBs)
4.  Create InfraEnv              ← Helm chart (generates ISO)
5.  Create pull-secret           ← Helm chart
    --- manual / Terraform step ---
6.  Provision AWS infra          ← Terraform (VPC, LBs, DNS, SGs)
7.  Convert ISO → AMI            ← Script
8.  Launch EC2 instances         ← Terraform (boot from AMI)
    --- automatic from here ---
9.  Agents register              ← Automatic (agents phone home to hub)
10. Agents approved              ← Automatic (if labels match) or manual
11. Install begins               ← AgentClusterInstall drives the install
12. Bootstrap complete           ← Control plane is up
13. Workers join                 ← Workers approved and join
14. Install complete             ← ClusterDeployment status: Installed
```

## What the Helm Chart Already Handles

| Resource | Template | With Sushy | Without Sushy |
|----------|----------|------------|---------------|
| Namespace | namespace.yaml | Yes | Yes |
| ClusterDeployment | clusterdeployment.yaml | Yes (platform: none) | Yes (platform: none) |
| AgentClusterInstall | agentclusterinstall.yaml | Yes | Yes |
| InfraEnv | infraenv.yaml | Yes | Yes |
| Pull Secret | secret-pull-secret.yaml | Yes | Yes |
| ManagedCluster | managedcluster.yaml | Yes | Yes |
| KlusterletAddonConfig | klusteraddonconfig.yaml | Yes | Yes |
| BareMetalHost | baremetalhost.yaml | **Yes** (BMC → sushy) | No |
| NMStateConfig | nmstateconfig.yaml | **Yes** (if needed) | No |
| BMC Credentials | secret-bmc-credentials.yaml | **Yes** | No |
| Install Config | secret-install-config.yaml | No (agent-based) | No (agent-based) |
| SSH Private Key | secret-ssh-private-key.yaml | No (agent-based) | No (agent-based) |

## What's Missing / Needs Adding

### 1. sushy-emulator EC2 Driver

A custom sushy-tools driver that translates Redfish operations to EC2 API
calls. Lives in `tools/sushy-ec2-driver/` in this repo.

- Python module implementing the sushy-tools driver interface
- Docker image packaging the driver with sushy-emulator
- Handles: power management, virtual media (ISO snapshot → EBS), system info

### 2. sushy-emulator Helm Templates (Optional)

Templates to deploy the sushy-emulator alongside the cluster resources. Could
be added to the provisioning chart with a toggle:

```yaml
sushyEmulator:
  enabled: false
  image: quay.io/<org>/sushy-ec2:latest
  isoSnapshotId: ""
```

### 3. AWS Infrastructure Provisioning (Outside Chart)

The Helm chart manages Kubernetes resources on the hub. AWS infra must be
provisioned separately. Options:

- **Terraform module** — most flexible, version-controlled, reusable
- **CloudFormation stack** — AWS-native, can be referenced from chart values
- **Crossplane** — Kubernetes-native, could live alongside the chart

Recommendation: **Terraform module** in this repo under
`terraform/aws-platform-none/` with variables that match the chart's values.

### 4. ISO-to-Snapshot Automation

A script or CI job that:
1. Waits for InfraEnv to generate the ISO URL
2. Downloads the ISO and uploads to S3
3. Imports as an EBS snapshot
4. Passes the snapshot ID to sushy-emulator config (or Terraform)

### 5. Agent Approval Automation

By default, agents need manual approval. Options:
- Auto-approve via label matching (already supported by InfraEnv `agentLabelSelector`)
- ClusterImageSet-based auto-approval
- Manual `oc approve agent`

### 6. Chart Values for This Pattern

```yaml
cluster:
  name: aws-none-test
  baseDomain: sandbox3321.opentlc.com
  platform: none
  imageSetRef: img4.22.13-x86-64-appsub
  sshPublicKey: "ssh-ed25519 ..."

none:
  apiVIPs:
    - 10.0.1.100     # API NLB internal IP or leave empty
  ingressVIPs:
    - 10.0.1.101     # Ingress NLB internal IP or leave empty
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0   # compact cluster
  hosts:
    - name: master-0
      role: master
      bootMACAddress: "0a:1b:2c:3d:4e:01"
      bmcAddress: "redfish-virtualmedia+https://sushy-ec2.aws-none-test.svc:8000/redfish/v1/Systems/i-0abc123"
    - name: master-1
      role: master
      bootMACAddress: "0a:1b:2c:3d:4e:02"
      bmcAddress: "redfish-virtualmedia+https://sushy-ec2.aws-none-test.svc:8000/redfish/v1/Systems/i-0def456"
    - name: master-2
      role: master
      bootMACAddress: "0a:1b:2c:3d:4e:03"
      bmcAddress: "redfish-virtualmedia+https://sushy-ec2.aws-none-test.svc:8000/redfish/v1/Systems/i-0ghi789"

sushyEmulator:
  enabled: true
  image: quay.io/<org>/sushy-ec2:latest
  isoSnapshotId: snap-0abc123def456

networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork:
    - cidr: 10.0.0.0/16
```

## Day-2 Operations Without Cloud Provider

| Concern | IPI (cloud-aware) | Platform None (manual) | Platform None + Sushy |
|---------|-------------------|----------------------|----------------------|
| Load Balancing | AWS ELB auto-created | NLB pre-created, or MetalLB | NLB pre-created, or MetalLB |
| DNS | Auto-managed Route53 | Manual Route53 records | Manual Route53 records |
| Storage | EBS CSI auto-installed | Manual EBS CSI, local-storage, or ODF | Manual EBS CSI, local-storage, or ODF |
| Node Scaling | MachineSet / Machine API | Manual EC2 + agent approval | Add BMH → Metal3 auto-provisions |
| Node Replacement | Automatic via Machine API | Manual: launch new EC2, approve agent, drain old | Add BMH → auto-provision, drain old |
| Ingress | AWS LB auto-configured | Manual NLB target group or MetalLB | Manual NLB target group or MetalLB |
| Certificates | Auto-renewed | Auto-renewed (same) | Auto-renewed (same) |

## Disconnected Variant

For a disconnected simulation on AWS:

1. No Internet Gateway / NAT Gateway on cluster subnets
2. VPC endpoints for S3, EC2, ELB (if needed for Terraform)
3. Mirror registry in the VPC (Quay mirror or simple registry)
4. Set `proxy`, `additionalTrustBundle`, `imageContentSources` in chart values
5. Discovery ISO includes the mirror config via `ignitionConfigOverride`

## Recommended Next Steps

1. **Build sushy EC2 driver** — implement the custom driver in
   `tools/sushy-ec2-driver/`, package as a container image
2. **Terraform module** — create `terraform/aws-platform-none/` to provision
   VPC, NLBs, DNS, SGs, and EC2 instances (in stopped state, ready for Metal3)
3. **ISO-to-snapshot script** — automate the discovery ISO → EBS snapshot
   pipeline
4. **Add sushy-emulator templates** — optional Helm templates in the
   provisioning chart to deploy the emulator pod + service
5. **End-to-end test** — deploy a 3-node compact cluster on AWS using the full
   BMH + sushy flow
6. **CI pipeline** — wire into a CI job for repeatable testing
