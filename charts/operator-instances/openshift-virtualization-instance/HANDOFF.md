# openshift-virtualization-instance — Handoff

## What it does
Deploys the `HyperConverged` CR for OpenShift Virtualization (KubeVirt). Configures live migration limits, CPU allocation ratio, cert rotation, workload update strategy, and feature gates.

## Current state
- **Not enabled** — commented out in hub ApplicationSet, `include: false` in defaults
- **Not tested** this session
- Pre-existing chart, not modified this session

## Outstanding
- **Several hardcoded values** — `completionTimeoutPerGiB: 800`, `progressTimeout: 150`, `batchEvictionSize: 10`, cert durations should all be parameterized in values.yaml
- **Missing**: common boot image list, permitted host devices, mediatedDevices configuration (GPU passthrough), SRIOV integration, storage import settings
- **No `spec.infra` / `spec.workloads` node placement** — no way to pin virt components or VM workloads to specific nodes
- **`disableSerialConsoleLog: true` hardcoded** — should be configurable; some environments need serial console for debugging
- **No network configuration** — missing `NetworkAddonsConfig` reference, bridge/SRIOV/OVN secondary network setup
- Parameterize hardcoded values and add node placement before enabling
