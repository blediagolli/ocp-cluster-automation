# Cluster buildout runbook

From nothing to a configured cluster, in order. Four imperative commands at the
start, and then every subsequent change is a pull request.

This is written from the `mgt/acm-hub` rebuild of 2026-10-12/13 (PRs #52–#73),
which is the only end-to-end run of the whole sequence. Every step below was
executed on a live cluster, and the hazards called out are ones that actually
happened rather than ones that could.

**The one rule:** after Stage 2 there is no `oc apply`. If a change needs to
reach the cluster, it reaches it by merging to `main`.

| Stage | What | Imperative? |
|---|---|---|
| 0 | Define the cluster in git, bare | git only |
| 1 | Provision the machines | `make bootstrap-hub` |
| 2 | Bootstrap GitOps | 4 × `oc apply` — the last ones |
| 3 | The enablement loop | the unit that repeats |
| 4 | Enable charts, one at a time | git only |
| 5 | Promote the charts to `proven` | git only |

---

## Stage 0 — define the cluster in git, bare

A new cluster is a directory under `clusters/<env>/<cluster>/`. Copy the shape
from an existing one; the fully-commented examples are in
[`docs/reference/`](reference/).

```
clusters/mgt/acm-hub/
├── applications/          # app-of-apps — one Application, platform-root
├── applicationsets/       # the eight ApplicationSets platform-root creates
├── bootstrap/             # the GitOps operator, ArgoCD instance, console plugin
├── bootstrap.yaml         # the install-config inputs for Stage 1
├── conf.yaml              # identity + the opt-in lists
├── kustomization.yaml     # lists applications/ and applicationsets/
├── namespace-sizes.yaml
├── operators.yaml         # settings shared by every operator chart
├── operators/<chart>.yaml # settings for one operator chart
├── overlay/
└── platform-config.yaml   # settings for every platform-config chart
```

**Bring it up bare.** `conf.yaml` starts with:

```yaml
platformCharts: []
operatorCharts: []
teams: []
deployPolicies: false
clusterRegistered: false    # until the cluster exists and ArgoCD can reach it
```

Empty lists are not a placeholder, they are the design. The ApplicationSets
exist and generate nothing, so the first sync after Stage 2 is a no-op rather
than the entire platform landing at once on a cluster nobody has looked at yet.

Settings can be written ahead of time. The values files are read only by charts
that are listed, so `platform-config.yaml` can be complete from day one while
`platformCharts` is still `[]` — which is exactly what makes re-enabling a chart
later a one-line change. On the acm-hub rebuild every chart's configuration
survived in `platform-config.yaml`; only the opt-in was withdrawn.

Under `missingkey=error` a map lookup fails before any `| default` can run, so
**every key above must be present even when empty**. Declare `operatorCharts: []`
rather than omitting it.

Related: [conf.yaml](cluster-configuration/conf-yaml.md) ·
[values precedence](cluster-configuration/values-precedence.md)

---

## Stage 1 — provision the machines

Covered in full by [bootstrap-hub.md](cluster-provisioning/bootstrap-hub.md) —
prerequisites, credentials, and the `bootstrap.yaml` fields. In short:

```bash
make bootstrap-hub-dry-run CLUSTER=mgt/acm-hub   # renders install-config, installs nothing
make bootstrap-hub         CLUSTER=mgt/acm-hub   # ~40 minutes on AWS IPI
```

Artifacts land in `install-<cluster>/`, which is **gitignored**. Two files there
matter and neither is recoverable:

- `auth/kubeconfig` — the only admin credential for the cluster
- `metadata.json` — what `make destroy-hub` reads to find the infrastructure

### Decide the node layout before you run it, not after

`acm-hub` is **3 × m5a.4xlarge in a compact layout**: three control-plane nodes,
no dedicated workers, all three carrying the worker role via
`scheduler.mastersSchedulable: true`. That choice propagates into several later
steps, so it is not a detail to leave to the installer's defaults:

- `ingress.controller.default.replicas` can be 3 only because there are three
  schedulable nodes. A count above the number of eligible nodes leaves the
  surplus router pods `Pending`.
- Any `nodePlacement` selecting `node-role.kubernetes.io/worker` matches *all*
  nodes here. The label exists cluster-wide only because `mastersSchedulable` is
  true — flip it to false and the label disappears everywhere at once, which
  strands every workload on a compact cluster.
- ODF's node selector has the same problem in reverse: it was written to keep
  Ceph off the control plane on a cluster with dedicated workers, and on a
  compact cluster it now places Ceph *on* the control plane.

48 vCPU total, ~38 usable once the control plane takes its share. That is enough
for the estate as it stands, with no real headroom for ODF.

### Verify before moving on

```bash
export KUBECONFIG=$PWD/install-<cluster>/auth/kubeconfig
oc get nodes
oc get co                                  # all Available, none Degraded or Progressing
oc adm top nodes                           # the baseline to compare later stages against
oc get pods -A --field-selector=status.phase=Pending
```

Record the baseline. Every later stage is judged against it, and "was that
already Pending?" is not a question you want to be answering from memory.

---

## Stage 2 — bootstrap GitOps

**The only imperative part of the whole runbook.** Four steps, in order, fully
explained in [bootstrap.md](cluster-configuration/bootstrap.md) — including why
they cannot be collapsed into one apply.

```bash
# 1. The GitOps operator. Its own directory, on its own, first.
oc apply -k clusters/mgt/acm-hub/bootstrap/openshift-gitops/operator

# 2. Wait for the CSV. Do not skip this.
oc get csv -n openshift-gitops-operator -w

# 3. The ArgoCD instance, the platform AppProject, and the CMP sidecar.
oc apply -k clusters/mgt/acm-hub/bootstrap/openshift-gitops/instance
oc apply -k clusters/mgt/acm-hub/bootstrap/openshift-gitops/console-plugin

# 4. The app-of-apps. This is the last thing applied by hand, ever.
oc apply -k clusters/mgt/acm-hub/applications
```

### The rule that matters most

**Never apply the ApplicationSets by hand.** `platform-root` creates them.

Applying `applicationsets/` directly produces a cluster that looks correct —
eight ApplicationSets, generating correctly — and is silently broken: the
objects have no owner, so **edits in git never reach the cluster again**. It
presents much later as "my change did nothing", and the only apparent fix is
another manual apply, which deepens the hole. This happened on the acm-hub
rebuild; the symptom and the recovery are written up in
[bootstrap.md](cluster-configuration/bootstrap.md#what-goes-wrong-when-applicationsets-are-applied-directly).

### Verify

```bash
oc get application platform-root -n openshift-gitops          # Synced / Healthy
oc get applicationsets -n openshift-gitops \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{"\n"}{end}'
```

Eight ApplicationSets, **every one carrying a tracking-id naming
`platform-root`**. A `<none>` in that column is the failure above.

```bash
oc get applications -n openshift-gitops
```

Expect nothing. The lists in `conf.yaml` are still empty, which is the point.

### Then flip the cluster on

One line in `conf.yaml`, as a PR like everything after it:

```yaml
clusterRegistered: true
```

For a hub this is true as soon as it exists — its ArgoCD destination is the
in-cluster `https://kubernetes.default.svc`, which is always resolvable. For a
managed cluster it stays false until the cluster is imported and has a cluster
secret in `openshift-gitops`.

Note that `clusterRegistered: true` is also what arms the chart readiness gate
(Stage 5): an `incubating` chart may not be listed on a registered cluster
without an `oca.io/under-test` annotation naming it.

---

## Stage 3 — the enablement loop

Everything from here on is the same seven steps, repeated once per chart. **One
chart per pull request**, each verified on the live cluster before the next one
is opened. The order in Stage 4 only holds if nothing is in flight.

**1. Pre-flight the dependency.** Most charts here name something another chart
created — a Secret, a CRD, a namespace. Confirm it exists *on the cluster*, not
in git:

```bash
oc get secret <name> -n <namespace>
oc get crd <name>
```

**2. Render it and read the output.** `include: true` is not evidence a chart
does anything; several of these charts render a no-op when under-configured.

```bash
helm template <chart> charts/platform-config/<chart> \
  -f clusters/<env>/<cluster>/platform-config.yaml
# or, through the same code path ArgoCD uses:
make render CLUSTER=<env>/<cluster> CHART=<chart>
```

For a chart that **adopts a live object** (`openshift-ingress`,
`openshift-apiserver`, `openshift-proxy`, `openshift-scheduler`), diff it
against the cluster before merging. This is the step that catches a field you
did not mean to assert:

```bash
make render CLUSTER=<env>/<cluster> CHART=<chart> | oc diff -f -
```

**3. Edit `conf.yaml`.** Add the chart name to `platformCharts` or
`operatorCharts`, **with a comment** saying what it asserts, what it depends on,
and what its first sync will disturb. The comments in
[`clusters/mgt/acm-hub/conf.yaml`](../clusters/mgt/acm-hub/conf.yaml) are the
house style, and they are the reason the order in Stage 4 is reconstructable at
all.

**4. Annotate the chart if it is `incubating`.** `chart-readiness.sh` check 3
refuses to let a registered cluster list an `incubating` chart, so the same
commit must add:

```yaml
oca.io/under-test: <cluster>@<YYYY-MM-DD>
```

The cluster name has to match exactly. The hatch expires after 30 days, and
re-dating it is not the way out — promoting the chart is (Stage 5).

**5. Run the checks.**

```bash
make validate
bash charts/platform-config/<chart>/tests/template-test.sh   # if the chart has one
```

`make validate` lints and renders, and runs the readiness gate. It does **not**
run the per-chart test suites. Charts that have one keep it in `tests/`, and it
is on you to run it.

**6. Open the PR against `main` and merge it.** Every ApplicationSet generator
is pinned to `revision: main`, so **nothing on a branch reaches the cluster** —
a branch can be validated but not observed. Always `--base main`; a PR based on
a branch that then gets squash-merged leaves commits that never land, with no
error anywhere.

**7. Watch the sync, then verify on the cluster.**

```bash
oc get applications -n openshift-gitops | grep <chart>
oc get events -n <namespace> --sort-by=.lastTimestamp | tail -20
```

Then update `HANDOFF.md` — the root one with a session entry, and the chart's
own if its behaviour or state changed.

### Two timing facts to hold onto

- **A failed sync pins the old SHA for roughly 25 minutes.** Fixing the cause
  and merging does not produce an immediate retry; ArgoCD is still holding the
  revision that failed. A fix that only changes a sync hook never auto-syncs at
  all and needs a manual refresh.
- **Sync waves order resources within one chart, not between charts.** Two
  Applications have no ordering relationship whatsoever. That is the whole
  reason Stage 4 is a sequence of merges rather than one list.

---

## Stage 4 — the order

The order to follow, with the dependency that fixes each position. Each row is
one pull request.

| # | Chart / switch | Fixed here because |
|---|---|---|
| 1 | `cert-manager` | Issues the certificates later charts name |
| 2 | `external-secrets` | Its *operand* creates the namespace vault-server writes into |
| 3 | `vault-server` | The secret backend; needs ESO first |
| 4 | `tls-certificates` | Needs a cert-manager ClusterIssuer |
| 5 | `teams` | Nothing above it; everything tenant-facing below it |
| 6 | `openshift-ingress` | Needs the wildcard certificate to exist |
| 7 | `openshift-apiserver` | The API is the recovery path for everything above |
| 8 | **ODF** | The heaviest thing on the cluster — size it before anything competes with it |
| 9 | `advanced-cluster-management` | What makes this a hub; its observability needs ODF |
| 10 | `deployPolicies: true` | **Optional.** Needs the CRDs the MultiClusterHub installs |

Steps 1–7 are the same on a hub and on a spoke. Steps 8–10 are what make a
cluster a hub, and the last of them is a reporting decision rather than a
configuration one.

### Where acm-hub actually differs

This order is **revised**, not purely historical. On the acm-hub rebuild, ACM
(#58) and `deployPolicies` (#59) went on at positions 4 and 5, before the
certificate chain and before ODF — which is why ODF is still outstanding there,
and why its capacity has to be measured against a cluster that is already
carrying a MultiClusterHub.

ODF moved below ACM for one reason: **it is the only component here big enough
to not fit, and the only way to find that out is to put it on a cluster that is
otherwise light.** On the first hub it was ODF's requests that held nodes at
~99% CPU requests, which left DaemonSet pods — ACS's collector among them —
permanently `Pending` on nodes that no amount of new capacity could relieve,
because a DaemonSet pod is pinned to its node. With ACM already in place that
failure arrives as two things being wrong at once, and ACM's pods are among the
ones that get squeezed.

The dependency runs the same way: ACM's `multiClusterObservability` needs ODF
serving object storage, so with ODF first it can go on in the same pass rather
than being deferred and forgotten.

### 4.1 `cert-manager` — `operatorCharts`

First on purpose: `openshift-apiserver` eventually names a Secret that cannot
exist until an issuer does.

Renders the operator plus one `ClusterIssuer` — `letsencrypt`, ACME over
**DNS-01 against Route53**. Everything else in its values (`selfSigned`,
`caIssuer`, `apiCert`, `ingressCert`) stays `include: false`, so nothing here
issues a certificate yet.

It needs **no secret in git**: the chart emits a `CredentialsRequest` and the
Cloud Credential Operator mints a Route53-scoped IAM user into
`cert-manager-dns01-credentials`. That is an AWS IPI mechanism and will not work
on a platform without CCO.

DNS-01 is not a preference. HTTP-01 cannot issue a wildcard, and it cannot reach
the API server's port either.

```bash
oc get clusterissuer letsencrypt                             # READY True
oc get secret cert-manager-dns01-credentials -n cert-manager
```

### 4.2 `external-secrets` — `operatorCharts`

**Must come before `vault-server`**, and the reason is not stylistic:
`vault-server` writes an `allow-eso-to-vault` NetworkPolicy into the
`external-secrets` namespace, and that namespace is created by the ESO
**operand**, not by its Subscription. Enable `vault-server` first and it cannot
go Synced.

The Subscription alone only runs a controller-manager. Nothing reconciles a
`SecretStore` or an `ExternalSecret` until the cluster-scoped
`ExternalSecretsConfig` named `cluster` exists, which is why
`externalSecretsConfig.include: true` is set in `operators.yaml`. Without it
those objects are accepted and sit with an empty status forever — which reads
from the outside like a broken Vault.

```bash
oc get externalsecretsconfig cluster
oc get ns external-secrets
```

### 4.3 `vault-server` — `platformCharts`

**This one does not finish on merge, and that is expected rather than a fault.**

Vault comes up **uninitialised and sealed**: three replicas, 10Gi PVCs, Raft,
`seal.type: shamir`. A sealed Vault fails its readiness probe, so the pods stay
`0/1` and the Application sits Progressing or Degraded until a human runs
`vault operator init` and unseals all three with 3 of the 5 key shares.

**Nothing in git can do that step** — it is Vault's own internal state, not
Kubernetes objects. The exact commands, verified end to end, are in
[`charts/platform-config/vault-server/HANDOFF.md`](../charts/platform-config/vault-server/HANDOFF.md#the-bootstrap-as-actually-run):
init, unseal all three, then the KV v2 engine, the Kubernetes auth method, the
policy and the `external-secrets` role, in one pass.

Four things to know before running it:

- **Keys must never reach a terminal, a log, or a chat transcript.** The
  documented commands redirect to a `0600` file or pipe through stdin for that
  reason. `--from-literal`, `export` and bare arguments all leave the value in
  shell history or in `ps` output.
- The keys from a previous cluster are worthless. A new Vault is a new init and
  a new set of shares.
- There is **no auto-unseal**, and the hub cannot seal against its own transit
  engine. So this recurs after *every* pod restart, including the sandbox's
  overnight stop. It is a standing operational cost, not a one-time step.
- The `ClusterSecretStore` it renders is named **`vault`**, not `vault-backend`.
  Charts that default to the latter need it set explicitly.

```bash
oc get pods -n vault                           # 1/1 after unsealing, 0/1 before
oc get clustersecretstore vault                # READY True
```

### 4.4 `tls-certificates` — `platformCharts`

Issues two Let's Encrypt certificates: a **wildcard** for the apps domain into
`openshift-ingress`, and an **API** certificate into `openshift-config`.

Nothing consumes either one yet, and that is the correct order: a Secret that
exists and is unused is harmless, while naming one that does not exist degrades
— or takes down — the object naming it.

Before enabling, verify the issuer rather than assuming it: Ready, registered
against the **production** ACME endpoint, solving DNS-01 via Route53, with a
`hostedZoneID` matching this cluster's zone.

**The production rate limit is real: five identical certificates per week.**
Deleting and recreating these `Certificate` objects to retry something will
exhaust that quota, and the lockout outlasts most sandboxes. Debug the issuer,
not the certificate.

```bash
oc get certificate -A                                   # READY True, both
oc get secret cert-manager-ingress-cert -n openshift-ingress
oc get secret cert-manager-api-cert     -n openshift-config
```

### 4.5 `teams` — `conf.yaml`

One entry generates **both** onboarding Applications — the namespaces and a
complete per-team ArgoCD instance — unless it opts out of one:

```yaml
teams:
  - team: team-alpha
```

Write any opt-out (`applicationGitops: false`, `namespaceConfig: false`)
**unquoted**. `"false"` in quotes is a non-empty string and is read as off, which
happens to be the same outcome here, but the unquoted form is the one that means
it.

Removing an entry does **not** retire a team. It deletes the Application, and
`preserveResourcesOnDeletion: true` then strands whatever it owned. Retiring is
`team.quiesce: true` in `teams/<team>.yaml` — let it sync, confirm, and only
then stop generating the Applications.

One hazard with teeth: switching `resourceQuota` or `limitRange` **off** on a
namespace that already has one **deletes the live object**, because the sync
policy is prune.

### 4.6 `openshift-ingress` — `platformCharts`

The first consumer of either certificate. **This chart does not create
`IngressController/default`** — the installer did — so `manageDefault: true`
means **adopting a live object**, and the live one serves the console and the
ArgoCD route. That is the path you would use to undo this, which is why what it
asserts matters more than usual.

On acm-hub it asserts three things and nothing else:

- `defaultCertificate` → `cert-manager-ingress-cert`
- `replicas: 3` — one router per node on a compact three-node cluster, up from
  the 2 the installer left
- `logging.access` — HAProxy access logs to a `Container` sidecar on each router
  pod

`placement` and `endpointPublishingStrategy` stay **empty**, and each would
misbehave differently if filled:

- `endpointPublishingStrategy` is documented as **not updatable**. The installer
  records its choice in *status* and leaves spec empty, so writing any value adds
  a field the operator will not act on and ArgoCD will re-apply forever —
  permanently OutOfSync, with nothing switching over.
- `placement` is **mutable**, which is what makes it the dangerous one. See the
  `mastersSchedulable` coupling in Stage 1.

**Two of the three assertions restart the router**: the replica change and the
logging sidecar both roll the deployment. Three replicas means it rolls rather
than drops, but watch the first sync rather than walking away from it.

Naming a Secret that is not there degrades `IngressController/default` on its
own, so confirm it first. Diff before merging — on a chart that adopts, the
render *is* the change.

```bash
echo | openssl s_client -connect console-openshift-console.apps.<domain>:443 \
  -servername console-openshift-console.apps.<domain> 2>/dev/null \
  | openssl x509 -noout -issuer            # want: O=Let's Encrypt
oc get ingresscontroller default -n openshift-ingress-operator
```

The router picked up the new certificate on its own during the rebuild; if it
has not, `oc rollout restart deployment/router-default -n openshift-ingress`.

### 4.7 `openshift-apiserver` — `platformCharts`

Last, deliberately. `oc` against the API endpoint is the recovery path when
anything above goes wrong, so the API endpoint is the last thing to disturb.

**Enabling the chart is not what wires the certificate up.** `apiServer:
include: true` on its own renders `audit.profile: Default`, which already equals
the live spec — a no-op adoption that leaves the certificate unused and looks
exactly like success. The actual change is the `servingCerts.namedCertificates`
block in `platform-config.yaml`, and on acm-hub it was missing for an entire
rebuild because the chart's HANDOFF claimed a `certificates.api` block that
belongs to `tls-certificates` as evidence the work was done.

```yaml
apiServer:
  include: true
  servingCerts:
    namedCertificates:
      - names:
          - api.<cluster-domain>          # must match certificates.api.dnsNames
        servingCertificate:
          name: cert-manager-api-cert     # must match certificates.api.secretName
```

Unlike ingress, **the failure here is not recoverable through the thing it
breaks**. A named certificate is a reference the API server resolves at apply
time, not a copy, so naming a Secret that is absent takes down the API server —
including the path you would fix it through. Confirm it is present and Ready in
`openshift-config` first, every time.

Two consequences of a successful merge:

- **The rollout touches every master, one at a time.** Budget 10–15 minutes of
  `kube-apiserver` Progressing on a three-node control plane, and do not read it
  as a failure before then.
- **Every CA-pinned kubeconfig stops working** — including
  `install-<cluster>/auth/kubeconfig`, which is the only admin credential and
  what `make destroy-hub` reads. The certificate is SNI-scoped to the names
  listed, so `api-int.<domain>` keeps the internal signer and in-cluster clients
  are unaffected.

Keep the original as break-glass and work from a copy with the CA stripped, so
`oc` falls back to the system trust store (which has ISRG Root X1):

```bash
grep -v 'certificate-authority-data' install-<cluster>/auth/kubeconfig \
  > install-<cluster>/auth/kubeconfig-letsencrypt
```

Which of the two files works is the signal for whether the swap has landed:
before, only the original; after, only the stripped copy. `install-*/` is
gitignored, so neither is committed.

```bash
echo | openssl s_client -connect api.<cluster-domain>:6443 2>/dev/null \
  | openssl x509 -noout -issuer -subject
oc --kubeconfig=install-<cluster>/auth/kubeconfig-letsencrypt get nodes
oc get co kube-apiserver
```

If ACM is already on the cluster — as it is on acm-hub, which took these steps
out of order — also confirm `oc get managedcluster local-cluster` is still
Available. Its `managedClusterClientConfigs` lists the **external** API URL, so
it is in scope for this change; its `caBundle` already carries the ISRG roots
alongside the internal signers, which is why it survives the swap.

### 4.8 ODF — `operatorCharts`

**The one that needs preparation rather than a list entry**, and the reason it
sits here rather than at position 4. It is the only component in this runbook
big enough to not fit, and a cluster that is otherwise light is the only place
you can find that out cleanly.

Two things to settle *before* adding the name:

**The node selector probably means the opposite of what it says.**
`clusters/<env>/<cluster>/operators/odf.yaml` selects
`node-role.kubernetes.io/worker Exists`, and its comment explains that this
keeps Ceph off the control plane. That was true on a cluster with dedicated
workers. On a **compact** cluster every node carries the worker role (Stage 1),
so the same selector now places Ceph **directly on the control plane** — which
is the configuration that caused the original failure. Read the selector against
the live node labels, not against the comment:

```bash
oc get nodes -L node-role.kubernetes.io/worker -L node-role.kubernetes.io/infra
```

**Capacity, measured rather than assumed.** ODF on `lean` measured ~14.4 vCPU
last time. Take the baseline first:

```bash
oc describe nodes | grep -A4 'Allocated resources'
oc get pods -A --field-selector=status.phase=Pending
```

Then **re-measure after the StorageClasses appear** — the CSI plugins and CephFS
show up late, so an early reading understates it.

The failure mode to watch for is specific and not self-healing: ODF's requests
hold the nodes near their CPU-request ceiling, and the pods that lose are
**DaemonSet** pods. A DaemonSet pod is pinned to its node, so **adding nodes
cannot rescue it** — it stays `Pending` on the node it was scheduled to. If that
happens, the fix is more nodes *and then* `mastersSchedulable: false`, in that
order, because flipping the flag first strands everything.

**The device set, as sized on acm-hub.** One OSD per node, backed by EBS rather
than local disk:

```yaml
deviceSets:
  count: 1
  replicas: 3
  storageSize: 1Ti
  storageClassName: gp3-csi     # ebs.csi.aws.com, the cluster default
```

3Ti raw, ~1Ti usable at 3x replication. `portable: true` in the template plus
gp3-csi's `WaitForFirstConsumer` binding creates each PVC in the zone its OSD
lands in, so with one node per AZ the volumes spread one per AZ and the zone
failure domain holds — no topology configuration needed. Every Ceph write is a
network write to EBS, so OSD latency is EBS latency; that is the trade on AWS
IPI with no instance store. Growing later is an expansion
(`allowVolumeExpansion: true` on gp3-csi), or another `count` for another OSD
per node.

One silent failure to know in advance: if the StorageCluster sits in
`Progressing` with Ceph reporting `HEALTH_OK` and **no `ocs-storagecluster-*`
StorageClasses**, read the `rook-ceph-operator` log for `key rotation cron job`
before anything else. An encryption key-rotation schedule that is not a valid
CronJob expression is accepted by the CRD and only fails much later, where it
aborts the OSD reconcile and looks exactly like slow initialisation.

```bash
oc get storagecluster -n openshift-storage      # Ready
oc get sc                                       # the Ceph StorageClasses
oc get cephcluster -n openshift-storage         # HEALTH_OK
oc get pods -A --field-selector=status.phase=Pending
```

### 4.9 `advanced-cluster-management` — `operatorCharts`

What makes this cluster a hub rather than a cluster. Skip it entirely on a
spoke. Installs the operator and the `MultiClusterHub`; `gitopsCluster` and the
ACM/MCE console plugins come with it.

After ODF for two reasons. The dependency: `multiClusterObservability` needs ODF
serving object storage, so with ODF already up it can be enabled in the same
pass rather than deferred and forgotten. And the diagnostics: ACM fails slowly,
so landing it on a cluster whose storage is already settled means a hub that
never comes up is an ACM problem rather than an open question.

Left off deliberately: `assistedService` and `hiveConfig` — the
`AgentServiceConfig` alone asks for 160Gi of PVCs, and nothing here provisions
bare metal.

**This one fails slow rather than hard.** The chart's wave ladder is 0 CRD wait
→ 1 MultiClusterHub → 2 MCH-Running wait → 3 the rest, and **both wait jobs are
Sync hooks with no timeout**. A hub that never reaches Running does not fail the
Application, it holds it Progressing indefinitely. Give the MCH a good fifteen
minutes before reading Progressing as a fault.

Watch capacity on the first sync, and if pods go `Pending`, **add capacity
rather than quietly dropping `availabilityConfig` to Basic**.

```bash
oc get multiclusterhub -n open-cluster-management   # phase must reach Running
oc get managedcluster local-cluster                 # Available
oc get pods -A --field-selector=status.phase=Pending
```

### 4.10 `deployPolicies: true` — `conf.yaml` (optional)

**Optional, and genuinely so.** A cluster is fully configured without it. The
ApplicationSet renders every policy with `REMEDIATION=inform`, so they report
drift rather than repair it: policies attest, and the platform-config charts
configure. Turning this on changes what you can *see*, not what the cluster
*does*. The one exception is `cluster-labels`, pinned to `enforce` in its own
generator config because `ManagedCluster` labels have no other writer.

It cannot come earlier. The gate is the **MultiClusterHub reporting Running**,
from the previous step — *not* its Subscription reaching `AtLatestKnown`. The
seven `policy.open-cluster-management.io` CRDs arrive with the MCH, not with the
CSV. Turned on before that, the first sync produces nine Applications stuck
`Missing` against resources that do not exist.

Last is also where it is most useful. A policy with nothing in scope reports
NonCompliant, and on acm-hub — where this went on at position 5, before the
teams and the certificate chain — `resource-quota` and `network-isolation` sat
NonCompliant with nothing to evaluate for days. Enabled here, the things they
attest already exist, so the first report is signal rather than noise.

```bash
oc get policy -A
oc get placement -A
```

See [acm-policies.md](governance/acm-policies.md).

---

## Stage 5 — promote the charts to `proven`

Only after a chart has been verified doing its job on the live cluster. Per
chart, **atomically** — the gate enforces all three together:

1. `oca.io/maturity: proven`
2. add `oca.io/proven-on: <cluster>@<YYYY-MM-DD>`
3. **remove** `oca.io/under-test` — a `proven` chart still carrying it fails as
   `CONFUSED`

Then regenerate the published table, or `--check` fails with `STALE`:

```bash
./scripts/chart-readiness.sh --write
```

`oca.io/maturity` is historical — it records that a chart has run somewhere, not
that it is deployed now. The `under-test` hatch expires after 30 days
(`STALE_DAYS=30`), and the script is explicit that re-dating it is not the way
out. Promote, or withdraw the chart.

See [chart readiness](cluster-configuration/chart-readiness.md).

---

## Stage 6 — what is not done yet

As of 2026-10-13, acm-hub has run **every step of Stage 4**, with 4.8 (ODF) taken
last rather than in position because ACM and the policies went on early there.
Its ODF is internal mode, 3x 1Ti gp3 EBS OSDs — one per node and so one per AZ —
cluster-wide encryption, `lean`.

Still to run, in rough order of difficulty:

- **`openshift-proxy`** — the safe one. The installer already creates
  `Proxy/cluster` with an empty spec, so applying an empty spec adopts an object
  that is there anyway.
- **`etcd-backup` / `etcd-defrag`** — cheap, self-contained.
- **`openshift-scheduler`** — read the `mastersSchedulable` coupling in Stage 1
  first. `false` on a compact cluster strands everything, and ArgoCD applies it
  on the first sync, before anyone is watching.
- **`multiClusterObservability`** — off because it needs ODF serving object
  storage. On a cluster built in the order above it goes on with ACM at 4.9;
  here it was blocked on 4.8, which is now unblocked.
- The remaining platform-config charts, by the same loop.

---

## Appendix — end-to-end verification

| What | Command | Expect |
|---|---|---|
| App-of-apps | `oc get application platform-root -n openshift-gitops` | Synced / Healthy |
| ApplicationSet ownership | tracking-id jsonpath in Stage 2 | all eight name `platform-root` |
| Every Application | `oc get applications -n openshift-gitops` | Synced / Healthy, one per listed chart |
| Cluster operators | `oc get co` | none Degraded |
| Nothing stranded | `oc get pods -A --field-selector=status.phase=Pending` | empty |
| Vault | `oc get clustersecretstore vault` | READY True (re-unseal after any restart) |
| ODF | `oc get storagecluster -n openshift-storage` | Ready, and nothing newly Pending |
| ACM *(hub only)* | `oc get multiclusterhub -n open-cluster-management` | Running |
| Router cert | `openssl s_client` against the console route | `O=Let's Encrypt` |
| API cert | `openssl s_client` against `api.<domain>:6443` | `O=Let's Encrypt` |
| Readiness gate | `make validate` | green |

## Related

- [Bootstrapping a hub](cluster-configuration/bootstrap.md) — Stage 2 in full
- [Provisioning a hub](cluster-provisioning/bootstrap-hub.md) — Stage 1 in full
- [conf.yaml](cluster-configuration/conf-yaml.md) — the switches the generators read
- [ApplicationSet mechanics](cluster-configuration/applicationsets.md)
- [Values precedence](cluster-configuration/values-precedence.md)
- [Chart readiness](cluster-configuration/chart-readiness.md) — Stage 5
- [Let's Encrypt DNS-01 setup](day2-cluster-config/letsencrypt-dns01-setup.md) — steps 4.4, 4.6 and 4.7
- [Troubleshooting](troubleshooting.md)
