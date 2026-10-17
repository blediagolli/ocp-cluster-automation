# Secrets

Every chart in this repo that needs a credential describes it the same way, and
a single `source` field decides where the value comes from. No chart requires a
secrets manager, and no chart invents credentials of its own.

## The three sources

| `source` | What the chart renders | Use it when |
|---|---|---|
| `existing` | Nothing | The Secret is already in the namespace — created by an operator, another chart, or by hand |
| `externalSecret` | An `ExternalSecret` | The cluster runs External Secrets Operator against Vault, AWS Secrets Manager, or any other backend |
| `inline` | A plain `Secret` | The cluster has no secrets manager yet |

`existing` is the default. A chart that defaulted to `externalSecret` would fail
on a cluster with no backend; one that defaulted to `inline` would quietly ship
an empty credential. Referencing a Secret and letting it not exist yet is the
only default that is wrong in a way you notice immediately.

The one exception is `charts/cluster-provisioning/openshift-provisioning`, which
defaults to `inline`: its Secrets live in a namespace the chart itself creates,
so nothing else is going to put them there, and the credentials have always come
from `provision.yaml`.

## The spec

The shape is identical in all three modes, so switching is a one-line change and
the chart consuming the Secret never has to care:

```yaml
secret:
  # Required in every mode — it is the Secret name the consumer references.
  name: keycloak-db
  source: externalSecret
  # Optional; kubernetes.io/tls, kubernetes.io/basic-auth, ...
  type: Opaque

  # --- source: externalSecret ---
  refreshInterval: 1h
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  path: secret/data/clusters/acm-hub/keycloak-db
  properties:
    - secretKey: password      # the key in the resulting Secret
      property: password       # the property at `path` in the backend

  # --- source: inline ---
  data:
    password: ""
```

Charts fill in `name`, `type` and anything structurally fixed — the key names a
CRD insists on, for instance — so a values file usually only sets `source`,
`path` and `properties`.

Values that are *not* secret but belong in the same Secret, so the consumer has
one object to mount, are written by the chart rather than configured here:
`keycloak.postgres.username`, `cost-management-service.ui.clientId` and so on.
They land in the Secret in every mode.

## Where the templates are

There is no shared renderer. Each chart writes its own YAML, in a template named
after the credential — `templates/postgres/postgres-externalsecret.yaml`,
`templates/secret-bmc-credentials.yaml`, and so on. Each one is literal YAML
under a three-way branch:

```
{{- if eq $s.source "externalSecret" }}
kind: ExternalSecret
...
{{- else if eq $s.source "inline" }}
kind: Secret
...
{{- else if ne $s.source "existing" }}
{{- fail ... }}
{{- end }}
```

That is deliberately repetitive. Helm cannot share a template across charts
without a library-chart dependency, so a shared helper has to be *copied* into
every chart and policed for drift — which buys duplication plus a guard, and
costs you the ability to read a template and know what it renders. Duplicated
literal YAML is the better trade here.

The last branch matters: without it a typo in `source` renders nothing at all
and the cluster quietly comes up without the Secret.

## Switching a cluster over

To move one credential from a secrets manager to values:

```yaml
    secret:
-     source: externalSecret
-     path: secret/data/clusters/acm-hub/keycloak-db
+     source: inline
+     data:
+       password: "..."
```

Nothing else changes. The Secret has the same name, the same keys and the same
type, and the Deployment or CR that mounts it is untouched.

## Composed blobs

Some consumers want a whole file with a secret embedded in it rather than one
key per value — Advanced Cluster Security reads an `auth-provider.yaml`, Quay a
`config.yaml`. Those charts pass the composed blob with `{{ .name }}`
placeholders naming entries in `properties` or `data`.

Under `externalSecret` the placeholders pass through to the ExternalSecret's
`target.template.data` and ESO substitutes them at sync time. Under `inline`
there is no ESO, so the chart substitutes them itself before emitting the
Secret. Same blob either way, which is the point.

## Validation

Each branch uses Helm's built-in `required`, so the failure arrives at render
time with the values path in the message.

`externalSecret` mode fails if `path` is missing, rather than producing an
ExternalSecret that fetches nothing.

`inline` mode fails if a key the consumer actually reads is missing *or empty*.
Empty counts as missing — `required` treats `""` as absent, which is what you
want here: charts ship the key names in `values.yaml` with `""` values to
document the shape, so presence alone proves nothing, and an empty password is
accepted by most client libraries and then surfaces as an auth failure several
components away.

An unrecognised `source` fails too, rather than silently rendering nothing.

`make validate` renders every chart for every cluster that enables it, so a
template that does not parse, or a required value a cluster forgot to set, is
caught there.

## Do not commit real credentials

`inline` mode puts the value in git. That is the point of it — a cluster with no
secrets manager has nowhere else to put it — but it means:

- Anyone with read access to the repo has the credential.
- Deleting it later does not remove it; it stays in history.
- This repo publishes a sanitized copy to a public mirror. A new secret in a
  values file has to be added to `.github/scripts/sanitize.sh` **before** it is
  committed, not after. See `CLAUDE.md`.

Use it for development clusters and for bringing a cluster up before its secrets
manager exists. Move to `externalSecret` once there is a backend to move to.

## Charts

| Chart | Credentials |
|---|---|
| `operators/keycloak` | Postgres owner password, realm client secrets and user passwords |
| `operators/advanced-cluster-security` | Central default TLS, OIDC auth provider |
| `operators/quay` | Config bundle, OIDC client |
| `operators/cost-management-metrics` | Keycloak service-account client |
| `operators/cost-management-service` | Postgres roles, object storage, UI oauth2-proxy, cost model sync |
| `operators/external-secrets` | Arbitrary secrets with no chart of their own |
| `platform-config/openshift-oauth` | Identity provider client secrets and bind passwords |
| `platform-config/tls-certificates` | API, ingress and CA certificates |
| `cluster-provisioning/openshift-provisioning` | Pull secret, AWS/vSphere credentials, SSH key, BMC credentials |
