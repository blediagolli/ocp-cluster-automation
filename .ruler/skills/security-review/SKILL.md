# Security Review

Use this skill when changes affect secrets, RBAC, cluster policies, operator installation, image sources, or network/security configuration.

## Instructions

- Search for committed credentials, tokens, pull-secret data, SSH material, kubeconfigs, and private registry credentials.
- Review RBAC for least privilege, especially `ClusterRoleBinding` and privileged service accounts.
- Check namespaces and labels used by security-sensitive controllers.
- Verify image registry, disconnected install, and image content source changes do not weaken provenance.
- Treat compliance, ACS, cert-manager, service mesh, logging, and marketplace changes as security-impacting.
- Flag broad policy selectors that could affect management or production clusters unexpectedly.

## Output Shape

- Findings first, ordered by severity.
- Include exact path and line.
- Include a concrete exploitation or failure scenario.
- Include the smallest credible fix.
