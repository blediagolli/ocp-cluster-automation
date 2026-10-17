#!/bin/bash
set -uo pipefail

# Helm Template Tests for the openshift-ingress chart
#
# The chart's whole job is to render one IngressController correctly for
# whichever platform the cluster actually runs on, so the bulk of this file is
# one case per endpointPublishingStrategy, plus the provider-parameter shapes
# under LoadBalancerService.
#
# The guard tests matter as much as the rendering ones. Three mistakes here are
# expensive on a live cluster — an empty spec applied over the real one, a
# nodePlacement label no node carries, and a strategy that differs from the
# installer's (which the API will not update) — so the chart refuses the first
# outright and renders nothing for the second and third unless asked.
#
# Usage: ./template-test.sh
# Requirements: helm 3.x

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); }

ON="--set ingress.controller.include=true --set ingress.controller.manageDefault=true"

render() {
  helm template test-ingress "$CHART_DIR" $* 2>&1
}

has() {
  echo "$1" | grep -qF -- "$2"
}

# $1 label, $2 output, $3... strings that must all be present
expect_all() {
  local label="$1" out="$2"; shift 2
  local missing=""
  for s in "$@"; do
    has "$out" "$s" || missing="$missing\n    missing: $s"
  done
  if [ -z "$missing" ]; then pass "$label"; else fail "$label"; printf "%b\n" "$missing"; fi
}

# $1 label, $2 output, $3... strings that must all be absent
expect_none() {
  local label="$1" out="$2"; shift 2
  local present=""
  for s in "$@"; do
    has "$out" "$s" && present="$present\n    unexpected: $s"
  done
  if [ -z "$present" ]; then pass "$label"; else fail "$label"; printf "%b\n" "$present"; fi
}

if ! command -v helm &>/dev/null; then
  echo "ERROR: helm not found in PATH"
  exit 1
fi

echo "openshift-ingress template tests"
echo

# ---------------------------------------------------------------- gates ----
echo "Gates"

out=$(render)
if [ -z "$(echo "$out" | grep -v '^---$' | grep -v '^$')" ]; then
  pass "defaults render nothing"
else
  fail "defaults render nothing"
fi

out=$(render --set ingress.controller.include=true)
if ! has "$out" "kind: IngressController"; then
  pass "include alone does not touch the default IngressController"
else
  fail "include alone does not touch the default IngressController"
fi

out=$(render --set ingress.controller.manageDefault=true)
if ! has "$out" "kind: IngressController"; then
  pass "manageDefault without include renders nothing"
else
  fail "manageDefault without include renders nothing"
fi

# ----------------------------------------------------------- empty spec ----
echo
echo "Empty-spec guard"

out=$(render $ON)
if has "$out" "nothing under ingress.controller is set"; then
  pass "managing the default with no settings is refused, not rendered as null"
else
  fail "managing the default with no settings is refused, not rendered as null"
fi

out=$(render $ON --set ingress.controller.default.replicas=2)
expect_all "one setting is enough to satisfy the guard" "$out" \
  "kind: IngressController" "replicas: 2"

# ----------------------------------------------------- strategy: absent ----
echo
echo "endpointPublishingStrategy"

out=$(render $ON --set ingress.controller.default.replicas=2)
expect_none "empty strategy renders no endpointPublishingStrategy at all" "$out" \
  "endpointPublishingStrategy"

out=$(render $ON --set ingress.controller.default.endpointPublishingStrategy=Nonsense)
if has "$out" "endpointPublishingStrategy must be one of"; then
  pass "an unknown strategy fails the render"
else
  fail "an unknown strategy fails the render"
fi

# ------------------------------------------- strategy: LoadBalancerService --
echo
echo "LoadBalancerService (AWS, Azure, GCP, IBMCloud, AlibabaCloud)"

LB="--set ingress.controller.default.endpointPublishingStrategy=LoadBalancerService"

out=$(render $ON $LB)
expect_all "bare LoadBalancerService carries the default External scope" "$out" \
  "type: LoadBalancerService" "scope: External"
expect_none "bare LoadBalancerService emits no providerParameters" "$out" \
  "providerParameters"

