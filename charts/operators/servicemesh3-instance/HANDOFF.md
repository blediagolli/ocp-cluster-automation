# servicemesh3-instance — Handoff

## What it does
Deploys a `ServiceMeshControlPlane` (Maistra v2 API) with ambient mode via `techPreview.meshConfig.mode`. Configures Grafana, Jaeger, Kiali, Prometheus addons, ingress/egress gateways, proxy logging, and traffic control.

## Current state
- **Not enabled** on any cluster (`include: false`)
- Not in any ApplicationSet element list
- Not tested
- Uses `maistra.io/v2` API — this is the legacy SMCP approach vs the newer Sail-based `servicemesh-ambient` chart

## Outstanding
- Jaeger storage is `Memory` with 100k traces — not suitable for production; parameterize for Elasticsearch or Tempo backend
- No `ServiceMeshMemberRoll` or `ServiceMeshMember` resources to enroll namespaces
- Ingress gateway service type is `ClusterIP` — may need `LoadBalancer` or `Route` for external traffic
- No mTLS policy configuration (PeerAuthentication)
- No resource limits on any component
- Clarify relationship with `servicemesh-ambient` chart — document which to use (Maistra SMCP vs Sail Istio)
- `techPreview.meshConfig.mode: ambient` may not be stable across OCP versions
