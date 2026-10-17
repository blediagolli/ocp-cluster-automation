#!/usr/bin/env bash
#
# Compare the clusters described in clusters/**/conf.yaml against the ones
# ArgoCD on the hub can actually reach, and report where `clusterRegistered`
# disagrees with reality.
#
# The flag exists because an Application whose destination ArgoCD cannot
# resolve does not just fail itself — it fails the whole ApplicationSet, for
# every cluster, and that surfaces as a Degraded platform-root. Setting
# clusterRegistered: false makes the generators yield no elements for that
# cluster, so no Application is created and there is nothing to resolve.
#
# The cost of a manual flag is that it goes stale: a cluster gets imported and
# nobody turns it on, or gets detached and nobody turns it off. This is the
# check for that. It needs a kubeconfig for the hub; everything else under
# `make validate` runs offline.
#
# --charts is the online half of scripts/chart-readiness.sh. That script can
# only check the repo against itself: that a chart annotated `proven` is still
# listed by a registered cluster. It cannot check the claim, because the claim
# is about a cluster. This can.
#
# What it asserts is deliberately stronger than Synced/Healthy. ArgoCD reports
# Synced/Healthy when it has applied the YAML it was handed and the resulting
# objects look well-formed — and an operator chart handed no values renders
# exactly a Namespace, an OperatorGroup and a Subscription, all three of which
# are perfectly healthy and none of which is the operator doing anything.
# ansible-automation-platform sat Synced/Healthy on the hub for weeks in that
# state. So the question here is whether the Application applied anything
# *beyond* those three kinds, with the exemption for charts whose CR is
# supplied elsewhere read from oca.io/operand-from rather than hardcoded.
#
# Usage: scripts/validate-clusters.sh [--quiet | --charts]
set -uo pipefail

QUIET=0
CHARTS=0
case "${1:-}" in
	--quiet)  QUIET=1 ;;
	--charts) CHARTS=1 ;;
	"")       ;;
	*)        echo "usage: $0 [--quiet | --charts]"; exit 2 ;;
esac

ARGOCD_NS="${ARGOCD_NS:-openshift-gitops}"
IN_CLUSTER="https://kubernetes.default.svc"
PROXY_FMT="https://cluster-proxy-addon-user.multicluster-engine.svc.cluster.local:9092"

command -v oc >/dev/null 2>&1 || { echo "validate-clusters: oc not found"; exit 2; }
oc whoami >/dev/null 2>&1 || {
	echo "validate-clusters: not logged in to a cluster — skipping (set KUBECONFIG to the hub)"
	exit 2
}

if [ "$CHARTS" = 1 ]; then
	# The three kinds every operator chart renders from the shared templates
	# under charts/operators/*/templates/install/. An Application that applied
	# only these did nothing the chart exists to do.
	INSTALL_KINDS="Namespace OperatorGroup Subscription"

	annotation() {
		awk -v key="$2" '
			/^annotations:/      { inc = 1; next }
			inc && /^[^ #]/      { inc = 0 }
			inc && $1 == key ":" { $1 = ""; sub(/^[ \t]+/, ""); print; exit }
		' "$1"
	}

	listed() {
		awk -v key="$1" '
			$0 ~ "^" key ":"        { f = 1; next }
			f && /^[^ #-]/          { f = 0 }
			f && /^[ ]*-[ ]*chart:/ { print $3 }
		' "$2"
	}

	# Every Application in one call, rather than two per chart. Partly for
	# speed, but mostly so a connection that drops midway fails once and
	# loudly: per-chart calls would each come back empty and the run would
	# report thirty Applications as MISSING from the hub, which is a false
	# accusation that reads exactly like a real one.
	apps=$(oc get application -n "$ARGOCD_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\t"}{range .status.resources[*]}{.kind}{","}{end}{"\n"}{end}' 2>&1) || {
		echo "validate-clusters: could not list Applications in $ARGOCD_NS"
		printf '%s\n' "$apps" | head -3
		exit 2
	}

	declare -A app_sync app_health app_kinds
	while IFS=$'\t' read -r n s h k; do
		[ -n "$n" ] || continue
		app_sync["$n"]="${s:-Unknown}"
		app_health["$n"]="${h:-Unknown}"
		app_kinds["$n"]="$k"
	done <<<"$apps"

	printf '%-52s %-10s %-9s %-10s %s\n' APPLICATION SYNC HEALTH OPERAND VERDICT
	cfail=0
	checked=0

	for conf in $(find clusters -mindepth 3 -maxdepth 3 -name conf.yaml | sort); do
		reg=$(awk '/^clusterRegistered:/ { print $2; exit }' "$conf")
		[ "$reg" = "true" ] || continue

		# clusters/<env>/<cluster>/conf.yaml — the Application name is built
		# from the same two path components the ApplicationSet generators use.
		rest="${conf#clusters/}"
		env="${rest%%/*}"
		cluster="${rest#*/}"; cluster="${cluster%/conf.yaml}"

		for pair in "platformCharts:platform-config:platform" "operatorCharts:operators:op"; do
			key="${pair%%:*}"; tail="${pair#*:}"
			group="${tail%%:*}"; prefix="${tail##*:}"

			for chart in $(listed "$key" "$conf"); do
				cy="charts/$group/$chart/Chart.yaml"
				[ -f "$cy" ] || continue
				app="$prefix-$env-$cluster-$chart"
				checked=$((checked + 1))

				mat=$(annotation "$cy" "oca.io/maturity")
				from=$(annotation "$cy" "oca.io/operand-from")

				sync="${app_sync[$app]:-ABSENT}"
				health="${app_health[$app]:-ABSENT}"

				# .status.resources is what ArgoCD actually applied, which is
				# the only honest answer to "did this chart do anything".
				operand=0
				IFS=, read -r -a kinds <<<"${app_kinds[$app]:-}"
				for kind in "${kinds[@]}"; do
					[ -n "$kind" ] || continue
					case " $INSTALL_KINDS " in *" $kind "*) continue ;; esac
					operand=$((operand + 1))
				done

				if [ "$sync" = ABSENT ]; then
					verdict="MISSING — no such Application on the hub"; cfail=1
				elif [ "$mat" != proven ]; then
					verdict="(incubating — not asserted)"
				elif [ "$sync" != Synced ] || [ "$health" != Healthy ]; then
					verdict="UNHEALTHY — annotated proven"; cfail=1
				elif [ "$operand" -eq 0 ] && [ -z "$from" ]; then
					verdict="SUBSCRIPTION-ONLY — Healthy, but applied no operand"; cfail=1
				elif [ "$operand" -eq 0 ]; then
					verdict="OK (operand from ${from%%/*})"
				else
					verdict=OK
				fi

				[ "$QUIET" = 1 ] && [ "${verdict#OK}" != "$verdict" ] && continue
				printf '%-52s %-10s %-9s %-10s %s\n' \
					"$app" "$sync" "$health" "$operand" "$verdict"
			done
		done
	done

	echo
	if [ "$cfail" -ne 0 ]; then
		echo "A proven chart is not doing on the cluster what the annotation claims."
		echo "SUBSCRIPTION-ONLY is the one to read twice: ArgoCD is green because it"
		echo "applied what it was given, and what it was given was an operator and no"
		echo "operand. Either turn the operand's include flag on in the cluster's"
		echo "values, or set oca.io/maturity: incubating in the chart."
		exit 1
	fi
	echo "OK   all $checked deployed charts match their oca.io/maturity"
	exit 0
