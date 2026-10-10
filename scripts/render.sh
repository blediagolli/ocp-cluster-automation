#!/usr/bin/env bash
#
# Render one chart for one cluster exactly the way ArgoCD renders it.
#
# Every chart in this repo is deployed by an ApplicationSet that feeds it a
# chain of values files -- env-level first, cluster-level last, later files
# winning. When a rendered value is wrong, the question is always "which file
# in the chain set it?", and that is hard to answer by reading, because the
# chain lives in the ApplicationSet rather than next to the chart.
#
# This reproduces the chain locally. The file lists below are copied from
# clusters/mgt/acm-hub/applicationsets/*.yaml -- if you change a valueFiles
# block there, change the matching one here.
#
# ArgoCD sets ignoreMissingValueFiles: true, so a file that does not exist is
# skipped rather than failing. This does the same, and --files shows you which
# ones were found.
#
#   scripts/render.sh dev/example-cluster keycloak            # the manifests
#   scripts/render.sh dev/example-cluster keycloak --files    # the chain, nothing else
#   scripts/render.sh dev/example-cluster keycloak --values   # the merged values
#
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

usage() {
  cat <<'EOF'
Usage: scripts/render.sh <cluster> <chart> [options]

  <cluster>  dev/example-cluster, or just example-cluster if the name is unambiguous
  <chart>    keycloak, tls-certificates, openshift-provisioning, ...

Options:
  --files        list the values chain and whether each file exists, then stop
  --values       print the merged values instead of the manifests
  --team <name>  required for the onboarding charts
  --help         this

Examples:
  scripts/render.sh dev/example-cluster keycloak
  scripts/render.sh dev/example-cluster keycloak --values | grep -A5 postgres
  scripts/render.sh mgt/acm-hub quay | oc apply --dry-run=client -f -
  scripts/render.sh dev/example-cluster namespace-config --team team-alpha
EOF
}

mode=manifests
team=""
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)  mode=files;  shift ;;
    --values) mode=values; shift ;;
    --team)   team="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done

