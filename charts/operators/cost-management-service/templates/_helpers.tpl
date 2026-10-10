{{/*
Cluster apps domain. An explicit costManagementService.clusterDomain wins;
otherwise it comes from the cluster's conf.yaml like every other chart here.
May be empty — the operator's Discovery phase works it out.
*/}}
{{- define "cost-management-service.clusterDomain" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $v.costManagementService.clusterDomain | default .Values.cluster.baseDomain -}}
{{- end -}}

{{/*
Default StorageClass. Per-component storageClass wins, then the chart-wide
one, then the cluster's.
*/}}
{{- define "cost-management-service.storageClass" -}}
{{- .component | default ((index .root.Values .root.Chart.Name).costManagementService.storageClass | default .root.Values.cluster.storageClass) -}}
{{- end -}}

{{/*
Keycloak URL for JWKS. Defaults to the keycloak chart's in-cluster Service,
which the CRD explicitly prefers: Envoy fetches JWKS from it, and going via
the Route would make token validation depend on the ingress path.

The Service is "<keycloak name>-service", not "<keycloak name>", and on the
httpEnabled path this repo uses only 8080 is open. Same trap documented in
the keycloak chart's HANDOFF.
*/}}
{{- define "cost-management-service.keycloakUrl" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $kc := $v.costManagementService.auth.keycloak -}}
{{- $kc.url | default "http://keycloak-service.keycloak.svc.cluster.local:8080" -}}
{{- end -}}

{{/*
The issuer Envoy validates tokens against. RHBK with a configured hostname
stamps the public Route URL into iss even when the client obtained the token
over the Service, so this must be the Route and not the JWKS URL above.
*/}}
{{- define "cost-management-service.keycloakIssuer" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $kc := $v.costManagementService.auth.keycloak -}}
{{- if $kc.issuerURL -}}
{{- $kc.issuerURL -}}
{{- else -}}
{{- with include "cost-management-service.clusterDomain" . -}}
{{- printf "https://sso.%s" . -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Secret holding the UI's oauth2-proxy client credentials. Matches the
operator's own default of "<cr name>-ui-oauth-client". Keys are client-id and
client-secret with HYPHENS — the Metrics Operator uses underscores for the
same two values and swapping them fails authentication silently.
*/}}
{{- define "cost-management-service.uiOauthSecretName" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $ui := $v.costManagementService.ui -}}
{{- $ui.oauthClientSecretName | default (printf "%s-ui-oauth-client" $v.costManagementService.name) -}}
{{- end -}}

{{/*
Postgres host the operator connects to. An explicit postgres.host always wins.
Otherwise it is CNPG's read-write Service, which is "<cluster name>-rw" and
not the Cluster name — pointing at the bare name resolves nothing.
*/}}
{{- define "cost-management-service.dbHost" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $pg := $v.costManagementService.postgres -}}
{{- if $pg.host -}}
{{- $pg.host -}}
{{- else -}}
{{- printf "%s-rw.%s.svc" $pg.name $v.costManagementService.namespace -}}
{{- end -}}
{{- end -}}

{{/*
Every database the bootstrap Job must create, ROS included only when enabled.
*/}}
{{- define "cost-management-service.databases" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $pg := $v.costManagementService.postgres -}}
{{- $dbs := $pg.databases | default list -}}
{{- if $v.costManagementService.ros.enabled -}}
{{- $dbs = concat $dbs ($pg.rosDatabases | default list) -}}
{{- end -}}
{{- toYaml $dbs -}}
{{- end -}}

{{/*
Every per-component role, ROS included only when enabled. The CRD requires a
matching user/password pair on the database Secret for each.
*/}}
{{- define "cost-management-service.dbRoles" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $pg := $v.costManagementService.postgres -}}
{{- $roles := $pg.roles | default list -}}
{{- if $v.costManagementService.ros.enabled -}}
{{- $roles = concat $roles ($pg.rosRoles | default list) -}}
{{- end -}}
{{- toYaml $roles -}}
{{- end -}}

{{/*
Kafka bootstrap address. Strimzi names the listener Service
"<kafka name>-kafka-bootstrap"; the plain-text listener in kafka.yaml is 9092.
*/}}
{{- define "cost-management-service.kafkaBootstrap" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $kafka := $v.costManagementService.kafka -}}
{{- if $kafka.bootstrapServers -}}
{{- $kafka.bootstrapServers -}}
{{- else -}}
{{- printf "%s-kafka-bootstrap.%s.svc:9092" $kafka.name $v.costManagementService.namespace -}}
{{- end -}}
{{- end -}}

{{/*
Keycloak token endpoint the cost model sync Job authenticates against.
Defaults to the same in-cluster Service the JWKS URL uses — the token it
returns still carries the Route as iss, which is what Envoy validates, so
going over the Service costs nothing and keeps this off the ingress path.
*/}}
{{- define "cost-management-service.costModelTokenUrl" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $cm := $v.costManagementService.costModel -}}
{{- if $cm.auth.tokenUrl -}}
{{- $cm.auth.tokenUrl -}}
{{- else -}}
{{- printf "%s/realms/%s/protocol/openid-connect/token" (include "cost-management-service.keycloakUrl" .) $v.costManagementService.auth.keycloak.realm -}}
{{- end -}}
{{- end -}}

{{/*
API origin the cost model sync Job talks to. Defaults to the gateway Service
rather than the Route: same Envoy, same JWT validation, no dependency on the
router being healthy and no TLS to trust. Envoy's listener is published on
port 80 of that Service.
*/}}
{{- define "cost-management-service.costModelApiUrl" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $cms := $v.costManagementService -}}
{{- if $cms.costModel.apiUrl -}}
{{- $cms.costModel.apiUrl -}}
{{- else -}}
{{- printf "http://%s-gateway.%s.svc" $cms.name $cms.namespace -}}
{{- end -}}
{{- end -}}

{{/*
The cost model's name, which is also the key the sync matches an existing
model on. Defaults to the CR name.
*/}}
{{- define "cost-management-service.costModelName" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $v.costManagementService.costModel.name | default $v.costManagementService.name -}}
{{- end -}}

{{/*
Render a spec.<component>.image block from costManagementService.images.<key>.
*/}}
{{- define "cost-management-service.image" -}}
{{- $img := index (index .root.Values .root.Chart.Name).costManagementService.images .key -}}
image:
  repository: {{ $img.repository }}
  tag: {{ $img.tag | quote }}
{{- end -}}
