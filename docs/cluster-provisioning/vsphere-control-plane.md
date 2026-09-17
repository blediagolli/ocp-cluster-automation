# vSphere Control Plane (Hybrid Agent-Based)

A hybrid provisioning mode for mixed clusters: vSphere VMs for the control plane, baremetal hosts for workers. The platform is set to `baremetal` or `none` (agent-based), but the control plane VMs are created and booted automatically by a Job that runs govc against vCenter.

## How it works

1. The chart creates two separate InfraEnvs — one for control plane (`*-cp`) and one for workers (`*-workers`)
2. A Kubernetes Job runs govc to create VMs in vCenter, attach the CP discovery ISO, and boot them
3. The control plane VMs register as agents via the CP InfraEnv
4. Baremetal workers register separately via the workers InfraEnv
5. The Assisted Installer installs the cluster across both VM and baremetal hosts

```
                     ┌── InfraEnv (CP)     → discovery ISO → vSphere VMs
                     │                                         (created by govc Job)
Git push → ArgoCD → ACM/Hive
                     │
                     └── InfraEnv (workers) → discovery ISO → baremetal hosts
                                                               (booted via BMC/Redfish)
```

### Split InfraEnvs

The standard agent-based flow uses a single InfraEnv. When `vsphereControlPlane.enabled: true`, the chart creates two:

| InfraEnv | Label selector | Used by |
|---|---|---|
| `<cluster>-cp` | `infraenv: <cluster>-cp` | Control plane VMs |
| `<cluster>-workers` | `infraenv: <cluster>-workers` | Worker BareMetalHosts |

BareMetalHost resources for workers are labeled with `infraenvs.agent-install.openshift.io: <cluster>-workers` so they attach to the worker InfraEnv, not the CP one.

## provision.yaml additions

Add the `vsphereControlPlane` block alongside your standard agent-based `provision.yaml`:

```yaml
cluster:
  platform: baremetal      # or none — the agent-based model

vsphereControlPlane:
  enabled: true
  automation: govc         # govc or ansible
  vcenter: vcenter.example.com
  username: administrator@vsphere.local
  password: ""
  insecure: true
  datacenter: DC1
  datastore: datastore1
  cluster: Cluster1
  network: VM Network
  folder: /DC1/vm/openshift
  resourcePool: ""
  masters:
    count: 3
    cpus: 4
    memoryMB: 16384
    diskGB: 120
  images:
    govc: "quay.io/openshift/origin-cli:latest"
  govcVersion: "v0.46.2"
```

The baremetal/none host definitions, networking, and VIPs are configured as normal in the platform section — see [baremetal](baremetal.md) or [platform-none](platform-none.md).

### CP ignition override

The CP InfraEnv can have its own ignition config override, separate from the workers:

```yaml
vsphereControlPlane:
  ignitionConfigOverride: '{"ignition":{"version":"3.1.0"},...}'
```

If not set, the top-level `ignitionConfigOverride` is used for the CP InfraEnv (if enabled).

## Additional resources generated

These are in addition to the standard agent-based resources:

| Resource | Purpose |
|---|---|
| InfraEnv (`*-cp`) | Separate discovery ISO for control plane VMs |
| InfraEnv (`*-workers`) | Separate discovery ISO for worker hosts |
| Job (`*-vsphere-cp`) | Runs govc to create and boot VMs in vCenter |
| ConfigMap (`*-vsphere-cp-govc`) | govc automation script |
| Secret (`*-vsphere-cp-creds`) | vCenter credentials for the Job |
| ServiceAccount + RBAC | Permissions for the Job to read InfraEnv ISO URLs |

### vcsim simulator

For testing without a real vCenter, enable the vCenter simulator:

```yaml
vsphereControlPlane:
  simulator:
    enabled: true
    image: "docker.io/vmware/vcsim:latest"
```

This deploys a vcsim Deployment that the govc Job connects to instead of a real vCenter. Useful for validating the provisioning workflow end-to-end in a lab environment.

## Prerequisites

- All [baremetal prerequisites](baremetal.md#prerequisites)
- vCenter access from the hub cluster (port 443)
- vCenter credentials with VM create/power/delete permissions
- Pre-existing datacenter, cluster, datastore, network, and folder in vCenter
- The govc or ansible runner container image accessible from the hub
