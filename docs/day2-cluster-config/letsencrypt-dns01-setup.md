# Let's Encrypt TLS for Managed Clusters (DNS-01)

Replaces the self-signed CA chain with publicly trusted Let's Encrypt certificates. Uses DNS-01 challenges so the ACME server can verify domain ownership without needing inbound HTTP access to the cluster.

DNS-01 is not a preference here, it is the only option: HTTP-01 cannot issue the `*.apps` wildcard the router needs, and cannot reach the API server on port 6443 at all.

Two solvers are supported, chosen with `cert-manager.acmeIssuer.dns01.provider`:

| `provider` | Zone lives in | Credentials |
|---|---|---|
| `route53` | AWS Route53 | CCO mints a scoped IAM user → two keys |
| `cloudDNS` | GCP Cloud DNS | CCO mints a service account with a custom role → one JSON key |

The provider follows the **zone**, not the cluster. They happen to match on every cluster here, but a cluster whose base domain is delegated to another cloud sets the provider its zone lives in.

## How it works

```
┌─────────────────────────────────────────────────────────────────┐
│  cert-manager controller (on managed cluster)                   │
│                                                                 │
│  1. Sees a Certificate CR referencing the "letsencrypt" issuer  │
│  2. Creates an ACME Order → Let's Encrypt returns a challenge   │
│  3. Writes a TXT record to Route53 / Cloud DNS:                 │
│       _acme-challenge.<domain> = <token>                        │
│  4. Let's Encrypt verifies the TXT record exists                │
│  5. Let's Encrypt issues a signed certificate                   │
│  6. cert-manager stores it in the target Secret                 │
│  7. OpenShift picks up the new Secret (API server / router)     │
│                                                                 │
│  Renewal happens automatically before expiry (renewBefore)      │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Cloud credentials (CredentialsRequest)

cert-manager needs DNS API access to create and delete TXT records. Rather than storing cloud keys in git, a `CredentialsRequest` tells the OpenShift Cloud Credential Operator (CCO) to mint a scoped identity. Either way CCO writes a Secret (`cert-manager-dns01-credentials`) into the `cert-manager` namespace automatically, and nothing goes in git.

This depends on CCO running in **Mint** mode, which is the installer default on both clouds. Under `Manual` (including any WIF/STS setup) the Secret has to be created out of band — a per-cluster prerequisite the chart cannot cover.

**`provider: route53`** — a scoped IAM user:

- `route53:GetChange`
- `route53:ChangeResourceRecordSets`
- `route53:ListResourceRecordSets`
- `route53:ListHostedZones`
- `route53:ListHostedZonesByName`

Two keys in the Secret: `aws_access_key_id`, `aws_secret_access_key`.

**`provider: cloudDNS`** — a dedicated GCP service account with a custom role:

- `dns.changes.create`, `dns.changes.get`
- `dns.resourceRecordSets.{create,delete,list,update}`
- `dns.managedZones.{get,list}`

One key in the Secret: `service_account.json`.

The first five are the same set OpenShift's own `openshift-ingress-gcp` request uses for the `*.apps` record; the `managedZones` pair is cert-manager's addition, for looking the zone up and reading back its own propagation. Note this is deliberately **not** `roles/dns.admin`, which cert-manager's upstream docs suggest: that role also carries `managedZones.create` and `.delete`, i.e. the ability to delete the zone serving the cluster, handed to a controller that only ever writes one TXT record.

**Chart:** `operators/cert-manager` → `clusterissuers.yaml`
**Values:** `cert-manager.acmeIssuer.dns01.{provider,credentialsSecretName}`

### 2. Let's Encrypt ClusterIssuer

An ACME ClusterIssuer configured with:
- **Server:** `https://acme-v02.api.letsencrypt.org/directory` (production)
- **Solver:** DNS-01, `route53` (region + hosted zone ID) or `cloudDNS` (project + managed zone name)
- **Credentials:** references the CCO-managed secret

An unrecognised `provider` fails the render. It has to: the alternative is a `CredentialsRequest` CCO ignores sitting next to an issuer with no solver, which reports Ready and then hangs every challenge.

**Chart:** `operators/cert-manager` → `clusterissuers.yaml`
**Values:** `cert-manager.acmeIssuer.*`

#### Pick the right zone

On both clouds the zone that matters is the one **authoritative for the challenge record**, which is not the cluster's own.

