# Troubleshooting

## Render a chart the way ArgoCD renders it

Charts in this repo are never rendered with their defaults alone. An
ApplicationSet feeds each one a chain of values files, env-level first and
cluster-level last, and the chain lives in the ApplicationSet rather than next
to the chart. So when a rendered value is wrong, the question is almost always
*which file in the chain set it* — and reading the chart will not tell you.

`make render` reproduces the chain locally:

```sh
make render CLUSTER=mgt/acm-hub CHART=keycloak
```

The cluster can be given as `<env>/<name>` or just `<name>` if that is
unambiguous. Anything under `charts/` works as the chart — the script picks the
right chain from where the chart lives.

### Which files are in play

```sh
make render CLUSTER=mgt/acm-hub CHART=keycloak FILES=1
```

```
chart:   charts/operators/keycloak
release: keycloak
cluster: clusters/mgt/acm-hub  (environment: mgt)

values chain, in order -- later files win:
  [chart]  charts/operators/keycloak/values.yaml
  [ok]     env/mgt/conf.yaml
  [ok]     env/mgt/operators.yaml
  [absent] env/mgt/operators/keycloak.yaml
  [ok]     clusters/mgt/acm-hub/conf.yaml
  [ok]     clusters/mgt/acm-hub/operators.yaml
  [ok]     clusters/mgt/acm-hub/operators/keycloak.yaml
```

`[absent]` is not an error. ArgoCD sets `ignoreMissingValueFiles: true`, so a
file that does not exist is skipped — which is also the most common reason a
value you set did not take effect: it went in a file later in the chain than
you thought, or in one nothing reads.

### What the values merged to

```sh
make render CLUSTER=mgt/acm-hub CHART=keycloak VALUES=1
```

Prints the merged values — chart defaults plus every file in the chain — rather
than the manifests. This is the fastest way to answer "is the chart even seeing
the value I set?", which is a different question from "is the template using it
correctly".

### Useful combinations

```sh
# does it still parse as Kubernetes objects?
make render CLUSTER=mgt/acm-hub CHART=quay | oc apply --dry-run=client -f -

# what changed between two clusters?
diff <(make render CLUSTER=dev/example-cluster CHART=cert-manager) \
     <(make render CLUSTER=mgt/acm-hub CHART=cert-manager)

# the onboarding charts render per team
make render CLUSTER=dev/example-cluster CHART=namespace-config TEAM=team-alpha
```

`scripts/render.sh` takes the same arguments as flags if you prefer
(`scripts/render.sh mgt/acm-hub keycloak --files`).

### A caveat worth knowing

The value-file chains in `scripts/render.sh` are copied from the `valueFiles:`
blocks in `clusters/mgt/acm-hub/applicationsets/*.yaml`. They are not read from
those files at runtime, so **if you change a `valueFiles:` block, change the
matching chain in the script.** There are five: operators, platform-config,
provisioning, and the two onboarding charts.

The same goes for `release:` in the output above. Each ApplicationSet pins
`helm.releaseName` rather than letting it default to the Application name,
because the Application name embeds the cluster name and Helm caps a release
name at 53 characters — a cluster named after its full DNS name would blow past
that and fail the render. The script repeats those pinned names so what it
prints matches what the cluster sees.

## A sync failed — read the revision, not just the error

ArgoCD keeps serving the last successfully rendered revision when a sync fails,
so the error you are looking at may describe a commit that is no longer HEAD.
Check `Revision` on the Application before debugging the message; a failed sync
can pin an old SHA for roughly 25 minutes.

## A value is correct in git but not on the cluster

In order of how often it is the answer:

1. **The file is not in the chain.** Run with `FILES=1` and look for it.
2. **A later file overrides it.** Run with `VALUES=1` and check the merged
   result rather than the file you edited.
3. **The feature is off.** Chart features default to `include: false`
   throughout this repo. A values block for a disabled feature renders nothing
   and reports nothing.
4. **ArgoCD has not synced.** See above.

## A Secret is missing

Every chart that needs a credential takes a `source` of `existing`,
`externalSecret` or `inline`, defaulting to `existing` — which renders nothing,
because the Secret is expected to be there already. A missing Secret usually
means the source was never changed from the default. See
[cluster-configuration/secrets.md](cluster-configuration/secrets.md).
