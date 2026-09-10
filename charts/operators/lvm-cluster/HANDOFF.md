# lvm-cluster — Handoff

## What it does
Deploys an `LVMCluster` CR for the LVM Storage operator (TopoLVM). Creates a volume group device class with thin provisioning on nodes, providing dynamic PV provisioning via a generated StorageClass.

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`lvmCluster.include: false`)
- Commented out in hub ApplicationSet (`cluster-config.yaml`)
- Not tested

## Outstanding
- Only supports a single device class — production setups may need multiple (e.g. SSD + HDD tiers)
- No `deviceSelector` (paths/optionalPaths) to control which block devices are used — currently uses all available
- No `nodeSelector` to restrict which nodes get LVM volumes
- `chunkSizeCalculationPolicy` and `metadataSizeCalculationPolicy` are hardcoded — should be parameterized
- Missing optional `tolerations` for dedicated storage nodes
- Needs testing on a cluster with the LVM Storage operator and available block devices