out=$(render $ON $LB --set ingress.controller.default.loadBalancer.scope=Internal)
expect_all "scope is settable to Internal" "$out" "scope: Internal"

out=$(render $ON $LB \
  --set ingress.controller.default.loadBalancer.dnsManagementPolicy=Unmanaged \
  --set 'ingress.controller.default.loadBalancer.allowedSourceRanges={10.0.0.0/8,192.168.0.0/16}')
expect_all "dnsManagementPolicy and allowedSourceRanges render" "$out" \
  "dnsManagementPolicy: Unmanaged" "- 10.0.0.0/8" "- 192.168.0.0/16"

# AWS NLB
out=$(render $ON $LB \
  --set ingress.controller.default.loadBalancer.providerParameters.type=AWS \
  --set ingress.controller.default.loadBalancer.providerParameters.aws.type=NLB \
  --set 'ingress.controller.default.loadBalancer.providerParameters.aws.networkLoadBalancer.eipAllocations={eipalloc-aaa,eipalloc-bbb}' \
  --set 'ingress.controller.default.loadBalancer.providerParameters.aws.networkLoadBalancer.subnets.ids={subnet-1}')
expect_all "AWS NLB with EIPs and subnet ids" "$out" \
  "type: AWS" "type: NLB" "networkLoadBalancer:" \
  "- eipalloc-aaa" "- eipalloc-bbb" "ids:" "- subnet-1"
expect_none "AWS NLB does not leak the classic block" "$out" "classicLoadBalancer"

# AWS Classic
out=$(render $ON $LB \
  --set ingress.controller.default.loadBalancer.providerParameters.type=AWS \
  --set ingress.controller.default.loadBalancer.providerParameters.aws.type=Classic \
  --set ingress.controller.default.loadBalancer.providerParameters.aws.classicLoadBalancer.connectionIdleTimeout=30m)
expect_all "AWS Classic with idle timeout" "$out" \
  "type: Classic" "classicLoadBalancer:" "connectionIdleTimeout: 30m"
expect_none "AWS Classic does not leak the NLB block" "$out" "networkLoadBalancer"

out=$(render $ON $LB \
  --set ingress.controller.default.loadBalancer.providerParameters.type=AWS \
  --set ingress.controller.default.loadBalancer.providerParameters.aws.type=Gateway)
if has "$out" "aws.type must be NLB or Classic"; then
  pass "an unknown AWS load balancer type fails the render"
else
  fail "an unknown AWS load balancer type fails the render"
fi

# Other providers
out=$(render $ON $LB \
  --set ingress.controller.default.loadBalancer.providerParameters.type=GCP \
  --set ingress.controller.default.loadBalancer.providerParameters.gcp.clientAccess=Global)
expect_all "GCP clientAccess" "$out" "type: GCP" "clientAccess: Global"

out=$(render $ON $LB \
  --set ingress.controller.default.loadBalancer.providerParameters.type=IBM \
  --set ingress.controller.default.loadBalancer.providerParameters.ibm.protocol=PROXY)
expect_all "IBM protocol" "$out" "type: IBM" "protocol: PROXY"

out=$(render $ON $LB \
  --set ingress.controller.default.loadBalancer.providerParameters.type=OpenStack \
  --set ingress.controller.default.loadBalancer.providerParameters.openstack.floatingIP=10.11.12.13)
expect_all "OpenStack floating IP" "$out" "type: OpenStack" "floatingIP: 10.11.12.13"

out=$(render $ON $LB --set ingress.controller.default.loadBalancer.providerParameters.type=Rackspace)
if has "$out" "providerParameters.type must be one of"; then
  pass "an unknown provider fails the render"
else
  fail "an unknown provider fails the render"
fi

# ------------------------------------------------- strategy: HostNetwork ---
echo
echo "HostNetwork (bare metal, vSphere, Nutanix, OpenStack, None, Libvirt)"

HN="--set ingress.controller.default.endpointPublishingStrategy=HostNetwork"

out=$(render $ON $HN)
expect_all "bare HostNetwork renders the type" "$out" "type: HostNetwork"
expect_none "bare HostNetwork emits no empty hostNetwork block" "$out" "hostNetwork:"

