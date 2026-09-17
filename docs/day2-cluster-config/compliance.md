# Compliance Operator Setup

Add `compliance-operator` to `operator-deployment.yaml` (channel: `stable`) and `compliance-scans` to `operatorInstanceCharts` in `conf.yaml`. Enable scans in `operator-instances.yaml`:

```yaml
scanSetting:
  include: true
scanSettingBinding:
  include: true
```

The chart defaults to daily STIG scans (ocp4-stig, ocp4-stig-node, rhcos4-stig profiles) at 01:00 UTC. Override `scanSetting.schedule` or `scanSettingBinding.profiles` in `operator-instances.yaml` for different profiles or timing.

**CRD quirk**: The compliance operator CRDs (ScanSetting, ScanSettingBinding) put all fields at the root level, not under `spec:`. The chart templates handle this correctly — if you're writing custom templates, don't nest fields under `spec`.

## TailoredProfiles

To customize a compliance profile (disable checks, change thresholds), add entries to `tailoredProfiles` in `operator-instances.yaml`:

```yaml
tailoredProfiles:
  - include: true
    name: custom-stig
    title: Custom STIG Profile
    description: STIG profile with site-specific exclusions
    extends: ocp4-stig
    disableRules:
      - name: ocp4-scheduler-no-bind-address
        rationale: Not applicable in our environment
    enableRules: []
    setValues:
      - name: ocp4-var-openshift-audit-profile
        rationale: Audit profile must be WriteRequestBodies per policy
        value: WriteRequestBodies
```

Then reference the TailoredProfile in `scanSettingBinding.profiles`:

```yaml
scanSettingBinding:
  profiles:
    - name: custom-stig
      kind: TailoredProfile
      apiGroup: compliance.openshift.io/v1alpha1
```
