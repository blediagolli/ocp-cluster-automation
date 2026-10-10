#!/usr/bin/env bash
#
# Validate the two onboarding charts.
#
# They are the only charts in this repo that turn a values file into a whole
# tenancy, and with prune: true an empty render deletes every namespace the
# team owns. So this checks more than "does it render" -- it checks that
# neither chart can be made to render nothing, in any state, including a
# quiesce and a values file that went missing.
#
# Run by `make validate-onboarding`, and as part of `make validate`.
#
# No `-e`: the checks below count failures and report all of them, rather than
# stopping at the first. Same reason the chart test scripts omit it.
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

CHARTS=(namespace-config application-gitops)
HELPER=templates/_helpers.tpl

fail=0
# Section 2's renders are kept so section 5 can scan them without rendering
# every pair a second time.
renders=$(mktemp -d)
trap 'rm -rf "$renders"' EXIT

note() { printf '%s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; fail=1; }
ok()   { printf 'OK   %s\n' "$*"; }

# The values chain each ApplicationSet feeds a chart is already written down
# once, in scripts/render.sh. Asking it for the chain instead of copying the
# valueFiles blocks a third time is the whole point -- a chain that drifts from
# the ApplicationSet makes this script validate something ArgoCD never renders.
#
# --files prints one line per entry, `  [ok]     <path>` for the ones that
# exist and `  [absent] <path>` for the ones ArgoCD skips under
# ignoreMissingValueFiles. Emits them as alternating -f / <path> words.
chain_args() {
  ./scripts/render.sh "$1" "$2" --team "$3" --files 2>/dev/null \
    | awk '$1 == "[ok]" { print "-f"; print $2 }'
}

# ---------------------------------------------------------------------------
# 1. The shared helper must be byte-identical in both charts.
#
# It is duplicated rather than put in a shared subchart because ArgoCD renders
# each chart straight from its path with no dependency build. Nothing in it
# reads a chart-specific key, so any difference between the two copies is
# drift, not intent -- and drift here means the empty-render guard behaves
# differently in the two halves of one team's tenancy.
# ---------------------------------------------------------------------------
reference="charts/onboarding/${CHARTS[0]}/$HELPER"
for chart in "${CHARTS[@]:1}"; do
  if ! cmp -s "$reference" "charts/onboarding/$chart/$HELPER"; then
    bad "charts/onboarding/$chart/$HELPER has drifted from $reference"
    diff -u "$reference" "charts/onboarding/$chart/$HELPER" | head -40
  fi
done
[ $fail -eq 0 ] && ok "$HELPER identical in all ${#CHARTS[@]} onboarding charts"

# ---------------------------------------------------------------------------
# 2. Lint and render every cluster x team pair through its real values chain.
#
# Note that `helm lint` on chart defaults alone is an ERROR by design once the
# guards exist -- an empty values file is exactly the state they refuse. So
# lint gets the same -f chain as the render.
#
# It is --strict because plain `helm lint` reports a tripped `required` or
# `fail` as a WARN and still exits 0 -- it is not a guard check at all. The
# guards are enforced by the renders in section 3, which use `helm template`
# and do fail.
#
# clusterRegistered is deliberately ignored. It decides whether ArgoCD creates
# the Application today; it says nothing about whether the chart would render
# when the cluster is finally registered, which is what this is for.
# ---------------------------------------------------------------------------
#
# Each team entry drives both ApplicationSets independently -- namespaceConfig
# and applicationGitops, absent meaning on. Only the enabled half is rendered
# here, deliberately: a team with applicationGitops: false is exactly the team
# with no `team.repo` to give an AppProject, so rendering the half ArgoCD will
# never generate would fail on a value that is correctly absent.
#
# teams_of() emits "<team> <namespaceConfig> <applicationGitops>" per entry.
teams_of() {
  awk '
    function flush() { if (name != "") print name, nc, ag; name = "" }
    /^teams:/                      { t = 1; next }
    /^[^ ]/                        { flush(); t = 0 }
    t && /^[ ]*-[ ]*team:/         { flush(); name = $3; nc = "true"; ag = "true"; next }
    t && /^[ ]*namespaceConfig:/   { v = $2; gsub(/"/, "", v); nc = v }
    t && /^[ ]*applicationGitops:/ { v = $2; gsub(/"/, "", v); ag = v }
    END { flush() }
  ' "$1"
}

pairs=0
while IFS= read -r conf; do
  cluster_path=${conf%/conf.yaml}
  cluster=${cluster_path#clusters/}
  while read -r team nc ag; do
    [ -n "$team" ] || continue
    [ -f "teams/$team.yaml" ] || { bad "$conf lists team '$team', but teams/$team.yaml does not exist"; continue; }
    if [ "$nc" = "false" ] && [ "$ag" = "false" ]; then
      bad "$conf lists team '$team' with both namespaceConfig and applicationGitops false -- the entry generates nothing, so it reads as onboarded while deploying neither half; remove the entry instead"
      continue
    fi
    for chart in "${CHARTS[@]}"; do
      case $chart in
        namespace-config)    [ "$nc" = "false" ] && continue ;;
        application-gitops)  [ "$ag" = "false" ] && continue ;;
      esac
      args=(); while IFS= read -r a; do args+=("$a"); done < <(chain_args "$cluster" "$chart" "$team")
      if ! out=$(helm lint --strict "charts/onboarding/$chart" "${args[@]}" 2>&1); then
        bad "helm lint $chart for $cluster/$team"; printf '%s\n' "$out" | head -20
      fi
      if ! out=$(./scripts/render.sh "$cluster" "$chart" --team "$team" 2>&1); then
        bad "helm template $chart for $cluster/$team"; printf '%s\n' "$out" | head -20
      elif ! printf '%s\n' "$out" | grep -q '^kind:'; then
        # Unconditional, with no exemption for a retiring team. Neither chart
        # has a legitimate empty render any more: both keep rendering their
        # namespaces through a quiesce, so zero resources can only mean a
        # values file that went missing. That is the single rule the whole
        # lifecycle design was simplified down to -- see section 3.
        bad "$chart renders ZERO resources for $cluster/$team -- with prune: true that deletes the team's tenancy"
        printf '%s\n' "$out" | head -20
      else
        # Both charts of one tenancy go in one file: the two Applications apply
        # into the same namespaces, so a collision between them matters as much
        # as one inside either.
        printf '%s\n' "$out" >> "$renders/${cluster//\//_}__$team.yaml"
      fi
      pairs=$((pairs + 1))
    done
  done < <(teams_of "$conf")
done < <(find clusters -name conf.yaml | sort)
ok "linted and rendered $pairs chart/cluster/team combinations"

# ---------------------------------------------------------------------------
# 3. An empty render must always be an error, and quiesce must never produce
#    one.
#
# This is the check the rest of the file exists for, and it is the whole of
# the lifecycle design. ArgoCD cannot tell "this team is being retired" from
# "this team's values file is gone" -- both are zero resources, and prune:
# true acts on either. Rather than teach the chart to tell them apart, there
# is no longer a first case: NEITHER CHART EVER RENDERS NOTHING. Both keep
# rendering their namespaces through a quiesce, so zero resources always
# means a broken values file and always fails.
#
# That one property is what removed team.offboard, the enforced two-phase
# ordering, allowEmpty: true on both ApplicationSets, and a Project/Namespace
# GVK exclusion -- each of which existed only to make an empty render safe.
# Deleting a tenancy is now a documented manual step; see HANDOFF.md.
#
# So the only phase left is quiesce, and what it must do is asserted directly
# rather than by resource count:
#
#   application-gitops  keeps <team>-gitops and NOTHING ELSE
#   namespace-config    keeps the namespaces, their quota and their limits;
#                       drops every RoleBinding and the managed-by label
# ---------------------------------------------------------------------------
base=(-f teams/team-alpha.yaml -f env/dev/namespace-sizes.yaml --set cluster.environment=dev)
for chart in "${CHARTS[@]}"; do
  path="charts/onboarding/$chart"

  if out=$(helm template t "$path" 2>&1); then
    bad "$chart renders with NO values file at all -- a deleted teams/<team>.yaml would silently delete the team's tenancy"
  fi

  # Quiesce must still name its subject. An emptied values file sets no keys,
  # so it can never satisfy "quiescing AND named" and stays on the failing
  # path above.
  if out=$(helm template t "$path" --set team.quiesce=true 2>&1); then
    bad "$chart accepts team.quiesce with no team.name -- an emptied values file is then indistinguishable from a deliberate quiesce"
  fi

  # A quoted "false" is truthy in a Go template, so it would quiesce the team
  # rather than leave it alone. The flag rejects a non-boolean outright.
  if out=$(helm template t "$path" "${base[@]}" --set-string "team.quiesce=false" 2>&1); then
    bad "$chart accepts team.quiesce: \"false\" as a string -- it is truthy in a template, so this spelling would quiesce the team"
  fi
done

# What quiesce means, asserted directly rather than by resource count: the
# namespaces survive, the team's access does not, and nothing can deploy into
# them. Each of the three is the point of a separate template, and a chart
# that kept any one of them would be quiescing in name only.
q_ns=$(helm template t charts/onboarding/namespace-config "${base[@]}" --set team.quiesce=true 2>/dev/null)
q_gitops=$(helm template t charts/onboarding/application-gitops "${base[@]}" --set team.quiesce=true 2>/dev/null)
quiesce_fail=0
qbad() { bad "$*"; quiesce_fail=1; }
printf '%s\n' "$q_gitops" | grep -qE '^kind: (ArgoCD|AppProject|RoleBinding)' \
  && qbad "application-gitops still renders the team's ArgoCD, AppProject or RoleBindings when team.quiesce is true -- quiesce exists to take the deploy machinery away"
# The namespace has to SURVIVE the quiesce, and it is the only thing that may.
# Empty is not an acceptable render: it trips ArgoCD's allowEmpty guard so
# nothing prunes at all, and an unrendered Namespace is re-resolved under
# OpenShift's project.openshift.io/v1 Project GVK and then silently never
# pruned. Both were observed on acm-hub; see HANDOFF.md.
printf '%s\n' "$q_gitops" | grep -q '^kind: Namespace' \
  || qbad "application-gitops renders no Namespace when team.quiesce is true -- an empty render trips ArgoCD's allowEmpty guard and prunes nothing at all"
printf '%s\n' "$q_ns" | grep -q '^kind: Namespace' \
  || qbad "namespace-config renders no Namespace when team.quiesce is true -- quiesce exists to keep the namespaces and their data"
printf '%s\n' "$q_ns" | grep -q 'name: team-alpha-admin$' \
  && qbad "namespace-config still renders the team's RoleBindings when team.quiesce is true -- withdrawing access is most of what quiesce is for"
printf '%s\n' "$q_ns" | grep -q 'argocd.argoproj.io/managed-by:' \
  && qbad "namespace-config still labels quiesced namespaces argocd.argoproj.io/managed-by -- the gitops-operator keeps the team's ArgoCD RBAC in place and the namespace is not actually quiesced"
printf '%s\n' "$q_ns" | grep -q 'gfo.io/lifecycle: quiesced' \
  || qbad "quiesced namespaces carry no gfo.io/lifecycle label -- nothing on the cluster then distinguishes a retained namespace from a live one"
[ $quiesce_fail -eq 0 ] && ok "quiesce keeps the namespaces and drops access; neither chart ever renders empty; an absent values file fails"

# ---------------------------------------------------------------------------
# 4. No two teams may claim the same namespace in the same environment.
#
# Helm cannot see this: each release only ever sees its own team's values. On
# a cluster the second Application adopts the first's namespace and the two
# then fight forever over its labels, quota and RoleBindings -- while ArgoCD
# reports both as Synced, because each is getting what it asked for.
# ---------------------------------------------------------------------------
dupes=$(for f in teams/*.yaml; do
  awk -v f="$f" '
    /^team:/ { inteam = 1; next }
    /^[^ ]/  { inteam = 0; inns = 0 }
    inteam && /^  namespaces:/ { inns = 1; next }
    inns && /^  [a-zA-Z]/      { inns = 0 }
    inns && /^    [a-z0-9-]+:/ { env = $1; sub(/:$/, "", env); next }
    inns && /^      - name:/   { print env, $3, f }
  ' "$f"
done | sort | awk '
  { key = $1 " " $2 }
  key == prev { print "  " $2 " in environment " $1 ": " owner " and " $3 }
  { prev = key; owner = $3 }
')
if [ -n "$dupes" ]; then
  bad "the same namespace is claimed by more than one team:"
  printf '%s\n' "$dupes"
else
  ok "no namespace is claimed by two teams in the same environment"
fi

# ---------------------------------------------------------------------------
# 5. The ResourceQuota and LimitRange toggles must actually toggle.
#
# They exist so an estate can come under this chart before it comes under its
# enforcement, which means they get used on live namespaces where prune: true
# turns "stopped rendering" into "deleted". A toggle that silently stopped
# working would be read as "nothing to do" in exactly the state where the
# chart is supposed to be removing an object.
#
# The default-on direction is checked too: a tier that lost its `include` key
# must keep rendering, since env/<env>/namespace-sizes.yaml written before
# these existed sets neither.
# ---------------------------------------------------------------------------
nsbase=(-f teams/team-alpha.yaml -f env/dev/namespace-sizes.yaml --set cluster.environment=dev)
count_kind() {
  local kind=$1; shift
  helm template t charts/onboarding/namespace-config "${nsbase[@]}" "$@" 2>/dev/null \
    | grep -c "^kind: $kind\$"
}
toggle_fail=0
check() {
  local what=$1 want=$2 got=$3; shift 3
  [ "$got" = "$want" ] && return
  bad "$what: expected $want, got $got"
  toggle_fail=1
}
check "ResourceQuota count with no toggles set"  2 "$(count_kind ResourceQuota)"
check "LimitRange count with no toggles set"     2 "$(count_kind LimitRange)"
check "ResourceQuota count, tier small off"      1 "$(count_kind ResourceQuota --set namespaceSizes.small.resourceQuota.include=false)"
check "LimitRange count, tier small off"         1 "$(count_kind LimitRange --set namespaceSizes.small.limitRange.include=false)"
check "ResourceQuota count, both namespaces off" 0 "$(count_kind ResourceQuota --set-json 'team.namespaces.dev=[{"name":"a","size":"small","resourceQuota":false}]' --set-json 'team.namespaces.stage=[{"name":"b","size":"medium","resourceQuota":false}]')"
# Tier off, one namespace opting back in -- the direction a migration runs.
check "LimitRange count, tier off + one opt-in"  1 "$(count_kind LimitRange --set namespaceSizes.small.limitRange.include=false --set-json 'team.namespaces.dev=[{"name":"a","size":"small"},{"name":"b","size":"small","limitRange":true}]' --set-json 'team.namespaces.stage=[]')"
[ $toggle_fail -eq 0 ] && ok "resourceQuota and limitRange toggle per tier and per namespace"

# ---------------------------------------------------------------------------
# 6. No two rendered objects in one tenancy may share kind + namespace + name.
#
# Helm does not deduplicate and does not complain: two documents with the same
# identity both reach the cluster, the second overwrites the first, and the
# tenancy ends up with whichever happened to render last. For a RoleBinding it
# is worse than losing one -- roleRef is immutable, so if the two name
# different roles the first apply succeeds and every sync after it fails on a
# field nobody edited.
#
# onboarding.roleBindings catches the duplicates it can see inside its own
# list. This catches the ones it cannot: a derived name colliding with the
# <team>-admin / <team>-view shorthand, a networkPolicy.custom entry reusing a
# baseline policy's name, or either chart colliding with the other.
# ---------------------------------------------------------------------------
identities() {
  awk '
    function flush() {
      if (kind != "" && name != "") print kind "/" (ns == "" ? "<cluster>" : ns) "/" name
      kind = ""; name = ""; ns = ""; inmeta = 0
    }
    /^---[ \t]*$/            { flush(); next }
    /^kind:/                 { kind = $2; next }
    /^metadata:[ \t]*$/      { inmeta = 1; next }
    /^[^ \t#]/               { inmeta = 0 }
    inmeta && /^  name:/     { name = $2 }
    inmeta && /^  namespace:/ { ns = $2 }
    END { flush() }
  ' "$1" | sort | uniq -d
}
collisions=0
for f in "$renders"/*.yaml; do
  [ -e "$f" ] || continue
  dup=$(identities "$f")
  if [ -n "$dup" ]; then
    pair=$(basename "$f" .yaml)
    bad "${pair/__/ / } renders more than one object with the same identity:"
    printf '  %s\n' $dup
    collisions=$((collisions + 1))
  fi
done
[ $collisions -eq 0 ] && ok "every rendered object has a unique kind/namespace/name within its tenancy"

# ---------------------------------------------------------------------------
# 7. The cleanup Job's requests must clear every tier's Container minimum.
#
# The Job runs inside a tenant namespace, under the LimitRange this same chart
# puts there, so its requests are constrained from BELOW as well as above. It
# shipped requesting cpu: 10m against tiers whose min was 50m at the time,
# which meant the hook could not run in any namespace that had a LimitRange --
# on any cluster. Both ends have moved since (Job 50m, every tier's min 10m),
# so this check passes with slack; it is here for the next override that does
# not, since a cluster-level namespace-sizes.yaml can raise a tier's min.
#
# Nothing already in this file could have caught that. The render is valid, the
# objects are schema-correct, and `oc apply --dry-run=server` passes because
# the LimitRange does not exist yet in a namespace being created. It only
# appears on a live first sync, and then only as events: admission rejects the
# POD, which the Job controller creates, not the Job, which ArgoCD creates. So
# the Application reports Synced and Healthy with the hook silently dead.
# ---------------------------------------------------------------------------
cpu_m()  { awk -v v="${1//\"/}" 'BEGIN{ if (v ~ /m$/) { sub(/m$/,"",v); print v+0 } else print v*1000 }'; }
mem_b()  { awk -v v="${1//\"/}" 'BEGIN{
             mult=1
             if (v ~ /Ki$/) mult=1024;            else if (v ~ /Mi$/) mult=1024^2
             else if (v ~ /Gi$/) mult=1024^3;     else if (v ~ /Ti$/) mult=1024^4
             else if (v ~ /K$/)  mult=1000;       else if (v ~ /M$/)  mult=1000^2
             else if (v ~ /G$/)  mult=1000^3;     else if (v ~ /T$/)  mult=1000^4
             gsub(/[A-Za-z]+$/,"",v); printf "%d", v*mult }'; }

extract() {
  awk '
    function flush_item() {
      if (itype == "Container" && (mincpu != "" || minmem != ""))
        print "LRMIN", ns, (mincpu == "" ? "-" : mincpu), (minmem == "" ? "-" : minmem)
      itype = ""; mincpu = ""; minmem = ""; inmin = 0
    }
    /^---[ \t]*$/ { if (kind == "LimitRange") flush_item(); kind=""; ns=""; inmeta=0; inreq=0; next }
    /^kind:/                  { kind = $2; next }
    /^metadata:[ \t]*$/       { inmeta = 1; next }
    /^[^ \t#]/                { inmeta = 0 }
    inmeta && /^  namespace:/ { ns = $2 }

    kind == "LimitRange" && /^    - /            { flush_item() }
    kind == "LimitRange" && /^      min:[ \t]*$/ { inmin = 1; next }
    kind == "LimitRange" && /^      [a-zA-Z]/    { inmin = 0 }
    kind == "LimitRange" && /^      type:/       { itype = $2 }
    kind == "LimitRange" && inmin && /^        cpu:/    { mincpu = $2 }
    kind == "LimitRange" && inmin && /^        memory:/ { minmem = $2 }

    kind == "Job" && /^            requests:[ \t]*$/ { inreq = 1; next }
    kind == "Job" && /^            [a-zA-Z]/         { inreq = 0 }
    kind == "Job" && inreq && /^              cpu:/    { jc = $2 }
    kind == "Job" && inreq && /^              memory:/ { jm = $2 }
    END { if (kind == "LimitRange") flush_item(); if (jc != "") print "JOBREQ", jc, jm }
  ' "$1"
}

floor_fail=0
for f in "$renders"/*.yaml; do
  [ -e "$f" ] || continue
  pair=$(basename "$f" .yaml); pair=${pair/__/ / }
  data=$(extract "$f")
  jreq=$(printf '%s\n' "$data" | awk '$1 == "JOBREQ" { print $2, $3; exit }')
  [ -n "$jreq" ] || continue            # cleanup.include false, nothing to check
  jc=${jreq% *}; jm=${jreq#* }
  while read -r _ ns mincpu minmem; do
    [ -n "$ns" ] || continue
    if [ "$mincpu" != "-" ] && [ "$(cpu_m "$jc")" -lt "$(cpu_m "$mincpu")" ]; then
      bad "$pair: cleanup Job requests cpu $jc in $ns, below that tier's Container min $mincpu -- admission will reject the Job's POD while the Application still reports Synced; raise cleanup.resources.requests.cpu"
      floor_fail=1
    fi
    if [ "$minmem" != "-" ] && [ "$(mem_b "$jm")" -lt "$(mem_b "$minmem")" ]; then
      bad "$pair: cleanup Job requests memory $jm in $ns, below that tier's Container min $minmem -- admission will reject the Job's POD while the Application still reports Synced; raise cleanup.resources.requests.memory"
      floor_fail=1
    fi
  done < <(printf '%s\n' "$data" | grep '^LRMIN ')
done
[ $floor_fail -eq 0 ] && ok "cleanup Job requests clear every tier's Container minimum"

note ""
if [ $fail -ne 0 ]; then
  note "onboarding charts are not valid"
  exit 1
fi
note "onboarding charts OK"
