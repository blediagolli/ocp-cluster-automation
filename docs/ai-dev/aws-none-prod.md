# aws-none-prod — Platform None Provisioning on AWS

**Cluster:** aws-none-prod (prod environment, platform: none)
**Hub:** cluster-c8444 (management cluster)
**Region:** us-east-2

## Overview

OpenShift deployed on AWS EC2 instances using the agent-based installer (platform: none) instead of AWS IPI. A sushy-emulator with a custom EC2 driver provides Redfish BMC API for EC2 instances, enabling the full BareMetalHost/Metal3 workflow.

## Architecture

```
Hub cluster (cluster-c8444)
  sushy-ec2 namespace     — sushy-emulator (Redfish → EC2 API)
  aws-none-prod namespace — ClusterDeployment, AgentClusterInstall, InfraEnv, BMHs

AWS (us-east-2)
  3x EC2 masters (m5.xlarge) — compact cluster, no workers
  NLBs for API (6443) and ingress (443/80)
  Route53 DNS: api.aws-none-prod.sandbox3321.opentlc.com, *.apps.aws-none-prod.sandbox3321.opentlc.com
```

## Key Files

| File | Purpose |
|---|---|
| `clusters/prod/aws-none-prod/conf.yaml` | Cluster identity, chart lists, deploy toggles |
| `clusters/prod/aws-none-prod/provision.yaml` | Provisioning values: hosts, networking, BMC addresses |
| `charts/cluster-provisioning/openshift-provisioning/` | Provisioning Helm chart (shared across platforms) |
| `charts/cluster-provisioning/sushy-ec2-emulator/` | Sushy emulator Helm chart |
| `tools/sushy-ec2-driver/` | Custom sushy EC2 driver source code |
| `charts/cluster-provisioning/aws-platform-none-design.md` | Architecture design doc |

## Sushy EC2 Emulator

The emulator runs in a dedicated `sushy-ec2` namespace on the hub, separate from the cluster provisioning namespace. This separation means:

- Emulator survives namespace cleanup/reprovisioning cycles
- No chicken-and-egg with provisioning resources
- BMH addresses cross namespaces: `sushy-ec2.sushy-ec2.svc:8000`

### Deploying the emulator

```bash
# Deploy chart resources
helm template sushy-ec2-emulator charts/cluster-provisioning/sushy-ec2-emulator/ \
  --set bootAMI=<ami-id> \
  --set 'instances.i-<id1>.uuid=aws-none-prod-master-0' \
  --set 'instances.i-<id1>.role=master' \
  --set 'instances.i-<id2>.uuid=aws-none-prod-master-1' \
  --set 'instances.i-<id2>.role=master' \
  --set 'instances.i-<id3>.uuid=aws-none-prod-master-2' \
  --set 'instances.i-<id3>.role=master' \
  | oc apply -f -

# Create AWS creds secret (not managed by chart — contains sensitive data)
oc create secret generic sushy-ec2-aws-creds -n sushy-ec2 \
  --from-literal=aws_access_key_id=<key> \
  --from-literal=aws_secret_access_key=<secret> \
  --from-literal=region=us-east-2 \
  --from-literal=s3_bucket=<bucket>

# Build and push image (via podman, bypasses Quay Bridge webhook)
REGISTRY=default-route-openshift-image-registry.apps.<hub-domain>
podman login --tls-verify=false -u $(oc whoami) -p $(oc whoami -t) "$REGISTRY"
podman build -t "$REGISTRY/sushy-ec2/sushy-ec2-emulator:latest" tools/sushy-ec2-driver/
podman push --tls-verify=false "$REGISTRY/sushy-ec2/sushy-ec2-emulator:latest"
```

### Post-InfraEnv: set ignition URL

After ArgoCD creates the InfraEnv and it generates a discovery ISO, patch the emulator with the ignition URL:

