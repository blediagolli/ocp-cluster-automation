# cert-manager-certs — Handoff

## What it does
Creates cert-manager ClusterIssuers (self-signed and CA) and Certificate resources for API server and ingress TLS. Bootstraps a CA chain: self-signed root → CA issuer → leaf certs. Optionally copies the CA cert to a ConfigMap for the cluster trust bundle via a PostSync Job.

## Current state
- Disabled by default (all toggles `false`)
- Enabled for `aws-test` cluster (`clusters/dev/aws-test/operator-instances.yaml`) with ACME/Let's Encrypt issuer via DNS01/Route53
- ACME issuer uses a `CredentialsRequest` to have the cloud credential operator provision Route53-scoped AWS credentials (no secrets in git)
- Self-signed and CA issuers still available but disabled on aws-test
- Used alongside `tls-certificates` platform chart: this chart creates the ClusterIssuers, `tls-certificates` creates the leaf Certificate CRs
- Old self-signed resources (selfsigned/cluster-ca issuers, CA bundle Job) are orphaned on aws-test — safe to prune manually

## Outstanding
- **Missing dnsNames/SANs** — `certificates.yaml` leaf certs (apiCert/ingressCert) have no `dnsNames`; use `tls-certificates` platform chart for leaf certs instead
- **Hardcoded secret names** — `api-cert-tls` and `ingress-cert-tls` in `certificates.yaml`; not an issue when using `tls-certificates` chart for leaf certs
- **Orphaned self-signed resources on aws-test** — enable pruning or manually delete the old selfsigned ClusterIssuer, cluster-ca Certificate/ClusterIssuer, and ca-bundle-copier Job/RBAC
