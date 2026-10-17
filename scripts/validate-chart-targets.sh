#!/usr/bin/env bash
#
# Check the `oca.io/target` annotation every chart carries in its Chart.yaml,
# and cross-check it against where each cluster's conf.yaml actually deploys
# the chart.
#
# The annotation records where a chart is *meant* to run, and there are only
# two answers: `hub` for the management plane every other cluster consumes
# (ACM, Hive, Vault, Keycloak, Quay), `spoke` for everything else.
#
# There is deliberately no third "both" value. Every cluster is a spoke,
# including the hub — ACM registers it as `local-cluster` and it appears in
# `oc get managedcluster` alongside the rest — so a chart with no constraint
# is simply a spoke chart, and "runs anywhere" and "runs on a spoke" are the
# same statement. That collapse is what makes the third check below
# one-directional: a spoke chart on the hub is always legal.
#
# Before the annotation existed the distinction lived entirely outside the
# charts: in which ApplicationSet owns a chart, and in prose scattered through
# docs/. charts/platform-config/vault-server is the case that motivated it — it
# sits in the platform-config directory alongside twenty-nine charts that each
# cluster runs its own copy of, and it is the one estate-wide service in there.
#
# The annotation names the cluster a chart is *for*, which is not always where
# its manifests land. acm-managed-cluster is the case to keep in mind: it is
# spoke, because it registers a spoke that was deployed outside ACM, even
# though cluster-import applies its objects on the hub. Where a chart lands is
# the ApplicationSet's business, and the two ApplicationSets that pin
# destination.server to the hub already encode it.
#
# Three checks. The first two are mechanical facts and fail; the third is a
# judgement about a label that is still young, so it warns. To promote it,
# change `warn=` to `fail=1` in the mismatch branch below.
#
# Runs offline — no kubeconfig, unlike validate-clusters.sh — so it belongs in
# `make validate`.
#
# Usage: scripts/validate-chart-targets.sh
set -uo pipefail

IN_CLUSTER="https://kubernetes.default.svc"
PROXY_FMT="https://cluster-proxy-addon-user.multicluster-engine.svc.cluster.local:9092"

VALID_TARGETS="hub spoke"

fail=0
warn=0

# ---------------------------------------------------------------------------
# 1. Every chart declares a target, and it is one of the two known values.
# ---------------------------------------------------------------------------

# Populated as `targets[<group>/<chart>]=hub` and reused by check 3.
declare -A targets

charts=0
for chart in $(find charts -mindepth 3 -maxdepth 3 -name Chart.yaml | sort); do
	rel="${chart#charts/}"; rel="${rel%/Chart.yaml}"
	charts=$((charts + 1))

	target=$(awk '
		/^annotations:/        { inc = 1; next }
		inc && /^[^ #]/        { inc = 0 }
		inc && /^[ ]+oca\.io\/target:/ { print $2; exit }
	' "$chart")

	if [ -z "$target" ]; then
		echo "MISSING  $chart — no oca.io/target annotation"
		fail=1
		continue
	fi

	case " $VALID_TARGETS " in
		*" $target "*) targets["$rel"]="$target" ;;
		*)
			echo "INVALID  $chart — oca.io/target: $target (expected one of: $VALID_TARGETS)"
			fail=1 ;;
	esac
done

[ "$fail" -eq 0 ] && echo "OK   all $charts charts declare a valid oca.io/target"

# ---------------------------------------------------------------------------
# 2. Every chart named in a conf.yaml resolves to a chart directory, and
# 3. a hub chart is not shipped anywhere but the hub.
#
# Only that one direction is checkable: the hub is a managed cluster too, so a
# spoke chart listed on it is correct, not a mismatch.
#
# Both lists are walked with the same awk idiom the validate-operators recipe
# uses: enter at the key, leave at the next unindented non-comment line, print
# the chart name from each entry.
# ---------------------------------------------------------------------------

listed() {
	awk -v key="$1" '
		$0 ~ "^" key ":"              { f = 1; next }
		f && /^[^ #-]/                { f = 0 }
		f && /^[ ]*-[ ]*chart:/       { print $3 }
	' "$2"
}

for conf in $(find clusters -mindepth 3 -maxdepth 3 -name conf.yaml | sort); do
	eval "$(awk '
		/^cluster:/            { inc = 1; next }
		inc && /^[^ #]/        { inc = 0 }
		inc && /^[ ]+name:/    { n = $2 }
		inc && /^[ ]+address:/ { a = $2 }
		function unquote(s) { gsub(/^"|"$/, "", s); return s }
		END { printf "name=%s; addr=%s\n", unquote(n), unquote(a) }' "$conf")"

	# Same derivation as validate-clusters.sh: an omitted address synthesises
	# the cluster-proxy URL, so the default is a spoke.
	dest="${addr:-$PROXY_FMT/$name}"
	if [ "$dest" = "$IN_CLUSTER" ]; then role=hub; else role=spoke; fi

	for pair in "platformCharts:platform-config" "operatorCharts:operators"; do
		key="${pair%%:*}"; group="${pair##*:}"

		for chart in $(listed "$key" "$conf"); do
			rel="$group/$chart"

			if [ ! -f "charts/$rel/Chart.yaml" ]; then
				echo "UNKNOWN  $conf lists $key: $chart — no chart at charts/$rel"
				fail=1
				continue
			fi

			target="${targets[$rel]:-}"
			[ -z "$target" ] && continue   # already reported by check 1

			if [ "$target" = "hub" ] && [ "$role" != "hub" ]; then
				echo "WARN     $conf is not the hub, but lists $key: $chart, annotated oca.io/target: hub"
				warn=1
			fi
		done
	done
done

if [ "$warn" -ne 0 ]; then
	echo "         a chart is deployed somewhere its annotation says it does not belong."
	echo "         Either the annotation in its Chart.yaml is wrong, or the cluster is."
fi

[ "$fail" -eq 0 ] || { echo "chart target annotations are inconsistent"; exit 1; }

echo "OK   every chart named in clusters/*/*/conf.yaml resolves to a chart directory"
[ "$warn" -eq 0 ] && echo "OK   no chart is deployed against its oca.io/target"

exit 0
