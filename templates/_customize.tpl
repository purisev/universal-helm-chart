{{/* vim: set filetype=mustache: */}}

{{/*
uhc.customMetadata
Resolves the user-supplied labels and annotations for one rendered resource and returns
them as JSON {"labels": {...}, "annotations": {...}}. Sources, last wins on key conflict:
  integrations.<integration>.customize.{labels,annotations} → entry.{labels,annotations}
The caller hands the result to uhc.workloadLabels / uhc.labelsWithExtra and
uhc.metadataAnnotations as "extra", which keep their own precedence around it
(chart-managed app.kubernetes.io/* labels still win).
Params: dict
  "ctx"         $ctx
  "integration" "<name>" (optional) — key under .Values.integrations owning the resource
  "entry"       dict (optional)     — the values entry the resource is rendered from
*/}}
{{- define "uhc.customMetadata" -}}
{{- $customize := dict -}}
{{- if .integration -}}
  {{- $customize = (index (.ctx.Values.integrations | default dict) .integration | default dict).customize | default dict -}}
{{- end -}}
{{- $entry := .entry | default dict -}}
{{- $labels := merge (dict) ($entry.labels | default dict) ($customize.labels | default dict) -}}
{{- $annots := merge (dict) ($entry.annotations | default dict) ($customize.annotations | default dict) -}}
{{- toJson (dict "labels" $labels "annotations" $annots) -}}
{{- end }}
