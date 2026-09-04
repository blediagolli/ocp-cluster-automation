# project-request-template — Handoff

## What it does
The most comprehensive chart in the repo. Deploys an OpenShift `Template` that defines what gets created in every new project namespace. Includes:
- Project with configurable labels, annotations, pod security standards
- Default-deny NetworkPolicies with granular allow rules (ingress, monitoring, API server)
- ResourceQuota and LimitRange defaults
- RoleBindings (admin for requesting user + additional custom bindings)
- ServiceAccount with optional imagePullSecrets
- EgressFirewall rules (OVN)
- Project config (request message) and self-provisioner ClusterRoleBinding removal

Also manages `projectConfig` (sets the custom project request template on the cluster) and `selfProvisioners` (removes the default self-provisioner ClusterRoleBinding).

## Current state
- **Enabled on hub** — in ApplicationSet and synced, `projectConfig.include: true`, `selfProvisioners.include: true`
- **Tested** — synced and healthy on hub cluster
- Pre-existing chart, not modified this session

## Outstanding
- **Well-parameterized** — one of the most complete charts; most features are toggleable
- **No egress NetworkPolicy** — only ingress policies are created; consider adding default egress rules alongside the EgressFirewall
- **No resource quota for services/configmaps/secrets** — only CPU, memory, pods, PVCs, and storage are quotaed
- **No annotation-based overrides** — no way for project owners to request non-default quotas via annotations
- Generally production-ready as-is; test with a project creation to verify the template renders correctly
