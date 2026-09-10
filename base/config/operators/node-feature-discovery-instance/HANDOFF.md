# node-feature-discovery-instance — Handoff

## What it does
Deploys a `NodeFeatureDiscovery` CR that runs NFD workers on all nodes to detect hardware features (CPU flags, PCI devices, kernel config) and apply labels for scheduling decisions.

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`nodeFeatureDiscovery.include: false`)
- Not in any ApplicationSet
- Not tested

## Outstanding
- Operand image is hardcoded to `v4.22` — should be parameterized or removed (operator manages the image)
- `workerConfig.configData` is inline with a hardcoded blacklist and whitelist — should be parameterized or at least made overridable via values
- `kconfigFile` path `/path/to/kconfig` is a placeholder — needs the real path or removal
- PCI device class whitelist (`0200`, `03`, `12`) is opinionated — document what these classes are (network, display, processing) or parameterize
- `sleepInterval: 60s` may be too frequent for large clusters — consider making configurable
- `servicePort: 12000` is hardcoded — should be parameterized
- Missing `topologyUpdater` configuration for NodeResourceTopology
- Needs testing on a multi-node cluster to verify labels are applied correctly
