# Compliance Operator Setup

Add `compliance` to `operatorCharts` in `conf.yaml`. That installs the operator and nothing else — the scans have their own `include: false` defaults. Turn them on in `operators.yaml`:

```yaml
compliance:
  operator:
    channel: stable
  scanSetting:
    include: true
  scanSettingBinding:
    include: true
```

`operator.channel` is required and has no default: the old `release-0.1` still resolves to v0.1.61 while `stable` is v1.10.x, and a Subscription on a stale-but-valid channel installs silently and stays years behind.

The chart defaults to daily STIG scans (ocp4-stig, ocp4-stig-node, rhcos4-stig profiles) at 01:00 UTC. Override `compliance.scanSetting.schedule` or `compliance.scanSettingBinding.profiles` for different profiles or timing.

**CRD quirk**: The compliance operator CRDs (ScanSetting, ScanSettingBinding) put all fields at the root level, not under `spec:`. The chart templates handle this correctly — if you're writing custom templates, don't nest fields under `spec`.

## TailoredProfiles

To customize a compliance profile (disable checks, change thresholds), add entries to `compliance.tailoredProfiles`:

```yaml
compliance:
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
compliance:
  scanSettingBinding:
    profiles:
      - name: custom-stig
        kind: TailoredProfile
        apiGroup: compliance.openshift.io/v1alpha1
```

The TailoredProfile renders at sync wave 0 and the ScanSettingBinding at wave 1, so the binding never names a profile that does not exist yet.