- **Route53** — `hostedZoneID` is the *parent* zone (`example.com`), because the per-cluster zone is private and cannot serve a public `_acme-challenge` record.
- **Cloud DNS** — `hostedZoneName` is the managed zone's **resource name** (`YOUR_GCP_DNS_ZONE`), not its DNS name (`example.com.`). It is nominally optional — cert-manager discovers the zone when it is empty — but set it on anything GCP IPI built. The installer creates a *private* zone for the cluster's subdomain alongside the public parent, so discovery has two candidates for exactly the names being validated, and picking the private one writes a record Let's Encrypt cannot resolve.

Read it off the cluster rather than guessing:

```bash
oc get dns.config cluster -o jsonpath='{.spec.publicZone.id}{"\n"}'
# projects/YOUR_GCP_PROJECT_ID/managedZones/YOUR_GCP_DNS_ZONE
#          └ projectID                 └ hostedZoneName
```

That same split horizon is why `recursiveNameserversOnly: true` is effectively required on GCP IPI: the cluster's own resolver answers from the private zone, so cert-manager's self-check never sees the record it just wrote.

### 3. Recursive nameserver override (CertManager CR)

By default, cert-manager verifies DNS propagation by querying the domain's authoritative nameservers directly. This fails whenever the answer from those servers is not the answer Let's Encrypt will get — two distinct causes, both common here:

- **Indirect delegation**, where the hosted zone's NS records aren't delegated from the parent zone. Normal in sandbox/workshop environments, where the parent is managed externally.
- **Split horizon**, where a private zone shadows the public one for exactly the names being validated. This is every GCP IPI cluster: the installer creates `<cluster>-<infraID>-private-zone` for the cluster's own subdomain.

The fix: `--dns01-recursive-nameservers-only` tells cert-manager to check propagation via public recursive resolvers (8.8.8.8, 1.1.1.1) instead. These follow the normal DNS resolution path and work regardless of NS delegation issues.

**Chart:** `operators/cert-manager` → `certmanager-config.yaml`
**Values:** `cert-manager.acmeIssuer.dns01.recursiveNameserversOnly`

### 4. Leaf certificates (tls-certificates chart)

The actual Certificate CRs for API server and ingress wildcard are in the `tls-certificates` platform chart. They reference the `letsencrypt` ClusterIssuer via `certManager.issuerRef.name`.

**Chart:** `tls-certificates` → `cert-manager.yaml`
**Values (cluster-level):** `platform-config.yaml` → `certManager.issuerRef.name: letsencrypt`

### 5. Proxy trust (not needed)

With Let's Encrypt, the signing CA (ISRG Root X1) is already in every OS/browser trust store. No custom CA bundle is needed in the cluster's Proxy config. The `openshift-proxy` chart renders with `trustedCA.name: ""` to clear any previous self-signed CA reference.

## File layout

```
charts/operators/cert-manager/
├── templates/
│   ├── install/                 ← the shared install block (waves -30..-28)
│   ├── clusterissuers.yaml      ← ACME issuer + CredentialsRequest
│   ├── certmanager-config.yaml  ← recursive nameserver override
│   ├── certificates.yaml        ← (unused — leaf certs in tls-certificates)
│   └── ca-bundle.yaml           ← (unused — no custom CA needed)
└── values.yaml                  ← acmeIssuer defaults

clusters/<env>/<cluster>/
├── conf.yaml                    ← lists cert-manager in operatorCharts,
│                                  tls-certificates in platformCharts
├── operators.yaml               ← enables acmeIssuer, picks the solver
└── platform-config.yaml         ← points issuerRef at "letsencrypt",
                                   declares the certificates
```

Worked example in the tree: `clusters/mgt/acm-hub` (route53). The `cloudDNS` counterpart was `clusters/dev/gcp-sno-dev`, deleted on 2026-10-15 with its cloud environment — recover it with `git show 462358a:clusters/dev/gcp-sno-dev/operators.yaml` if you need the annotated original, and see "Current state" below for what it proved.

## Enabling for a new cluster

### Prerequisites
- Cloud Credential Operator functional and in **Mint** mode
- A **public** hosted zone authoritative for the cluster's base domain
- `cert-manager` listed in the cluster's `operatorCharts`. With `installOperators: true` the chart installs the operator itself; with `false` it only renders the CRs and assumes the operator is already there.

### Steps

1. **Find the public zone.** On an IPI cluster the cluster itself knows:
   ```bash
   oc get dns.config cluster -o jsonpath='{.spec.publicZone}{"\n"}'
   ```
   Note that this is deliberately not `.spec.privateZone`, which is the one that cannot serve the challenge.