out=$(render $ON $HN \
  --set ingress.controller.default.hostNetwork.protocol=PROXY \
  --set ingress.controller.default.hostNetwork.httpPort=8080 \
  --set ingress.controller.default.hostNetwork.httpsPort=8443 \
  --set ingress.controller.default.hostNetwork.statsPort=1937)
expect_all "HostNetwork ports and PROXY protocol" "$out" \
  "hostNetwork:" "protocol: PROXY" "httpPort: 8080" "httpsPort: 8443" "statsPort: 1937"

out=$(render $ON $HN --set ingress.controller.default.loadBalancer.providerParameters.type=AWS)
if has "$out" "Provider parameters only apply to LoadBalancerService"; then
  pass "provider parameters against a non-LoadBalancer strategy fail the render"
else
  fail "provider parameters against a non-LoadBalancer strategy fail the render"
fi

# -------------------------------------- strategies: NodePortService/Private -
echo
echo "NodePortService and Private"

out=$(render $ON --set ingress.controller.default.endpointPublishingStrategy=NodePortService \
  --set ingress.controller.default.nodePort.protocol=PROXY)
expect_all "NodePortService with PROXY" "$out" "type: NodePortService" "nodePort:" "protocol: PROXY"

out=$(render $ON --set ingress.controller.default.endpointPublishingStrategy=Private \
  --set ingress.controller.default.private.protocol=TCP)
expect_all "Private with TCP" "$out" "type: Private" "private:" "protocol: TCP"

# --------------------------------------------------------- nodePlacement ---
echo
echo "nodePlacement"

out=$(render $ON --set ingress.controller.default.replicas=2)
expect_none "empty placement renders no nodePlacement" "$out" "nodePlacement"

out=$(render $ON --set ingress.controller.default.placement=node-role.kubernetes.io/infra)
expect_all "placement renders a nodeSelector" "$out" \
  "nodePlacement:" "nodeSelector:" "node-role.kubernetes.io/infra:"
expect_none "placement without tolerations renders none" "$out" "tolerations:"

out=$(render $ON --set ingress.controller.default.placement=node-role.kubernetes.io/infra \
  --set 'ingress.controller.default.tolerations[0].effect=NoSchedule' \
  --set 'ingress.controller.default.tolerations[0].operator=Exists')
expect_all "tolerations render under nodePlacement" "$out" \
  "tolerations:" "effect: NoSchedule" "operator: Exists"

# ------------------------------------------------------- the other knobs ---
echo
echo "Certificate, TLS profile, HSTS, HTTP/2, logging"

out=$(render $ON --set ingress.controller.defaultCertificate.enabled=true \
  --set ingress.controller.defaultCertificate.name=cert-manager-ingress-cert)
expect_all "defaultCertificate" "$out" "defaultCertificate:" "name: cert-manager-ingress-cert"

out=$(render $ON --set ingress.controller.tlsSecurityProfile.enabled=true)
expect_all "custom TLS profile carries ciphers and a minimum version" "$out" \
  "tlsSecurityProfile:" "type: Custom" "minTLSVersion: VersionTLS12" "TLS_AES_128_GCM_SHA256"

out=$(render $ON --set ingress.controller.tlsSecurityProfile.enabled=true \
  --set ingress.controller.tlsSecurityProfile.type=Intermediate)
expect_all "a named TLS profile renders without a custom block" "$out" "type: Intermediate"
expect_none "a named TLS profile renders no ciphers" "$out" "ciphers:"

out=$(render $ON --set ingress.controller.hsts.enabled=true)
expect_all "HSTS response header" "$out" \
  "Strict-Transport-Security" "max-age=31536000"

out=$(render $ON --set ingress.controller.replicas=0 --set ingress.controller.http2.enabled=true \
  --set ingress.controller.default.replicas=2)
expect_all "HTTP/2 is an annotation, not a spec field" "$out" \
  "ingress.operator.openshift.io/default-enable-http2: \"true\""

LOG="$ON --set ingress.controller.logging.enabled=true"
SYSLOG="$LOG --set ingress.controller.logging.destination.type=Syslog \
  --set ingress.controller.logging.destination.syslog.address=10.0.0.1"

