# Policy values

Per-cluster and fleet-wide values for the policies in [`policies/`](../policies).

```
policy-values/
  global.env                 fleet defaults
  clusters/<cluster>.env     per-cluster overrides
```

`policies/stable/cluster-config-maps` turns these into ConfigMaps in
`open-cluster-management-policies`:

| File | ConfigMap |
|---|---|
| `global.env` | `policy-config` |
| `clusters/local-cluster.env` | `policy-config-local-cluster` |

Policies read them with a two-tier hub template — the cluster's own ConfigMap
wins, the fleet default fills in:

```yaml
'{{hub dig "data" "etcdEncryptionType" ""
  (lookup "v1" "ConfigMap" "open-cluster-management-policies"
    (printf "policy-config-%s" .ManagedClusterName))
  | default (fromConfigMap "open-cluster-management-policies" "policy-config" "etcdEncryptionType") hub}}'
```

`lookup` for the per-cluster half because it returns an empty result for a
cluster with no ConfigMap; `fromConfigMap` for the fleet default because that
one is always present, so an error there is a real error rather than a missing
override.

## Adding a cluster

Create `clusters/<name>.env`, then add a `configMapGenerator` entry for it in
`policies/stable/cluster-config-maps/kustomization.yaml`. Both steps — the
file alone does nothing.

**The filename must be the `ManagedCluster` name, not the cluster's friendly
name.** The hub template builds the ConfigMap name from `.ManagedClusterName`,
so the hub is `local-cluster.env`, not `acm-hub.env`. Get it wrong and the
lookup silently misses and every value falls back to the global default —
which looks like it is working.

A cluster with no file is fine and expected: it takes the fleet defaults.

## Format

Flat `KEY=value`, one per line. No nesting.

```sh
etcdEncryptionType=aescbc
allowedRegistries=["registry.redhat.io","quay.io"]
```

The flatness is forced, not stylistic. ACM's template engine has **no
`fromYaml`** — it exposes a subset of sprig, and the YAML helpers are Helm
additions sprig never had. A policy cannot parse structured YAML out of a
ConfigMap at propagation time, so the structure has to be resolved earlier, by
kustomize. An earlier draft of this tree used nested YAML and would have
failed on every cluster.

Lists are stored as JSON arrays and unquoted in the template with `toLiteral`,
since a ConfigMap holds only strings:

```yaml
allowedRegistries: '{{hub ... | toLiteral hub}}'
```

Without `toLiteral` the value lands as a string that looks like a list.

Note also that kustomize cannot merge two `envs:` files into one ConfigMap —
it fails with `illegally repeats the key`. That is why the merge happens in
the hub template rather than here, and why there are two ConfigMaps rather
than one merged one.

## What does not go here

**No secrets.** These become plain ConfigMaps readable by anything in the
policy namespace, and the policies are inform-only — they read configuration
to compare against, never credentials. Secrets belong in Vault, reached by an
ExternalSecret alongside the chart that needs them.

**Nothing a chart should own.** If a value configures a cluster, it belongs in
that cluster's `platform-config.yaml`. These files hold only what a policy
needs in order to know what "correct" looks like.
