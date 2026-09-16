# cert-manager-certs — Handoff

## What it does
Creates cert-manager ClusterIssuers (self-signed and CA) and Certificate resources for API server and ingress TLS. Bootstraps a CA chain: self-signed root → CA issuer → leaf certs. Optionally copies the CA cert to a ConfigMap for the cluster trust bundle via a PostSync Job.

## Current state
- Disabled by default (all toggles `false`)
- Enabled for `aws-test` cluster (`clusters/dev/aws-test/operator-instances.yaml`) with self-signed + CA issuers + CA bundle
- Used alongside `tls-certificates` platform chart: this chart creates the ClusterIssuers, `tls-certificates` creates the leaf Certificate CRs
- CA bundle distributed via `caBundle` toggle — PostSync Job copies CA cert to ConfigMap in `openshift-config`, referenced by `openshift-proxy` chart for cluster trust
- Tested and deployed on aws-test (all apps Synced/Healthy)

## Outstanding
- **Missing dnsNames/SANs** — `certificates.yaml` leaf certs (apiCert/ingressCert) have no `dnsNames`; use `tls-certificates` platform chart for leaf certs instead
- **Hardcoded secret names** — `api-cert-tls` and `ingress-cert-tls` in `certificates.yaml`; not an issue when using `tls-certificates` chart for leaf certs
- **No ACME/Let's Encrypt issuer** — Only self-signed and internal CA; add ACME ClusterIssuer option for production use
