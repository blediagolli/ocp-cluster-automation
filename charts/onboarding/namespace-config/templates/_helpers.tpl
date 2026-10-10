{{- /*
Shared by both charts under charts/onboarding/. The two copies are
byte-identical -- `make validate-onboarding` fails if they drift. Nothing here
reads a chart-specific values key; everything comes through .Values.team and
.Values.cluster, which both charts have. Do not edit one copy.
*/ -}}

{{- /*
"true" when this team is quiesced, "" otherwise.

Quiesce is the ONLY lifecycle flag. It means "stop deploying, withdraw access,
keep everything else": the team's ArgoCD instance, its AppProject and every
RoleBinding go, while the namespaces and all the data in them stay. It is
fully reversible -- removing the flag brings the team back in one sync.

                       namespace-config renders      application-gitops renders
  ""                   everything                    everything
  quiesce              namespaces, quota, limits,    <team>-gitops, and nothing
                       NetworkPolicies -- no         in it
                       RoleBindings, no managed-by

Set it in teams/<team>.yaml to apply everywhere, or in
clusters/<env>/<cluster>/teams/<team>.yaml to apply on one cluster only.

BOTH CHARTS KEEP RENDERING THEIR NAMESPACES, SO NEITHER EVER RENDERS EMPTY.
That is load-bearing, and it is the reason there is no second flag:

  - An empty render is now always a bug -- a deleted or truncated values file.
    onboarding.validate can therefore fail on it unconditionally, because
    there is no legitimate empty state left to tell it apart from.
  - ArgoCD refuses to auto-sync an Application whose every remaining resource
    needs pruning (`auto-sync will wipe out all resources`) unless
    allowEmpty: true. Never rendering empty means never meeting that guard, so
    the ApplicationSets do not have to switch it off.
  - A Namespace that stops rendering is re-resolved under OpenShift's
    project.openshift.io/v1 Project GVK, loses its tracking-id, and is then
    silently never pruned. Keeping it rendered keeps it tracked.

All three were found the hard way on acm-hub; see HANDOFF.md.

DELETING a team is deliberately not a chart feature. Quiesce it, confirm, drop
its entry from the cluster's conf.yaml, then delete the namespaces by hand --
the procedure is in HANDOFF.md. These charts refuse to render nothing, which
means they can never be the thing that deletes a tenancy.

What quiesce does NOT do is stop pods that are already running. It removes the
ability to deploy, not the workloads already deployed. Scale those down first
if that matters; this chart does not own them and cannot see them.

team.name is required alongside the flag so quiescing always reads as a
sentence that names its subject: `team: {name: team-alpha, quiesce: true}`.
*/ -}}
{{- define "onboarding.quiescing" -}}
{{- $team := .Values.team | default dict -}}
{{- $v := $team.quiesce -}}
{{- /* A quoted "false" is truthy in a Go template, so it would quiesce the
       team rather than leave it alone. Reject anything that is not a bool. */ -}}
{{- if and (not (kindIs "invalid" $v)) (not (kindIs "bool" $v)) -}}
{{- fail (printf "team.quiesce is %q, which is not a boolean — write true or false unquoted. A quoted \"false\" is truthy in a Go template, so this would quiesce the team rather than leave it alone" (toString $v)) -}}
{{- end -}}
{{- if $v -}}
{{- if not $team.name -}}
{{- fail "team.quiesce is true but team.name is not set — quiescing withdraws every RoleBinding and deletes the team's ArgoCD instance, so the values file has to name the team it is doing that to" -}}
{{- end -}}
true
{{- end -}}
{{- end -}}

