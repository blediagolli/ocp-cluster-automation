{{- define "cluster.cloudLabel" -}}
{{- if eq .Values.cluster.platform "vsphere" }}vSphere
{{- else if eq .Values.cluster.platform "aws" }}Amazon
{{- else if eq .Values.cluster.platform "baremetal" }}BareMetal
{{- else }}Other
{{- end -}}
{{- end -}}

{{- define "cluster.isIPI" -}}
{{- if or (eq .Values.cluster.platform "vsphere") (eq .Values.cluster.platform "aws") }}true
{{- else }}false
{{- end -}}
{{- end -}}

{{- define "cluster.isAgent" -}}
{{- if or (eq .Values.cluster.platform "baremetal") (eq .Values.cluster.platform "none") }}true
{{- else }}false
{{- end -}}
{{- end -}}

{{- define "imagePullSecret" }}
{{- with .Values.imageContentSources }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"email\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password .email (printf "%s:%s" .username .password | b64enc) | b64enc }}
{{- end }}
{{- end }}
