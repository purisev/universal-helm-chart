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
Fail when a Service port entry cannot produce a valid spec.ports[].port. The renderers
fall back from one key to the other, so an entry carrying neither resolves to nothing
and the Service takes `port: <nil>`. A lone named targetPort is the same story one step
further on: spec.ports[].port is an int32, so a name cannot stand in for it. The schema
can express neither rule in a readable message, so the check lives here.
Params: dict "ports" <the ports map> "source" <values path, e.g. `service.ports for workload "web"`>
*/}}
{{- define "uhc.assertServicePortsDeclared" -}}
{{- $source := .source -}}
{{- range $pName, $p := (.ports | default dict) -}}
{{- $entry := $p | default dict -}}
{{- if not (or $entry.port $entry.targetPort) -}}
{{- fail (printf "%s: port %q declares neither port nor targetPort. Set port, or a numeric targetPort for it to fall back to." $source $pName) -}}
{{- else if and (not $entry.port) (not (regexMatch "^[0-9]+$" (toString $entry.targetPort))) -}}
{{- fail (printf "%s: port %q names its targetPort %q and declares no port. A Service port is a number and cannot fall back to a name, so set port explicitly." $source $pName (toString $entry.targetPort)) -}}
{{- end -}}
{{- end -}}
{{- end }}
