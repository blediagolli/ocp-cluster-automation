{{- define "vault-server.hostname" -}}
{{- if .Values.vault.route.hostname -}}
{{- .Values.vault.route.hostname -}}
{{- else -}}
vault.{{ .Values.cluster.baseDomain }}
{{- end -}}
{{- end -}}

{{- define "vault-server.address" -}}
{{- if .Values.secretStore.server -}}
{{- .Values.secretStore.server -}}
{{- else -}}
https://vault-active.{{ .Values.vault.namespace }}.svc:8200
{{- end -}}
{{- end -}}

{{- define "vault-server.storageClass" -}}
{{- if .Values.cluster.storageClass -}}
{{- .Values.cluster.storageClass -}}
{{- else -}}
gp3-csi
{{- end -}}
{{- end -}}
