#!/usr/bin/env bash
#
# Bootstrap an OpenShift cluster on AWS using openshift-install.
# Designed for standing up the initial ACM hub before the GitOps
# provisioning chart (which requires ACM) can take over.
#
# Usage:
#   ./scripts/bootstrap-aws-hub.sh <values-file>
#   ./scripts/bootstrap-aws-hub.sh clusters/mgt/acm-hub/bootstrap.yaml
#
# The values file uses the same structure as the provisioning chart:
#   cluster.name, cluster.baseDomain, aws.region, etc.
#
# Prerequisites:
#   - openshift-install (in PATH or OPENSHIFT_INSTALL env var)
#   - yq v4+ (in PATH)
#   - AWS credentials configured (env vars, ~/.aws/credentials, or instance profile)
#   - A pull secret file (referenced in values or PULL_SECRET_FILE env var)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OPENSHIFT_INSTALL="${OPENSHIFT_INSTALL:-openshift-install}"
INSTALL_DIR="${INSTALL_DIR:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <values-file>

Bootstrap an OpenShift cluster on AWS via openshift-install.

Options:
  --install-dir <dir>   Directory for install artifacts (default: install-<cluster-name>)
  --dry-run             Generate install-config.yaml without running the installer
  --destroy             Tear down a previously bootstrapped cluster
  -h, --help            Show this help

Environment variables:
  OPENSHIFT_INSTALL     Path to openshift-install binary (default: openshift-install)
  INSTALL_DIR           Override install artifact directory
  PULL_SECRET_FILE      Path to pull secret JSON file (overrides values)
  SSH_PUBLIC_KEY_FILE   Path to SSH public key file (overrides values)

Examples:
  # Provision a new hub cluster
  ./scripts/bootstrap-aws-hub.sh clusters/mgt/acm-hub/bootstrap.yaml

  # Preview the install-config without installing
  ./scripts/bootstrap-aws-hub.sh --dry-run clusters/mgt/acm-hub/bootstrap.yaml

  # Tear down
  ./scripts/bootstrap-aws-hub.sh --destroy clusters/mgt/acm-hub/bootstrap.yaml
EOF
  exit 0
}

err() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

check_prereqs() {
  command -v yq >/dev/null 2>&1 || err "yq v4+ is required (https://github.com/mikefarah/yq)"
  if [[ "${DRY_RUN}" != "true" ]]; then
    command -v "${OPENSHIFT_INSTALL}" >/dev/null 2>&1 || err "openshift-install not found. Set OPENSHIFT_INSTALL or add to PATH."
  fi
}

val() {
  yq eval "$1" "${VALUES_FILE}"
}

val_default() {
  local result
  result="$(yq eval "$1" "${VALUES_FILE}")"
  if [[ "${result}" == "null" || -z "${result}" ]]; then
    echo "$2"
  else
    echo "${result}"
  fi
}