```bash
IGNITION_URL=$(oc get infraenv aws-none-prod -n aws-none-prod -o jsonpath='{.status.isoDownloadURL}' | sed 's/minimal.iso/discovery.ign/')
# Or get the full URL from the assisted-service API
oc set env deployment/sushy-ec2-emulator -n sushy-ec2 SUSHY_EC2_IGNITION_URL="$IGNITION_URL"
```

## Provisioning Flow

1. Sushy emulator deployed to `sushy-ec2` namespace (must be running first)
2. ArgoCD syncs `provision-prod-aws-none-prod` app → creates namespace, ClusterDeployment, AgentClusterInstall, InfraEnv, BMHs
3. InfraEnv generates discovery ISO URL
4. Patch sushy emulator with ignition URL (manual step)
5. Metal3 processes BMHs → calls sushy → sushy starts EC2 instances with discovery ISO
6. Agents register with hub → appear in `oc get agents -n aws-none-prod`
7. AgentClusterInstall drives the install once requirements are met (3 control plane agents)

## Run Log

### Run 1 (2026-09-15) — Initial attempt

**Result:** Failed — BMHs stuck in `provisioning` for 11+ hours, no agents registered.

**What happened:**
- Provisioning resources created in `aws-none-prod` namespace
- Sushy emulator deployed in same namespace
- BMHs created with addresses pointing to `sushy-ec2.aws-none-prod.svc:8000`
- EC2 instances existed but agents never phoned home
- AgentClusterInstall state: `insufficient` — needed 3 control plane agents, had 0

**Root cause:** Not fully diagnosed before cleanup. Possible issues:
- Ignition URL may not have been set or was stale
- EC2 instances may not have booted from discovery ISO correctly
- Network connectivity between EC2 instances and hub assisted-service

### Run 2 (2026-09-16) — Cleanup and restructure

**Actions taken:**
1. Deleted `aws-none-prod` namespace (required clearing BMH finalizers)
2. Created sushy-ec2-emulator Helm chart
3. Moved emulator to dedicated `sushy-ec2` namespace
4. Built and pushed image via podman (Quay Bridge webhook workaround)
5. Updated provision.yaml BMH addresses to reference new namespace
6. Disabled cluster import (`deployImport: false`) during provisioning

**What was fixed during this run:**
- Sync-wave ordering: ClusterDeployment moved to wave 357 (before ACI at 358 and InfraEnv at 359)
- BMH and BMC secrets moved to waves 361-362 (after InfraEnv), fixing a deadlock where BMH ownerReferences on secrets kept them "Progressing" and blocked all later waves
- Pull secret recreated from hub cluster's pull secret

**Current state:** BMHs provisioning, waiting for agents to register.

### Run 3 (2026-09-16) — Debugging and fixing bootstrap

**Root cause of Run 2 failure:** Sushy pod restart during `_reimage_and_start` execution (caused by `oc set env` for ignition URL). The reimage background thread was killed mid-process, and the new pod's `PERMANENT_CACHE` was empty.

**Actions taken:**
1. Manually triggered reimage via sushy Redfish API (InsertMedia + boot Cd + Power On)
2. Agents registered and install started successfully
3. Discovered NTP and inter-host connectivity validation failures (resolved automatically)
4. Discovered cross-zone load balancing was disabled on the API NLB — master-1/master-2 couldn't reach the API server on master-0 during bootstrap
5. Enabled cross-zone LB on both API and ingress NLBs
6. Changed `api-int` DNS from NLB alias (public IPs) to direct A records with private IPs — fixes NAT hairpin issue where NLB client IP preservation breaks connections through NAT gateway
7. Nodes registered, control plane bootstrapped, etcd and kube-apiserver became available
8. Ironic re-sent deploy commands (InsertMedia + boot Cd + Power On) during bootstrap, triggering a second reimage that destroyed master-1 and master-2's installed OS
9. Fixed sushy driver: added `reimage_done` flag to `PERMANENT_CACHE` that prevents re-reimaging; also clears `boot_device` and `virtual_media_inserted` after reimage
10. Converted chart from `helm.sh/hook-weight` to `argocd.argoproj.io/sync-wave` annotations
11. Cleaned up namespace for Run 4

