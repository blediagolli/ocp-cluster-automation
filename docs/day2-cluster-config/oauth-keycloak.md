# OpenShift OAuth with Keycloak OIDC

The hub runs Keycloak as a central IdP. Managed clusters authenticate against it using OpenID Connect. Setup has three parts: hub-side Keycloak config, managed-cluster secret, and the GitOps chart values.

## 1. Register the cluster as a Keycloak OIDC client (hub side)

Add an `openshift` client to the Keycloak realm in the hub's keycloak values:

```yaml
# clusters/mgt/acm-hub/operators/keycloak.yaml
keycloak:
  realm:
    clients:
      openshift:
        include: true
        clientSecret: "<generate-a-random-secret>"
        redirectUris:
          - "https://oauth-openshift.apps.<cluster-domain>/oauth2callback/<provider-name>"
        webOrigins:
          - "https://oauth-openshift.apps.<cluster-domain>"
```

The `<provider-name>` must match the `name:` in the managed cluster's `identityProviders` list (e.g. `keycloak`).

The `keycloak` chart already includes a `groups` protocol mapper that puts Keycloak group membership into the `groups` claim on the OIDC token. This is what drives OpenShift group sync — no CronJob or group-sync operator needed.

## 2. Make the OIDC client secret available on the cluster

The OAuth CR cannot carry the client secret inline — it can only name a Secret in `openshift-config`.

The `openshift-oauth` chart can create it, and `clientSecret.source` says from where — the same three sources every chart in this repo uses, see [Secrets](../cluster-configuration/secrets.md).

**On a cluster with external-secrets (preferred)**, set `source: externalSecret` and point `path` at the same Vault path the Keycloak realm writes its client secrets to. ESO keeps the two ends in sync; nothing imperative, nothing in git. See step 3.

**Without external-secrets**, set `source: inline` and put the value in `data.clientSecret`. That writes the client secret into git, so it is for development clusters only — and if this repo publishes a sanitized public copy, add it to `.github/scripts/sanitize.sh` before committing.

**Or create the Secret by hand** and leave `source` at its default of `existing`:

```bash
oc create secret generic openshift-oidc-client-secret \
  --from-literal=clientSecret='<same-secret-as-keycloak-client>' \
  -n openshift-config
```

That last path leaves cluster login dependent on a step nothing in git records — treat it as a stopgap until ESO is on the cluster.

## 3. Configure the openshift-oauth chart (managed cluster)

In the managed cluster's `platform-config.yaml`:

```yaml
oauth:
  include: true
  groupRBAC:
    - group: admins
      clusterRole: cluster-admin
    - group: users
      clusterRole: edit
  identityProviders:
    - name: keycloak
      type: OpenID
      mappingMethod: claim
      openID:
        clientID: openshift
        clientSecret:
          name: openshift-oidc-client-secret
          # Drop everything below on a cluster without external-secrets, and
          # the default source: existing applies — see step 2.
          source: externalSecret
          path: secret/data/clusters/<hub-cluster>/keycloak-realm
          properties:
            # clientSecret is the key name OpenShift requires; the property is
            # whatever the issuer stored it under.
            - secretKey: clientSecret
              property: client-openshift
        issuer: "https://sso.apps.<hub-domain>/realms/<realm>"
        claims:
          preferredUsername:
            - preferred_username
          name:
            - name
          email:
            - email
          groups:
            - groups
        extraScopes:
          - email
          - profile
```

The `groupRBAC` list creates ClusterRoleBindings that map Keycloak groups to OpenShift ClusterRoles. Groups are auto-created by the OIDC provider when users log in — the chart intentionally does **not** manage Group resources to avoid ArgoCD self-heal conflicts (ArgoCD would reset the `users` field on every sync, breaking group membership).

Add `openshift-oauth` to `conf.yaml`:

```yaml
platformCharts:
  - chart: openshift-oauth
```

## Pitfalls

- **ArgoCD + Group resources**: Do not create Group CRs in the chart. OpenShift updates the `users` list on login. ArgoCD sees the drift, resets it, and users lose group membership. Only manage ClusterRoleBindings.
- **Orphaned identities**: If you delete a user and re-create it (or switch `mappingMethod`), the old Identity object may block login with `users.user.openshift.io "username" not found`. Fix: `oc delete identity keycloak:<username>` and `oc delete user <username>`.
- **issuer URL**: Must exactly match the Keycloak realm URL including trailing path (`/realms/<name>`). No trailing slash.
- **Hub TLS**: The managed cluster's OAuth server must trust the hub's TLS certificate. If the hub uses Let's Encrypt, this works out of the box (ISRG Root X1 is in all trust stores). If the hub uses a private CA, add it to the managed cluster's proxy trustedCA bundle.