{{- /*
Fails the render if anything the templates consume is missing. Emits nothing.
Called at the top of every template in both charts.

Every check is unconditional. Neither chart has a legitimate empty render, so
there is no retirement branch to exempt -- which is the simplification the
single-flag design buys.

team.readers is deliberately absent: a team with no read-only group is
legitimate, and the RoleBinding for it renders under `with`.
*/ -}}
{{- define "onboarding.validate" -}}
{{- $team := .Values.team | default dict -}}
{{- $cluster := .Values.cluster | default dict -}}
{{- $_ := required "team.name is required — it names or namespaces every object both onboarding charts create, and an empty value renders zero resources, which ArgoCD's prune: true reads as \"delete everything this team owns\"" $team.name -}}
{{- $_ = required (printf "team.admins is required — it is the group bound to ClusterRole/admin on %s's namespaces and to role:admin in its ArgoCD, so an empty value renders a RoleBinding with no subject and nobody on the team can reach anything the chart just created" $team.name) $team.admins -}}
{{- $_ = required (printf "cluster.environment is required — %s's namespaces are selected with team.namespaces.<environment>, so an empty environment selects none, renders nothing, and lets prune: true delete the live ones; it comes from clusters/<env>/<cluster>/conf.yaml" $team.name) $cluster.environment -}}
{{- /* `required` only catches nil and "" -- an empty map passes it, which is
       exactly the shape a half-deleted values file leaves behind. */ -}}
{{- if not $team.namespaces -}}
{{- fail (printf "team.namespaces is required — %s has no namespaces in any environment, which is either a deleted teams/%s.yaml or a typo one level up; both render nothing and let prune: true remove the team's live namespaces" $team.name $team.name) -}}
{{- end -}}
{{- end -}}

{{- /*
The namespaces this team owns on this cluster, as a list.

The expression was copy-pasted verbatim into four templates before this helper
existed and would have been in six after the NetworkPolicy and RoleBinding
templates landed. `default list` is what makes a team legitimately absent from
an environment render nothing rather than fail -- the guard that a team has
namespaces in SOME environment is in onboarding.validate.
*/ -}}
{{- define "onboarding.namespaces" -}}
{{- index .Values.team.namespaces .Values.cluster.environment | default list | toYaml -}}
{{- end -}}

{{- /*
The namespace holding the team's own ArgoCD instance. Ten hardcoded copies of
`{{ .Values.team.name }}-gitops` before this existed.
*/ -}}
{{- define "onboarding.teamGitops" -}}
{{- printf "%s-gitops" .Values.team.name -}}
{{- end -}}

{{- /*
The team's allowed source repos, as a YAML list, for the AppProject.

team.repo was a single string and the existing teams/*.yaml still set it that
way, so both spellings are honoured and a file that sets both gets the union --
an env- or cluster-level override adding a repo should add it, not replace the
central one. Guarded with `fail` rather than `required` because `required`
passes an empty list.
*/ -}}
{{- define "onboarding.repos" -}}
{{- $team := .Values.team | default dict -}}
{{- $repos := list -}}
{{- with $team.repos -}}
{{- if kindIs "slice" . -}}
{{- $repos = . -}}
{{- else -}}
{{- $repos = list . -}}
{{- end -}}
{{- end -}}
{{- if and $team.repo (not (has $team.repo $repos)) -}}
{{- $repos = append $repos $team.repo -}}
{{- end -}}
{{- if not $repos -}}
{{- fail (printf "team.repos is required — it becomes the AppProject's sourceRepos, and an AppProject with an empty sourceRepos refuses every Application %s creates with \"application repo is not permitted\"; the older scalar team.repo is still honoured" ($team.name | default "this team")) -}}
{{- end -}}
{{- toYaml $repos -}}
{{- end -}}

{{- /*
Fails on a namespace whose size is not a key in namespaceSizes. Emits nothing.
Called as: include "onboarding.requireSize" (list $ .name .size)

Without it `index` yields nil and the typo surfaces twenty lines later as
"nil pointer evaluating interface {}.resourceQuota", which names neither the
namespace nor the size.
*/ -}}
{{- define "onboarding.requireSize" -}}
{{- $root := index . 0 -}}
{{- $ns := index . 1 -}}
{{- $size := index . 2 -}}
{{- if not (index $root.Values.namespaceSizes ($size | default "")) -}}
{{- fail (printf "team.namespaces.%s[].size is %q for namespace %s, which is not a key in namespaceSizes (have: %s) — a namespace with an unknown tier gets no ResourceQuota and no LimitRange at all" $root.Values.cluster.environment ($size | default "") $ns (keys $root.Values.namespaceSizes | sortAlpha | join ", ")) -}}
{{- end -}}
{{- end -}}

