# Azure (IPI)

Standard IPI provisioning on Microsoft Azure. Hive creates a resource group, a vnet with
regional subnets, Azure DNS records, load balancers and virtual machines, and runs the
OpenShift installer.

> **Not yet run on a live cluster.** The chart's `oca.io/proven-on` stamp refers to the
> GCP single-node path. The Azure templates render and are covered by the chart's test
> suite, but no Azure cluster has completed an install from this repo. Delete this note
> and re-stamp `Chart.yaml` the day one does.

## provision.yaml

```yaml
provision:
  include: true

cluster:
  name: azure-dev
  baseDomain: example.com
  platform: azure
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

azure:
  baseDomainResourceGroupName: dns-rg
  region: eastus
  masters:
    vmSize: Standard_D4s_v3
    zones: []                  # empty = spread across the region's zones
    osDisk:
      diskType: Premium_LRS
      diskSizeGB: 128
  workers:
    vmSize: Standard_D4s_v3
    zones: []
    osDisk:
      diskType: Premium_LRS
      diskSizeGB: 128

secrets:
  source: externalSecret
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  azureCreds:
    path: secret/data/azure/credentials
    properties:
      - secretKey: osServicePrincipal.json
        property: osServicePrincipal.json
```

Field names are Azure's own — `vmSize`, `osDisk.diskType` taking a storage SKU — rather
than AWS's `instanceType`/`rootVolume` or GCP's `machineType`, so each line transcribes
one-for-one into install-config and the Hive MachinePool.

### baseDomainResourceGroupName appears twice, not once

