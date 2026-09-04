## Compliance Report — Next Steps

### Current State
- `scripts/compliance-report.sh` works end-to-end: profiles, scans, results summary, HTML report generation
- Tested on a live cluster with CIS profile scan (ocp4-cis)
- Uses a UBI9 helper pod with `openscap-scanner` installed at runtime to generate HTML from ARF data in scan PVCs

### Planned: CronJob Helm Chart
Turn the report generation into a cluster-native CronJob so reports are generated automatically without admin intervention.

**Chart location:** `base/config/compliance-reports/` (new chart)

**What it should create:**
- **CronJob** — runs on a schedule (e.g. daily after scans complete), mounts scan result PVCs, runs `oscap xccdf generate report`, writes HTML to an output PVC or pushes to S3/OBC
- **PVC** (optional) — for storing generated HTML reports inside the cluster
- **ServiceAccount + RBAC** — the job needs read access to ComplianceScan resources and scan result PVCs in `openshift-compliance`

**Key decisions to make:**
1. **Output destination** — PVC (simple, serve via httpd sidecar or Route) vs. S3/OBC (scalable, integrates with ACM observability)
2. **Scan discovery** — hardcode PVC names in values, or have the job dynamically discover PVCs via `compliance.openshift.io/scan-name` labels (needs RBAC for PVC list)
3. **Image strategy** — bake a custom image with `openscap-scanner` pre-installed, or keep the UBI + `dnf install` approach (simpler but slower startup)

### Implementation notes
- The Compliance Operator stores ARF results in `.bzip2` files; decompressed data is in `.bzip2.out` — oscap reads from `.out` directly
- PVCs are labeled `compliance.openshift.io/scan-name=<scan-name>`
- Helper pods need master/control-plane tolerations if scan PVCs are bound to master nodes
- The existing `compliance-scans` Helm chart handles ScanSetting/ScanSettingBinding creation — the CronJob chart should complement it, not duplicate it