if [[ ${#positional[@]} -ne 2 ]]; then
  usage >&2
  exit 2
fi

cluster_arg="${positional[0]}"
chart="${positional[1]}"

# --- Resolve the cluster to clusters/<env>/<name> -----------------------------
# Accepts the full env/name or just the name, so you do not have to remember
# which environment a cluster lives in.
if [[ "$cluster_arg" == */* ]]; then
  cluster_path="clusters/$cluster_arg"
else
  matches=(clusters/*/"$cluster_arg")
  if [[ ${#matches[@]} -ne 1 || ! -d "${matches[0]}" ]]; then
    echo "no single cluster named '$cluster_arg'. Candidates:" >&2
    find clusters -mindepth 2 -maxdepth 2 -type d | sed 's|^clusters/|  |' >&2
    exit 1
  fi
  cluster_path="${matches[0]}"
fi

if [[ ! -d "$cluster_path" ]]; then
  echo "no such cluster: $cluster_path" >&2
  find clusters -mindepth 2 -maxdepth 2 -type d | sed 's|^clusters/|  |' >&2
  exit 1
fi

env_name=$(basename "$(dirname "$cluster_path")")

# --- Find the chart and pick its values chain ---------------------------------
# Which chain applies is decided by where the chart lives, because that is what
# decides which ApplicationSet deploys it.
cluster_name=$(basename "$cluster_path")

if [[ -d "charts/operators/$chart" ]]; then
  chart_path="charts/operators/$chart"
  # cluster-operators.yaml
  release="$chart"
  chain=(
    "env/$env_name/conf.yaml"
    "env/$env_name/operators.yaml"
    "env/$env_name/operators/$chart.yaml"
    "$cluster_path/conf.yaml"
    "$cluster_path/operators.yaml"
    "$cluster_path/operators/$chart.yaml"
  )
elif [[ -d "charts/platform-config/$chart" ]]; then
  chart_path="charts/platform-config/$chart"
  # cluster-platform-config.yaml, and cluster-import.yaml for
  # acm-managed-cluster -- the two use the same four files, and both pin the
  # release name to the chart.
  release="$chart"
  chain=(
    "env/$env_name/conf.yaml"
    "env/$env_name/platform-config.yaml"
    "$cluster_path/conf.yaml"
    "$cluster_path/platform-config.yaml"
  )
elif [[ -d "charts/cluster-provisioning/$chart" ]]; then
  chart_path="charts/cluster-provisioning/$chart"
  # cluster-provisioning.yaml. Note there is no conf.yaml in this chain.
  release="$chart"
  chain=(
    "env/$env_name/provision.yaml"
    "$cluster_path/provision.yaml"
  )
elif [[ -d "charts/onboarding/$chart" ]]; then
  chart_path="charts/onboarding/$chart"
  if [[ -z "$team" ]]; then
    echo "the onboarding charts render per team -- pass --team <name>" >&2
    echo "teams defined:" >&2
    find teams -name '*.yaml' | sed 's|^teams/|  |;s|\.yaml$||' >&2
    exit 2
  fi
  if [[ "$chart" == "namespace-config" ]]; then
    # cluster-onboarding-namespaces.yaml
    release="$chart-$team"
    chain=(
      "teams/$team.yaml"
      "env/$env_name/conf.yaml"
      "env/$env_name/namespace-sizes.yaml"
      "env/$env_name/teams/$team.yaml"
      "$cluster_path/conf.yaml"
      "$cluster_path/namespace-sizes.yaml"
      "$cluster_path/teams/$team.yaml"
    )
  else
    # cluster-onboarding-gitops.yaml
    release="$chart-$team"
    chain=(
      "teams/$team.yaml"
      "env/$env_name/conf.yaml"
      "env/$env_name/teams/$team.yaml"
      "$cluster_path/conf.yaml"
      "$cluster_path/teams/$team.yaml"
    )
  fi
else
  echo "no chart named '$chart' under charts/" >&2
  echo "available:" >&2
  find charts -mindepth 3 -maxdepth 3 -name Chart.yaml \
    | sed 's|/Chart.yaml$||;s|^charts/|  |' | sort >&2
  exit 1
fi

# The release names above are the releaseName: each ApplicationSet pins, not
# the Application name -- see the comment on any of those blocks for why the
# two are kept apart. Helm's cap is 53 characters; chart and team names leave
# plenty of room, so this only fires if a new one is unreasonably long, and it
# would fail the same way in ArgoCD.
if [[ ${#release} -gt 53 ]]; then
  echo "release name '$release' is ${#release} characters; Helm allows 53" >&2
  exit 1
fi

# --- Build the -f list, skipping what is not there ----------------------------
args=()
for f in "${chain[@]}"; do
  [[ -f "$f" ]] && args+=(-f "$f")
done

if [[ "$mode" == "files" ]]; then
  echo "chart:   $chart_path"
  echo "release: $release"
  echo "cluster: $cluster_path  (environment: $env_name)"
  echo
  echo "values chain, in order -- later files win:"
  echo "  [chart]  $chart_path/values.yaml"
  for f in "${chain[@]}"; do
    if [[ -f "$f" ]]; then
      printf '  [ok]     %s\n' "$f"
    else
      printf '  [absent] %s\n' "$f"
    fi
  done
  exit 0
fi

if [[ "$mode" == "values" ]]; then
  # Helm 4 dropped the COMPUTED VALUES section from --debug, so to see the
  # merged result we render a stub chart that prints nothing but .Values,
  # carrying the real chart's defaults so the merge is the same one the real
  # render does.
  stub=$(mktemp -d)
  [[ -n "$stub" && -d "$stub" ]] || { echo "could not create a temp dir" >&2; exit 1; }
  trap 'test -n "${stub:-}" && test -d "${stub:-}" && rm -rf -- "${stub:?}"' EXIT
  mkdir -p "$stub/templates"
  printf 'apiVersion: v2\nname: values\nversion: 0.0.0\n' > "$stub/Chart.yaml"
  cp "$chart_path/values.yaml" "$stub/values.yaml"
  printf '{{ toYaml .Values }}\n' > "$stub/templates/values.yaml"
  helm template "$release" "$stub" "${args[@]}" | sed '1,2d'
  exit 0
fi

exec helm template "$release" "$chart_path" "${args[@]}"
