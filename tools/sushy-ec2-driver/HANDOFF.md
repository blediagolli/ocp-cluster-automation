# Sushy EC2 Driver — Handoff

## What It Is

A Redfish BMC emulator that maps Redfish API calls to AWS EC2 operations. Metal3/Ironic
treats EC2 instances as bare-metal servers, enabling OpenShift agent-based installation on
AWS with `platform: none`.

## Architecture

```
Metal3 BMO ──Redfish──▶ sushy-ec2-emulator (Flask) ──boto3──▶ AWS EC2 API
                              │
                              ├─ app.py        Redfish HTTP endpoints
                              ├─ ec2_driver.py  EC2 backend (power, boot, virtual media, reimage)
                              └─ Dockerfile     gunicorn, 2 workers, port 8000
```

**Key flow — "insert ISO and boot from CD":**
1. Ironic calls InsertVirtualMedia with an ISO URL → driver records it (no download)
2. Ironic sets boot device to `Cd` → driver records it
3. Ironic calls Reset/On → driver detects `boot_device=Cd + media_inserted + BOOT_AMI set`
4. Driver runs volume-swap reimage: stop instance → set user-data (minimal ignition) →
   detach old root → create volume from RHCOS AMI snapshot → attach as root → start
5. Instance boots RHCOS from fresh volume, ignition from EC2 user-data runs on first boot

