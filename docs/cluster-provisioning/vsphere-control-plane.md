# vSphere Control Plane (Hybrid Agent-Based)

A hybrid provisioning mode for mixed clusters: vSphere VMs for the control plane (and optionally workers), bare metal hosts for workers. The platform is set to `baremetal` or `none` (agent-based), but the VMs are created and booted automatically by a Job that runs govc against vCenter.

## How it works

1. The chart creates two separate InfraEnvs — one for control plane (`*-cp`) and one for workers (`*-workers`)
2. A Kubernetes Job runs govc to create VMs in vCenter, attach the CP discovery ISO, and boot them
3. The VMs register as agents via the CP InfraEnv — the Job approves them with the correct role and sets their hostname
4. Bare metal workers register separately via the workers InfraEnv
5. The Assisted Installer installs the cluster across both VM and bare metal hosts

```
                     ┌── InfraEnv (CP)     → discovery ISO → vSphere VMs (masters + VM workers)
                     │                                         (created by govc Job)
Git push → ArgoCD → ACM/Hive
                     │
                     └── InfraEnv (workers) → discovery ISO → bare metal hosts
                                                               (booted via BMC/Redfish)
```

### Split InfraEnvs

The standard agent-based flow uses a single InfraEnv. When `vsphereControlPlane.enabled: true`, the chart creates two:

| InfraEnv | Label selector | Used by |
|---|---|---|
| `<cluster>-cp` | `infraenv: <cluster>-cp` | Control plane VMs + vSphere worker VMs |
| `<cluster>-workers` | `infraenv: <cluster>-workers` | Worker BareMetalHosts |

BareMetalHost resources for workers are labeled with `infraenvs.agent-install.openshift.io: <cluster>-workers` so they attach to the worker InfraEnv, not the CP one. All vSphere VMs (masters and workers) boot from the CP InfraEnv ISO.

### Agent hostname assignment

The govc/ansible Job sets `spec.hostname` on each Agent CR during approval. DHCP does not always set hostnames on discovery-booted VMs, so the Job patches:
- Masters: `<cluster>-master-<N>`
- VM workers: `<cluster>-vsphere-worker-<N>`

These match the VM names in vCenter.

## provision.yaml

Add the `vsphereControlPlane` block alongside your standard agent-based `provision.yaml`. Use `platform: none` for user-managed networking (DHCP on vSphere, static on bare metal):

```yaml
cluster:
  platform: none

vsphereControlPlane:
  enabled: true
  automation: govc         # govc or ansible
  vcenter: vcenter.example.com
  username: ""             # or sourced from ExternalSecret
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
    cpus: 8
    memoryMB: 32768
    diskGB: 120
  workers:                 # optional vSphere worker VMs
    count: 1
    cpus: 16
    memoryMB: 65536
    diskGB: 200
```

Set `workers.count: 0` (default) if all workers are bare metal.

The baremetal/none host definitions, networking, and VIPs are configured as normal in the platform section — see [baremetal](baremetal.md) or [platform-none](platform-none.md).

### provisionRequirements

Set `workerAgents` to the **total** of VM workers + bare metal workers:

```yaml
none:
  provisionRequirements:
    controlPlaneAgents: 3
    workerAgents: 4        # 1 VM worker + 3 BM workers
```

### CP ignition override

The CP InfraEnv can have its own ignition config override, separate from the workers:

```yaml
vsphereControlPlane:
  ignitionConfigOverride: '{"ignition":{"version":"3.1.0"},...}'
```

If not set, the top-level `ignitionConfigOverride` is used for the CP InfraEnv (if enabled).

### ExternalSecrets for credentials

Instead of inline credentials, use ExternalSecrets to source them from Vault:

```yaml
externalSecrets:
  enabled: true
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  refreshInterval: 1h
  vsphereControlPlaneCreds:
    path: secret/data/vsphere/credentials
    properties:
      - secretKey: username
        property: username
      - secretKey: password
        property: password
  bmcCreds:
    path: secret/data/bmc/credentials
    properties:
      - secretKey: username
        property: username
      - secretKey: password
        property: password
  pullSecret:
    path: secret/data/openshift/pull-secret
    properties:
      - secretKey: .dockerconfigjson
        property: .dockerconfigjson
```

See [examples/provision-vsphere-cp-bm-workers.yaml](examples/provision-vsphere-cp-bm-workers.yaml) for a complete working example.

## Additional resources generated

These are in addition to the standard agent-based resources:

| Resource | Purpose |
|---|---|
| InfraEnv (`*-cp`) | Separate discovery ISO for control plane VMs |
| InfraEnv (`*-workers`) | Separate discovery ISO for worker hosts |
| Job (`*-vsphere-cp`) | Runs govc to create and boot VMs in vCenter |
| ConfigMap (`*-vsphere-cp-govc`) | govc automation script |
| Secret (`*-vsphere-cp-creds`) | vCenter credentials for the Job (or ExternalSecret) |
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