2. **Set operators.yaml** for the cluster — AWS:
   ```yaml
   cert-manager:
     operator:
       channel: stable-v1
     acmeIssuer:
       include: true
       email: your-email@example.com
       dns01:
         provider: route53
         region: <aws-region>
         hostedZoneID: <zone-id>
         recursiveNameserversOnly: true   # true if NS delegation is indirect
   ```

   …or GCP:
   ```yaml
   cert-manager:
     operator:
       channel: stable-v1
     acmeIssuer:
       include: true
       email: your-email@example.com
       dns01:
         provider: cloudDNS
         projectID: <gcp-project>
         hostedZoneName: <managed-zone-resource-name>
         recursiveNameserversOnly: true   # effectively required on GCP IPI
   ```

3. **Set platform-config.yaml** for the cluster:
   ```yaml
   provider: cert-manager
   certManager:
     issuerRef:
       name: letsencrypt
       kind: ClusterIssuer
   ```
   Remove `proxy.trustedCA.name` if previously set to a self-signed CA bundle.

   Set `certificates.api.dnsNames` and `certificates.ingress.dnsNames` explicitly. The chart derives them from `cluster.baseDomain` when they are empty, and `cluster.baseDomain` in this repo is the *apps* domain — so the derived names come out as `api.apps.<cluster>…` and `*.apps.apps.<cluster>…`, which issue cleanly and match nothing.

4. **Push to git** — ArgoCD syncs the changes:
   - CCO provisions DNS credentials → cert-manager namespace
   - ClusterIssuer registers with Let's Encrypt
   - Certificate CRs trigger ACME DNS-01 challenges
   - Certs issued and stored in Secrets

5. **Only then** point the API server and router at them — `openshift-apiserver`'s `servingCerts.namedCertificates` and `openshift-ingress`'s `defaultCertificate`. Naming a Secret that is not yet there degrades the object naming it, and on the API server of a single-node cluster that is not a degradation you can `oc` your way out of. Wait for both Certificates to report `Ready=True` first; this is a separate commit, not a separate paragraph of the same one.

### Timeline
- CredentialsRequest → Secret: ~30 seconds
- ACME registration: ~5 seconds
- DNS01 challenge + verification: 1–3 minutes per cert
- Router/API server cert reload: may need a rollout restart

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| ClusterIssuer not ready | `oc get clusterissuer letsencrypt -o yaml` | Check ACME server reachability and email validity |
| Challenge stuck "pending" | `oc get challenges -A -o wide` | Check the reason — usually DNS propagation or credential issues |
| "REFUSED" from nameservers | Challenge querying wrong NS | Enable `recursiveNameserversOnly: true` |
| TXT record missing in the zone | `dig _acme-challenge.<domain> TXT` | Check the CCO secret exists in the cert-manager namespace; check the minted identity's permissions |
| TXT record written but never resolves (GCP) | `gcloud dns record-sets list --zone=<private-zone>` | It went into the cluster's private zone. Pin `hostedZoneName` to the public one |
| CCO secret never appears | `oc get credentialsrequest -n openshift-cloud-credential-operator cert-manager-dns01 -o yaml` | `provisioned: false` with a Manual-mode message means CCO is not minting — create the Secret out of band |
| Cert issued but browser still "not secure" | Old cert cached in router | `oc rollout restart deployment/router-default -n openshift-ingress` |
| Console/auth x509 errors after switch | Pods still trust old CA | They self-heal on rollout — wait for pod restart or restart manually |
| Rate limited by Let's Encrypt | Too many certs for same domain in a week | Use staging server (`acme-staging-v02`) for testing |
| ACM shows "Unreachable" / x509 after cert switch | Hive's admin kubeconfig has old CA | See "Post-switch: fixing Hive/ACM connectivity" below |

## Post-switch: fixing Hive/ACM connectivity

When you switch the API server cert from a self-signed CA to Let's Encrypt, the Hive `ClusterDeployment` on the hub will show `Unreachable: True` with an x509 error. This happens because:

1. Hive stores an admin kubeconfig for each managed cluster as a Secret in the cluster's namespace on the hub
2. That kubeconfig contains `certificate-authority-data` with the original OpenShift-generated kube-apiserver CA
3. When Hive connects to the spoke API, it validates the cert against **only** that CA bundle — not the system trust store
4. The new Let's Encrypt cert isn't signed by that CA, so validation fails