**What was learned:**
- The sushy PERMANENT_CACHE is lost on pod restart — don't restart the pod between Ironic's deploy sequence and the install completing
- NLBs must have cross-zone load balancing enabled for multi-AZ bootstrap
- `api-int` DNS must resolve to private IPs (not NLB public IPs) when instances are in private subnets with NAT — NLB client IP preservation changes the source IP to the NAT gateway's public IP, which breaks security group rules restricted to the VPC CIDR
- Ironic periodically re-sends InsertMedia/boot/power commands as part of BMH reconciliation — the sushy driver must guard against re-reimaging

### Run 4 (2026-09-16) — Successful install

**Result:** Success — OpenShift 4.22.13 fully installed, all 34 cluster operators Available.

**Timeline:**
- 15:16 — ArgoCD synced provisioning resources (sync-wave ordered)
- 15:22 — Pull secret created manually, ACI synced, InfraEnv generated ISO
- 15:23 — Sushy patched with ignition URL, rolling restart completed
- 15:23:52 — Ironic sent InsertMedia + boot Cd + Power On for all 3 instances
- 15:24:27 — All 3 instances reimaged with RHCOS, `reimage_done` flag set
- 15:25 — Agents registered, validation passed, install started (27%)
- 15:29 — Writing image to disk → rebooting (48%)
- 15:31 — master-0, master-1 configuring; master-2 waiting for control plane
- 15:34 — master-0, master-1 done; master-2 entered "Waiting for bootkube"
- 15:54 — etcd installer deploying static pods to masters
- 15:55 — etcd Available on master-0 (5/5 Running)
- 15:59 — kube-apiserver Available, kube-controller-manager Available
- 16:04 — Bootkube complete, master-2 rebooted to "Configuring" (81%)
- 16:07 — All 3 nodes Ready, master-2 "Joined" (90%)
- 16:12 — All agents Done, ACI 87% finalizing
- 16:17 — Install complete: 100%, all 34 COs Available, cluster version 4.22.13

**What worked:**
- Sync-wave annotations (0-9) ensured correct resource creation order
- `reimage_done` guard prevented Ironic re-reimage loop — no spurious reimages in sushy logs
- Cross-zone LB (enabled in Run 3) allowed multi-AZ bootstrap
- `api-int` pointing to private IPs (changed in Run 3) prevented NAT hairpin issues
- NTP config (added in Run 3) — no NTP validation failures
- Total time from ArgoCD sync to install complete: ~55 minutes

**No manual interventions needed during install** — only pre-install setup: pull secret creation and ignition URL patching.

## Lessons Learned

### 1. Namespace termination blocked by BMH finalizers
BareMetalHost resources have `baremetalhost.metal3.io` finalizers that prevent namespace deletion. Must patch finalizers to null before the namespace will terminate:
```bash
for bmh in $(oc get baremetalhosts -n <ns> -o name); do
  oc patch $bmh -n <ns> --type merge -p '{"metadata":{"finalizers":null}}'
done
```
Also need to clear finalizers on PreprovisioningImages and BMC credential secrets.

### 2. Quay Bridge webhook blocks builds in new namespaces
The Quay Bridge operator installs a MutatingWebhookConfiguration that intercepts all Build objects cluster-wide. It checks if the builder SA has Quay robot account secrets. If `namespaceCreationDefault: false`, new namespaces never get provisioned, but the webhook still blocks.

**Fix:** Add the namespace to `denylistNamespaces` in the QuayIntegration CR (and the quay-registry chart template).

**Workaround:** Build with podman locally and push directly to the internal registry via its external route.

