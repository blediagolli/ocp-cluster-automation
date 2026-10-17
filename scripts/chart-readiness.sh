#!/usr/bin/env bash
#
# Check the `oca.io/maturity` annotation every chart carries in its Chart.yaml,
# and generate the table in docs/cluster-configuration/chart-readiness.md from
# it.
#
# The annotation records whether a chart has actually run on a live cluster,
# and there are only two answers:
#
#   proven       its objects have been applied to a real cluster and observed
#                working. `oca.io/proven-on: <cluster>@<YYYY-MM-DD>` says where
#                and when.
#   incubating   everything else. Renders, lints, reviewed — none of that
#                counts. A chart is incubating until someone watched it work.
#
# There is deliberately no third "partially proven" value. The thing that would
# earn one — an operator chart whose Subscription is live but whose operand CR
# has never been rendered — is already visible in the generated table's Operand
# column, and calling such a chart `proven` is exactly the claim this file
# exists to stop. advanced-cluster-management is proven; ansible-automation-
# platform, whose Application has been Synced and Healthy on the hub for weeks
# while `oc get ansibleautomationplatform -A` returns nothing, is not.
#
# That distinction is the whole point. ArgoCD reporting Synced/Healthy means it
# applied the YAML it was given. If the chart was given values that render only
# a Subscription, Healthy is a statement about three objects and says nothing
# about whether the operator does its job.
#
# Seven checks. `proven` is a claim about history — this chart's objects have
# been applied somewhere and observed working — not a claim about the present.
# Nothing here asks whether a chart is deployed *right now*.
#
# An earlier version did, asserting `proven <=> deployed on a registered
# cluster` so the annotation could not drift from what ArgoCD reads. It was
# wrong in the direction that matters: it made every proven chart orphan the
# moment its cluster was torn down or emptied, demoting 22 charts for a reason
# that had nothing to do with the charts. Tearing down a cluster does not
# un-run the thing that ran on it. That check is gone; `oca.io/proven-on` says
# *where and when*, which is what makes the claim auditable, and the remaining
# direction — check 3, a registered cluster does not deploy an incubating
# chart — is a deployment-safety gate, not a readiness one.
#
# Check 5 puts a clock on the escape hatch, because the defect this replaces —
# 40 chart HANDOFFs all claiming "research prototype ... not synced to any
# cluster", 8 of them live — was a status line with no expiry.
#
# Runs offline — no kubeconfig, unlike validate-clusters.sh — so it belongs in
# `make validate`. Offline checks can only enforce internal consistency; for
# whether a proven chart is still healthy, see validate-clusters.sh.
#
# Usage: scripts/chart-readiness.sh [--check | --write]
#   (no flag)  print the generated table to stdout
#   --check    run the checks, and verify the committed doc matches
#   --write    run the checks, and rewrite the generated region of the doc
set -uo pipefail

DOC="docs/cluster-configuration/chart-readiness.md"
BEGIN_MARK="<!-- BEGIN GENERATED: chart-readiness -->"
END_MARK="<!-- END GENERATED -->"
STALE_DAYS=30

# Charts reachable from a registered cluster through a lifecycle flag rather
# than through platformCharts/operatorCharts. Each is listed with the flag
# that deploys it, so the "Deployed on" column can say `via <flag>` instead of
# showing them as deployed nowhere. Check 4 keeps the table itself honest.
declare -A GATED=(
	["platform-config/acm-managed-cluster"]="deployImport"
	["cluster-provisioning/openshift-provisioning"]="deployProvision"
	["onboarding/namespace-config"]="teams"
	["onboarding/application-gitops"]="teams"
)

VALID_MATURITY="proven incubating"

fail=0
mode="${1:-}"

# ---------------------------------------------------------------------------
# Read the annotations. Same awk idiom as validate-chart-targets.sh: enter at
# the annotations key, leave at the next unindented non-comment line.
# ---------------------------------------------------------------------------

declare -A maturity provenon undertest target operandfrom

