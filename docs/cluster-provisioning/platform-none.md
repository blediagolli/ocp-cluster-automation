# Platform None (Agent-Based)

Agent-based provisioning with `platform: none` — the cluster manages no infrastructure directly. This is used for:

- **AWS with sushy-EC2 emulator**: EC2 instances that look like baremetal via a Redfish translation layer
- **Pre-existing VMs**: VMs already created manually or by another tool
- **Edge/remote sites**: any host reachable via Redfish but not managed by a cloud provider

The key difference from `baremetal` is that `platform: none` sets `userManagedNetworking: true` on the AgentClusterInstall — the user is responsible for load balancers, DNS, and network infrastructure.

## provision.yaml

```yaml
provision:
  include: true

cluster:
  name: aws-none-prod
  baseDomain: example.com
  platform: none
  environment: prod
  clusterSet: default
  imageSetRef: img4.22.13-x86-64-appsub
  networkType: OVNKubernetes
  sshPublicKey: "ssh-ed25519 AAAA..."

masters:
  count: 3

workers:
  count: 0

none:
  apiVIPs: []              # empty when VIPs are managed externally (e.g. NLB, F5)
  ingressVIPs: []
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0
  bmc:
    username: admin
    password: password
  hosts:
    - name: aws-none-prod-master-0
      role: master
      bootMACAddress: "02:ff:dc:94:79:5f"
      bmcAddress: "redfish-virtualmedia+https://sushy-ec2.sushy-ec2.svc:8000/redfish/v1/Systems/i-0c7f5f12f9786b5f3"
      automatedCleaningMode: disabled
    - name: aws-none-prod-master-1
      role: master
      bootMACAddress: "06:ff:cf:8a:ce:c7"
      bmcAddress: "redfish-virtualmedia+https://sushy-ec2.sushy-ec2.svc:8000/redfish/v1/Systems/i-026c6c28c35033a71"
      automatedCleaningMode: disabled
    - name: aws-none-prod-master-2
      role: master
      bootMACAddress: "0a:ff:c8:49:0a:71"
      bmcAddress: "redfish-virtualmedia+https://sushy-ec2.sushy-ec2.svc:8000/redfish/v1/Systems/i-08c15c603bfe4590d"
      automatedCleaningMode: disabled

ntp:
  enabled: true
  sources:
    - 169.254.169.123      # AWS time sync service

networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork:
    - cidr: 10.1.0.0/16
```

## How it differs from baremetal

| Behavior | `platform: baremetal` | `platform: none` |
|---|---|---|
| `userManagedNetworking` | `false` (not set) | `true` |
| VIPs | managed by the cluster (keepalived) | user-managed (external LB) |
| DNS | user creates A records for VIPs | user creates A records pointing to LB or individual nodes |
| Load balancing | built-in (HAProxy on nodes) | user-managed (NLB, F5, etc.) |

The provisioning flow, resource types, and chart templates are otherwise identical — the same AgentClusterInstall, InfraEnv, and BareMetalHost templates render for both platforms.

## Sushy-EC2 emulator

For testing agent-based provisioning on AWS without physical hardware, this repo includes a sushy-ec2 emulator chart at `charts/cluster-provisioning/sushy-ec2-emulator/`.

Sushy-EC2 translates Redfish BMC API calls into AWS EC2 API calls — it makes EC2 instances look like baremetal servers with BMC interfaces. This enables the full agent-based provisioning flow on AWS.

### How it works

```
BareMetalHost → Redfish API → sushy-ec2 emulator → EC2 API → AWS
                  (on hub)                            (power on/off, boot ISO, status)
```

The emulator:
- Exposes a Redfish API endpoint on the hub cluster (`sushy-ec2.sushy-ec2.svc:8000`)
- Maps EC2 instance IDs to virtual BMC UUIDs
- Translates power-on/off, boot-from-ISO, and status operations to EC2 API calls
- Builds from source using an OpenShift BuildConfig

### Emulator values

```yaml
# charts/cluster-provisioning/sushy-ec2-emulator/values.yaml
instances:
  i-0c7f5f12f9786b5f3:
    uuid: aws-none-prod-master-0
    role: master
  i-026c6c28c35033a71:
    uuid: aws-none-prod-master-1
    role: master
  i-08c15c603bfe4590d:
    uuid: aws-none-prod-master-2
    role: master
```

BareMetalHost resources point to the emulator's Redfish endpoint instead of a real BMC:
```
redfish-virtualmedia+https://sushy-ec2.sushy-ec2.svc:8000/redfish/v1/Systems/<ec2-instance-id>
```

### Deploying the emulator

The emulator is deployed separately from the cluster provisioning chart. Deploy it before creating the cluster:

1. Set AWS credentials and instance mappings in the emulator chart values
2. Deploy via ArgoCD or Helm
3. Create the cluster's `provision.yaml` with BMC addresses pointing to the emulator

## Resources generated

Same as [baremetal](baremetal.md#resources-generated), with `userManagedNetworking: true` set on the AgentClusterInstall.

## Prerequisites

- Same as [baremetal prerequisites](baremetal.md#prerequisites), plus:
- User-managed DNS and load balancing for API and ingress endpoints
- For sushy-EC2: AWS credentials with EC2 permissions, EC2 instances pre-created, sushy-ec2 emulator chart deployed on the hub

## Troubleshooting

Same troubleshooting steps as [baremetal](baremetal.md#troubleshooting). Additional checks for sushy-EC2:

1. Verify the emulator pod is running:
   ```bash
   oc get pods -n sushy-ec2
   ```

2. Test Redfish connectivity from the hub:
   ```bash
   curl -k https://sushy-ec2.sushy-ec2.svc:8000/redfish/v1/Systems/
   ```

3. Check emulator logs for EC2 API errors:
   ```bash
   oc logs -n sushy-ec2 deploy/sushy-ec2
   ```
