#!/usr/bin/env bash
#
# Scaffold a PolicyGenerator directory holding an OperatorPolicy.
#
# This is generate-policy.sh --operator under another name, because "generate an
# operator policy" is the thing people go looking for. The logic lives in one
# place on purpose: two near-identical scaffolders drift, and the drift shows up
# as policies whose shape depends on which script happened to create them.
#
#   scripts/generate-operator-policy.sh compliance-operator \
#     --namespace openshift-compliance --channel stable
#
set -euo pipefail

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/generate-policy.sh" --operator "$@"
