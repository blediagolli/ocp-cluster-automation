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
# Usage: scripts/validate-clusters.sh [--quiet]
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

ARGOCD_NS="${ARGOCD_NS:-openshift-gitops}"
IN_CLUSTER="https://kubernetes.default.svc"
PROXY_FMT="https://cluster-proxy-addon-user.multicluster-engine.svc.cluster.local:9092"

command -v oc >/dev/null 2>&1 || { echo "validate-clusters: oc not found"; exit 2; }
oc whoami >/dev/null 2>&1 || {
	echo "validate-clusters: not logged in to a cluster — skipping (set KUBECONFIG to the hub)"
	exit 2
}

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
