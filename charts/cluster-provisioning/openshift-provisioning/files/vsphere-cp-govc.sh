#!/bin/bash
set -euo pipefail

echo "=== vSphere Control Plane Automation (govc) ==="

ARCH=$(uname -m)
case "${ARCH}" in
  x86_64)  GOVC_ARCH="x86_64" ;;
  aarch64) GOVC_ARCH="arm64" ;;
  *)       echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

echo "--- Downloading govc ${GOVC_VERSION} ---"
curl -sL -o /tmp/govc.tar.gz \
  "https://github.com/vmware/govmomi/releases/download/${GOVC_VERSION}/govc_Linux_${GOVC_ARCH}.tar.gz"
tar -xzf /tmp/govc.tar.gz -C /usr/local/bin govc
chmod +x /usr/local/bin/govc
echo "govc installed: $(govc version)"

export GOVC_URL="${VCENTER}"
export GOVC_USERNAME="${VCENTER_USERNAME}"
export GOVC_PASSWORD="${VCENTER_PASSWORD}"
export GOVC_INSECURE="${VCENTER_INSECURE}"
export GOVC_DATACENTER="${DATACENTER}"
export GOVC_DATASTORE="${DATASTORE}"

INFRAENV_NAME="${INFRAENV_NAME:-${CLUSTER_NAME}}"
WORKER_COUNT="${WORKER_COUNT:-0}"

echo "--- Waiting for InfraEnv ISO URL (${INFRAENV_NAME}) ---"
ISO_URL=""
for i in $(seq 1 60); do
  ISO_URL=$(oc get infraenv "${INFRAENV_NAME}" -n "${CLUSTER_NAME}" \
    -o jsonpath='{.status.isoDownloadURL}' 2>/dev/null || true)
  if [ -n "${ISO_URL}" ]; then
    echo "ISO URL available"
    break
  fi
  echo "  Attempt ${i}/60: waiting..."
  sleep 10
done
if [ -z "${ISO_URL}" ]; then
  echo "ERROR: Timed out waiting for InfraEnv ISO URL"
  exit 1
fi

echo "--- Downloading discovery ISO ---"
curl -skL -o /tmp/discovery.iso "${ISO_URL}"
echo "ISO downloaded: $(du -h /tmp/discovery.iso | cut -f1)"

ISO_DS_PATH="${CLUSTER_NAME}/discovery.iso"
echo "--- Uploading ISO to datastore ---"
govc datastore.mkdir -ds="${DATASTORE}" "${CLUSTER_NAME}" 2>/dev/null || true
govc datastore.upload -ds="${DATASTORE}" /tmp/discovery.iso "${ISO_DS_PATH}"
echo "ISO uploaded to [${DATASTORE}] ${ISO_DS_PATH}"
rm -f /tmp/discovery.iso

