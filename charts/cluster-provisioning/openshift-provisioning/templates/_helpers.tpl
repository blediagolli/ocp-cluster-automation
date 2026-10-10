{{- define "cluster.cloudLabel" -}}
{{- if eq .Values.cluster.platform "vsphere" }}vSphere
{{- else if eq .Values.cluster.platform "aws" }}Amazon
{{- else if eq .Values.cluster.platform "baremetal" }}BareMetal
{{- else }}Other
{{- end -}}
{{- end -}}

{{- define "cluster.platformLabel" -}}
{{- if eq (include "cluster.isAgent" .) "true" }}agent-baremetal
{{- else }}{{ .Values.cluster.platform }}
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

{{- /* Single-node OpenShift: one control plane node that also runs the
       workload, no workers at all. The only thing that makes a cluster SNO is
       masters.count: 1, so that is what this reads — there is no separate
       toggle to get out of step with the replica counts the installer
       actually sees. */}}
{{- define "cluster.isSNO" -}}
{{- if eq (int .Values.masters.count) 1 }}true
{{- else }}false
{{- end -}}
{{- end -}}

{{- /* Rejected at render time rather than left to fail hours later inside a
       Hive provisioning pod. A single master with workers alongside it is not
       a supported topology: etcd has no quorum to lose but the installer
       still refuses the combination, and the failure arrives as an opaque
       install error long after the ClusterDeployment went green. */}}
{{- define "cluster.validateTopology" -}}
{{- if and (eq (include "cluster.isSNO" .) "true") (gt (int .Values.workers.count) 0) }}
{{- fail (printf "masters.count: 1 is single-node OpenShift and requires workers.count: 0 — got %d" (int .Values.workers.count)) }}
{{- end }}
{{- if and (eq (include "cluster.isSNO" .) "true") (eq (include "cluster.isAgent" .) "true") }}
{{- $platformCfg := index .Values .Values.cluster.platform }}
{{- if ne (int $platformCfg.provisionRequirements.controlPlaneAgents) 1 }}
{{- fail (printf "masters.count: 1 needs %s.provisionRequirements.controlPlaneAgents: 1 — got %d" .Values.cluster.platform (int $platformCfg.provisionRequirements.controlPlaneAgents)) }}
{{- end }}
{{- end }}
{{- end -}}

{{- /* cluster.useExternalSecret is gone: `secrets.source` on each credential
       replaces externalSecrets.enabled plus a path check. See secrets.yaml. */}}

{{- /* The pull secret this chart synthesises for a mirror registry. Plain
       JSON, so it can go in stringData like every other inline secret; base64
       for a `data:` field is the caller's job. */}}
{{- define "imagePullSecretJSON" }}
{{- with .Values.imageContentSources }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"email\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password .email (printf "%s:%s" .username .password | b64enc) }}
{{- end }}
{{- end }}

{{- define "imagePullSecret" }}
{{- include "imagePullSecretJSON" . | b64enc }}
{{- end }}
