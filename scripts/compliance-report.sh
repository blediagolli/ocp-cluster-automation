#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-openshift-compliance}"
OUTPUT_DIR="${OUTPUT_DIR:-./compliance-reports}"
HELPER_IMAGE="${HELPER_IMAGE:-registry.access.redhat.com/ubi9/ubi:latest}"
SCAN_FILTER=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
  cat <<EOF
Compliance Operator report tool for OpenShift

Usage: $(basename "$0") <command> [options]

Commands:
  profiles         List available compliance profiles
  scans            List scans and their status
  results          Summarise ComplianceCheckResult pass/fail counts
  report           Generate HTML reports from completed scan ARF data

Options:
  -n, --namespace  Namespace  (default: openshift-compliance)
  -o, --output     Output dir (default: ./compliance-reports)
  -s, --scan       Filter to a single scan name
  -h, --help       Show this help

Environment:
  HELPER_IMAGE     Base image for helper pod (default: registry.access.redhat.com/ubi9/ubi:latest)

Examples:
  $(basename "$0") profiles
  $(basename "$0") results
  $(basename "$0") report -s ocp4-stig
  $(basename "$0") report -o /tmp/reports
EOF
}

require_oc() {
  if ! command -v oc &>/dev/null; then
    echo -e "${RED}Error: oc CLI not found in PATH${NC}" >&2
    exit 1
  fi
  if ! oc whoami &>/dev/null; then
    echo -e "${RED}Error: not logged in to an OpenShift cluster${NC}" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# profiles - list available compliance profiles
# ---------------------------------------------------------------------------
cmd_profiles() {
  require_oc
  echo -e "${CYAN}Available compliance profiles in ${NAMESPACE}:${NC}"
  oc get profiles.compliance.openshift.io -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,TITLE:.title,PRODUCT:.metadata.labels.compliance\.openshift\.io/product-type' \
    --sort-by=.metadata.name
}

# ---------------------------------------------------------------------------
# scans - list compliance scans and status
# ---------------------------------------------------------------------------
cmd_scans() {
  require_oc
  echo -e "${CYAN}Compliance scans in ${NAMESPACE}:${NC}"
  oc get compliancescans -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,RESULT:.status.result' \
    --sort-by=.metadata.name
}

# ---------------------------------------------------------------------------
# results - summarise ComplianceCheckResults
# ---------------------------------------------------------------------------
cmd_results() {
  require_oc

  local scans
  if [[ -n "$SCAN_FILTER" ]]; then
    scans="$SCAN_FILTER"
  else
    scans=$(oc get compliancescans -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
  fi

  if [[ -z "$scans" ]]; then
    echo -e "${YELLOW}No compliance scans found in ${NAMESPACE}${NC}"
    return
  fi

  for scan in $scans; do
    echo -e "\n${CYAN}=== $scan ===${NC}"

    local pass fail info manual not_applicable error
    pass=$(oc get compliancecheckresults -n "$NAMESPACE" \
      -l "compliance.openshift.io/scan-name=${scan},compliance.openshift.io/check-status=PASS" \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')
    fail=$(oc get compliancecheckresults -n "$NAMESPACE" \
      -l "compliance.openshift.io/scan-name=${scan},compliance.openshift.io/check-status=FAIL" \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')
    info=$(oc get compliancecheckresults -n "$NAMESPACE" \
      -l "compliance.openshift.io/scan-name=${scan},compliance.openshift.io/check-status=INFO" \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')
    manual=$(oc get compliancecheckresults -n "$NAMESPACE" \
      -l "compliance.openshift.io/scan-name=${scan},compliance.openshift.io/check-status=MANUAL" \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')
    not_applicable=$(oc get compliancecheckresults -n "$NAMESPACE" \
      -l "compliance.openshift.io/scan-name=${scan},compliance.openshift.io/check-status=NOT-APPLICABLE" \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')
    error=$(oc get compliancecheckresults -n "$NAMESPACE" \
      -l "compliance.openshift.io/scan-name=${scan},compliance.openshift.io/check-status=ERROR" \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')

    echo -e "  ${GREEN}PASS:${NC}           $pass"
    echo -e "  ${RED}FAIL:${NC}           $fail"
    echo -e "  ${YELLOW}MANUAL:${NC}         $manual"
    echo -e "  INFO:           $info"
    echo -e "  NOT-APPLICABLE: $not_applicable"
    echo -e "  ${RED}ERROR:${NC}          $error"

    if [[ "$fail" -gt 0 ]]; then
      echo -e "\n  ${RED}Failed checks:${NC}"
      oc get compliancecheckresults -n "$NAMESPACE" \
        -l "compliance.openshift.io/scan-name=${scan},compliance.openshift.io/check-status=FAIL" \
        -o custom-columns='  RULE:.metadata.name,SEVERITY:.severity' --no-headers
    fi
  done
}

# ---------------------------------------------------------------------------
# report - extract ARF results and generate HTML reports
# ---------------------------------------------------------------------------
cleanup_pod() {
  local pod_name=$1
  echo "  Cleaning up helper pod ${pod_name}..."
  oc delete pod "$pod_name" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1
}

cmd_report() {
  require_oc
  mkdir -p "$OUTPUT_DIR"

  local scans
  if [[ -n "$SCAN_FILTER" ]]; then
    scans="$SCAN_FILTER"
  else
    scans=$(oc get compliancescans -n "$NAMESPACE" \
      -o jsonpath='{range .items[?(@.status.phase=="DONE")]}{.metadata.name}{"\n"}{end}')
  fi

  if [[ -z "$scans" ]]; then
    echo -e "${YELLOW}No completed compliance scans found in ${NAMESPACE}${NC}"
    return
  fi

  for scan in $scans; do
    echo -e "\n${CYAN}=== Generating reports for scan: $scan ===${NC}"

    local pvcs
    pvcs=$(oc get pvc -n "$NAMESPACE" \
      -l "compliance.openshift.io/scan-name=${scan}" \
      -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [[ -z "$pvcs" ]]; then
      echo -e "  ${YELLOW}No result PVCs found for scan ${scan}${NC}"
      continue
    fi

    for pvc in $pvcs; do
      echo -e "  Processing PVC: ${pvc}"
      local pod_name="compliance-report-$(echo "${pvc}" | md5sum | cut -c1-8)"

      trap "cleanup_pod $pod_name" EXIT

      oc apply -n "$NAMESPACE" -f - <<EOF >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: ${NAMESPACE}
  labels:
    app: compliance-report-helper
spec:
  containers:
    - name: report
      image: ${HELPER_IMAGE}
      command:
        - bash
        - -c
        - |
          dnf install -y openscap-scanner bzip2 &>/dev/null
          sleep 600
      volumeMounts:
        - name: scan-results
          mountPath: /results
  volumes:
    - name: scan-results
      persistentVolumeClaim:
        claimName: ${pvc}
  restartPolicy: Never
  tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
EOF

      echo "  Waiting for helper pod to be ready..."
      if ! oc wait pod/"$pod_name" -n "$NAMESPACE" --for=condition=Ready --timeout=60s >/dev/null 2>&1; then
        echo -e "  ${RED}Helper pod failed to start. Skipping PVC ${pvc}${NC}"
        cleanup_pod "$pod_name"
        continue
      fi

      echo "  Installing openscap-scanner (this may take a moment)..."
      local retries=0
      while ! oc exec -n "$NAMESPACE" "$pod_name" -- rpm -q openscap-scanner &>/dev/null; do
        if [[ $retries -ge 60 ]]; then
          echo -e "  ${RED}Timed out waiting for openscap-scanner install. Skipping PVC ${pvc}${NC}"
          cleanup_pod "$pod_name"
          continue 2
        fi
        sleep 5
        retries=$((retries + 1))
      done

      echo "  Generating HTML reports inside helper pod..."
      oc exec -n "$NAMESPACE" "$pod_name" -- bash -c '
        shopt -s nullglob
        found=0
        for dir in /results/*/; do
          for arf in "${dir}"*.bzip2; do
            found=1
            out="${arf}.out"
            if [[ ! -f "$out" ]]; then
              bunzip2 -kf "$arf" 2>/dev/null || true
              if [[ -f "${arf%.bzip2}" ]]; then
                mv "${arf%.bzip2}" "$out"
              fi
            fi
            if [[ -f "$out" ]]; then
              html="${arf%.xml.bzip2}.html"
              oscap xccdf generate report --output "$html" "$out" 2>/dev/null && \
                echo "GENERATED:${html}" || \
                echo "FAILED:${out}"
            fi
          done
        done
        if [[ $found -eq 0 ]]; then
          echo "NO_RESULTS"
        fi
      '

      local scan_dir="${OUTPUT_DIR}/${scan}"
      mkdir -p "$scan_dir"

      local html_files
      html_files=$(oc exec -n "$NAMESPACE" "$pod_name" -- find /results -name '*.html' 2>/dev/null || true)

      if [[ -n "$html_files" ]]; then
        while IFS= read -r html_path; do
          local filename
          filename=$(basename "$html_path")
          oc cp "${NAMESPACE}/${pod_name}:${html_path}" "${scan_dir}/${filename}" >/dev/null 2>&1
          echo -e "  ${GREEN}Saved: ${scan_dir}/${filename}${NC}"
        done <<< "$html_files"
      else
        echo -e "  ${YELLOW}No HTML reports generated for ${pvc}${NC}"
      fi

      cleanup_pod "$pod_name"
      trap - EXIT
    done
  done

  echo -e "\n${GREEN}Reports saved to ${OUTPUT_DIR}/${NC}"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
COMMAND="${1:-}"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -o|--output)    OUTPUT_DIR="$2"; shift 2 ;;
    -s|--scan)      SCAN_FILTER="$2"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

case "$COMMAND" in
  profiles) cmd_profiles ;;
  scans)    cmd_scans ;;
  results)  cmd_results ;;
  report)   cmd_report ;;
  -h|--help|help|"") usage ;;
  *) echo "Unknown command: $COMMAND" >&2; usage; exit 1 ;;
esac
