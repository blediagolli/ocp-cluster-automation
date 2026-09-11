{{- define "tls-certificates.provider" -}}
{{- $certProvider := index . 0 -}}
{{- $globalProvider := index . 1 -}}
{{- default $globalProvider $certProvider -}}
{{- end -}}

{{- define "tls-certificates.apiDnsNames" -}}
{{- if .Values.certificates.api.dnsNames -}}
{{- .Values.certificates.api.dnsNames | toYaml -}}
{{- else -}}
- api.{{ .Values.cluster.baseDomain }}
{{- end -}}
{{- end -}}

{{- define "tls-certificates.ingressDnsNames" -}}
{{- if .Values.certificates.ingress.dnsNames -}}
{{- .Values.certificates.ingress.dnsNames | toYaml -}}
{{- else -}}
- "*.apps.{{ .Values.cluster.baseDomain }}"
{{- end -}}
{{- end -}}
