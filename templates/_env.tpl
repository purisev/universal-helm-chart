{{/* vim: set filetype=mustache: */}}

{{/*
Environment variables: NAMESPACE fieldRef → global.env → root env → extraEnv.
Params:
- dict "ctx" $ctx
- dict "extraEnv" $wl.env
- optional dict "inherit" $wl.inherit.env with keys:
  - global: false → exclude global.env
  - root:   false → exclude root env
  All keys default to true (inherit everything).
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.envVars" -}}
{{- $ctx := .ctx }}
{{- $extraEnv := .extraEnv | default dict }}
{{- $inherit := .inherit | default dict }}
{{- $wantGlobal := true }}
{{- if hasKey $inherit "global" }}
  {{- $wantGlobal = ne (index $inherit "global") false }}
{{- end }}
{{- $wantRoot := true }}
{{- if hasKey $inherit "root" }}
  {{- $wantRoot = ne (index $inherit "root") false }}
{{- end }}
- name: NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- if and $wantGlobal $ctx.Values.global }}
{{- range $envName, $value := ($ctx.Values.global.env | default dict) }}
- name: {{ $envName }}
  {{- toYaml $value | nindent 2 }}
{{- end }}
{{- end }}
{{- if $wantRoot }}
{{- range $envName, $value := ($ctx.Values.env | default dict) }}
- name: {{ $envName }}
  {{- toYaml $value | nindent 2 }}
{{- end }}
{{- end }}
{{- range $envName, $value := $extraEnv }}
- name: {{ $envName }}
  {{- toYaml $value | nindent 2 }}
{{- end }}
{{- end }}

{{/*
envFrom block with merged root + local envSecrets and envConfigMaps.
Same name appearing in both root and workload lists collapses into a single
secretRef/configMapRef — first occurrence wins, in source-list order
(`uniq` over `concat root workload`). The result is shorter rendered YAML
and a quieter argo CD diff.

A note on order. Without dedup, two distinct names overlapping in both lists
(e.g. root=[A], workload=[shared, A]) would render as [A, shared, A] —
k8s envFrom is last-wins per key, so any keys present in BOTH A and shared
would resolve to A's value (since A appears last). After dedup the order is
[A, shared] and the same conflicting keys would resolve to shared's value.
Operationally this never bites in practice, because charts in the wild use
distinct sets of secrets / configMaps for envFrom and don't rely on that
last-wins ordering. If a workload genuinely needs a specific override
ordering between A and shared, the right fix is to set the conflicting
keys explicitly via `env`, not to rely on duplicated envFrom entries.

Params:
  dict "rootSecrets"     $ctx.Values.envSecrets
       "workloadSecrets"   $wl.envSecrets
       "rootConfigMaps"  $ctx.Values.envConfigMaps  (pass empty list when inherit disabled)
       "workloadConfigMaps" $wl.envConfigMaps
For jobs call without workload* params.
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.envFrom" -}}
{{- $rootSecrets := .rootSecrets | default list }}
{{- $workloadSecrets := .workloadSecrets | default list }}
{{- $rootConfigMaps := .rootConfigMaps | default list }}
{{- $workloadConfigMaps := .workloadConfigMaps | default list }}
{{- $secrets := uniq (concat $rootSecrets $workloadSecrets) }}
{{- $configMaps := uniq (concat $rootConfigMaps $workloadConfigMaps) }}
{{- if or $secrets $configMaps }}
envFrom:
  {{- range $secrets }}
  - secretRef:
      name: {{ . }}
  {{- end }}
  {{- range $configMaps }}
  - configMapRef:
      name: {{ . }}
  {{- end }}
{{- end }}
{{- end }}
