# Baremetal Provisioning with Agent-Based Installer

This guide covers provisioning OpenShift clusters on baremetal (and platform-none) infrastructure using ACM's agent-based installer, driven entirely by GitOps.

## Overview

Baremetal provisioning uses the same GitOps workflow as cloud provisioning ([Part 1](Part-1.md)) — define `conf.yaml` and `provision.yaml`, push to git, and the `cluster-provisioning` ApplicationSet handles the rest. The difference is the provisioning flow:

1. The Helm chart creates ACM/Hive resources including BareMetalHost and InfraEnv CRs
2. The InfraEnv generates a discovery ISO customized for the cluster
3. Each BareMetalHost connects to the physical server's BMC via Redfish
4. The BMC boots the server from the discovery ISO (virtual media)
5. The Assisted Installer agent registers the host with ACM
6. Once all hosts are discovered and validated, the OpenShift install begins

```
Git push → ArgoCD → ACM/Hive
                       │
                       ├── InfraEnv → discovery ISO
                       ├── BareMetalHost → Redfish → BMC → boot ISO
                       ├── Assisted Installer → validate hosts → install
                       └── ClusterDeployment → import to ACM
```

## provision.yaml for baremetal

The `provision.yaml` for a baremetal cluster defines the platform, networking, and host inventory:

```yaml
provision:
  include: true

cluster:
  name: edge-01
  baseDomain: example.com
  platform: baremetal
  environment: prod
  clusterSet: default
  imageSetRef: img4.17.0-x86-64
  networkType: OVNKubernetes
  sshPublicKey: "ssh-ed25519 AAAA..."

masters:
  count: 3

baremetal:
  apiVIPs:
    - 10.0.0.100
  ingressVIPs:
    - 10.0.0.101
  hosts:
    - name: master-0
      role: master
      bmcAddress: redfish-virtualmedia://bmc-01.example.com/redfish/v1/Systems/1
      bootMACAddress: "aa:bb:cc:dd:ee:00"
    - name: master-1
      role: master
      bmcAddress: redfish-virtualmedia://bmc-02.example.com/redfish/v1/Systems/1
      bootMACAddress: "aa:bb:cc:dd:ee:01"
    - name: master-2
      role: master
      bmcAddress: redfish-virtualmedia://bmc-03.example.com/redfish/v1/Systems/1
      bootMACAddress: "aa:bb:cc:dd:ee:02"

networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork:
    - cidr: 10.0.0.0/24

nmstate:
  - name: master-0
    interfaces:
      - name: eno1
        type: ethernet
        state: up
        ipv4:
          enabled: true
          address:
            - ip: 10.0.0.10
              prefix-length: 24
          dhcp: false
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 10.0.0.1
          next-hop-interface: eno1
    dns-resolver:
      config:
        server:
          - 10.0.0.1
```

## Resources generated

The provisioning chart generates these resources for an agent-based install:

| Resource | Purpose |
|---|---|
| Namespace | Cluster namespace on the hub |
| ClusterDeployment | Hive cluster definition (`platform: none` or `baremetal`) |
| AgentClusterInstall | Networking config (VIPs, cluster/service/machine networks) |
| InfraEnv | Discovery ISO configuration, SSH key, pull secret |
| NMStateConfig | Per-host static network configuration |
| BareMetalHost | BMC connection (Redfish address, credentials, boot MAC) |
| ManagedCluster | ACM registration |
| KlusterletAddonConfig | ACM addon config |
| Secrets | BMC credentials per host, pull secret, SSH key |

The chart uses `cluster.platform` to determine which templates to render. Agent-based templates are gated by the `isAgent` helper in `_helpers.tpl`.

## BMC credentials

Each BareMetalHost needs BMC credentials in a Secret. The chart generates these from `provision.yaml`. Each host references its own secret (`<host-name>-bmc-credentials`).

BMC addresses use the Redfish virtual media protocol:
```
redfish-virtualmedia://<bmc-host>/redfish/v1/Systems/1
```

## Sushy-EC2 emulator

For testing baremetal provisioning workflows without physical hardware, this repo includes a sushy-ec2 emulator chart at `charts/cluster-provisioning/sushy-ec2-emulator/`.

Sushy-EC2 translates Redfish BMC API calls into AWS EC2 API calls — it makes EC2 instances look like baremetal servers with BMC interfaces. This allows testing the full agent-based provisioning flow on AWS.

The emulator:
- Exposes a Redfish API endpoint on the hub cluster
- Maps EC2 instance IDs to virtual BMC UUIDs
- Translates power-on/off, boot-from-ISO, and status operations to EC2 API calls
- Builds from source using an OpenShift BuildConfig

```yaml
# sushy-ec2 emulator values
instances:
  i-0c7f5f12f9786b5f3:
    uuid: my-cluster-master-0
    role: master
  i-0a1b2c3d4e5f67890:
    uuid: my-cluster-master-1
    role: master
```

BareMetalHost resources then point to the emulator's Redfish endpoint instead of a real BMC.

## Troubleshooting

### Host not discovering

1. Check InfraEnv status — the discovery ISO URL should be populated
2. Check BareMetalHost status — look for BMC connection errors
3. Verify BMC network connectivity from the hub cluster (port 443 for Redfish, port 6183 for virtual media)
4. Check that `bootMACAddress` matches the actual NIC

### Agent not registering

1. Check that the discovery ISO booted successfully (BMC virtual console if available)
2. Verify NMStateConfig gives the host network connectivity to the hub
3. Check the assisted-service logs on the hub: `oc logs -n multicluster-engine deploy/assisted-service`

### Install stuck

1. Check AgentClusterInstall status and conditions
2. Verify all hosts passed validation (minimum CPU, memory, disk)
3. Check that API and ingress VIPs are reachable from the host network

## Prerequisites

- OpenShift hub cluster with ACM and the Central Infrastructure Management service enabled
- BMC access via Redfish to all target hosts
- Network connectivity: hub → BMC (Redfish), hosts → hub (assisted-service registration)
- DNS records for API and ingress VIPs
- For sushy-ec2: AWS credentials with EC2 permissions, EC2 instances pre-created

## Further reading

- [Part 1: Provisioning clusters with GitOps + ACM](Part-1.md)
- [Part 2: Configuring clusters with ApplicationSets and Helm](Part-2.md)
- [Day 2 cluster configuration guide](day2-cluster-config.md)
