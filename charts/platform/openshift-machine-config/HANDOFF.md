# openshift-machine-config — Handoff

**Modified:** 2026-09-04 (deep dive agents)

## What it does

Manages node-level configuration via the Machine Config Operator. Templates:
- **KubeletConfig** (worker + master) — maxPods, image GC, eviction thresholds, API QPS/burst
- **ContainerRuntimeConfig** — CRI-O pidsLimit, log size, log level
- **MachineConfig chrony** — NTP server configuration
- **MachineConfig kernel** — kernel arguments and sysctls
- **SELinux permissive** — opt-in only, disabled by default (compliance fix this session)
- **MachineConfigPool infra** — infra node pool with nodeSelector and maxUnavailable

## What changed this session

- Added KubeletConfig for master pool (was worker-only)
- Added ContainerRuntimeConfig template
- Added MachineConfig for kernel args and sysctls
- Made SELinux permissive opt-in (`include: false`) — was accidentally defaulting to permissive (critical bug fix)
- Added MachineConfigPool for infra nodes

## Current state

- Active on hub and clusters (in ApplicationSet shared config list)
- All new sections default to `include: false` — safe to sync without side effects

## Outstanding

- Tune eviction thresholds per-cluster based on workload density
- Configure NTP servers if not using defaults
