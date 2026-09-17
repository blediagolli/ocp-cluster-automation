# Values Precedence

How Helm values are merged across multiple levels, from chart defaults to cluster-specific overrides.

## The values chain

Every ApplicationSet merges Helm values from multiple files, with more-specific files overriding less-specific ones:

```
chart defaults (values.yaml)
  → env/<env>/<values-file>.yaml       (environment-level)
  → clusters/<env>/<name>/<values-file>.yaml  (cluster-level)
```

The values file name depends on the ApplicationSet:

| ApplicationSet | Values files merged |
|---|---|
| `cluster-platform-config` | `conf.yaml` + `platform-config.yaml` |
| `cluster-operator-instances` | `conf.yaml` + `operator-instances.yaml` |
| `cluster-operators-appset` | `conf.yaml` + `operator-deployment.yaml` |
| `cluster-provisioning` | `provision.yaml` |

All ApplicationSets use `ignoreMissingValueFiles: true`, so absent files are silently skipped. This means you can define environment-level defaults and only override what's different at the cluster level.

## The include pattern

Every feature in every chart defaults to `include: false` in the chart's `values.yaml`. Nothing deploys unless explicitly enabled.

```yaml
# charts/platform-config/openshift-oauth/values.yaml
oauth:
  include: false

# clusters/dev/my-cluster/platform-config.yaml
oauth:
  include: true
  identityProviders:
    - name: keycloak
      type: OpenID
      ...
```

This makes charts safe to add to `platformCharts` — adding the chart name doesn't deploy anything until you set `include: true` for the relevant features.

## Environment-level defaults

The `env/<env>/` directory holds shared defaults for all clusters in an environment. Cluster-level files override these.

```
env/
  dev/
    conf.yaml                  # shared cluster identity defaults
    platform-config.yaml       # shared platform chart values
    operator-instances.yaml    # shared operator instance values
    operator-deployment.yaml   # shared operator subscription values
  mgt/
    ...
  prod/
    ...
```

This avoids repeating the same values across every cluster in an environment. For example, all dev clusters might share the same OAuth provider, ACS Central endpoint, and operator versions — define these once in `env/dev/` and override per-cluster only where needed.
