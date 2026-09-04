# mtv-controller — Handoff

## What it does
Deploys a `ForkliftController` CR for the Migration Toolkit for Virtualization (MTV). Enables VM migration from VMware/RHV/oVirt/OpenStack to OpenShift Virtualization with UI plugin, validation, and volume populator features.

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`forkliftController.include: false`)
- Commented out in hub ApplicationSet (`cluster-config.yaml`)
- Not tested

## Outstanding
- Feature flags (`feature_ui_plugin`, `feature_validation`, `feature_volume_populator`) are hardcoded to `true` — should be parameterized
- Missing `controller_max_vm_inflight` setting to limit concurrent migrations
- No `inventory_volume_size` or `controller_precopy_interval` configuration
- No VDDK init image configuration for VMware migrations (`feature_vddk_init_image`)
- Namespace defaults to `openshift-mtv` — verify this matches the operator's install namespace
- Needs testing with at least one source provider (VMware/RHV) configured