{{- /*
"true" when this namespace should get the named object, "" when it should not.
Called as: include "onboarding.manages" (list $ $nsEntry "resourceQuota")

Two levels, and the narrower one wins:

  namespaceSizes.<tier>.<which>.include   the tier's default, true if absent
  team.namespaces.<env>[].<which>         this one namespace, a bare boolean

Both directions are useful, and the second is the one migration needs. Turning
a tier off and opting namespaces back in one at a time is how an existing
estate comes under this chart without a flag day: the namespaces arrive under
GitOps first, and enforcement follows per namespace, at whatever pace the teams
can absorb.

Beware what turning one OFF means for a namespace that already has the object:
sync policy is prune: true, so the live ResourceQuota or LimitRange is DELETED,
not left alone. The namespace becomes unbounded the moment it syncs. That is
the right behaviour -- this chart owns the object or it does not, and a
half-owned object is the thing GitOps exists to prevent -- but it is not what
"turn it off" sounds like.

A string "false" is rejected rather than quietly accepted: it is truthy in Go
templates, so `resourceQuota: "false"` would turn the object ON.
*/ -}}
{{- define "onboarding.manages" -}}
{{- $root := index . 0 -}}
{{- $ns := index . 1 -}}
{{- $which := index . 2 -}}
{{- $tier := index $root.Values.namespaceSizes $ns.size | default dict -}}
{{- $on := dig "include" true (index $tier $which | default dict) -}}
{{- if hasKey $ns $which -}}
{{- $on = index $ns $which -}}
{{- end -}}
{{- if not (kindIs "bool" $on) -}}
{{- fail (printf "%s for namespace %s is %q, which is not a boolean — write true or false unquoted; a quoted \"false\" is truthy in a template and would switch the object ON" $which $ns.name (toString $on)) -}}
{{- end -}}
{{- if $on -}}true{{- end -}}
{{- end -}}

{{- /*
The tier's ResourceQuota limits, as a YAML map, with every null-valued key
dropped. Called as: include "onboarding.quotaHard" (list $ $nsEntry)

Dropping nulls here rather than leaving it to Helm is not belt-and-braces --
Helm's own handling is inconsistent and cannot be relied on. A key set to null
in a values file is DELETED if this chart's values.yaml also declares it, but
SURVIVES AS A LITERAL null if it was introduced further down the chain. So
nulling requests.cpu (declared here) removes it, while nulling configmaps
(introduced in env/<env>/namespace-sizes.yaml) renders `configmaps: null` into
the ResourceQuota and the API rejects the apply. Filtering in the template
makes null mean the same thing everywhere it is written.

That is what makes a tier override subtractive as well as additive, which it
otherwise is not: maps deep-merge, so without this there is no way to take a
limit off a tier for one cluster short of restating the tier.
*/ -}}
{{- define "onboarding.quotaHard" -}}
{{- $root := index . 0 -}}
{{- $ns := index . 1 -}}
{{- $tier := index $root.Values.namespaceSizes $ns.size | default dict -}}
{{- $hard := dict -}}
{{- range $k, $v := ((($tier.resourceQuota) | default dict).hard | default dict) -}}
{{- if not (kindIs "invalid" $v) -}}
{{- $hard = set $hard $k $v -}}
{{- end -}}
{{- end -}}
{{- if not $hard -}}
{{- fail (printf "size %q leaves namespace %s with no ResourceQuota limits at all — every key under namespaceSizes.%s.resourceQuota.hard is absent or null. A ResourceQuota with an empty `hard` enforces nothing while looking managed, so say it out loud instead: `resourceQuota: {include: false}` on the tier, or `resourceQuota: false` on the namespace entry" $ns.size $ns.name $ns.size) -}}
{{- end -}}
{{- toYaml $hard -}}
{{- end -}}

