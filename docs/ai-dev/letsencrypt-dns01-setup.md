# Let's Encrypt TLS for Managed Clusters (DNS01/Route53)

Replaces the self-signed CA chain with publicly trusted Let's Encrypt certificates. Uses DNS01 challenges via Route53 so the ACME server can verify domain ownership without needing inbound HTTP access to the cluster.

## How it works

```
┌─────────────────────────────────────────────────────────────────┐
│  cert-manager controller (on managed cluster)                   │
│                                                                 │
│  1. Sees a Certificate CR referencing the "letsencrypt" issuer  │
│  2. Creates an ACME Order → Let's Encrypt returns a challenge   │
│  3. Writes a TXT record to Route53:                             │
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

### 1. AWS credentials (CredentialsRequest)

cert-manager needs Route53 API access to create/delete TXT records. Rather than storing AWS keys in git, a `CredentialsRequest` tells the OpenShift Cloud Credential Operator (CCO) to provision a scoped IAM user with only Route53 permissions:

- `route53:GetChange`
- `route53:ChangeResourceRecordSets`
- `route53:ListResourceRecordSets`
- `route53:ListHostedZones`
- `route53:ListHostedZonesByName`

The CCO creates a Secret (`cert-manager-dns01-credentials`) in the `cert-manager` namespace automatically. No secrets in git.

**Chart:** `cert-manager-certs` → `clusterissuers.yaml`
**Values:** `acmeIssuer.dns01.credentialsSecretName`

### 2. Let's Encrypt ClusterIssuer

An ACME ClusterIssuer configured with:
- **Server:** `https://acme-v02.api.letsencrypt.org/directory` (production)
- **Solver:** DNS01 via Route53, pointing at the hosted zone ID
- **Credentials:** references the CCO-managed secret for both `accessKeyID` and `secretAccessKey`

**Chart:** `cert-manager-certs` → `clusterissuers.yaml`
**Values:** `acmeIssuer.*`

### 3. Recursive nameserver override (CertManager CR)

By default, cert-manager verifies DNS propagation by querying the domain's authoritative nameservers directly. This fails when the Route53 hosted zone's NS records aren't properly delegated from the parent zone (common in sandbox/workshop environments where the parent zone is managed externally).

The fix: `--dns01-recursive-nameservers-only` tells cert-manager to check propagation via public recursive resolvers (8.8.8.8, 1.1.1.1) instead. These follow the normal DNS resolution path and work regardless of NS delegation issues.

**Chart:** `cert-manager-certs` → `certmanager-config.yaml`
**Values:** `acmeIssuer.dns01.recursiveNameserversOnly`

### 4. Leaf certificates (tls-certificates chart)

The actual Certificate CRs for API server and ingress wildcard are in the `tls-certificates` platform chart. They reference the `letsencrypt` ClusterIssuer via `certManager.issuerRef.name`.

**Chart:** `tls-certificates` → `cert-manager.yaml`
**Values (cluster-level):** `platform-config.yaml` → `certManager.issuerRef.name: letsencrypt`

### 5. Proxy trust (not needed)

With Let's Encrypt, the signing CA (ISRG Root X1) is already in every OS/browser trust store. No custom CA bundle is needed in the cluster's Proxy config. The `openshift-proxy` chart renders with `trustedCA.name: ""` to clear any previous self-signed CA reference.

## File layout

```
charts/operator-instances/cert-manager-certs/
├── templates/
│   ├── clusterissuers.yaml      ← ACME issuer + CredentialsRequest
│   ├── certmanager-config.yaml  ← recursive nameserver override
│   ├── certificates.yaml        ← (unused — leaf certs in tls-certificates)
│   └── ca-bundle.yaml           ← (unused — no custom CA needed)
└── values.yaml                  ← acmeIssuer defaults

clusters/dev/aws-test/
├── operator-instances.yaml      ← enables acmeIssuer with zone ID + region
└── platform-config.yaml         ← points issuerRef at "letsencrypt"
```

## Enabling for a new cluster

### Prerequisites
- Cluster deployed on AWS with Cloud Credential Operator functional
- A Route53 hosted zone for the cluster's base domain
- cert-manager operator installed

### Steps

1. **Get the Route53 hosted zone ID** for the cluster's domain

2. **Set operator-instances.yaml** for the cluster:
   ```yaml
   acmeIssuer:
     include: true
     email: your-email@example.com
     dns01:
       region: <aws-region>
       hostedZoneID: <zone-id>
       recursiveNameserversOnly: true   # set true if NS delegation is indirect
   ```

3. **Set platform-config.yaml** for the cluster:
   ```yaml
   certManager:
     issuerRef:
       name: letsencrypt
       kind: ClusterIssuer
   ```
   Remove `proxy.trustedCA.name` if previously set to a self-signed CA bundle.

4. **Push to git** — ArgoCD syncs the changes:
   - CCO provisions Route53 credentials → cert-manager namespace
   - ClusterIssuer registers with Let's Encrypt
   - Certificate CRs trigger ACME DNS01 challenges
   - Certs issued and stored in Secrets
   - API server and router pick up the new certs

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
| TXT record missing in Route53 | `dig _acme-challenge.<domain> TXT` | Check CCO secret exists in cert-manager namespace; check IAM permissions |
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

## Current state (aws-test)

- **API cert:** Let's Encrypt, issuer CN=YE1, expires Dec 15 2026
- **Ingress cert:** Let's Encrypt, issuer CN=YE2, wildcard `*.apps.aws-test.sandbox3321.opentlc.com`
- **Renewal:** automatic, 15 days before expiry (renewBefore: 360h)
- **Hive admin kubeconfig:** patched to remove old CA data (2026-09-16)
- **Old self-signed resources:** orphaned on cluster (selfsigned/cluster-ca issuers, CA bundle Job) — safe to prune