The fix is to remove `certificate-authority-data` from the kubeconfig so Hive falls back to the system trust store, which already has the ISRG Root X1 (Let's Encrypt root).

### Steps

Find the admin kubeconfig secret name:
```bash
oc get secret -n <cluster-namespace> -o name | grep admin-kubeconfig
```

The secret has two keys that both need patching: `kubeconfig` and `raw-kubeconfig`.

For each key:
```bash
# Extract
oc get secret <secret-name> -n <cluster-namespace> \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/kc.yaml

# Remove the CA data
grep -v 'certificate-authority-data' /tmp/kc.yaml > /tmp/kc-patched.yaml

# Verify it works
KUBECONFIG=/tmp/kc-patched.yaml oc whoami

# Patch the secret
PATCHED_B64=$(base64 < /tmp/kc-patched.yaml)
oc patch secret <secret-name> -n <cluster-namespace> \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/data/kubeconfig\", \"value\": \"${PATCHED_B64}\"}]"
```

Repeat with `/data/raw-kubeconfig` in the jsonpath and patch path.

Hive reconciles within ~60 seconds. The `Unreachable` condition should flip to `False` and the ACM console will show the cluster as reachable.

### Why both keys?

- `kubeconfig` — used by some Hive controllers and the ACM console
- `raw-kubeconfig` — the original kubeconfig as generated during install, also used by Hive for reachability checks

Both contain the same `certificate-authority-data` and both need to be patched.

### Will Hive overwrite the patch?

No. Hive only generates this secret at install time. It does not reconcile the kubeconfig contents afterward, so the patch persists. If cert-manager renews the Let's Encrypt cert, no action is needed — the new cert is still signed by the same trusted CA chain.

## Current state

Checked 2026-10-15. One live cluster uses this, and one proved the other solver before being destroyed.

### acm-hub — `route53`, complete

- **ClusterIssuer:** `letsencrypt`, `Ready=True`, production ACME, DNS-01 via Route53 against the parent zone `example.com`
- **API cert:** `cert-manager-api-cert` in `openshift-config`, `Ready=True`, expires 2027-01-11, renews 2026-12-27
- **Ingress cert:** `cert-manager-ingress-cert` in `openshift-ingress`, `Ready=True`, wildcard `*.apps.CLUSTER_DOMAIN`
- **Both consumed:** the router since #70, `APIServer/cluster` since #73
- **Consequence:** `install-acm-hub/auth/kubeconfig` no longer works, because it pins `certificate-authority-data` to the internal signer. Use the CA-stripped copy.

### gcp-sno-dev — `cloudDNS`, destroyed 2026-10-15

The cluster is gone: its RHDP OPEN environment (`YOUR_GCP_PROJECT_ID`) was reclaimed and
`clusters/dev/gcp-sno-dev` was deleted with it. **The `cloudDNS` solver is not gone** —
it lives in `charts/operators/cert-manager` and is unchanged. This is the record of the
only end-to-end run it has had, kept because that run is the entire evidence base for
the solver and there is currently no GCP cluster to re-prove it on.

What it demonstrated, observed on the cluster on 2026-10-14 before teardown:

- **ClusterIssuer:** `letsencrypt`, `Ready=True`, production ACME, DNS-01 via Cloud DNS against `YOUR_GCP_DNS_ZONE` in `YOUR_GCP_PROJECT_ID`, `recursiveNameserversOnly: true`
- **Both certificates issued on the first sync** — `cert-manager-api-cert` in `openshift-config` and `cert-manager-ingress-cert` in `openshift-ingress`, `Ready=True`, issuer `C=US, O=Let's Encrypt`, expiring 2027-01-12, SANs `api.gcp-sno-dev…` and `*.apps.gcp-sno-dev…` plus the bare apps domain. No retried challenges.
- **CCO minted the credential** from the eight named permissions, `provisioned: true`, with the single `service_account.json` key — so `roles/dns.admin` is genuinely unnecessary, not merely believed to be.
- **Both consumed** one merge after issue, per step 5 above. Verified from outside the cluster: `api:6443` and the console route both presented the Let's Encrypt chain, and the CA-pinned admin kubeconfig started failing with `x509: certificate signed by unknown authority`, which is the confirming negative.

What it did **not** get to prove: the `hostedZoneName` / `recursiveNameserversOnly` pair
were set from the start, so the split-horizon failure they defend against was never
actually observed on this cluster. The reasoning for them is in "Pick the right zone"
above and rests on the zone layout GCP IPI creates, which was confirmed — the
installer's `<cluster>-<infraID>-private-zone` did exist alongside the public parent,
covering exactly the names being validated. Deliberately untested: a wrong solver
configuration burns Let's Encrypt's five-failed-validations-per-hour budget.

Also untested: the Hive/ACM reachability fix below. This was a *managed* cluster, so it
needed the admin-kubeconfig CA strip, and the environment was reclaimed before that was
applied. The procedure is the same one acm-hub's own kubeconfig needed and is documented
from that; treat it as verified for the hub case and unverified for the managed case.
