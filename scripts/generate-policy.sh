#!/usr/bin/env bash
#
# Scaffold a PolicyGenerator directory under policies/.
#
# A policy in this repo is not a hand-written Policy CR. It is a directory of
# plain Kubernetes manifests plus a policy-generator-config.yaml that says how to
# wrap them; the ACM PolicyGenerator kustomize plugin does the wrapping, run by
# the repo-server CMP sidecar at sync time. That split is the whole point -- the
# manifest you write is the manifest you would apply, so it is reviewable without
# reading through a layer of Policy boilerplate.
#
# The boilerplate is still boilerplate though, and getting one field wrong in
# policy-generator-config.yaml fails as an opaque render error. Hence this.
#
# The ${...} tokens in the generated files are substituted at render time by the
# CMP (and by `make validate-policies`) using sed, never a template engine --
# ACM hub templates ({{hub ... hub}}) share the file and must pass through intact.
#
#   scripts/generate-policy.sh etcd-encryption
#   scripts/generate-policy.sh compliance-operator --operator --channel stable
#
# Adapted from the directory shape used by auto-shift/autoshiftv2 (Apache-2.0).
#
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

usage() {
  cat <<'EOF'
Usage: scripts/generate-policy.sh <name> [options]

  <name>  directory name and policy name, e.g. etcd-encryption

Options:
  --operator              scaffold an OperatorPolicy instead of a config policy
  --tier <tier>           stable (default), certified or community
  --severity <level>      low, medium, high, critical (default high)
  --categories <text>     ACM categories annotation
  --controls <text>       ACM controls annotation
  --namespace <ns>        operator install namespace (--operator only)
  --channel <channel>     operator subscription channel (--operator only, default stable)
  --help                  this

Every generated policy is remediationAction: ${REMEDIATION}, which the hub
ApplicationSet pins to "inform". Policies attest; the charts configure. See
docs/governance/acm-policies.md before changing that.
EOF
}

name=""
operator=false
tier="stable"
severity="high"
categories="CM Configuration Management"
controls="CM-2 Baseline Configuration"
op_namespace=""
op_channel="stable"

while [ $# -gt 0 ]; do
  case "$1" in
    --operator)   operator=true; shift ;;
    --tier)       tier="$2"; shift 2 ;;
    --severity)   severity="$2"; shift 2 ;;
    --categories) categories="$2"; shift 2 ;;
    --controls)   controls="$2"; shift 2 ;;
    --namespace)  op_namespace="$2"; shift 2 ;;
    --channel)    op_channel="$2"; shift 2 ;;
    --help|-h)    usage; exit 0 ;;
    -*)           echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$name" ] || { echo "only one name may be given" >&2; exit 2; }
      name="$1"; shift ;;
  esac
done

[ -n "$name" ] || { usage >&2; exit 2; }

# The generated Application is named policy-<name>, and ArgoCD Application names
# have to be DNS labels. Catch it here rather than as a sync failure.
case "$name" in
  *[!a-z0-9-]*|-*|*-) echo "name must be lowercase alphanumeric with internal dashes: $name" >&2; exit 2 ;;
esac
if [ ${#name} -gt 56 ]; then
  echo "name is ${#name} characters; policy-$name must stay within the 63-character DNS label limit" >&2
  exit 2
fi

case "$tier" in
  stable|certified|community) ;;
  *) echo "tier must be stable, certified or community: $tier" >&2; exit 2 ;;
esac

dir="policies/$tier/$name"
[ ! -e "$dir" ] || { echo "$dir already exists" >&2; exit 1; }

if $operator && [ -z "$op_namespace" ]; then
  echo "--operator requires --namespace (the operator's install namespace)" >&2
  exit 2
fi

mkdir -p "$dir/manifests"

cat > "$dir/kustomization.yaml" <<'EOF'
# The marker file the hub-acm-policies ApplicationSet globs for, and the entry
# point the CMP's `kustomize build` uses. PolicyGenerator runs as a generator
# plugin, which is why the render needs --enable-alpha-plugins.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
generators:
  - policy-generator-config.yaml
EOF

cat > "$dir/policy-generator-config.yaml" <<EOF
apiVersion: policy.open-cluster-management.io/v1
kind: PolicyGenerator
metadata:
  name: $name