echo "--- Creating control plane VMs ---"
for i in $(seq 0 $((MASTER_COUNT - 1))); do
  VM_NAME="${CLUSTER_NAME}-master-${i}"

  if govc vm.info "${VM_NAME}" >/dev/null 2>&1; then
    echo "${VM_NAME}: already exists, skipping creation"
  else
    echo "${VM_NAME}: creating (${MASTER_CPUS} CPU, ${MASTER_MEMORY_MB}MB RAM, ${MASTER_DISK_GB}GB disk)..."
    govc vm.create \
      -m="${MASTER_MEMORY_MB}" \
      -c="${MASTER_CPUS}" \
      -disk="${MASTER_DISK_GB}GB" \
      -net="${NETWORK}" \
      -pool="${RESOURCE_POOL}" \
      -folder="${FOLDER}" \
      -on=false \
      -iso="[${DATASTORE}] ${ISO_DS_PATH}" \
      -disk.controller=pvscsi \
      -net.adapter=vmxnet3 \
      "${VM_NAME}"
    govc device.boot -vm="${VM_NAME}" -order=cdrom,disk
  fi

  POWER=$(govc vm.info -json "${VM_NAME}" 2>/dev/null | \
    grep -o '"powerState":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
  if [ "${POWER}" != "poweredOn" ]; then
    echo "${VM_NAME}: powering on..."
    govc vm.power -on "${VM_NAME}"
  fi
done

if [ "${WORKER_COUNT}" -gt 0 ]; then
  echo "--- Creating vSphere worker VMs ---"
  for i in $(seq 0 $((WORKER_COUNT - 1))); do
    VM_NAME="${CLUSTER_NAME}-vsphere-worker-${i}"

    if govc vm.info "${VM_NAME}" >/dev/null 2>&1; then
      echo "${VM_NAME}: already exists, skipping creation"
    else
      echo "${VM_NAME}: creating (${WORKER_CPUS} CPU, ${WORKER_MEMORY_MB}MB RAM, ${WORKER_DISK_GB}GB disk)..."
      govc vm.create \
        -m="${WORKER_MEMORY_MB}" \
        -c="${WORKER_CPUS}" \
        -disk="${WORKER_DISK_GB}GB" \
        -net="${NETWORK}" \
        -pool="${RESOURCE_POOL}" \
        -folder="${FOLDER}" \
        -on=false \
        -iso="[${DATASTORE}] ${ISO_DS_PATH}" \
        -disk.controller=pvscsi \
        -net.adapter=vmxnet3 \
        "${VM_NAME}"
      govc device.boot -vm="${VM_NAME}" -order=cdrom,disk
    fi

    POWER=$(govc vm.info -json "${VM_NAME}" 2>/dev/null | \
      grep -o '"powerState":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
    if [ "${POWER}" != "poweredOn" ]; then
      echo "${VM_NAME}: powering on..."
      govc vm.power -on "${VM_NAME}"
    fi
  done
fi

TOTAL_VM_COUNT=$((MASTER_COUNT + WORKER_COUNT))
echo "--- Waiting for ${TOTAL_VM_COUNT} non-BMH agents (${MASTER_COUNT} master + ${WORKER_COUNT} worker) ---"
for attempt in $(seq 1 120); do
  AGENT_NAMES=$(oc get agents -n "${CLUSTER_NAME}" \
    -l '!agent-install.openshift.io/bmh' \
    -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

  COUNT=0
  if [ -n "${AGENT_NAMES}" ]; then
    COUNT=$(echo "${AGENT_NAMES}" | wc -w | tr -d ' ')
  fi

  if [ "${COUNT}" -ge "${TOTAL_VM_COUNT}" ]; then
    echo "Found ${COUNT} non-BMH agents"
    APPROVED_MASTERS=0
    for AGENT in ${AGENT_NAMES}; do
      APPROVED=$(oc get agent "${AGENT}" -n "${CLUSTER_NAME}" \
        -o jsonpath='{.spec.approved}' 2>/dev/null || echo "false")
      if [ "${APPROVED}" = "true" ]; then
        echo "  ${AGENT}: already approved"
        CURRENT_ROLE=$(oc get agent "${AGENT}" -n "${CLUSTER_NAME}" \
          -o jsonpath='{.spec.role}' 2>/dev/null || echo "")
        if [ "${CURRENT_ROLE}" = "master" ]; then
          APPROVED_MASTERS=$((APPROVED_MASTERS + 1))
        fi
        continue
      fi
      if [ "${APPROVED_MASTERS}" -lt "${MASTER_COUNT}" ]; then
        echo "  Approving ${AGENT} as master..."
        oc patch agent "${AGENT}" -n "${CLUSTER_NAME}" \
          --type merge -p '{"spec":{"approved":true,"role":"master"}}'
        APPROVED_MASTERS=$((APPROVED_MASTERS + 1))
      else
        echo "  Approving ${AGENT} as worker..."
        oc patch agent "${AGENT}" -n "${CLUSTER_NAME}" \
          --type merge -p '{"spec":{"approved":true,"role":"worker"}}'
      fi
    done
    echo "All ${TOTAL_VM_COUNT} VM agents processed (${MASTER_COUNT} master, ${WORKER_COUNT} worker)"
    echo "=== vSphere control plane automation complete ==="
    exit 0
  fi

  echo "  Attempt ${attempt}/120: ${COUNT}/${TOTAL_VM_COUNT} agents registered..."
  sleep 15
done

echo "ERROR: Timed out waiting for agents"
exit 1
