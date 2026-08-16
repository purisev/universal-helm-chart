{{/* vim: set filetype=mustache: */}}

{{/*
Auto-generated volumes for all configMaps entries that have mountPath set.
Opt-in per entry: only rendered when entry.enabled and entry.mountPath are both set.
Skips entries explicitly disabled by inherit.configMapMount.<name>: false (granular form).
Params: dict "ctx" $ctx (optional "granularDisable" $map)
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.configMapAutoVolumesFiltered" -}}
{{- $ctx := .ctx }}
{{- $granular := .granularDisable | default dict }}
{{- range $cmName := keys ($ctx.Values.configMaps | default dict) | sortAlpha }}
{{- $cm := index $ctx.Values.configMaps $cmName }}
{{- if and (hasKey $cm "enabled") $cm.enabled $cm.mountPath (ne (index $granular $cmName) false) }}
- name: cm-{{ $cmName }}
  configMap:
    name: {{ include "uhc.fullname" $ctx }}-{{ $cmName }}
    {{- if $cm.defaultMode }}
    defaultMode: {{ $cm.defaultMode }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Backwards-compatible wrapper: same as uhc.configMapAutoVolumesFiltered with no
granular disable map. Used by existing call sites that don't carry inherit.configMapMount.
Params: $ctx
*/}}
{{- define "uhc.configMapAutoVolumes" -}}
{{- include "uhc.configMapAutoVolumesFiltered" (dict "ctx" .) -}}
{{- end }}

{{/*
Whether at least one configMap auto-mount volume would be rendered for the given
context and granularDisable map. Returns "true" or empty string.
Params: dict "ctx" $ctx (optional "granularDisable" $map)
*/}}
{{- define "uhc.hasConfigMapAutoVolumes" -}}
{{- $ctx := .ctx }}
{{- $granular := .granularDisable | default dict }}
{{- $found := "" }}
{{- range $cmName, $cm := ($ctx.Values.configMaps | default dict) }}
{{- if and (hasKey $cm "enabled") $cm.enabled $cm.mountPath (ne (index $granular $cmName) false) }}
{{- $found = "true" }}
{{- end }}
{{- end }}
{{- $found -}}
{{- end }}

{{/*
Resolves an inherit.configMapMount value into a normalized {enabled, granular} dict.
Bool form (true/false) toggles all auto-mounts; map form ({name: false}) disables
specific entries while keeping others. Returns JSON so callers can fromJson it.
Params: an inherit dict (typically $wl.inherit, or the override dict passed to
sidecars). Reads inherit.configMapMount.
*/}}
{{- define "uhc.resolveConfigMapMount" -}}
{{- $inherit := . | default dict -}}
{{- $enabled := true -}}
{{- $granular := dict -}}
{{- $cmm := index $inherit "configMapMount" -}}
{{- if not (kindIs "invalid" $cmm) -}}
  {{- if kindIs "bool" $cmm -}}
    {{- $enabled = $cmm -}}
  {{- else if kindIs "map" $cmm -}}
    {{- $granular = $cmm -}}
  {{- end -}}
{{- end -}}
{{- dict "enabled" $enabled "granular" $granular | toJson -}}
{{- end }}