generate_install_config() {
  local cluster_name base_domain region network_type fips
  local master_count master_type master_vol_size master_vol_type
  local worker_count worker_type worker_vol_size worker_vol_type
  local ssh_pub_key pull_secret

  cluster_name="$(val '.cluster.name')"
  base_domain="$(val '.cluster.baseDomain')"
  region="$(val_default '.aws.region' 'us-east-2')"
  network_type="$(val_default '.cluster.networkType' 'OVNKubernetes')"
  fips="$(val_default '.cluster.fips' 'false')"

  master_count="$(val_default '.masters.count' '3')"
  master_type="$(val_default '.aws.masters.instanceType' 'm5.xlarge')"
  master_vol_size="$(val_default '.aws.masters.rootVolume.size' '120')"
  master_vol_type="$(val_default '.aws.masters.rootVolume.type' 'gp3')"

  worker_count="$(val_default '.workers.count' '3')"
  worker_type="$(val_default '.aws.workers.instanceType' 'm5.xlarge')"
  worker_vol_size="$(val_default '.aws.workers.rootVolume.size' '120')"
  worker_vol_type="$(val_default '.aws.workers.rootVolume.type' 'gp3')"

  # Pull secret: env var > values file path > values inline
  if [[ -n "${PULL_SECRET_FILE:-}" ]]; then
    [[ -f "${PULL_SECRET_FILE}" ]] || err "PULL_SECRET_FILE not found: ${PULL_SECRET_FILE}"
    pull_secret="$(cat "${PULL_SECRET_FILE}")"
  else
    local ps_path
    ps_path="$(val_default '.pullSecretFile' '')"
    ps_path="${ps_path/#\~/$HOME}"
    if [[ -n "${ps_path}" && -f "${ps_path}" ]]; then
      pull_secret="$(cat "${ps_path}")"
    else
      pull_secret="$(val_default '.cluster.pullSecret' '')"
      [[ -n "${pull_secret}" ]] || err "No pull secret provided. Set PULL_SECRET_FILE, pullSecretFile in values, or cluster.pullSecret inline."
    fi
  fi

  # SSH public key: env var > values file path > values inline
  if [[ -n "${SSH_PUBLIC_KEY_FILE:-}" ]]; then
    [[ -f "${SSH_PUBLIC_KEY_FILE}" ]] || err "SSH_PUBLIC_KEY_FILE not found: ${SSH_PUBLIC_KEY_FILE}"
    ssh_pub_key="$(cat "${SSH_PUBLIC_KEY_FILE}")"
  else
    local ssh_path
    ssh_path="$(val_default '.sshPublicKeyFile' '')"
    ssh_path="${ssh_path/#\~/$HOME}"
    if [[ -n "${ssh_path}" && -f "${ssh_path}" ]]; then
      ssh_pub_key="$(cat "${ssh_path}")"
    else
      ssh_pub_key="$(val_default '.cluster.sshPublicKey' '')"
    fi
  fi

  # Master availability zones
  local master_zones_yaml=""
  local master_zone_count
  master_zone_count="$(yq eval '.aws.masters.zones | length' "${VALUES_FILE}")"
  if [[ "${master_zone_count}" -gt 0 ]]; then
    master_zones_yaml="$(yq eval -o=json '.aws.masters.zones' "${VALUES_FILE}")"
  fi

  # Worker availability zones
  local worker_zones_yaml=""
  local worker_zone_count
  worker_zone_count="$(yq eval '.aws.workers.zones | length' "${VALUES_FILE}")"
  if [[ "${worker_zone_count}" -gt 0 ]]; then
    worker_zones_yaml="$(yq eval -o=json '.aws.workers.zones' "${VALUES_FILE}")"
  fi

  # Build install-config.yaml
  cat > "${INSTALL_DIR}/install-config.yaml" <<EOF
apiVersion: v1
metadata:
  name: ${cluster_name}
baseDomain: ${base_domain}
networking:
  networkType: ${network_type}
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: ${master_count}
  platform:
    aws:
      type: ${master_type}
      rootVolume:
        size: ${master_vol_size}
        type: ${master_vol_type}
EOF

  if [[ -n "${master_zones_yaml}" ]]; then
    cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
      zones: ${master_zones_yaml}
EOF
  fi

  cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
compute:
  - hyperthreading: Enabled
    name: worker
    replicas: ${worker_count}
    platform:
      aws:
        type: ${worker_type}
        rootVolume:
          size: ${worker_vol_size}
          type: ${worker_vol_type}
EOF

  if [[ -n "${worker_zones_yaml}" ]]; then
    cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
        zones: ${worker_zones_yaml}
EOF
  fi

  local hosted_zone
  hosted_zone="$(val_default '.aws.hostedZone' '')"

  cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
platform:
  aws:
    region: ${region}
EOF

  if [[ -n "${hosted_zone}" ]]; then
    cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
    hostedZone: ${hosted_zone}
EOF
  fi

  if [[ "${fips}" == "true" ]]; then
    cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
fips: true
EOF
  fi

  # Proxy
  local proxy_enabled
  proxy_enabled="$(val_default '.proxy.enabled' 'false')"
  if [[ "${proxy_enabled}" == "true" ]]; then
    local http_proxy https_proxy no_proxy
    http_proxy="$(val '.proxy.httpProxy')"
    https_proxy="$(val '.proxy.httpsProxy')"
    no_proxy="$(val '.proxy.noProxy')"
    cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
proxy:
  httpProxy: "${http_proxy}"
  httpsProxy: "${https_proxy}"
  noProxy: "${no_proxy}"
EOF
  fi

  # Additional trust bundle
  local trust_bundle
  trust_bundle="$(val_default '.cluster.additionalTrustBundle' '')"
  if [[ -n "${trust_bundle}" ]]; then
    {
      echo "additionalTrustBundle: |"
      echo "${trust_bundle}" | sed 's/^/  /'
    } >> "${INSTALL_DIR}/install-config.yaml"
  fi

  # Pull secret (single-line JSON)
  local escaped_ps
  escaped_ps="$(echo "${pull_secret}" | tr -d '\n')"
  cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
pullSecret: '${escaped_ps}'
EOF

  # SSH key
  if [[ -n "${ssh_pub_key}" ]]; then
    cat >> "${INSTALL_DIR}/install-config.yaml" <<EOF
sshKey: ${ssh_pub_key}
EOF
  fi

  info "Generated ${INSTALL_DIR}/install-config.yaml"
}

