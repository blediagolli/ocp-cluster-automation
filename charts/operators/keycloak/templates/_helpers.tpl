{{/*
Name of the Secret holding the Postgres credentials. Shared by the
ExternalSecret that creates it, the StatefulSet and the Keycloak CR's
db.usernameSecret / db.passwordSecret, so all three stay in agreement when
postgres.secretName is overridden.
*/}}
{{- define "keycloak.postgresSecretName" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $v.postgres.secretName | default (printf "%s-db" $v.postgres.name) -}}
{{- end -}}

{{/*
Name of the Secret holding realm credentials — client secrets and user
passwords. Created by realm-externalsecret.yaml from Vault and consumed by the
realm-sync Job; never rendered into the KeycloakRealmImport, which has no way
to reference a Secret and would commit them to git.
*/}}
{{- define "keycloak.realmSecretName" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $v.realm.secret.secretName | default (printf "%s-realm-credentials" $v.instance.name) -}}
{{- end -}}

{{/*
Turn an arbitrary client key or username into a legal environment variable
suffix, so "user1" and "my-client" become USER1 and MY_CLIENT.
*/}}
{{- define "keycloak.envSuffix" -}}
{{- . | upper | regexReplaceAll "[^A-Z0-9]" "_" -}}
{{- end -}}

{{/*
Name of the realm's default composite role. Keycloak creates
"default-roles-<realm>" with every realm and hangs offline_access,
uma_authorization and the account client roles off it.
*/}}
{{- define "keycloak.defaultRole" -}}
{{- $v := index .Values .Chart.Name -}}
{{- printf "default-roles-%s" $v.realm.name -}}
{{- end -}}

{{/*
A realm user's full realm-role list: whatever values asked for, plus the realm
default composite.

The default has to be spelled out because neither path that creates a user adds
it. KeycloakRealmImport takes the user representation literally, and the
realm-sync Job's role loop only grants the roles it is given. A user without it
has no offline_access role, and any client asking for the offline_access scope
— ACS Central does, on every auth-code login — is refused with "Offline tokens
not allowed for the user or client".
*/}}
{{- define "keycloak.userRealmRoles" -}}
{{- $roles := .user.realmRoles | default list -}}
{{- $default := include "keycloak.defaultRole" .root -}}
{{- if not (has $default $roles) -}}
{{- $roles = prepend $roles $default -}}
{{- end -}}
{{- toYaml $roles -}}
{{- end -}}

{{/*
In-cluster base URL of the Keycloak Service, for jobs that talk to the admin
API. The operator names the Service "<keycloak name>-service" and only opens
the listener Keycloak was configured for: 8443 when a tlsSecret is supplied,
otherwise 8080 with httpEnabled. Hardcoding https/8443 makes admin jobs hang
until they time out whenever the edge-route (httpEnabled) path is used.
*/}}
{{- define "keycloak.serviceUrl" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $host := printf "%s-service.%s.svc.cluster.local" $v.instance.name (include "operator.crNamespace" .) -}}
{{- if $v.instance.tlsSecret -}}
{{- printf "https://%s:8443" $host -}}
{{- else -}}
{{- printf "http://%s:8080" $host -}}
{{- end -}}
{{- end -}}

{{/*
Database host for the Keycloak CR. An explicit keycloak.db.host always wins, so
an external database can still be used. Otherwise, when the bundled Postgres is
enabled, point at its in-namespace Service. Empty means "no db block at all".
*/}}
{{- define "keycloak.dbHost" -}}
{{- $v := index .Values .Chart.Name -}}
{{- if $v.instance.db.host -}}
{{- $v.instance.db.host -}}
{{- else if $v.postgres.include -}}
{{- printf "%s.%s.svc" $v.postgres.name (include "operator.crNamespace" .) -}}
{{- end -}}
{{- end -}}
