# Baremetal (Agent-Based)

Agent-based provisioning for physical servers. The Assisted Installer discovers hosts via a discovery ISO, validates them, and runs the install.

## Provisioning flow

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

## provision.yaml

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

workers:
  count: 0

baremetal:
  apiVIPs:
    - 10.0.0.100
  ingressVIPs:
    - 10.0.0.101
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 0
  bmc:
    username: admin
    password: ""
  hosts:
    - name: master-0
      role: master
      bootMACAddress: "aa:bb:cc:dd:ee:00"
      bmcAddress: "idrac-virtualmedia+https://bmc-01.example.com/redfish/v1/Systems/System.Embedded.1"
      bmcInsecure: true
      automatedCleaningMode: metadata
    - name: master-1
      role: master
      bootMACAddress: "aa:bb:cc:dd:ee:01"
      bmcAddress: "idrac-virtualmedia+https://bmc-02.example.com/redfish/v1/Systems/System.Embedded.1"
    - name: master-2
      role: master
      bootMACAddress: "aa:bb:cc:dd:ee:02"
      bmcAddress: "idrac-virtualmedia+https://bmc-03.example.com/redfish/v1/Systems/System.Embedded.1"

networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork:
    - cidr: 10.0.0.0/24
```

## Static network configuration (NMState)

For hosts that need static IPs, bonding, or VLANs, add `nmstate` to each host entry:

```yaml
baremetal:
  hosts:
    - name: master-0
      role: master
      bootMACAddress: "b4:96:91:e9:48:e4"
      bmcAddress: "idrac-virtualmedia+https://bmc-01.example.com/redfish/v1/Systems/System.Embedded.1"
      nmstate:
        config:
          interfaces:
            - name: bond0
              type: bond
              state: up
              ipv4:
                enabled: true
                address:
                  - ip: 10.0.0.10
                    prefix-length: 24
                dhcp: false
              link-aggregation:
                mode: 802.3ad
                options:
                  miimon: "100"
                slaves:
                  - ens2f0
                  - ens2f1
          dns-resolver:
            config:
              search:
                - internal.example.com
              server:
                - 10.0.0.1
          routes:
            config:
              - destination: 0.0.0.0/0
                next-hop-address: 10.0.0.1
                next-hop-interface: bond0
                table-id: 254
        interfaces:
          - name: ens2f0
            macAddress: "b4:96:91:e9:48:e4"
          - name: ens2f1
            macAddress: "b4:96:91:e9:48:e5"
```

The chart generates an NMStateConfig CR per host. The InfraEnv selects NMStateConfigs via label matching, so the discovery ISO includes the correct network configuration for each host.

## BMC credentials

Each BareMetalHost needs BMC credentials. The chart creates a Secret per host (`<host-name>-bmc-credentials`). By default, all hosts use the shared `baremetal.bmc.username` and `baremetal.bmc.password`. Per-host overrides are supported:

```yaml
baremetal:
  bmc:
    username: admin
    password: default-password
  hosts:
    - name: master-0
      bmcUsername: special-user     # overrides bmc.username for this host
      bmcPassword: special-pass    # overrides bmc.password for this host
```

### BMC address formats

BMC addresses use the Redfish virtual media protocol. The prefix depends on the hardware vendor:

```
idrac-virtualmedia+https://<bmc-host>/redfish/v1/Systems/System.Embedded.1    # Dell iDRAC
redfish-virtualmedia+https://<bmc-host>/redfish/v1/Systems/1                  # generic Redfish
```

## Dual-stack networking

The chart supports dual-stack (IPv4 + IPv6) networking:

```yaml
baremetal:
  apiVIPs:
    - 10.0.0.100
    - "2610:30:401C:2352::10"
  ingressVIPs:
    - 10.0.0.101
    - "2610:30:401C:2352::11"

networking:
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
    - cidr: "fd01::/48"
      hostPrefix: 64
  serviceNetwork:
    - 172.30.0.0/16
    - "fd02::/112"
  machineNetwork:
    - cidr: 10.0.0.0/24
    - cidr: "2610:30:401C:2352::/64"
```

## Resources generated

| Resource | Purpose |
|---|---|
| Namespace | Cluster namespace on the hub |
| ClusterDeployment | Hive cluster definition with `platform.agentBareMetal` |
| AgentClusterInstall | Networking config (VIPs, cluster/service/machine networks) |
| InfraEnv | Discovery ISO configuration, SSH key, pull secret |
| NMStateConfig | Per-host static network configuration (if nmstate defined) |
| BareMetalHost | BMC connection (Redfish address, credentials, boot MAC) per host |
| ManagedCluster | ACM registration |
| KlusterletAddonConfig | ACM addon config |
| Secret (`*-bmc-credentials`) | BMC credentials per host |
| Secret (`*-pull-secret`) | Container registry pull secret |

## Prerequisites

- OpenShift hub with ACM and Central Infrastructure Management service enabled
- BMC access via Redfish to all target hosts (port 443 for Redfish, port 6183 for virtual media)
- Network connectivity: hub to BMCs, hosts to hub (assisted-service registration)
- DNS records for API and ingress VIPs
- ClusterImageSet matching `imageSetRef`

## Troubleshooting

### Host not discovering

1. Check InfraEnv status — the discovery ISO URL should be populated:
   ```bash
   oc get infraenv <name> -n <name> -o jsonpath='{.status.isoDownloadURL}'
   ```

2. Check BareMetalHost status — look for BMC connection errors:
   ```bash
   oc get bmh -n <name> -o wide
   ```

3. Verify BMC network connectivity from the hub cluster (port 443 for Redfish, port 6183 for virtual media)

4. Check that `bootMACAddress` matches the actual NIC on the server

### Agent not registering

1. Check that the discovery ISO booted successfully (BMC virtual console if available)
2. Verify NMStateConfig gives the host network connectivity to the hub
3. Check the assisted-service logs:
   ```bash
   oc logs -n multicluster-engine deploy/assisted-service
   ```

### Install stuck

1. Check AgentClusterInstall status and conditions:
   ```bash
   oc get agentclusterinstall <name> -n <name> -o yaml
   ```

2. Verify all hosts passed validation (minimum CPU, memory, disk)

3. Check that API and ingress VIPs are reachable from the host network