# Prints everything after the key, not $2: oca.io/operand-from carries a
# sentence for the two charts whose operand is not another chart's file.
annotation() {
	awk -v key="$2" '
		/^annotations:/      { inc = 1; next }
		inc && /^[^ #]/      { inc = 0 }
		inc && $1 == key ":" { $1 = ""; sub(/^[ \t]+/, ""); print; exit }
	' "$1"
}

# How many templates a chart has outside the shared install scaffolding. Used
# by check 7 as well as by the table, so it is defined above both.
operand_count() {
	find "charts/$1/templates" -type f \( -name '*.yaml' -o -name '*.yml' \) \
		-not -path '*/install/*' -not -path '*/tests/*' 2>/dev/null | wc -l | tr -d ' '
}

charts=0
while read -r chart; do
	rel="${chart#charts/}"; rel="${rel%/Chart.yaml}"
	charts=$((charts + 1))

	target["$rel"]=$(annotation "$chart" "oca.io/target")
	maturity["$rel"]=$(annotation "$chart" "oca.io/maturity")
	provenon["$rel"]=$(annotation "$chart" "oca.io/proven-on")
	undertest["$rel"]=$(annotation "$chart" "oca.io/under-test")
	operandfrom["$rel"]=$(annotation "$chart" "oca.io/operand-from")
done < <(find charts -mindepth 3 -maxdepth 3 -name Chart.yaml | sort)

# ---------------------------------------------------------------------------
# 1. Every chart declares a maturity, and it is one of the two known values.
# 2. proven carries a well-formed oca.io/proven-on; incubating carries none.
# ---------------------------------------------------------------------------

STAMP_RE='^[a-z0-9][a-z0-9.-]*@[0-9]{4}-[0-9]{2}-[0-9]{2}$'

for rel in "${!maturity[@]}"; do
	m="${maturity[$rel]}"
	if [ -z "$m" ]; then
		echo "MISSING  charts/$rel/Chart.yaml — no oca.io/maturity annotation"
		fail=1
		continue
	fi
	case " $VALID_MATURITY " in
		*" $m "*) ;;
		*)
			echo "INVALID  charts/$rel/Chart.yaml — oca.io/maturity: $m (expected one of: $VALID_MATURITY)"
			fail=1
			continue ;;
	esac

	p="${provenon[$rel]}"
	if [ "$m" = proven ]; then
		if [ -z "$p" ]; then
			echo "UNPROVEN charts/$rel/Chart.yaml — oca.io/maturity: proven with no oca.io/proven-on"
			fail=1
		elif ! [[ "$p" =~ $STAMP_RE ]]; then
			echo "MALFORMED charts/$rel/Chart.yaml — oca.io/proven-on: $p (expected <cluster>@<YYYY-MM-DD>)"
			fail=1
		fi
	elif [ -n "$p" ]; then
		echo "CONFUSED charts/$rel/Chart.yaml — oca.io/maturity: incubating but carries oca.io/proven-on: $p"
		fail=1
	fi
done

# ---------------------------------------------------------------------------
# Read the clusters. Which are registered, and what each one lists.
# ---------------------------------------------------------------------------

declare -A listed_on    # rel -> space-separated registered cluster names
declare -A registered   # cluster name -> 1

