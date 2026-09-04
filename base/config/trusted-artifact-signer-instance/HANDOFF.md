# trusted-artifact-signer-instance — Handoff

## What it does
Deploys Red Hat Trusted Artifact Signer (RHTAS) for software supply chain signing and verification. Configures Fulcio (certificate authority), Rekor (transparency log), and TUF (update framework) via the `RHTAS` CR.

## Current state
- **Not enabled** on any cluster (`include: false`)
- Not in any ApplicationSet element list
- Not tested

## Outstanding
- Minimal configuration — only toggles for Fulcio, Rekor, and TUF with no sub-configuration
- Missing Fulcio issuer/CA configuration (OIDC issuer URL, certificate chain)
- Missing Rekor storage backend configuration (default uses in-memory; needs persistent storage for production)
- No TUF root/target repository configuration
- No Cosign/Tekton Chains integration configuration
- No resource limits or replica counts
- Should add `ClusterImagePolicy` or `ImagePolicy` resources for admission-time signature verification
- API is `v1beta1` — verify compatibility with the installed operator version
