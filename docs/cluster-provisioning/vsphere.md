# vSphere (IPI)

Standard IPI provisioning on VMware vSphere. Hive drives the installer which creates VMs via the vCenter API.

## provision.yaml

```yaml
provision:
  include: true

cluster:
  name: vsphere-prod
  baseDomain: example.com
  platform: vsphere
  environment: prod
  clusterSet: default
  imageSetRef: img4.22.13-x86-64-appsub
  networkType: OVNKubernetes
  sshPublicKey: "ssh-ed25519 AAAA..."

masters:
  count: 3

workers:
  count: 3

vsphere:
  vcenter: vcenter.example.com
  username: administrator@vsphere.local
  password: ""
  datacenter: DC1
  datastore: datastore1
  cluster: Cluster1
  folder: /DC1/vm/openshift
  network: VM Network
  cacertificate: |
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----
  apiVIP: 10.0.0.100
  ingressVIP: 10.0.0.101
  masters:
    cpus: 4
    coresPerSocket: 2
    memoryMB: 16384
    diskGB: 120
  workers:
    cpus: 4
    coresPerSocket: 2
    memoryMB: 16384
    diskGB: 120
```

## Resources generated

| Resource | Purpose |
|---|---|
| Namespace | Cluster namespace on the hub |
| ClusterDeployment | Hive cluster definition with `platform.vsphere` |
| MachinePool | Worker node pool (CPU, memory, disk config) |
| ManagedCluster | ACM registration |
| KlusterletAddonConfig | ACM addon config |
| Secret (`*-vsphere-creds`) | vCenter username and password |
| Secret (`*-vsphere-certs`) | vCenter CA certificate |
| Secret (`*-install-config`) | Generated install-config.yaml |
| Secret (`*-pull-secret`) | Container registry pull secret |
| Secret (`*-ssh-private-key`) | SSH key for node access |

## How it works

1. ArgoCD syncs the provisioning chart, creating the resources above
2. Hive creates a provisioning pod that runs the OpenShift installer
3. The installer connects to vCenter using the credentials and CA certificate
4. VMs are created in the specified datacenter/cluster/folder/datastore with the specified network
5. OpenShift is installed on the VMs
6. Hive marks the ClusterDeployment as installed
7. ACM imports the cluster via ManagedCluster

## vSphere field reference

| Field | Description |
|---|---|
| `vcenter` | vCenter FQDN or IP |
| `username` | vCenter SSO user (e.g., `administrator@vsphere.local`) |
| `password` | vCenter password |
| `datacenter` | vSphere datacenter name |
| `datastore` | Default datastore for VM disks |
| `cluster` | vSphere compute cluster name |
| `folder` | VM folder path (e.g., `/DC1/vm/openshift`) |
| `network` | Port group name for VM networking |
| `cacertificate` | vCenter CA certificate (PEM format) |
| `apiVIP` | Virtual IP for the API server |
| `ingressVIP` | Virtual IP for ingress (*.apps) |

## Prerequisites

- vCenter credentials with VM create/delete permissions
- vCenter CA certificate (download from `https://vcenter.example.com/certs/download.zip`)
- Pre-existing datacenter, cluster, datastore, network, and folder
- DNS records for API and ingress VIPs (or DHCP + DNS configured)
- DHCP on the VM network (unless using static IPs via custom manifests)
- ClusterImageSet matching `imageSetRef`

## Troubleshooting

1. Check ClusterDeployment status:
   ```bash
   oc get clusterdeployment <name> -n <name> -o yaml
   ```

2. Check provisioning pod logs:
   ```bash
   oc logs -n <name> -l hive.openshift.io/cluster-deployment-name=<name>
   ```

3. Common issues:
   - **Certificate errors**: verify `cacertificate` matches vCenter's actual CA
   - **Permission denied**: ensure the vCenter user has VM create/delete/power permissions on the target folder
   - **Network unreachable**: check that the hub cluster can reach vCenter on port 443
   - **VIP conflicts**: ensure API and ingress VIPs are not already in use
