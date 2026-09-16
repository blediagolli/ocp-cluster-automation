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

**Current state:** Awaiting git push + ArgoCD sync to recreate provisioning resources.

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

### 5. Image pull requires rolebinding in new namespace
When using the internal registry, service accounts in the namespace need `system:image-puller` role to pull images. This isn't automatic for manually created namespaces:
```bash
oc policy add-role-to-group system:image-puller system:serviceaccounts:<ns> -n <ns>
```