placementBindingDefaults:
  name: binding-$name
policyDefaults:
  namespace: \${POLICY_NAMESPACE}
  remediationAction: \${REMEDIATION}
  severity: $severity
  # One ConfigurationPolicy holding every manifest, rather than one each. The
  # policy is a single assertion, so a single compliance verdict is what you want.
  consolidateManifests: true
  evaluationInterval:
    compliant: \${EVAL_COMPLIANT}
    noncompliant: \${EVAL_NONCOMPLIANT}
  standards:
    - NIST SP 800-53
  categories:
    - $categories
  controls:
    - $controls
  placement:
    placementPath: placement.yaml
policies:
  - name: $name
    manifests:
      - path: manifests/
EOF

cat > "$dir/placement.yaml" <<EOF
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: Placement
metadata:
  name: placement-$name
  # PolicyGenerator requires this explicitly even though the policies land in the
  # same namespace -- it will not infer it from policyDefaults.
  namespace: \${POLICY_NAMESPACE}
spec:
  # Deliberately no spec.clusterSets. The tenancy boundary is the
  # ManagedClusterSetBinding that policies/$tier/policy-framework creates in the
  # policy namespace -- a Placement can only see sets bound there. With no
  # predicates this selects every cluster in every bound set.
  #
  # Beware: a Placement that matches nothing produces a Policy that reports
  # Compliant, which is indistinguishable from one that is genuinely passing.
  # Check for propagated instances, not for a green tick. See
  # docs/governance/acm-policies.md.
  #
  # To make this policy opt-in instead, add a label predicate here and have
  # policies/$tier/cluster-labels stamp the label onto the clusters that want it:
  #
  #   predicates:
  #     - requiredClusterSelector:
  #         labelSelector:
  #           matchExpressions:
  #             - key: gfo.io/$name
  #               operator: In
  #               values: ['true']
  #
  # Keep evaluating on clusters the hub has temporarily lost, so an unreachable
  # cluster shows as stale rather than silently dropping out of the policy.
  tolerations:
    - key: cluster.open-cluster-management.io/unreachable
      operator: Exists
    - key: cluster.open-cluster-management.io/unavailable
      operator: Exists
EOF

if $operator; then
  cat > "$dir/manifests/operator-policy.yaml" <<EOF
# OperatorPolicy rather than a ConfigurationPolicy wrapping a Subscription.
# A ConfigurationPolicy can only confirm that a Subscription object exists; an
# operator wedged on a failed InstallPlan would still report compliant.
# OperatorPolicy understands the lifecycle -- Subscription, InstallPlan, CSV --
# so it reports whether the operator is actually working.
#
# PolicyGenerator passes policy.open-cluster-management.io kinds through without
# wrapping them, so this lands on the hub as-is inside the generated Policy.
apiVersion: policy.open-cluster-management.io/v1beta1
kind: OperatorPolicy
metadata:
  name: $name
spec:
  remediationAction: \${REMEDIATION}
  severity: $severity
  complianceType: musthave
  # Nothing here approves an upgrade; in inform mode there is nothing to approve.
  upgradeApproval: None
  subscription:
    name: $name
    namespace: $op_namespace
    channel: $op_channel
    source: redhat-operators
    sourceNamespace: openshift-marketplace
EOF
else
  cat > "$dir/manifests/README.md" <<EOF
Put the bare Kubernetes resources this policy attests to in this directory, as
you would apply them. PolicyGenerator wraps them in a ConfigurationPolicy; do not
write the wrapper yourself.

Delete this file once there is a manifest here -- PolicyGenerator reads every
file under \`path: manifests/\`, and a README is not a manifest.
EOF
fi

cat > "$dir/README.md" <<EOF
# $name

Attests that ... (what must be true, and on which clusters).

**Written by:** ... (the chart that actually creates this state; a policy here
only reports on it). See docs/governance/acm-policies.md for why that split exists.

## Checking it

\`\`\`bash
oc get policy -n open-cluster-management-policies $name
oc get policy -A | grep $name   # propagated copies -- empty means the placement matched nothing
\`\`\`
EOF

echo "created $dir"
echo "next: edit $dir/manifests/, then run 'make validate-policies'"
