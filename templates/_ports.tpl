{{/* vim: set filetype=mustache: */}}

{{/*
Ordered port-name list for service.ports / container ports rendering.
Convention: "http" (if present) is rendered first, "metrics" (if present) last,
all other ports alphabetically between. Returns a JSON-encoded list of names;
caller decodes with `fromJsonArray`.
Param: a map (e.g. $wl.service.ports). Output: JSON array of strings.
*/}}
{{- define "uhc.orderedPortNames" -}}
{{- $names := keys (. | default dict) -}}
{{- $first := list -}}
{{- if has "http" $names -}}{{- $first = list "http" -}}{{- end -}}
{{- $last := list -}}
{{- if has "metrics" $names -}}{{- $last = list "metrics" -}}{{- end -}}
{{- $middle := without (without $names "http") "metrics" | sortAlpha -}}
{{- concat $first $middle $last | toJson -}}
{{- end }}
