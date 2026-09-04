# compliance-scans — Handoff

**Date:** 2026-09-04

## What it does
Configures OpenShift Compliance Operator scanning: ScanSetting (schedule, roles, tolerations, raw result storage), ScanSettingBinding (profile selection), and TailoredProfile (custom rule enable/disable).

## What was done this session
- Fixed spec nesting bug — ScanSetting fields were at wrong YAML indentation level
- Added TailoredProfile support for customizing compliance profiles with enable/disable rules
- Added rawResultStorage tolerations for control-plane node scanning
- Made scanTolerations configurable (default: tolerate all)
- Pre-configured STIG profiles (ocp4-stig, ocp4-stig-node, rhcos4-stig) with CIS/PCI-DSS commented

## Current state
- **Enabled** on dev cluster (`scanSetting.include: true`, `scanSettingBinding.include: true`)
- Disabled by default in values.yaml
- Not in any ApplicationSet yet — needs to be uncommented in `cluster-config.yaml`

## Gotchas
- `autoApplyRemediations: true` will automatically fix findings — use with caution, can reboot nodes
- Profiles must be installed by the Compliance Operator before binding references them
