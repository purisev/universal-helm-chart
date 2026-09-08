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

{{/*
Fail when a Service port entry declares neither port nor targetPort. Both renderers
fall back from one key to the other, so an entry carrying neither resolves to nothing:
the Service would take `port: <nil>` and the container-port derivation would hunt for a
port named "<nil>". The schema cannot state "one of these two" in a readable message,
so the check lives here.
Params: dict "ports" <the ports map> "source" <values path, e.g. `service.ports for workload "web"`>
*/}}
{{- define "uhc.assertServicePortsDeclared" -}}
{{- $source := .source -}}
{{- range $pName, $p := (.ports | default dict) -}}
{{- $entry := $p | default dict -}}
{{- if not (or $entry.port $entry.targetPort) -}}
{{- fail (printf "%s: port %q declares neither port nor targetPort. Set one of them — the other falls back to it." $source $pName) -}}
{{- end -}}
{{- end -}}
{{- end }}
