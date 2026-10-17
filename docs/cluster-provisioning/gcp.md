# GCP (IPI)

Standard IPI provisioning on Google Cloud. Hive creates Compute Engine instances, a
VPC with regional subnets, Cloud DNS records and load balancers, and runs the OpenShift
installer.

> **Proven on 2026-10-14.** `clusters/dev/gcp-sno-dev` — single node, `us-central1-a`,
> 4.22.13 — installed from this repo, registered with ACM and came up Available.
> `Chart.yaml` carries `oca.io/proven-on: gcp-sno-dev@2026-10-14`.
>
> **That cluster no longer exists.** The RHDP OPEN environment holding it
> (`YOUR_GCP_PROJECT_ID`) was reclaimed on 2026-10-15 and the cluster directory was
> deleted in the same change. The stamp stays, and deliberately: `oca.io/proven-on`
> records that this path *was* exercised against a real cloud on a given date,
> not that the cluster is still up. Nothing in `make validate` ties the two
> together — the check that used to is gone. See "If you are bringing GCP back"
> at the end of this document.

## provision.yaml

```yaml
provision:
  include: true

cluster:
  name: gcp-dev
  baseDomain: example.com
  platform: gcp
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

gcp:
  projectID: my-project
  region: us-central1
  masters:
    machineType: n2-standard-4
    zones: []                  # empty = spread across the region's zones
    osDisk:
      diskType: pd-ssd
      diskSizeGB: 128
  workers:
    machineType: n2-standard-4
    zones: []
    osDisk:
      diskType: pd-ssd
      diskSizeGB: 128

secrets:
  source: externalSecret
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  gcpCreds:
    path: secret/data/gcp/credentials
    properties:
      - secretKey: osServiceAccount.json
        property: osServiceAccount.json
```

Field names are GCP's own — `machineType`, `osDisk.diskType`, `osDisk.diskSizeGB` —
rather than AWS's `instanceType`/`rootVolume`, so each line transcribes one-for-one into
install-config and the Hive MachinePool.

### projectID appears once, not twice

`gcp.projectID` goes into install-config only. Hive's `ClusterDeployment.spec.platform.gcp`
has no project field — it reads the project out of the service account key. The asymmetry
with `region`, which appears in both, looks like an omission and is not.

### Disk type

`pd-ssd` is not really optional for the control plane. etcd fails its fsync latency
checks on `pd-standard`, and the cluster then degrades under load rather than failing the
install — the worse outcome, because it looks like a working cluster until it is busy.

### Zones

Zones on GCP are instance placement and nothing else:

```yaml
gcp:
  masters:
    zones:
      - us-central1-a
      - us-central1-b
      - us-central1-c
```

Leave them empty and the installer spreads across the region's zones, which is normally
what you want. Unlike AWS, there is no network cost to an unbounded pool — GCP subnets
are regional and the installer creates one Cloud NAT per cluster, not one per zone.

## Single-node OpenShift