This is the exact inverse of [GCP's `projectID`](gcp.md#projectid-appears-once-not-twice),
and the two are worth reading together, because each looks like a bug if you have just
read the other.

| | Where the chart emits it |
|---|---|
| GCP `projectID` | install-config only — `ClusterDeployment.spec.platform.gcp` has no such field |
| Azure `baseDomainResourceGroupName` | install-config **and** `ClusterDeployment.spec.platform.azure` |

Hive does not parse install-config. It keeps its own copy of the resource group and uses
it to reconcile DNS records and, later, to deprovision. Omit it from the
ClusterDeployment and the install still succeeds — the installer has its own copy — while
Hive reports `DNSNotReady` against a resource group nobody told it about. The chart emits
both from the one value, so there is nothing to keep in sync.

**It is not the cluster's resource group.** The installer creates that one itself, names
it `<infraID>-rg`, and deletes it on teardown. The group named here pre-exists, holds the
public DNS zone for `cluster.baseDomain`, and must outlive the cluster.

### Zones are strings, and they are bare digits

Azure availability zones are `"1"`, `"2"`, `"3"` — not region-suffixed names like
`us-east-1a` or `us-central1-a`. The install-config and MachinePool fields are
`[]string`, so the obvious transcription is the one that breaks:

```yaml
zones:
  - 1        # parses as an integer; the installer rejects it
```

The chart quotes them on the way out, so either spelling in `provision.yaml` works. The
test suite's Azure fixture deliberately writes them unquoted to keep that true.

Not every Azure region has availability zones. In one that does not, an empty list is the
only valid value — naming `"1"` in a non-zonal region fails the install.

### A pre-existing vnet is repeated into the MachinePool

Same root cause as `baseDomainResourceGroupName` above — Hive does not read
install-config — but it fails in a nastier way, because the cluster installs clean.

```yaml
azure:
  networkResourceGroupName: network-rg   # all four go together
  virtualNetwork: my-vnet
  controlPlaneSubnet: master-subnet
  computeSubnet: worker-subnet
```

Hive's `MachinePool.spec.platform.azure` has its own `virtualNetwork`,
`networkResourceGroupName` and `computeSubnet`, and its documented defaults are
`${infraID}-vnet` and `${infraID}-worker-subnet` — names that exist only when the
installer built the network itself. In a BYO-vnet install they name nothing.

So if the chart emitted these into install-config only, the installer would place the
initial workers correctly, the cluster would come up healthy, and the breakage would
wait for the first scale-up or machine replacement: Hive generates MachineSets pointed
at a vnet that was never created. The chart emits them into both, from the one set of
values. `tests/template-test.sh` Test 22 asserts each appears exactly twice.

`controlPlaneSubnet` is the exception and appears once — a worker pool has no
control-plane subnet, and the MachinePool has no such field.

`outboundType` is repeated for the same reason: the MachinePool defaults it to
`Loadbalancer` whatever install-config says, so a `UserDefinedRouting` cluster would
otherwise get worker MachineSets built for an outbound load balancer it deliberately
does not have.

GCP needs no counterpart to any of this: its MachinePool has no network fields at all.

### Disk type

`Premium_LRS` is not really optional for the control plane, for the same reason `pd-ssd`
is not on GCP: etcd fails its fsync latency checks on `Standard_LRS`, and the cluster
then degrades under load rather than failing the install — the worse outcome, because it
looks like a working cluster until it is busy.

The `s` in `Standard_D4s_v3` is load-bearing. It marks a VM size that supports Premium
SSD; pair a non-`s` size with `Premium_LRS` and the install fails on an unsupported
storage type.

## Single-node OpenShift

One master, no workers. `masters.count: 1` is the whole switch — see
[cluster topology](README.md#cluster-topology).

```yaml
masters:
  count: 1

workers:
  count: 0

azure:
  baseDomainResourceGroupName: dns-rg
  region: eastus
  masters:
    vmSize: Standard_D8s_v3      # 8 vCPU / 32 GiB — the SNO floor
    zones:
      - "1"                      # a single-node cluster lives in one zone
    osDisk:
      diskType: Premium_LRS
      diskSizeGB: 200
  workers:                       # never instantiated; keys are read anyway
    vmSize: Standard_D4s_v3
    zones: []
    osDisk:
      diskType: Premium_LRS
      diskSizeGB: 128
```

The default `Standard_D4s_v3` is 4 vCPU / 16 GiB — half the memory a single node needs,
since it runs the control plane and the workload on one instance.

### What differs from a 3/3 cluster, and from AWS

- No MachinePool — a zero-replica pool would leave Hive reconciling empty MachineSets.
- `compute[0].platform` is `{}`. Azure sits with GCP here, not AWS. On AWS the empty
  compute pool keeps the master zones, because machine pools bound the AZs the VPC spans
  and an unbounded pool hangs a NAT gateway, and therefore an Elastic IP, off every AZ.
  An Azure vnet and its subnets are regional, and outbound is a single load balancer or
  NAT gateway per cluster, so zones cost nothing in the network and naming them for a
  pool that will never have a machine only adds a validation failure mode.
  `tests/template-test.sh` Test 21 asserts it.

Hive still creates a temporary bootstrap VM, so the install briefly runs two instances.
Budget quota for both.

Day-2 charts are a separate decision. Start with `platformCharts: []` and
`operatorCharts: []`, provision, confirm the cluster is healthy, then add charts one at a
time — every chart lands on the same node as the control plane. The same three to think
twice about apply as on AWS: `machine-health-checks`, `etcd-defrag` and `odf` (see
[aws.md](aws.md#single-node-openshift)).

## Credentials

Hive mounts `platform.azure.credentialsSecretRef` into the install pod, so the hub needs
a long-lived **service principal with a client secret**. There is no keyless option for
this leg: the install pod has nowhere to get a federated token from.

The chart writes the whole document under one Secret key, `osServicePrincipal.json` — the
only name Hive reads. So unlike `awsCreds`, which maps two properties into two keys, an
ExternalSecret here lands the entire document under a single `secretKey`. Storing the
four fields as four separate properties produces a Secret that looks right and
authenticates against nothing.

Create the service principal and shape its output:

```bash
az ad sp create-for-rbac \
  --name openshift-installer \
  --role Contributor \
  --scopes "/subscriptions/$SUBSCRIPTION_ID" \
  --query '{subscriptionId:`'"$SUBSCRIPTION_ID"'`,tenantId:tenant,clientId:appId,clientSecret:password}' \
  -o json > osServicePrincipal.json
```

`create-for-rbac` returns `appId`/`password`/`tenant`, which are not the names the
installer reads — the query above renames them and adds the subscription, which the
command does not return at all.

`Contributor` alone is not enough. The installer creates role assignments for the
cluster's own identities, which needs `User Access Administrator` (or a custom role with
`Microsoft.Authorization/roleAssignments/write`):

```bash
az role assignment create --assignee "$CLIENT_ID" \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

Store it in Vault:

```bash
vault kv put secret/azure/credentials osServicePrincipal.json=@osServicePrincipal.json
```

For a lab you can inline it instead, with `secrets.source: inline` and
`azure.servicePrincipalJSON` as a block scalar. Do not commit a real client secret.

### Client secrets expire

`az ad sp create-for-rbac` issues a secret with a default lifetime — one or two years
depending on tenant policy, and tenants commonly cap it far shorter. Expiry does not
affect a running cluster, whose operators hold their own credentials, but it silently
breaks everything Hive does on the hub's behalf: DNS reconciliation, machine pool
scaling, and deprovision. The failure looks like a cluster that will not delete.

Re-issuing the secret and rewriting the Vault path is enough; the ExternalSecret picks it
up on its next refresh and nothing in git changes.

### Azure AD Workload Identity

Workload identity does not remove the service principal above. It applies to the
*installed cluster's* own operators — image registry, ingress, machine-api — letting them
use short-lived federated tokens instead of a shared client secret.

`azure.credentialsMode: Manual` is the first half and is wired up today. The second half
is not: it needs `ccoctl azure create-all` run out of band per cluster, its generated
manifests fed in through the chart's `customManifests` ConfigMap, and a
`boundServiceAccountSigningKeySecretRef` on the ClusterDeployment, which the chart does
not template. **Setting `credentialsMode: Manual` on its own gives a cluster whose
operators have no credentials at all.** Leave it empty until that follow-up lands.

## Resources generated

| Resource | Purpose |
|---|---|
| Namespace | Cluster namespace on the hub |
| ClusterDeployment | Hive cluster definition with `platform.azure` |
| MachinePool | Worker node pool — omitted when `workers.count: 0` |
| ManagedCluster | ACM registration, labelled `cloud: Azure` |
| KlusterletAddonConfig | ACM addon config |
| Secret (`*-azure-creds`) | Service principal under `osServicePrincipal.json` |
| Secret (`*-install-config`) | Generated install-config.yaml |
| Secret (`*-pull-secret`) | Container registry pull secret |
| Secret (`*-ssh-private-key`) | SSH key for node access |

## How it works

1. ArgoCD syncs the provisioning chart, creating the resources above
2. Hive creates a provisioning pod that runs the OpenShift installer
3. The installer creates a resource group, a vnet with two regional subnets, Azure DNS
   records, load balancers and virtual machines
4. OpenShift is installed on those instances
5. Hive marks the ClusterDeployment as installed
6. ACM imports the cluster via ManagedCluster

## Prerequisites

None of these are GitOps-able; do them before setting `deployProvision: true`.

- An **Azure DNS public zone** for the base domain, in a resource group that is not the
  cluster's. This is the usual first failure: the installer will not create the zone.
- A service principal with `Contributor` **and** `User Access Administrator`, and a
  client secret for it, stored in Vault at `secret/azure/credentials`.
- These resource providers registered on the subscription: `Microsoft.Compute`,
  `Microsoft.Network`, `Microsoft.Storage`, `Microsoft.ManagedIdentity`,
  `Microsoft.Authorization`, `Microsoft.Resources`, `Microsoft.DBforPostgreSQL`.
- A ClusterImageSet on the hub matching `imageSetRef`.
- Quota in the region for the cluster's VMs **plus the temporary bootstrap node**, and
  for public IP addresses. Azure quota is per VM family — `Standard_DSv3 Family vCPUs`
  is a separate line from the subscription's total.

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
   - **DNSNotReady**: the Azure DNS public zone does not exist, the service principal
     cannot manage it, or `baseDomainResourceGroupName` names the wrong group. Check the
     ClusterDeployment's own copy, not just install-config.
   - **AuthorizationFailed creating a role assignment**: the service principal has
     `Contributor` but not `User Access Administrator`.
   - **InvalidParameter on zones**: zones reached the installer as integers, or the
     region has no availability zones and one was named anyway.
   - **Unsupported storage type**: a non-`s` VM size paired with `Premium_LRS`.
   - **Quota exceeded**: remember the bootstrap node, and that quota is per VM family.
   - **Authentication errors**: confirm the Secret key is spelled
     `osServicePrincipal.json`, and that it holds one JSON document rather than four
     separate keys. Hive reports nothing useful for either.
   - **A cluster that will not delete**: the client secret has expired. Re-issue it and
     rewrite the Vault path.
   - **Degraded etcd on a healthy-looking cluster**: `diskType` is `Standard_LRS`.
