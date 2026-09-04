# metallb-config — Handoff

## What it does
Deploys MetalLB instance and associated resources: IPAddressPools, L2Advertisements, BGPPeers, and BGPAdvertisements. Provides bare-metal LoadBalancer service support via Layer 2 or BGP mode.

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (all toggles `include: false`, empty lists)
- Commented out in hub ApplicationSet (`cluster-config.yaml`)
- Not tested

## Outstanding
- Well structured — each resource type has its own toggle and template, supports multiple pools/peers/advertisements via range loops
- MetalLB CR `spec` is empty — consider adding `nodeSelector` and `tolerations` for speaker pods
- IPAddressPool missing `autoAssign` and `avoidBuggyIPs` fields
- L2Advertisement missing `nodeSelectors` and `interfaces` fields for targeted announcements
- BGPPeer missing `holdTime`, `keepaliveTime`, `routerID`, `nodeSelectors`, and `password` (auth) fields
- No example values provided — add commented examples in values.yaml showing a sample L2 and BGP setup
- Needs testing on a bare-metal or vSphere cluster with the MetalLB operator installed
