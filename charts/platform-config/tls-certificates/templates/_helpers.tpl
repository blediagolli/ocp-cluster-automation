{{- /* Resolve a certificate's provider: its own override, else the global one.

       `manual`, `external-secret` and `vault` used to be three providers.
       They were three spellings of one thing — put the certificate in a Secret
       — differing only in where the bytes came from, which is exactly what the
       shared `secret:` spec expresses. They are now one provider, `secret`,
       with `secret.source` picking inline or externalSecret.

       The old names fail rather than aliasing to `secret`: their per-provider
       values blocks (manual.<cert>, vault.<cert>, externalSecret.<cert>) are
       gone, so quietly accepting the name would render a certificate with no
       data in it. A cert-manager or sealed-secret provider is unaffected. */}}
{{- define "tls-certificates.provider" -}}
{{- $certProvider := index . 0 -}}
{{- $globalProvider := index . 1 -}}
{{- $p := default $globalProvider $certProvider -}}
{{- if has $p (list "manual" "external-secret" "vault") -}}
{{- fail (printf "tls-certificates: provider %q was replaced by provider: secret — move the certificate's data under certificates.<cert>.secret (source: inline for manual, source: externalSecret for external-secret/vault). See charts/platform-config/tls-certificates/values.yaml." $p) -}}
{{- end -}}
{{- if not (has $p (list "cert-manager" "sealed-secret" "secret")) -}}
{{- fail (printf "tls-certificates: provider must be one of cert-manager, sealed-secret, secret — got %q" $p) -}}
{{- end -}}
{{- $p -}}
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
