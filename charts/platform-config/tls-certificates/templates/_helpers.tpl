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

{{- define "tls-certificates.apiCommonName" -}}
{{- if .Values.certificates.api.dnsNames -}}
{{- first .Values.certificates.api.dnsNames -}}
{{- else -}}
api.{{ .Values.cluster.baseDomain }}
{{- end -}}
{{- end -}}

{{- define "tls-certificates.ingressDnsNames" -}}
{{- if .Values.certificates.ingress.dnsNames -}}
{{- .Values.certificates.ingress.dnsNames | toYaml -}}
{{- else -}}
- "*.apps.{{ .Values.cluster.baseDomain }}"
{{- end -}}
{{- end -}}

{{- define "tls-certificates.ingressCommonName" -}}
{{- if .Values.certificates.ingress.dnsNames -}}
{{- first .Values.certificates.ingress.dnsNames -}}
{{- else -}}
*.apps.{{ .Values.cluster.baseDomain }}
{{- end -}}
{{- end -}}