out=$(render $SYSLOG)
expect_all "syslog access logging" "$out" \
  "logging:" "syslog:" "address: 10.0.0.1" "port: 10514" "type: Syslog"

out=$(render $SYSLOG --set ingress.controller.logging.destination.syslog.facility=local2 \
  --set ingress.controller.logging.destination.syslog.maxLength=2048)
expect_all "syslog facility and maxLength" "$out" "facility: local2" "maxLength: 2048"

out=$(render $SYSLOG)
expect_none "syslog omits facility and maxLength when unset" "$out" "facility:" "maxLength:"

out=$(render $LOG)
expect_all "logging defaults to the container sidecar" "$out" "logging:" "access:" "type: Container"
expect_none "a bare container destination renders no parameters" "$out" \
  "container:" "maxLength:" "syslog:" "httpLogFormat:" "logEmptyRequests:"

out=$(render $LOG --set ingress.controller.logging.destination.container.maxLength=4096)
expect_all "container maxLength" "$out" "container:" "maxLength: 4096"

# httpLogFormat and logEmptyRequests sit beside destination, not inside it.
# Nesting them under destination is the easy mistake and the API rejects it,
# so assert the indentation, not just the presence of the keys.
#
# Via a values file rather than --set: a real HAProxy format string is full of
# spaces, and render() word-splits its arguments.
fmt_values=$(mktemp)
trap 'rm -f "$fmt_values"' EXIT
cat > "$fmt_values" <<'YAML'
ingress:
  controller:
    include: true
    manageDefault: true
    logging:
      enabled: true
      httpLogFormat: '%ci:%cp [%t] %ft %b/%s %B %bq %HM %HU %HV'
      logEmptyRequests: Ignore
YAML
out=$(render -f "$fmt_values")
expect_all "httpLogFormat and logEmptyRequests are siblings of destination" "$out" \
  '      httpLogFormat: "%ci:%cp [%t] %ft %b/%s %B %bq %HM %HU %HV"' \
  "      logEmptyRequests: Ignore"

out=$(render $LOG --set ingress.controller.logging.destination.type=Journal)
if has "$out" "logging.destination.type must be one of"; then
  pass "an unknown logging destination fails the render"
else
  fail "an unknown logging destination fails the render"
fi

out=$(render $LOG --set ingress.controller.logging.destination.type=Syslog)
if has "$out" "syslog.address is empty"; then
  pass "syslog without a collector address fails the render"
else
  fail "syslog without a collector address fails the render"
fi

out=$(render $LOG --set ingress.controller.logging.destination.syslog.address=10.0.0.1)
if has "$out" "syslog.* is set but logging.destination.type is Container"; then
  pass "syslog parameters against a container destination fail the render"
else
  fail "syslog parameters against a container destination fail the render"
fi

out=$(render $SYSLOG --set ingress.controller.logging.destination.container.maxLength=2000)
if has "$out" "container.maxLength is set but logging.destination.type is Syslog"; then
  pass "container parameters against a syslog destination fail the render"
else
  fail "container parameters against a syslog destination fail the render"
fi

out=$(render $LOG --set ingress.controller.logging.destination.container.maxLength=100)
if has "$out" "container.maxLength must be between 480 and 8192"; then
  pass "a container maxLength below the floor fails the render"
else
  fail "a container maxLength below the floor fails the render"
fi

# The two destinations have different ceilings: 8192 for Container, 4096 for
# Syslog. A value legal for one is not legal for the other.
out=$(render $SYSLOG --set ingress.controller.logging.destination.syslog.maxLength=8192)
if has "$out" "syslog.maxLength must be between 480 and 4096"; then
  pass "a syslog maxLength above its own lower ceiling fails the render"
else
  fail "a syslog maxLength above its own lower ceiling fails the render"
fi

out=$(render $LOG --set ingress.controller.logging.logEmptyRequests=Maybe)
if has "$out" "logEmptyRequests must be Log or Ignore"; then
  pass "an unknown logEmptyRequests policy fails the render"
else
  fail "an unknown logEmptyRequests policy fails the render"
fi

# ------------------------------------------------------------- summary -----
echo
echo "-----------------------------------"
echo "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
