{{/*
Shared by every chart under charts/operators/. Identical in all of them —
do not edit one copy.

Namespace the chart's custom resources live in. Defaults to the operator's own
install namespace, which is the common case: most operators that have CRs at
all are installed beside the CRs they reconcile. Charts whose operator watches
a namespace it is not installed in (ACS Central lands in stackrox from an
operator in rhacs-operator) set <chart>.namespace explicitly.
*/}}
{{- define "operator.crNamespace" -}}
{{- $v := index .Values .Chart.Name -}}
{{- $v.namespace | default $v.operator.namespace -}}
{{- end -}}