listed() {
	awk -v key="$1" '
		$0 ~ "^" key ":"        { f = 1; next }
		f && /^[^ #-]/          { f = 0 }
		f && /^[ ]*-[ ]*chart:/ { print $3 }
	' "$2"
}

while read -r conf; do
	name=$(awk '
		/^cluster:/         { inc = 1; next }
		inc && /^[^ #]/     { inc = 0 }
		inc && /^[ ]+name:/ { gsub(/^"|"$/, "", $2); print $2; exit }' "$conf")
	reg=$(awk '/^clusterRegistered:/ { print $2; exit }' "$conf")

	[ "$reg" = "true" ] || continue
	registered["$name"]=1

	for pair in "platformCharts:platform-config" "operatorCharts:operators"; do
		key="${pair%%:*}"; group="${pair##*:}"
		for chart in $(listed "$key" "$conf"); do
			listed_on["$group/$chart"]="${listed_on[$group/$chart]:-} $name"
		done
	done
done < <(find clusters -mindepth 3 -maxdepth 3 -name conf.yaml | sort)

# ---------------------------------------------------------------------------
# 3. A registered cluster does not deploy an incubating chart, unless that
#    chart is explicitly under test on that cluster.
#
# This is the one that replaces a quarantine branch. A branch keeps unproven
# charts out of main by moving files, which a single `git checkout` undoes and
# which costs a permanent merge tax on the four byte-identical install
# templates. This costs nothing and cannot be bypassed by a checkout.
# ---------------------------------------------------------------------------

for rel in "${!listed_on[@]}"; do
	[ "${maturity[$rel]:-}" = "incubating" ] || continue
	ut="${undertest[$rel]:-}"
	ut_cluster="${ut%@*}"

	for cluster in ${listed_on[$rel]}; do
		if [ "$ut_cluster" != "$cluster" ]; then
			echo "UNPROVEN $cluster deploys charts/$rel, which is incubating"
			echo "         Either prove it and set oca.io/maturity: proven, or mark it"
			echo "         oca.io/under-test: $cluster@$(date +%F) while you work on it."
			fail=1
		fi
	done
done

# ---------------------------------------------------------------------------
# 4. A gated chart's entry is real, so the exemption table cannot rot either.
# 5. An under-test claim expires. The escape hatch is a timer, not a hole.
# ---------------------------------------------------------------------------

for rel in "${!GATED[@]}"; do
	if [ -z "${maturity[$rel]:-}" ]; then
		echo "STALE    GATED lists $rel, which is not a chart"
		fail=1
	fi
done

now=$(date +%s)
for rel in "${!undertest[@]}"; do
	ut="${undertest[$rel]}"
	[ -n "$ut" ] || continue

	if ! [[ "$ut" =~ $STAMP_RE ]]; then
		echo "MALFORMED charts/$rel/Chart.yaml — oca.io/under-test: $ut (expected <cluster>@<YYYY-MM-DD>)"
		fail=1
		continue
	fi
	if [ "${maturity[$rel]}" = "proven" ]; then
		echo "CONFUSED charts/$rel/Chart.yaml — proven, but still carries oca.io/under-test"
		fail=1
		continue
	fi

	day="${ut#*@}"
	# BSD date on macOS, GNU date in CI.
	then_s=$(date -j -f %Y-%m-%d "$day" +%s 2>/dev/null || date -d "$day" +%s 2>/dev/null)
	if [ -z "$then_s" ]; then
		echo "MALFORMED charts/$rel/Chart.yaml — oca.io/under-test: $ut is not a real date"
		fail=1
		continue
	fi
	age=$(( (now - then_s) / 86400 ))
	if [ "$age" -gt "$STALE_DAYS" ]; then
		echo "EXPIRED  charts/$rel/Chart.yaml — under test on ${ut%@*} for $age days (limit $STALE_DAYS)"
		echo "         Prove it, or take it off the cluster. Do not re-date the annotation."
		fail=1
	fi
done

# ---------------------------------------------------------------------------
# 6. No chart HANDOFF.md states a status of its own.
#
# This is the defect that started all of it: 40 of the 41 operator HANDOFFs
# carried the identical line
#
#   **Status:** research prototype on `research/operator-charts`. Not synced
#   to any cluster.
#
# while eight of those charts were running on acm-hub. Prose duplicating a
# fact has one failure mode and it always happens. So the rule is not "the
# Status line must agree with oca.io/maturity" — that is still a second copy,
# and still needs editing twice per promotion. The line may only *point* at
# the annotation. A pointer asserts nothing, so it cannot be wrong.
# ---------------------------------------------------------------------------

HANDOFF_STATUS='**Status:** see [chart readiness](../../../docs/cluster-configuration/chart-readiness.md); `oca.io/maturity` in `Chart.yaml` is the source of truth.'

while read -r handoff; do
	line=$(grep -m1 '^\*\*Status:\*\*' "$handoff") || continue
	[ "$line" = "$HANDOFF_STATUS" ] && continue
	echo "CLAIMS   $handoff states a status of its own:"
	echo "           $line"
	echo "         Per-chart status lives in oca.io/maturity and nowhere else."
	echo "         Use exactly this line, or drop it:"
	echo "           $HANDOFF_STATUS"
	fail=1
done < <(find charts -mindepth 3 -maxdepth 3 -name HANDOFF.md | sort)

# ---------------------------------------------------------------------------
# 7. A chart with no operand template of its own says where its CR comes from.
#
# Ten operator charts render nothing but a Namespace, an OperatorGroup and a
# Subscription. Five of those are finished — something else supplies the CR,
# and `oca.io/operand-from` is where that is written down. The other five are
# unfinished, and the only thing separating the two groups is whether anyone
# knew. So the annotation is required the moment such a chart claims `proven`:
# an installed operator with no operand and no explanation is an idle
# controller-manager, not a working chart.
#
# scripts/validate-clusters.sh --charts reads the same annotation to decide
# which live Applications are allowed to have applied only a Subscription,
# which is why this is an annotation and not a table in one of the scripts.
# ---------------------------------------------------------------------------

for rel in "${!maturity[@]}"; do
	from="${operandfrom[$rel]:-}"
	n=$(operand_count "$rel")

	if [ "$n" -gt 0 ] && [ -n "$from" ]; then
		echo "CONFUSED charts/$rel/Chart.yaml — has $n operand template(s) of its own,"
		echo "         but claims oca.io/operand-from: $from"
		fail=1
	elif [ "$n" -eq 0 ] && [ -z "$from" ] && [ "${maturity[$rel]}" = "proven" ]; then
		echo "HOLLOW   charts/$rel is proven but renders nothing beyond its Subscription"
		echo "         If something else supplies its CR, say so in Chart.yaml:"
		echo "           oca.io/operand-from: <chart/templates/file.yaml, or how it is created>"
		echo "         If nothing does, the chart is unfinished and is not proven."
		fail=1
	fi
done

[ "$fail" -eq 0 ] || { echo "chart maturity annotations are inconsistent"; exit 1; }

# ---------------------------------------------------------------------------
# The table. Every column is derived, so no hand-maintained cell can go stale.
#
# Operand answers "what does this chart do beyond installing an operator?" and
# is counted from the tree, not from a render: charts/operators/*/templates
# holds four byte-identical install files that every operator chart shares, so
# everything outside install/ and tests/ is the chart's actual content. A
# `gated` count is operand templates that are all behind an include flag — they
# exist, but nothing renders unless a cluster's values turn them on.
# ---------------------------------------------------------------------------

operand() {
	local d="charts/$1" n=0 ungated=0 f last
	while read -r f; do
		[ -z "$f" ] && continue
		n=$((n + 1))
		# Wrapped means the whole document is behind a flag: an `if` in column
		# zero, and an `end` as the last non-blank line. Testing only the first
		# few lines misses charts/operators/quay/templates/config-bundle-secret
		# .yaml, whose guard sits below a comment block.
		last=$(grep -v '^[[:space:]]*$' "$f" | tail -1)
		if grep -qE '^\{\{-?[[:space:]]*if' "$f" && [[ "$last" =~ ^\{\{-?[[:space:]]*end ]]; then
			continue
		fi
		ungated=$((ungated + 1))
	done < <(find "$d/templates" -type f \( -name '*.yaml' -o -name '*.yml' \) \
		-not -path '*/install/*' -not -path '*/tests/*' 2>/dev/null | sort)

	# Nearly every template in this repo is wrapped in an include flag, so
	# "gated" is the norm and worth no ink. The three that render
	# unconditionally are the anomaly, so those are the ones marked.
	if [ "$n" -eq 0 ]; then
		# A chart with no operand template either has its CR supplied from
		# outside — check 7 insists that be declared — or renders nothing but
		# a Subscription, which is the thing worth spotting.
		[ -n "${operandfrom[$1]:-}" ] && echo "elsewhere" || echo "none"
	elif [ "$ungated" -eq 0 ]; then echo "$n"
	else echo "$n, always on"
	fi
}

emit() {
	echo "$BEGIN_MARK"
	echo
	echo "| Chart | Group | Target | Maturity | Operand | Deployed on | Verified |"
	echo "|---|---|---|---|---|---|---|"
	for rel in $(printf '%s\n' "${!maturity[@]}" | sort); do
		group="${rel%%/*}"; name="${rel##*/}"
		dep="${listed_on[$rel]:-}"
		dep="${dep# }"
		dep="${dep// /, }"
		if [ -z "$dep" ] && [ -n "${GATED[$rel]:-}" ]; then
			dep="via \`${GATED[$rel]}\`"
		fi
		[ -z "$dep" ] && dep="—"

		if [ "${maturity[$rel]}" = proven ]; then
			mat="proven"; ev="${provenon[$rel]}"
		else
			mat="incubating"
			ev="${undertest[$rel]:+under test since ${undertest[$rel]#*@}}"
			[ -z "$ev" ] && ev="—"
		fi

		echo "| \`$name\` | $group | ${target[$rel]:-?} | $mat | $(operand "$rel") | $dep | $ev |"
	done
	echo
	n_p=0; n_i=0
	for rel in "${!maturity[@]}"; do
		[ "${maturity[$rel]}" = proven ] && n_p=$((n_p + 1)) || n_i=$((n_i + 1))
	done
	echo "$n_p proven, $n_i incubating, $charts charts total."
	echo
	echo "$END_MARK"
}

case "$mode" in
	--write)
		[ -f "$DOC" ] || { echo "no $DOC to write into"; exit 1; }
		skel=$(mktemp); body=$(mktemp)
		awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
			$0 == b { skip = 1; print "@@GENERATED@@"; next }
			$0 == e { skip = 0; next }
			!skip   { print }' "$DOC" >"$skel"
		if ! grep -q '@@GENERATED@@' "$skel"; then
			echo "no generated region in $DOC"; rm -f "$skel" "$body"; exit 1
		fi
		emit >"$body"
		# awk -v cannot carry a multi-line value, so splice from the file.
		# Build the result beside the doc and move it into place: redirecting
		# straight into $DOC truncates it if awk then fails.
		out=$(mktemp)
		if ! awk -v f="$body" '
			$0 == "@@GENERATED@@" { while ((getline l < f) > 0) print l; next }
			{ print }' "$skel" >"$out"; then
			echo "failed to splice $DOC — left unchanged"; rm -f "$skel" "$body" "$out"; exit 1
		fi
		mv "$out" "$DOC"
		rm -f "$skel" "$body"
		echo "OK   wrote the generated region of $DOC"
		;;
	--check)
		[ -f "$DOC" ] || { echo "no $DOC — run scripts/chart-readiness.sh --write"; exit 1; }
		committed=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
			$0 == b { p = 1 } p { print } $0 == e { p = 0 }' "$DOC")
		if [ "$committed" != "$(emit)" ]; then
			echo "STALE    $DOC does not match the charts it describes"
			echo "         Run: scripts/chart-readiness.sh --write"
			diff <(echo "$committed") <(emit) | head -20
			exit 1
		fi
		echo "OK   all $charts charts declare a valid oca.io/maturity"
		echo "OK   no registered cluster deploys an incubating chart unannounced"
		echo "OK   no chart HANDOFF.md states a status of its own"
		echo "OK   every proven chart renders an operand, or says where its CR comes from"
		echo "OK   $DOC matches"
		;;
	"")
		emit
		;;
	*)
		echo "usage: $0 [--check | --write]"; exit 2 ;;
esac

exit 0
