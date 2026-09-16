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

## Current state

- **Enabled on aws-test** — kubeletconfig-worker, kubeletconfig-master, containerruntimeconfig active with defaults
- Chrony, kernel args, SELinux permissive, infra MCP remain optional (`include: false`)
- **Generic `customMachineConfigs` template** — define arbitrary MachineConfigs via values (files + kernel args) without creating new templates. See commented examples in `values.yaml`.

## Outstanding

- Tune eviction thresholds per-cluster based on workload density
- Configure NTP servers if not using defaults (AWS clusters use Amazon Time Sync by default)
