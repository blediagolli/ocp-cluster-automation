{{- define "cluster-operators.target" -}}
{{- index .Values.targets .Values.profile .Values.clusterType -}}
{{- end -}}

{{- define "cluster-operators.operator" -}}
{{- index .Values.operators . -}}
{{- end -}}
