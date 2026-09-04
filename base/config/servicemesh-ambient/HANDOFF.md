# servicemesh-ambient — Handoff

## What it does
Deploys OpenShift Service Mesh 3.x (Sail-based / Istio upstream) in ambient mode. Creates Istio control plane, IstioCNI, Ztunnel, Kiali, and required namespaces. Uses the `sailoperator.io/v1` API.

## Current state
- **Not enabled** on any cluster (all components `include: false`)
- Not in any ApplicationSet element list
- Not tested
- This is the **Sail/Istio-based** (v3) ambient chart — separate from `servicemesh3-instance` which uses the Maistra `ServiceMeshControlPlane` API

## Outstanding
- Pilot resource requests are hardcoded (100m CPU, 256Mi memory) — parameterize in values.yaml
- No Istio Gateway or GatewayClass resources for traffic ingress
- No WaypointProxy configuration for L7 processing in ambient mode
- Missing mTLS/PeerAuthentication policy configuration
- Kiali `authStrategy` should be validated against the cluster's OAuth setup
- Ztunnel resource limits not configurable
- Clarify overlap with `servicemesh3-instance` chart — consider consolidating or documenting when to use which