{{- /*
The tier's LimitRange items, as a YAML list, with every null-valued field
dropped and any item left empty removed.
Called as: include "onboarding.limitRangeItems" (list $ $nsEntry)

namespaceSizes.<tier>.limitRange.types is a MAP keyed by LimitRange type
(Container, Pod, PersistentVolumeClaim), not the list the API wants. It was a
list and is deliberately no longer one: Helm replaces a list wholesale rather
than merging it, so overriding a single `max` for one cluster meant restating
every field of every item -- and a restatement silently goes stale the day the
environment tier changes. Keyed by type it deep-merges, so `max: null` in a
cluster file is one line and means one thing. The list is rebuilt here, sorted
by type so the render is stable.
*/ -}}
{{- define "onboarding.limitRangeItems" -}}
{{- $root := index . 0 -}}
{{- $ns := index . 1 -}}
{{- $tier := index $root.Values.namespaceSizes $ns.size | default dict -}}
{{- $lr := $tier.limitRange | default dict -}}
{{- if hasKey $lr "limits" -}}
{{- fail (printf "namespaceSizes.%s.limitRange.limits is no longer read — it is now `types`, a map keyed by Container/Pod/PersistentVolumeClaim instead of a list, so that a cluster can override one field rather than restating every item. Leaving the old key in place would render a LimitRange missing every limit it names" $ns.size) -}}
{{- end -}}
{{- $items := list -}}
{{- range $type := (keys ($lr.types | default dict) | sortAlpha) -}}
{{- $spec := index $lr.types $type -}}
{{- if not (kindIs "invalid" $spec) -}}
{{- $item := dict "type" $type -}}
{{- range $field := (list "default" "defaultRequest" "max" "min" "maxLimitRequestRatio") -}}
{{- $raw := index $spec $field -}}
{{- if not (kindIs "invalid" $raw) -}}
{{- if not (kindIs "map" $raw) -}}
{{- fail (printf "namespaceSizes.%s.limitRange.types.%s.%s is %q — it has to be a map of resource name to quantity, such as {cpu: 500m, memory: 512Mi}" $ns.size $type $field (toString $raw)) -}}
{{- end -}}
{{- $m := dict -}}
{{- range $k, $v := $raw -}}
{{- if not (kindIs "invalid" $v) -}}
{{- $m = set $m $k $v -}}
{{- end -}}
{{- end -}}
{{- if $m -}}
{{- $item = set $item $field $m -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- /* Only `type` left means every field under it was nulled out, which is an
       item the API accepts and that constrains nothing. */ -}}
{{- if gt (len (keys $item)) 1 -}}
{{- $items = append $items $item -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if not $items -}}
{{- fail (printf "size %q leaves namespace %s with no LimitRange items at all — every type under namespaceSizes.%s.limitRange.types is absent or fully nulled. Say it out loud instead: `limitRange: {include: false}` on the tier, or `limitRange: false` on the namespace entry" $ns.size $ns.name $ns.size) -}}
{{- end -}}
{{- toYaml $items -}}
{{- end -}}

