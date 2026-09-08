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

{{/*
Every port name the Pod of one workload declares: its own ports map when it has one,
otherwise the names its Service contributes, plus the sidecar ports and the injected
metrics port. A Service targetPort may name any of these; anything else names a port
no container serves.
Params: dict "ctx" $ctx "wl" $wl
Returns a JSON array of names.
*/}}
{{- define "uhc.podPortNames" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $names := list -}}
{{- if $wl.ports -}}
  {{- $names = keys $wl.ports -}}
{{- else if and $wl.service (ne (index $wl.service "enabled") false) -}}
  {{- if $wl.service.ports -}}
    {{- range $pName, $p := $wl.service.ports -}}
      {{- if regexMatch "^[0-9]+$" (toString (($p | default dict).targetPort | default ($p | default dict).port)) -}}
        {{- $names = append $names $pName -}}
      {{- end -}}
    {{- end -}}
  {{- else if regexMatch "^[0-9]+$" (toString ($wl.service.targetPort | default $wl.service.port)) -}}
    {{- $names = append $names "http" -}}
  {{- end -}}
{{- end -}}
{{- $names = concat $names (include "uhc.sidecarPortNames" (dict "sidecars" $wl.sidecars) | fromJsonArray) -}}
{{- $metricsType := ($wl.metrics | default dict).type | default (($ctx.Values.integrations.monitoring.defaults | default dict).type | default "service") -}}
{{- if and (include "uhc.metricsExposeService" (dict "ctx" $ctx "wl" $wl)) (ne $metricsType "pod") -}}
  {{- $names = append $names "metrics" -}}
{{- end -}}
{{- $names | uniq | toJson -}}
{{- end }}

{{/*
Fail when a Service targetPort names a port no container in the Pod declares. Both
Service shapes route by that name, so a name nothing serves yields a Service with
endpoints on a port that never answers. Numeric targetPorts need no check.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName "ports" <ports map or nil>
        "scalarTarget" <the scalar targetPort or nil> "prefix" <"service" / "headlessService">
*/}}
{{- define "uhc.assertNamedTargetPorts" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $wlName := .wlName -}}
{{- $prefix := .prefix -}}
{{- $declared := include "uhc.podPortNames" (dict "ctx" $ctx "wl" $wl) | fromJsonArray -}}
{{- range $pName, $p := (.ports | default dict) -}}
{{- $entry := $p | default dict -}}
{{- $target := toString ($entry.targetPort | default $entry.port) -}}
{{- if and (not (regexMatch "^[0-9]+$" $target)) (not (has $target $declared)) -}}
{{- include "uhc.assertNumericContainerPort" (dict "value" $target "containerName" $wlName "source" (printf "%s.ports.%s.targetPort" $prefix $pName)) -}}
{{- end -}}
{{- end -}}
{{- if .scalarTarget -}}
{{- $target := toString .scalarTarget -}}
{{- if and (not (regexMatch "^[0-9]+$" $target)) (not (has $target $declared)) -}}
{{- include "uhc.assertNumericContainerPort" (dict "value" $target "containerName" $wlName "source" (printf "%s.targetPort" $prefix)) -}}
{{- end -}}
{{- end -}}
{{- end }}
