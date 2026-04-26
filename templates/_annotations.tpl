{{/* vim: set filetype=mustache: */}}

{{/*
uhc.reloaderAnnotations
Returns YAML for the Stakater Reloader annotation dict (or empty if reloader disabled).
When integrations.stakater.reloader.enabled is true:
  - if .annotations is non-empty → emit it as-is (user fully overrides)
  - else → emit { reloader.stakater.com/auto: "true" } as the chart default
Used at four sites: Deployment / StatefulSet / ConfigMap metadata.annotations and
ExternalSecret spec.target.template.metadata.annotations (ESO propagates to the Secret).
Params: $ctx (the dot)
*/}}
{{- define "uhc.reloaderAnnotations" -}}
{{- $reloader := (.Values.integrations | default dict).stakater | default dict -}}
{{- $reloader = $reloader.reloader | default dict -}}
{{- if $reloader.enabled -}}
{{- $custom := $reloader.annotations | default dict -}}
{{- if $custom -}}
{{- toYaml $custom -}}
{{- else -}}
{{- toYaml (dict "reloader.stakater.com/auto" "true") -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
uhc.syncWaveAnnotation
Returns YAML map { "argocd.argoproj.io/sync-wave": "<n>" } when:
  - integrations.argocd.syncWaves.enabled is true (chart-wide gate)
  - integrations.argocd.syncWaves.<kind> is set to a non-null value
Returns empty otherwise. A null/missing per-kind field is the granular off-switch — it
distinguishes from a 0 wave (which is a valid wave, not a disable).
Params: dict "ctx" $ctx "kind" "<kind>"
*/}}
{{- define "uhc.syncWaveAnnotation" -}}
{{- $sw := ((.ctx.Values.integrations | default dict).argocd | default dict).syncWaves | default dict -}}
{{- if $sw.enabled -}}
{{- if hasKey $sw .kind -}}
{{- $val := index $sw .kind -}}
{{- if not (kindIs "invalid" $val) -}}
{{- toYaml (dict "argocd.argoproj.io/sync-wave" ($val | toString)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
uhc.metadataAnnotations
Builds the merged annotation dict for a resource's metadata.annotations and emits it as
YAML INCLUDING the leading "annotations:" header. Returns empty when the merged dict has
no entries (so caller can blindly include it without producing an empty annotations: block).

Merge precedence (lowest-to-highest, last wins on key conflict):
  commonAnnotations → reloader (if includeReloader) → sync-wave (per kind) → extra

Params: dict
  "ctx"             $ctx
  "kind"            "<resource-kind>" — e.g. "deployment", "service", "ingress" — used for
                                       sync-wave lookup. Pass "" to skip sync-wave.
  "includeReloader" bool (default false) — only Deployment/StatefulSet/ConfigMap and
                                           ExternalSecret target template should pass true.
  "extra"           dict (optional) — per-resource user annotations (highest precedence).

Output is rendered at zero indent — caller controls nindent.
*/}}
{{- define "uhc.metadataAnnotations" -}}
{{- $ctx := .ctx -}}
{{- $kind := .kind -}}
{{- $includeReloader := default false .includeReloader -}}
{{- $extra := default dict .extra -}}
{{- $annots := dict -}}
{{- $annots = mergeOverwrite $annots ($ctx.Values.commonAnnotations | default dict) -}}
{{- if $includeReloader -}}
  {{- $rel := include "uhc.reloaderAnnotations" $ctx | fromYaml -}}
  {{- if $rel -}}{{- $annots = mergeOverwrite $annots $rel -}}{{- end -}}
{{- end -}}
{{- if $kind -}}
  {{- $sw := include "uhc.syncWaveAnnotation" (dict "ctx" $ctx "kind" $kind) | fromYaml -}}
  {{- if $sw -}}{{- $annots = mergeOverwrite $annots $sw -}}{{- end -}}
{{- end -}}
{{- if $extra -}}{{- $annots = mergeOverwrite $annots $extra -}}{{- end -}}
{{- if $annots -}}
annotations:
  {{- toYaml $annots | nindent 2 }}
{{- end -}}
{{- end }}