{{- /*
Labels every resource in both charts carries. `component` is added per call
site, not here.

Three conventional labels are deliberately absent:

  helm.sh/chart              encodes the chart version, so under this repo's
                             bump-on-every-change rule its only behaviour is to
                             rewrite one label on every object in every tenant
                             namespace on every commit -- which selfHeal then
                             re-applies. A no-op version bump would show as
                             simultaneous OutOfSync across all tenants and bury
                             real drift. The provenance is already in git.
  app.kubernetes.io/version  same churn, and neither chart has an appVersion.
  app.kubernetes.io/instance this is ArgoCD's own tracking label when
                             resourceTrackingMethod is `label`, which the root
                             HANDOFF.md flags as hazardous. Setting it here
                             means fighting the controller the day anyone
                             flips tracking. part-of gives the per-team
                             selector that was actually wanted.

part-of is also what the manual delete at the end of a retirement selects on
(`oc delete ns -l app.kubernetes.io/part-of=<team>`), so it is load-bearing
rather than decorative.

managed-by is multi-cluster-config rather than Helm's conventional
.Release.Service because Helm never runs against these clusters, ArgoCD does
-- matching the namespaces each chart under charts/operators creates.

team.metadata is rendered here rather than on the Namespace alone so that
Gatekeeper constraints, Kyverno policies and ACM policies can select a team's
objects by org/division/app wherever they live, not just its namespaces. It is
a free-form map: a new column in the tracker becomes a new label with no chart
change. Kubernetes rejects an invalid key or a value over 63 characters at
apply time, naming the offending label.
*/ -}}
{{- define "onboarding.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/managed-by: multi-cluster-config
app.kubernetes.io/part-of: {{ .Values.team.name }}
{{- range $key, $value := (.Values.team.metadata | default dict) }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- /*
Every RoleBinding the team gets in each of its namespaces, as a YAML list of
{name, kind, subject, role}. Emitted by rolebindings.yaml, once per namespace.

team.admins and team.readers stay as shorthand for the two bindings every team
has, and keep their original <team>-admin / <team>-view names so adopting this
list renames nothing. Everything else goes in team.roleBindings, which is an
unbounded list -- an app can carry an AD admin group, an AD user group, a CI/CD
group, an APM group and a migration group, and the same group can appear twice
against different roles.

Names are derived from the group and the role rather than the list position,
because a position-derived name would rename every binding below an insertion
-- and a renamed RoleBinding is a delete plus a create, which briefly removes
a team's access to its own namespace mid-sync.
*/ -}}
{{- define "onboarding.roleBindings" -}}
{{- $team := .Values.team | default dict -}}
{{- $out := list -}}
{{- with $team.admins -}}
{{- $out = append $out (dict "name" (printf "%s-admin" $team.name) "kind" "Group" "subject" . "role" "admin") -}}
{{- end -}}
{{- with $team.readers -}}
{{- $out = append $out (dict "name" (printf "%s-view" $team.name) "kind" "Group" "subject" . "role" "view") -}}
{{- end -}}
{{- range $i, $rb := ($team.roleBindings | default list) -}}
{{- if not $rb.group -}}
{{- fail (printf "team.roleBindings[%d] has no group — every entry binds one subject to one role, and an entry with no group renders a RoleBinding with an empty subject, which grants nothing and reports no error" $i) -}}
{{- end -}}
{{- if not $rb.role -}}
{{- fail (printf "team.roleBindings[%d] (group %s) has no role — it is the ClusterRole name to bind, such as admin, edit or view" $i $rb.group) -}}
{{- end -}}
{{- /* regexReplaceAll takes the subject as its SECOND argument, so it cannot be
       piped into -- a pipeline passes the string as the replacement instead and
       yields the pattern's leftovers, which here was the empty string for every
       entry. Caught only by the duplicate check below. */ -}}
{{- $derived := printf "%s-%s" $rb.group $rb.role | lower -}}
{{- $derived = regexReplaceAll "[^a-z0-9.-]+" $derived "-" | trunc 63 | trimAll "-." -}}
{{- if not $derived -}}
{{- fail (printf "team.roleBindings[%d] (group %q, role %q) has no character a RoleBinding name may contain — names are lowercase alphanumerics, '-' and '.'; set an explicit `name:` on the entry" $i $rb.group $rb.role) -}}
{{- end -}}
{{- $name := $rb.name | default $derived -}}
{{- $out = append $out (dict "name" $name "kind" ($rb.kind | default "Group") "subject" $rb.group "role" $rb.role) -}}
{{- end -}}
{{- /* Two bindings with one name in one namespace is not an error to Kubernetes
       -- the second simply replaces the first, and roleRef is immutable, so
       the sync then fails on every subsequent run with a message about the
       roleRef field rather than about the duplicate. Catch it here instead. */ -}}
{{- $seen := dict -}}
{{- range $rb := $out -}}
{{- if hasKey $seen $rb.name -}}
{{- fail (printf "two of %s's RoleBindings are both named %q (groups %s and %s) — they would overwrite each other in every namespace, and because roleRef is immutable the sync would fail from then on; give one of them an explicit `name:`" $team.name $rb.name (index $seen $rb.name) $rb.subject) -}}
{{- end -}}
{{- $seen = set $seen $rb.name $rb.subject -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}
