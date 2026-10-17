# pod-security

Attests that ... (what must be true, and on which clusters).

**Written by:** ... (the chart that actually creates this state; a policy here
only reports on it). See docs/governance/acm-policies.md for why that split exists.

## Checking it

```bash
oc get policy -n open-cluster-management-policies pod-security
oc get policy -A | grep pod-security   # propagated copies -- empty means the placement matched nothing
```