**Minimal ignition** (must fit EC2's 16KB user-data limit):
- `agent.service` — discovery agent that registers with assisted-service
- `agent-fix-bz1964591` script
- Pull secret (`/root/.docker/config.json`)
- `restore-firstboot.service` — recreates `/boot/ignition.firstboot` on shutdown so the
  installed OS re-processes ignition after Ironic reimages
- `passwd` section (SSH keys for `core` user)
- CA cert is dropped (public CA is trusted)

## Current State (2026-09-16)

### Deployment
- **Namespace:** `aws-none-prod`
- **Service:** `sushy-ec2.aws-none-prod.svc:8000` (used in BMC addresses)
- **Image:** built via `podman` and pushed to internal registry
  (`default-route-openshift-image-registry.apps.cluster-c8444.dyn.redhatworkshops.io/aws-none-prod/sushy-ec2-emulator`)
- **Build note:** OpenShift BuildConfig was blocked by Quay webhook in this namespace;
  podman was used as a workaround

### Environment Variables (live deployment)
| Var | Value | Source |
|-----|-------|--------|
| `AWS_REGION` | `us-east-2` | Secret `sushy-ec2-aws-creds` |
| `AWS_ACCESS_KEY_ID` | (from secret) | Secret `sushy-ec2-aws-creds` |
| `AWS_SECRET_ACCESS_KEY` | (from secret) | Secret `sushy-ec2-aws-creds` |
| `SUSHY_EC2_BOOT_AMI` | `ami-00c830a23b63d4db9` | Deployment env |
| `SUSHY_EC2_IGNITION_URL` | **STALE — points to old infra-env** | Deployment env |
| `SUSHY_EC2_CONFIG` | `/config/instances.json` | Deployment env |

### EC2 Instances (us-east-2)
| Instance | Type | Role |
|----------|------|------|
| `i-0c7f5f12f9786b5f3` | m5.2xlarge | master-0 |
| `i-026c6c28c35033a71` | m5.2xlarge | master-1 |
| `i-08c15c603bfe4590d` | m5.2xlarge | master-2 |

All instances are **stopped**. Instance type was changed from m5.xlarge to m5.2xlarge
imperatively (not yet reflected in Terraform — see TODO).

### Cluster Resources
- **BMHs:** 3, in provisioning state
- **AgentClusterInstall:** status `insufficient` (waiting for agents)
- **InfraEnv:** recreated 2026-09-16T01:52:51Z (old one was stale)
- **Agents:** none registered

### Credentials
- **Ironic API:** `ironic-user` / `<from ironic-auth secret>` (via `localhost:6385`)
- **SSH key:** `~/.ssh/aws-none-prod` (EC2 key pair: `aws-none-prod-key`)
- **BMC auth:** `admin` / `password` (dummy — the emulator ignores these)

## What Was Done This Session

### Problems Found and Fixed

1. **Ignition firstboot flag consumed on discovery boot** — RHCOS only processes ignition
   once. After Ironic reimages the instance (volume swap), the installed OS skips ignition
   because `/boot/ignition.firstboot` was already consumed during discovery.
   - **Fix:** Added `restore-firstboot.service` to the minimal ignition. This systemd unit
     runs on shutdown/reboot and recreates the firstboot flag.

2. **SSH keys missing from minimal ignition** — couldn't SSH to instances for debugging.
   - **Fix:** Added `passwd` section pass-through in `_fetch_discovery_ignition()`.

3. **Ironic nodes stuck in `wait call-back`** — after deleting/recreating ClusterDeployment,
   old Ironic node records blocked new provisioning.
   - **Fix:** Used Ironic API to transition nodes to `deleted`:
     ```bash
     # From inside metal3-ironic pod:
     curl -sk -u ironic-user:$IRONIC_PASSWORD \
       -X PUT -H 'Content-Type: application/json' \
       -d '{"target":"deleted"}' \
       https://localhost:6385/v1/nodes/$NODE_UUID/states/provision
     ```

4. **`userManagedNetworking` missing** — platform `none` requires this but the chart
   template didn't set it.
   - **Fix:** Added conditional in `agentclusterinstall.yaml`:
     ```yaml
     {{- if eq .Values.cluster.platform "none" }}
     userManagedNetworking: true
     {{- end }}
     ```

5. **ArgoCD reverting uncommitted chart changes** — self-heal reverted
   `userManagedNetworking` because the chart change wasn't committed.
   - **Temporary fix:** Applied `argocd.argoproj.io/compare-options: IgnoreExtraneous`
     annotation. **Permanent fix:** commit the chart change.

6. **Stale InfraEnv after ClusterDeployment recreation** — agent registration failed with
   "infra-env id does not exist".
   - **Fix:** Deleted and recreated InfraEnv. New InfraEnv has a new discovery ignition URL
     that must be set on the emulator deployment.

### Files Modified (uncommitted)

- `tools/sushy-ec2-driver/ec2_driver.py` — restore-firstboot.service, passwd pass-through
- `charts/cluster-provisioning/openshift-provisioning/templates/agentclusterinstall.yaml` —
  userManagedNetworking conditional

## Before Next Installation Attempt

### Critical — must do first

1. **Update `SUSHY_EC2_IGNITION_URL`** on the emulator deployment to point to the new
   InfraEnv's discovery ignition URL:
   ```bash
   # Get the new URL:
   oc get infraenv aws-none-prod -n aws-none-prod -o jsonpath='{.status.isoDownloadURL}' \
     | sed 's|/downloads/image|/downloads/files?file_name=discovery.ign|; s|api_key=[^&]*|api_key=<TOKEN>|'
   # Or from the InfraEnv status:
   oc get infraenv aws-none-prod -n aws-none-prod -o yaml
   # Then patch the deployment:
   oc set env deployment/sushy-ec2-emulator -n aws-none-prod \
     SUSHY_EC2_IGNITION_URL='<new-url>'
   ```

2. **Commit the code changes** so ArgoCD manages them properly:
   - `ec2_driver.py` — firstboot fix + SSH key pass-through
   - `agentclusterinstall.yaml` — userManagedNetworking

### Should do

3. **Update `deploy/deployment.yaml`** reference manifest — it still references the old
   `SUSHY_EC2_S3_BUCKET` env var and is missing `SUSHY_EC2_BOOT_AMI` and
   `SUSHY_EC2_IGNITION_URL`.

4. **Update Terraform** — instance type was changed from m5.xlarge to m5.2xlarge
   imperatively. Update `terraform/aws-platform-none/variables.tf`:
   ```hcl
   variable "master_instance_type" {
     default = "m5.2xlarge"   # was m5.xlarge
   }
   ```

5. **Rebuild the emulator image** after committing `ec2_driver.py` changes.

### Nice to have

6. **NMStateConfig support** — the chart currently has no NMStateConfig template for
   platform `none`. User wants the option for both static IP and DHCP configurations.

## Reimage Cooldown

The driver has a 300-second cooldown (`REIMAGE_COOLDOWN`) per instance to prevent Ironic
retry loops from repeatedly reimaging. If Ironic sends multiple power-on requests within
5 minutes, the driver skips the volume swap and just starts the instance.

## Debugging Tips

- **Emulator logs:** `oc logs deployment/sushy-ec2-emulator -n aws-none-prod`
- **Ironic node state:** exec into `metal3-ironic` pod and use:
  ```bash
  curl -sk -u ironic-user:$IRONIC_PASSWORD https://localhost:6385/v1/nodes | python3 -m json.tool
  ```
- **SSH to instances:** `ssh -i ~/.ssh/aws-none-prod core@<private-ip>` (need VPN or
  bastion; instances are on private subnet 10.1.0.0/16)
- **Agent registration issues:** Check `/var/log/agent/agent.log` on the RHCOS instance
- **EC2 user-data:** Verify ignition was set: `aws ec2 describe-instance-attribute
  --instance-id <id> --attribute userData --region us-east-2`

## Infrastructure (Terraform)

AWS resources in `terraform/aws-platform-none/`:
- VPC with public/private subnets in us-east-2
- NLB for API (port 6443) and Ingress (ports 80, 443)
- Route53 DNS: `api.aws-none-prod.sandbox3321.opentlc.com`,
  `*.apps.aws-none-prod.sandbox3321.opentlc.com`
- Security groups allowing Redfish, API, SSH, inter-node traffic
- EC2 instances with `sushy-managed` tag