fi

# ArgoCD resolves a destination by server URL, not by name, so that is what
# this compares. The secret holds both base64-encoded.
servers=$(oc get secret -n "$ARGOCD_NS" -l argocd.argoproj.io/secret-type=cluster \
	-o jsonpath='{range .items[*]}{.data.server}{"\n"}{end}' 2>/dev/null \
	| while read -r b64; do [ -n "$b64" ] && printf '%s\n' "$b64" | base64 -d && echo; done)

managed=$(oc get managedcluster -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

printf '%-46s %-14s %-9s %-7s %s\n' CONF CLUSTER REACHABLE FLAG VERDICT
fail=0

for conf in $(find clusters -mindepth 3 -maxdepth 3 -name conf.yaml | sort); do
	eval "$(awk '
		/^cluster:/            { inc = 1; next }
		inc && /^[^ #]/        { inc = 0 }
		inc && /^[ ]+name:/    { n = $2 }
		inc && /^[ ]+address:/ { a = $2 }
		/^clusterRegistered:/  { f = $2 }
		function unquote(s) { gsub(/^"|"$/, "", s); return s }
		END {
			printf "name=%s; addr=%s; flag=%s\n",
				unquote(n), unquote(a), (f == "" ? "ABSENT" : f)
		}' "$conf")"

	dest="${addr:-$PROXY_FMT/$name}"

	if [ "$dest" = "$IN_CLUSTER" ]; then
		reachable=yes          # the hub itself; always resolvable
	elif printf '%s\n' "$servers" | grep -qxF "$dest"; then
		reachable=yes
	else
		reachable=no
	fi

	case "$reachable/$flag" in
		yes/true|no/false) verdict=OK ;;
		no/true)
			verdict="MISMATCH — no cluster secret for $dest"
			printf '%s\n' "$managed" | grep -qxF "$name" \
				&& verdict="$verdict (ManagedCluster exists; GitOpsCluster has not propagated it)"
			fail=1 ;;
		yes/false)
			verdict="MISMATCH — reachable, so this cluster is getting nothing"
			fail=1 ;;
		*/ABSENT)
			verdict="MISSING — no clusterRegistered key; missingkey=error will fail the generator"
			fail=1 ;;
		*) verdict="MISMATCH — clusterRegistered is '$flag', expected true or false"; fail=1 ;;
	esac

	[ "$QUIET" = 1 ] && [ "$verdict" = OK ] && continue
	printf '%-46s %-14s %-9s %-7s %s\n' "$conf" "$name" "$reachable" "$flag" "$verdict"
done

if [ "$fail" -ne 0 ]; then
	echo
	echo "clusterRegistered disagrees with the hub. On for a cluster ArgoCD cannot"
	echo "reach fails every ApplicationSet, not just that cluster; off for one it"
	echo "can reach means that cluster is silently getting nothing."
	exit 1
fi

echo "OK   clusterRegistered matches the hub for every cluster"
