{{/* vim: set filetype=mustache: */}}

{{/*
Core helpers that don't fit a dedicated cluster file.
The main helper library is split across:
  _labels.tpl       — name, fullname, labels, workloadLabels, workloadSelectorLabels
  _annotations.tpl  — reloaderAnnotations, syncWaveAnnotation, metadataAnnotations
  _env.tpl          — envVars, envFrom
  _workload.tpl     — container/pod/scheduling specs, configMap auto-mount helpers
  _metrics.tpl      — monitoring/scrape helpers
  _jobs.tpl         — jobGroups merge, hash, naming, hook annotations, tasks
*/}}

{{/*
ESO API version: v1 (ESO >= 0.10) or v1beta1 (ESO < 0.10).
Detected via .Capabilities.APIVersions.Has — works on live cluster.
Falls back to v1beta1 when rendering offline (helm template without --kube-version).
*/}}
{{- define "uhc.esoApiVersion" -}}
{{- if .Capabilities.APIVersions.Has "external-secrets.io/v1" -}}
external-secrets.io/v1
{{- else -}}
external-secrets.io/v1beta1
{{- end -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "uhc.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "uhc.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