attach_additional_volumes() {
  local vol_enabled
  vol_enabled="$(val_default '.additionalVolume.enabled' 'false')"
  [[ "${vol_enabled}" == "true" ]] || return 0

  command -v aws >/dev/null 2>&1 || err "aws CLI is required for additionalVolume support."
  command -v jq >/dev/null 2>&1 || err "jq is required for additionalVolume support."

  local region infra_id vol_size vol_type device
  region="$(val_default '.aws.region' 'us-east-2')"
  infra_id="$(jq -r '.infraID' "${INSTALL_DIR}/metadata.json")"
  vol_size="$(val_default '.additionalVolume.size' '1000')"
  vol_type="$(val_default '.additionalVolume.type' 'gp3')"
  device="$(val_default '.additionalVolume.device' '/dev/sdb')"

  info "Attaching ${vol_size}GiB ${vol_type} volumes to cluster nodes..."

  local instances
  instances="$(aws ec2 describe-instances \
    --region "${region}" \
    --filters \
      "Name=tag:kubernetes.io/cluster/${infra_id},Values=owned" \
      "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone]' \
    --output text)"

  [[ -n "${instances}" ]] || err "No running instances found for cluster ${infra_id}"

  while IFS=$'\t' read -r instance_id az; do
    info "  Creating ${vol_size}GiB volume in ${az} for ${instance_id}..."
    local volume_id
    volume_id="$(aws ec2 create-volume \
      --region "${region}" \
      --availability-zone "${az}" \
      --size "${vol_size}" \
      --volume-type "${vol_type}" \
      --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${infra_id}-additional},{Key=kubernetes.io/cluster/${infra_id},Value=owned}]" \
      --query 'VolumeId' \
      --output text)"

    aws ec2 wait volume-available --region "${region}" --volume-ids "${volume_id}"

    aws ec2 attach-volume \
      --region "${region}" \
      --volume-id "${volume_id}" \
      --instance-id "${instance_id}" \
      --device "${device}" \
      --output text > /dev/null

    info "  Attached ${volume_id} to ${instance_id} as ${device}"
  done <<< "${instances}"

  info "Additional volumes attached to all nodes."
}

# --- Main ---

DRY_RUN=false
DESTROY=false
VALUES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --destroy)     DESTROY=true; shift ;;
    -h|--help)     usage ;;
    -*)            err "Unknown option: $1" ;;
    *)             VALUES_FILE="$1"; shift ;;
  esac
done

[[ -n "${VALUES_FILE}" ]] || err "Values file required. Run with --help for usage."
[[ -f "${VALUES_FILE}" ]] || err "Values file not found: ${VALUES_FILE}"

check_prereqs

CLUSTER_NAME="$(val '.cluster.name')"
[[ -n "${CLUSTER_NAME}" && "${CLUSTER_NAME}" != "null" ]] || err "cluster.name is required in values file"

if [[ -z "${INSTALL_DIR}" ]]; then
  INSTALL_DIR="${REPO_ROOT}/install-${CLUSTER_NAME}"
fi

if [[ "${DESTROY}" == "true" ]]; then
  info "Destroying cluster '${CLUSTER_NAME}' using artifacts in ${INSTALL_DIR}"
  [[ -d "${INSTALL_DIR}" ]] || err "Install directory not found: ${INSTALL_DIR}. Cannot destroy without install artifacts."
  "${OPENSHIFT_INSTALL}" destroy cluster --dir "${INSTALL_DIR}" --log-level info
  info "Cluster '${CLUSTER_NAME}' destroyed."
  exit 0
fi

info "Bootstrapping hub cluster '${CLUSTER_NAME}' on AWS"
info "  Region:  $(val_default '.aws.region' 'us-east-2')"
info "  Masters: $(val_default '.masters.count' '3') x $(val_default '.aws.masters.instanceType' 'm5.xlarge')"
info "  Workers: $(val_default '.workers.count' '3') x $(val_default '.aws.workers.instanceType' 'm5.xlarge')"

mkdir -p "${INSTALL_DIR}"

# Keep a backup — openshift-install consumes install-config.yaml
generate_install_config
cp "${INSTALL_DIR}/install-config.yaml" "${INSTALL_DIR}/install-config.yaml.bak"

if [[ "${DRY_RUN}" == "true" ]]; then
  info "Dry run — install-config.yaml written to ${INSTALL_DIR}/install-config.yaml"
  info "Review it, then run: ${OPENSHIFT_INSTALL} create cluster --dir ${INSTALL_DIR}"
  exit 0
fi

info "Running openshift-install create cluster (this takes ~30-45 minutes)..."
"${OPENSHIFT_INSTALL}" create cluster --dir "${INSTALL_DIR}" --log-level info

attach_additional_volumes

info "Cluster '${CLUSTER_NAME}' is ready."
info "  Kubeconfig: ${INSTALL_DIR}/auth/kubeconfig"
info "  Console:    https://console-openshift-console.apps.${CLUSTER_NAME}.$(val '.cluster.baseDomain')"
info ""
info "Next steps:"
info "  export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig"
info "  # Install ACM, ArgoCD, and point at this repo to continue GitOps bootstrap"
