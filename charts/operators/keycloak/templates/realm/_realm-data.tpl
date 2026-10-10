{{/*
Everything the realm-sync ConfigMap and Job need, worked out from values once
and emitted as YAML so both can read the same answer.

This is here rather than at the top of either of them because it is the part
you almost never need while troubleshooting: when the Job fails you want its
bash, and when a file it reads looks wrong you want the ConfigMap. Shaping
values into those is a separate job from doing either.

Every template takes the chart's root context and is called with
`include "..." . | fromYamlArray` (or `fromYaml` for the two maps).
*/}}

{{/*
The partialImport payload: one entry per included client.

Only the fields a client always has are set unconditionally. The rest are
added when present, because partialImport reads an explicit empty list as "the
client has none of these" and would strip scopes or mappers a client already
had.
*/}}
{{- define "keycloak.realmClients" -}}
{{- $v := index .Values .Chart.Name }}
{{- $clientList := list }}
{{- range $name, $client := $v.realm.clients }}
{{- if $client.include }}
{{- $c := dict "clientId" $client.clientId "enabled" true "protocol" "openid-connect" "clientAuthenticatorType" "client-secret" "publicClient" $client.publicClient "standardFlowEnabled" $client.standardFlowEnabled "directAccessGrantsEnabled" $client.directAccessGrantsEnabled "redirectUris" $client.redirectUris "webOrigins" $client.webOrigins }}
{{- if $client.serviceAccountsEnabled }}
{{- $_ := set $c "serviceAccountsEnabled" $client.serviceAccountsEnabled }}
{{- end }}
{{- if $client.defaultClientScopes }}
{{- $_ := set $c "defaultClientScopes" $client.defaultClientScopes }}
{{- end }}
{{- if $client.optionalClientScopes }}
{{- $_ := set $c "optionalClientScopes" $client.optionalClientScopes }}
{{- end }}
{{- if $client.protocolMappers }}
{{- $_ := set $c "protocolMappers" $client.protocolMappers }}
{{- end }}
{{- $clientList = append $clientList $c }}
{{- end }}
{{- end }}
{{- $clientList | toYaml }}
{{- end }}

{{/*
clientId -> the env var carrying that client's secret. Confidential clients
only; a public client has no secret to inject. The Job passes this to
inject.py as CLIENT_ENV_MAP, which is what keeps the secret values themselves
out of the ConfigMap and out of the Job's argv.
*/}}
{{- define "keycloak.realmClientEnv" -}}
{{- $v := index .Values .Chart.Name }}
{{- $clientEnvMap := dict }}
{{- range $name, $client := $v.realm.clients }}
{{- if and $client.include (not $client.publicClient) }}
{{- $_ := set $clientEnvMap $client.clientId (printf "CLIENT_SECRET_%s" (include "keycloak.envSuffix" $name)) }}
{{- end }}
{{- end }}
{{- $clientEnvMap | toYaml }}
{{- end }}

{{/*
Per-user work the Job has to do after the realm import: create the user if the
import never did, then set a password from the Vault-backed Secret and attach
realm roles and group memberships.

Users are deliberately NOT part of the partialImport payload. partialImport
with OVERWRITE deletes and recreates the resource, which changes the Keycloak
user ID — and that ID is the OIDC `sub`. OpenShift keys its identities on it,
so an existing user would come back as a new identity and `mappingMethod:
claim` would then refuse the login as a collision. Creating only what is
missing leaves established users and their IDs alone.
*/}}
{{- define "keycloak.realmUserOps" -}}
{{- $v := index .Values .Chart.Name }}
{{- $userOps := list }}
{{- range $v.realm.users }}
{{- $profile := dict "username" .username "enabled" true }}
{{- with .email }}
{{- $_ := set $profile "email" . }}
{{- $_ := set $profile "emailVerified" true }}
{{- end }}
{{- with .firstName }}{{- $_ := set $profile "firstName" . }}{{- end }}
{{- with .lastName }}{{- $_ := set $profile "lastName" . }}{{- end }}
{{- /* Keycloak stores every attribute value as a list, even single ones. */}}
{{- with .attributes }}
{{- $attrs := dict }}
{{- range $k, $v := . }}
{{- $_ := set $attrs $k (list ($v | toString)) }}
{{- end }}
{{- $_ := set $profile "attributes" $attrs }}
{{- end }}
{{- $realmRoles := include "keycloak.userRealmRoles" (dict "user" . "root" $) | fromYamlArray }}
{{- $op := dict "username" .username "groups" (.groups | default list) "realmRoles" $realmRoles "profile" $profile }}
{{- if .passwordProperty }}
{{- $_ := set $op "envVar" (printf "USER_PASSWORD_%s" (include "keycloak.envSuffix" .username)) }}
{{- end }}
{{- $userOps = append $userOps $op }}
{{- end }}
{{- $userOps | toYaml }}
{{- end }}

{{/*
Service-account users, one per client that has one and asks for attributes or
roles on it. Keycloak never copies a client's own attributes into its tokens,
so a protocol mapper reading org_id finds nothing unless the value is set here,
on service-account-<clientId>.
*/}}
{{- define "keycloak.realmServiceAccountOps" -}}
{{- $v := index .Values .Chart.Name }}
{{- $saOps := list }}
{{- range $name, $client := $v.realm.clients }}
{{- if and $client.include $client.serviceAccountsEnabled $client.serviceAccount }}
{{- $saAttrs := dict }}
{{- range $k, $v := ($client.serviceAccount.attributes | default dict) }}
{{- $_ := set $saAttrs $k (list ($v | toString)) }}
{{- end }}
{{- $saRoles := $client.serviceAccount.realmRoles | default list }}
{{- if or $saAttrs $saRoles }}
{{- $saOps = append $saOps (dict "username" (printf "service-account-%s" ($client.clientId | lower)) "clientId" $client.clientId "attributes" $saAttrs "realmRoles" $saRoles) }}
{{- end }}
{{- end }}
{{- end }}
{{- $saOps | toYaml }}
{{- end }}

{{/*
The clients that have to be attached to a custom client scope after the import.

Two separate problems. partialImport has no clientScopes field at all, so a
scope the realm does not already have can only be created through the admin API
— and the realm import that could have created it only ever runs when the realm
is first built. Then, even with the scope present, partialImport resolves a
client's defaultClientScopes by name and silently drops any it cannot find, so
the attachment is re-asserted explicitly afterwards rather than trusted.
Builtin scopes are left out: Keycloak already has them, which is why this only
picks up names that appear in realm.clientScopes.
*/}}
{{- define "keycloak.realmScopeAttach" -}}
{{- $v := index .Values .Chart.Name }}
{{- $scopeAttach := list }}
{{- range $cname, $client := $v.realm.clients }}
{{- if $client.include }}
{{- range $client.defaultClientScopes }}
{{- if hasKey ($v.realm.clientScopes | default dict) . }}
{{- $scopeAttach = append $scopeAttach (dict "clientId" $client.clientId "scope" . "kind" "default") }}
{{- end }}
{{- end }}
{{- range $client.optionalClientScopes }}
{{- if hasKey ($v.realm.clientScopes | default dict) . }}
{{- $scopeAttach = append $scopeAttach (dict "clientId" $client.clientId "scope" . "kind" "optional") }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- $scopeAttach | toYaml }}
{{- end }}
