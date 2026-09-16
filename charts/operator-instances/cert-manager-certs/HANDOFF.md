# cert-manager-certs — Handoff

## What it does
Creates cert-manager ClusterIssuers (self-signed and CA) and Certificate resources for API server and ingress TLS. Bootstraps a CA chain: self-signed root → CA issuer → leaf certs.

## Current state
- Disabled by default (all toggles `false`)
- Enabled for `aws-test` cluster (`clusters/dev/aws-test/operator-instances.yaml`) with self-signed + CA issuers
- Used alongside `tls-certificates` platform chart: this chart creates the ClusterIssuers, `tls-certificates` creates the leaf Certificate CRs

## Outstanding
- **Missing dnsNames/SANs** — API and ingress certificates have no `dnsNames` or `subject` fields; cert-manager will generate certs without SANs, which most TLS clients reject
- **Missing commonName** — Leaf certificates don't set `commonName`
- **Hardcoded secret names** — `api-cert-tls` and `ingress-cert-tls` are hardcoded in templates; should be parameterized
- **No ACME/Let's Encrypt issuer** — Only self-signed and internal CA; add ACME ClusterIssuer option for production use
- **No APIServer/IngressController patching** — After creating certs, the API server and ingress controller need to be configured to use them (via openshift-apiserver and openshift-ingress charts)
- **Needs testing** — Deploy with cert-manager operator installed
