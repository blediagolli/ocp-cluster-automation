# Bootstrap Hub Cluster (AWS)

Before ACM and the GitOps provisioning chart can manage spoke clusters, you need a running hub cluster. The `bootstrap-aws-hub.sh` script wraps `openshift-install` to stand one up on AWS using a values file that follows the same structure as the provisioning chart.

## Prerequisites

- `openshift-install` in PATH (or set `OPENSHIFT_INSTALL`)
- `yq` v4+
- AWS credentials configured (`~/.aws/credentials`, env vars, or instance profile)
- A pull secret from [console.redhat.com](https://console.redhat.com/openshift/downloads)
- An SSH key pair for node access

### Optional (for additional volumes)

- `aws` CLI
- `jq`

## Setup

### Credentials

```bash
# Pull secret
mkdir -p ~/.openshift
cp ~/Downloads/pull-secret.txt ~/.openshift/pull-secret.json
chmod 600 ~/.openshift/pull-secret.json

# SSH key (dedicated key for the cluster)
ssh-keygen -t ed25519 -f ~/.ssh/acm-hub -N "" -C "acm-hub-bootstrap"

# AWS credentials
mkdir -p ~/.aws && chmod 700 ~/.aws
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
EOF
chmod 600 ~/.aws/credentials
```

### Values file

Edit `clusters/mgt/acm-hub/bootstrap.yaml` with your environment-specific values:

```yaml
cluster:
  name: acm-hub
  baseDomain: your-domain.example.com
  networkType: OVNKubernetes

pullSecretFile: ~/.openshift/pull-secret.json
sshPublicKeyFile: ~/.ssh/acm-hub.pub

masters:
  count: 3

workers:
  count: 0       # 0 for compact (3-node) cluster

aws:
  region: us-east-2
  masters:
    instanceType: m5.2xlarge    # 8 vCPU / 32 GiB per node
    rootVolume:
      size: 200
      type: gp3

# Optional: attach a secondary disk to each node for LocalStorage/ODF
additionalVolume:
  enabled: true
  size: 1000      # GiB
  type: gp3
  device: /dev/sdb
```

## Usage

```bash
# Preview the generated install-config.yaml
make bootstrap-hub-dry-run

# Provision the cluster (~30-45 minutes)
make bootstrap-hub

# Tear down the cluster and all AWS resources
make destroy-hub
```

You can override the values file path:

```bash
make bootstrap-hub BOOTSTRAP_VALUES=path/to/other-values.yaml
```

### Running via container (macOS workaround)

On macOS Sequoia, `openshift-install` 4.22+ may fail with a Cluster API controller timeout. The workaround is to run the installer inside a Linux container:

```bash
# 1. Generate install-config locally (dry-run works natively)
make bootstrap-hub-dry-run

# 2. Download the Linux openshift-install binary
curl -sL "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.22/openshift-install-linux.tar.gz" \
  | tar -xz -C install-acm-hub openshift-install

# 3. Back up the install-config (the installer consumes it)
cp install-acm-hub/install-config.yaml install-acm-hub/install-config.yaml.bak

# 4. Run inside a UBI container (requires podman machine running)
podman run --rm \
  -v $(pwd)/install-acm-hub:/install:Z \
  -v ~/.aws:/root/.aws:ro,Z \
  registry.access.redhat.com/ubi9/ubi-minimal:latest \
  /install/openshift-install create cluster --dir /install --log-level info

# 5. Attach additional volumes (run from the host after install)
# The script handles this automatically when run natively; for the container
# approach, use the aws CLI directly (see bootstrap-aws-hub.sh attach_additional_volumes)
```

## Compact (3-node) cluster

Setting `workers.count: 0` creates a compact cluster where the control plane nodes are schedulable for workloads. The installer detects this and sets `MastersSchedulable: true` automatically.

Recommended instance sizing for compact clusters:

| Use case | Instance type | Per-node | Total (3 nodes) | ~Monthly cost |
|---|---|---|---|---|
| Testing (operators only) | m5.2xlarge | 8 vCPU / 32 GiB | 24 vCPU / 96 GiB | ~$841 |
| Production (with workloads) | m5.4xlarge | 16 vCPU / 64 GiB | 48 vCPU / 192 GiB | ~$1,683 |

## Additional volumes

When `additionalVolume.enabled: true`, the script attaches an EBS volume to each node after the cluster is ready. The volumes are tagged with `kubernetes.io/cluster/<infra-id>=owned` so they are cleaned up automatically by `make destroy-hub`.

This is useful for:
- OpenShift Data Foundation (ODF)
- Local Storage Operator
- Any workload requiring dedicated block storage

## Recovery

### Laptop dies or process is interrupted

The install state is saved in the `install-<cluster-name>/` directory (default: `install-acm-hub/`). **Do not delete this directory.**

- **Resume** the install:
  ```bash
  openshift-install create cluster --dir install-acm-hub --log-level info
  ```
  The installer picks up where it left off.

- **Clean up** if it gets stuck:
  ```bash
  make destroy-hub
  ```
  Then start fresh with `make bootstrap-hub`.

The worst case scenario is partial AWS resources left running (VPCs, EC2 instances, ELBs). `make destroy-hub` uses the saved `metadata.json` to find and remove all cluster resources.

### Additional volumes not attached

If the cluster installed successfully but the volume attachment step failed (e.g., missing `aws` CLI), you can re-run just the attachment:

```bash
# Install aws CLI and jq if needed, then:
./scripts/bootstrap-aws-hub.sh clusters/mgt/acm-hub/bootstrap.yaml
```

Or attach volumes manually using the AWS console or CLI, targeting instances tagged with `kubernetes.io/cluster/<infra-id>=owned`.

## Post-install next steps

```bash
export KUBECONFIG=install-acm-hub/auth/kubeconfig

# Verify the cluster is healthy
oc get nodes
oc get clusteroperators

# Install ACM, ArgoCD, and point at this repo to continue GitOps bootstrap
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `OPENSHIFT_INSTALL` | `openshift-install` | Path to the installer binary |
| `INSTALL_DIR` | `install-<cluster-name>` | Directory for install artifacts |
| `PULL_SECRET_FILE` | (from values) | Override pull secret file path |
| `SSH_PUBLIC_KEY_FILE` | (from values) | Override SSH public key file path |