One master, no workers. `masters.count: 1` is the whole switch — see
[cluster topology](README.md#cluster-topology).

```yaml
masters:
  count: 1

workers:
  count: 0

gcp:
  projectID: my-project
  region: us-central1
  masters:
    machineType: n2-standard-8   # 8 vCPU / 32 GiB — the SNO floor
    zones:
      - us-central1-a            # a single-node cluster lives in one zone
    osDisk:
      diskType: pd-ssd
      diskSizeGB: 200
  workers:                       # never instantiated; keys are read anyway
    machineType: n2-standard-4
    zones: []
    osDisk:
      diskType: pd-ssd
      diskSizeGB: 128
```

The default `n2-standard-4` is 4 vCPU / 16 GiB — half the memory a single node needs,
since it runs the control plane and the workload on one instance.

### What differs from a 3/3 cluster, and from AWS

- No MachinePool — a zero-replica pool would leave Hive reconciling empty MachineSets.
- `compute[0].platform` is `{}`. **This is where GCP and AWS diverge.** On AWS the empty
  compute pool keeps the master zones, because machine pools are what bound the AZs the
  VPC spans and an unbounded pool hangs a NAT gateway, and therefore an Elastic IP, off
  every AZ in the region. On GCP there is nothing to bound: subnets are regional and
  Cloud NAT is one regional resource per cluster. Carrying zones into a pool that will
  never have a machine would only get them validated against the region for no benefit.
  Do not "fix" this to match AWS — `tests/template-test.sh` Test 18 asserts it.

Hive still creates a temporary bootstrap instance, so the install briefly runs two
instances. Budget quota for both.

Day-2 charts are a separate decision. Start a new single-node cluster with
`platformCharts: []` and `operatorCharts: []`, provision it, confirm it is healthy, then
add charts one at a time — every chart lands on the same node as the control plane. The
same three to think twice about apply as on AWS: `machine-health-checks`, `etcd-defrag`
and `odf` (see [aws.md](aws.md#single-node-openshift)).

## Credentials

Hive mounts `platform.gcp.credentialsSecretRef` into the install pod, so the hub needs a
long-lived **service account JSON key**. There is no keyless option for this leg: the
install pod has nowhere to get a federated token from.

The chart writes the whole key file under one Secret key, `osServiceAccount.json` — the
only name Hive reads. So unlike `awsCreds`, which maps two properties into two keys, an
ExternalSecret here lands the entire file under a single `secretKey`.

Store it in Vault:

```bash
vault kv put secret/gcp/credentials osServiceAccount.json=@/path/to/key.json
```

For a lab you can inline it instead, with `secrets.source: inline` and
`gcp.serviceAccountJSON` as a block scalar. Do not commit a real key.

### When the key's project is not the cluster's project

Check this before storing the key, because it is silent until teardown:

```bash
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["project_id"])' key.json
```

If that does **not** equal `gcp.projectID`, rewrite it before it goes into
Vault. The two legs read different sources, and only one of them reads your
values file:

| Who | Project it uses |
|---|---|
| The installer, creating the cluster | `platform.gcp.projectID` from install-config |
| Hive itself — DNS reconciliation, deprovision | `project_id` from the key file |

So a mismatched key installs perfectly well into the right project and then
fails at the other end: deleting the ClusterDeployment runs a deprovision
pointed at the key's project, which deletes nothing and leaves the whole
cluster orphaned — running, billable, and no longer tracked by anything. ACM
reports the cluster gone.

Rewriting the field is safe. The JWT is signed with `private_key` and
identifies the caller by `client_email`; `project_id` is only the default
project hint Google's client libraries read, which is exactly the thing Hive is
picking up.

```bash
python3 - <<'EOF'
import json
d = json.load(open('key.json'))
d['project_id'] = 'my-project'          # match gcp.projectID
json.dump(d, open('key-hive.json', 'w'), indent=2)
EOF
vault kv put secret/gcp/credentials osServiceAccount.json=@key-hive.json
```

This is the normal case on Red Hat Demo Platform OPEN environments, which hand
out a per-environment project but host the service account centrally — the key
says the central project and the cluster belongs in yours.

### Workload Identity Federation

WIF does not remove the key above. It applies to the *installed cluster's* own operators —
image registry, ingress, machine-api — letting them use short-lived federated tokens
instead of minted service accounts.

`gcp.credentialsMode: Manual` is the first half and is wired up today. The second half is
not: it needs `ccoctl gcp create-all` run out of band per cluster, its generated manifests
fed in through the chart's `customManifests` ConfigMap, and a
`boundServiceAccountSigningKeySecretRef` on the ClusterDeployment, which the chart does
not template. **Setting `credentialsMode: Manual` on its own gives a cluster whose
operators have no credentials at all.** Leave it empty until that follow-up lands.

## Resources generated

| Resource | Purpose |
|---|---|
| Namespace | Cluster namespace on the hub |
| ClusterDeployment | Hive cluster definition with `platform.gcp` |
| MachinePool | Worker node pool — omitted when `workers.count: 0` |
| ManagedCluster | ACM registration, labelled `cloud: Google` |
| KlusterletAddonConfig | ACM addon config |
| Secret (`*-gcp-creds`) | Service account key under `osServiceAccount.json` |
| Secret (`*-install-config`) | Generated install-config.yaml |
| Secret (`*-pull-secret`) | Container registry pull secret |
| Secret (`*-ssh-private-key`) | SSH key for node access |

## How it works

1. ArgoCD syncs the provisioning chart, creating the resources above
2. Hive creates a provisioning pod that runs the OpenShift installer
3. The installer creates a VPC, two regional subnets, a Cloud Router and Cloud NAT,
   Cloud DNS records, load balancers and Compute Engine instances
4. OpenShift is installed on those instances
5. Hive marks the ClusterDeployment as installed
6. ACM imports the cluster via ManagedCluster

## Prerequisites

None of these are GitOps-able; do them before setting `deployProvision: true`.

- A **Cloud DNS public managed zone** for the base domain, in the same project. This is
  the usual first failure: the installer will not create the zone for you.
- A service account with the installer roles, and a JSON key for it, stored in Vault at
  `secret/gcp/credentials`.
- These APIs enabled on the project: Compute Engine, Cloud DNS, IAM, IAM Service Account
  Credentials, Cloud Resource Manager, Service Usage.
- A ClusterImageSet on the hub matching `imageSetRef`.
- Quota in the region for the cluster's instances **plus the temporary bootstrap node**,
  and for in-use external IP addresses.

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
   - **DNSNotReady**: the Cloud DNS public managed zone for the base domain does not
     exist, or the service account cannot manage it.
   - **InstallError on an API call**: an API is not enabled on the project. The error
     names the API; enable it and let Hive retry.
   - **Quota exceeded**: remember the bootstrap node. A 3/3 cluster needs seven instances
     briefly, not six.
   - **Authentication errors**: confirm the Secret key is spelled `osServiceAccount.json`.
     Hive looks for that exact name and reports nothing useful when it is missing.
   - **Degraded etcd on a healthy-looking cluster**: `diskType` is `pd-standard`.

## Removing a GCP cluster

Deleting `clusters/<env>/<cluster>/` is **not** the first step, and doing it first is
how the hub ends up with a namespace stuck in `Terminating` indefinitely.

The ApplicationSet stops generating `provision-<env>-<cluster>` as soon as the
directory is gone, so ArgoCD prunes the `ClusterDeployment`. Hive reacts to that
deletion by launching a **deprovision job** that calls the GCP API to destroy the
cluster's instances, VPC, DNS records and load balancers, and it holds the object
with a `hive.openshift.io/deprovision` finalizer until that job succeeds.

That is correct behaviour and what you want when the cloud resources are still
there. It is exactly wrong when they are not — a reclaimed OPEN environment, a
deleted project, or expired credentials. The job cannot authenticate, retries
forever, the finalizer never clears, and the namespace never finishes deleting.

### Order of operations

**If the GCP resources still exist** — let Hive do its job. Remove the directory,
merge, and watch the deprovision job complete. The namespace clears on its own.

**If the GCP resources are already gone** — tell Hive not to try, *before* the
removal reaches `main`:

```bash
oc patch clusterdeployment <name> -n <name> \
  --type=merge -p '{"spec":{"preserveOnDelete":true}}'
```

`preserveOnDelete` makes Hive skip the deprovision job and release the object
immediately. Then merge the removal and let ArgoCD prune normally.

This field is deliberately **not** in the provisioning chart's values. It only ever
matters on the way out, and a cluster whose values file is being deleted has no
values file left to carry it — setting it in git would mean one commit to add it, a
sync, and a second commit to delete the directory, for a flag that is read exactly
once.

**If you already merged and the namespace is hung**, the finalizer has to come off
by hand. Confirm the deprovision job is failing for the reason you think it is
before doing this — on a live cloud it would orphan real, billable resources:

```bash
oc logs -n <name> -l hive.openshift.io/job-type=deprovision --tail=20
oc patch clusterdeployment <name> -n <name> \
  --type=merge -p '{"metadata":{"finalizers":null}}'
```

### What is left behind either way

- **The ACM/Hive namespace** on the hub, once the finalizer clears.
- **Nothing in Cloud DNS** that matters if the project is gone with it. If the
  project survives, check for leftover `_acme-challenge` TXT records in the public
  zone — cert-manager removes them after each challenge, but a cluster destroyed
  mid-challenge can leave one.
- **The Vault secrets** (`secret/gcp/credentials`, the pull secret, the SSH key).
  Shared across clusters, so do not delete them with one cluster.

## If you are bringing GCP back

The chart and its docs are complete and unchanged; only a cluster directory was
removed. To stand a new one up:

1. A new GCP project and a public Cloud DNS managed zone for the base domain.
2. `vault kv put secret/gcp/credentials osServiceAccount.json=@key.json` on the hub,
   replacing the old key.
3. A new `clusters/<env>/<cluster>/` — recover the deleted one with
   `git show 462358a:clusters/dev/gcp-sno-dev/provision.yaml` and friends, then
   replace the project ID, base domain, region and zone throughout.
4. Update `.github/sanitize.env` — `GCP_PROJECT_ID`, `GCP_BASE_DOMAIN` and
   `GCP_DNS_ZONE_NAME` all name the old environment, and the sanitizer will happily
   redact strings nothing in the repo contains any more.
5. For TLS, the `cloudDNS` solver is already in `charts/operators/cert-manager` and
   was proven end to end on the cluster this section is about. See
   `docs/day2-cluster-config/letsencrypt-dns01-setup.md`.
