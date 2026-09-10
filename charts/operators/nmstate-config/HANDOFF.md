# nmstate-config — Handoff

## What it does
Deploys an `NMState` CR to enable the NMState operator, which provides node network configuration management via `NodeNetworkConfigurationPolicy` (NNCP) resources.

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`nmstate.include: false`)
- Not in any ApplicationSet
- Not tested

## Outstanding
- The NMState CR is minimal (empty spec) which is correct — the operator needs just the CR to start the handler DaemonSet
- No `NodeNetworkConfigurationPolicy` templates — this chart only activates the operator, doesn't configure any network interfaces. Consider adding NNCP templates for common patterns (bonding, VLAN, bridge, static IP)
- Missing `nodeSelector` support to limit which nodes run the nmstate handler
- No `NodeNetworkConfigurationEnactment` status monitoring
- Needs to be added to an ApplicationSet to be deployed
- Needs testing to verify the handler pods start on all nodes