### 3. Sushy emulator should be in its own namespace
Having the emulator in the same namespace as provisioning resources means:
- Deleting the namespace to start over kills the emulator too
- Must rebuild/redeploy the emulator each time
- Image, BuildConfig, and ImageStream are lost

Dedicated namespace keeps the emulator stable across provisioning cycles.

### 4. Ignition URL is a manual post-step
The InfraEnv generates a unique ISO URL with an embedded JWT token. The sushy emulator needs this URL to inject ignition config during boot. This creates a two-phase deploy:
1. ArgoCD creates InfraEnv → ISO URL generated
2. Manual patch of sushy deployment with the ignition URL

Future improvement: automate this with a Job or controller that watches InfraEnv status and patches the sushy deployment.

### 5. Sync-wave ordering is critical for agent-based provisioning
The provisioning chart uses `argocd.argoproj.io/sync-wave` annotations for correct ordering:
- Wave 0: Namespace
- Wave 1: Non-BMC secrets (pull secret, SSH keys, etc.)
- Wave 2: ClusterDeployment (must exist before ACI and InfraEnv)
- Wave 3: AgentClusterInstall (references ClusterDeployment)
- Wave 4: InfraEnv (references ClusterDeployment, generates ISO)
- Wave 5: KlusterAddonConfig, MachinePool
- Wave 6: BMC credential secrets + NMStateConfig
- Wave 7: BareMetalHosts (reference BMC secrets, trigger provisioning)
- Wave 8: ManagedCluster
- Wave 9: ManagedClusterInfo

If BMHs have no wave annotation, they're created at wave 0 (first). Metal3 adds ownerReferences from BMHs to their BMC secrets, making ArgoCD see the secrets as "Progressing". This blocks all later waves — including ClusterDeployment and InfraEnv — creating a deadlock.

### 8. Cross-zone load balancing required for multi-AZ bootstrap
During bootstrap, only the bootstrap node runs the API server. If the NLB has cross-zone disabled, nodes in other AZs can't reach the API. Enable cross-zone on both API and ingress NLBs.

### 9. api-int DNS must use private IPs with NAT gateways
When instances are in private subnets with NAT, `api-int` DNS should resolve to private IPs (A records), not an internet-facing NLB alias. With NLB client IP preservation, the source IP seen by the target is the NAT gateway's public IP, not the instance's private IP. Security group rules restricted to the VPC CIDR (e.g., port 22623 allowing only 10.1.0.0/16) will reject traffic from the NAT's public IP.

### 10. Sushy reimage_done guard prevents Ironic re-reimage loop
Ironic periodically re-sends InsertMedia + set boot Cd + Power On as part of BMH reconciliation. Without a guard, each power-on re-triggers `_reimage_and_start`, destroying the installed OS. The driver uses a `reimage_done` flag in `PERMANENT_CACHE` — once set after the first successful reimage, subsequent power-on commands skip the reimage path.

### 6. Pull secret is not managed by git
The `cluster.pullSecret` value is sensitive and not stored in the repo. It must be manually created after namespace recreation:
```bash
oc create secret generic <cluster>-pull-secret -n <cluster> \
  --from-file=.dockerconfigjson=<pull-secret-file> \
  --type=kubernetes.io/dockerconfigjson
```

### 7. Image pull requires rolebinding in new namespace
When using the internal registry, service accounts in the namespace need `system:image-puller` role to pull images. This isn't automatic for manually created namespaces:
```bash
oc policy add-role-to-group system:image-puller system:serviceaccounts:<ns> -n <ns>
```

### 11. Don't restart sushy pod during Ironic deploy sequence
The `PERMANENT_CACHE` is in-memory. If the pod restarts between Ironic's InsertMedia/boot-set/Power-On and the completion of the reimage thread, the reimage is killed and the cache is lost. Schedule sushy updates for periods when no BMHs are being provisioned.
