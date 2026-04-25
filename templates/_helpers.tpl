{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}

{{- define "uhc.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated at 63 chars because some Kubernetes name fields are limited to this (DNS naming spec).
If the release name already contains the chart name it is used as the full name.
*/}}
{{- define "uhc.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels for chart-level singleton resources (ServiceAccount, Ingress, RBAC, etc.).
Honors labels.standard.{enabled,partOf,name,instance,version,managedBy} toggles and merges
.Values.commonLabels with standard-wins precedence (chart-managed app.kubernetes.io/* labels
cannot be shadowed by commonLabels). Returns empty when all toggles are off and commonLabels
is empty — caller decides whether to emit the labels: header.
Params: $ctx (the dot)
*/}}
{{- define "uhc.labels" -}}
{{- $std := .Values.labels.standard | default dict -}}
{{- $stdLabels := dict -}}
{{- if $std.enabled -}}
  {{- if $std.partOf -}}{{- $_ := set $stdLabels "app.kubernetes.io/part-of" (include "uhc.fullname" .) -}}{{- end -}}
  {{- if $std.name -}}{{- $_ := set $stdLabels "app.kubernetes.io/name" (include "uhc.name" .) -}}{{- end -}}
  {{- if $std.instance -}}{{- $_ := set $stdLabels "app.kubernetes.io/instance" .Release.Name -}}{{- end -}}
  {{- if and $std.version .Chart.AppVersion -}}{{- $_ := set $stdLabels "app.kubernetes.io/version" (.Chart.AppVersion | toString) -}}{{- end -}}
  {{- if $std.managedBy -}}{{- $_ := set $stdLabels "app.kubernetes.io/managed-by" .Release.Service -}}{{- end -}}
{{- end -}}
{{- $merged := merge $stdLabels (.Values.commonLabels | default dict) -}}
{{- if $merged -}}
{{- toYaml $merged -}}
{{- end -}}
{{- end }}

{{/*
Full labels for a named workload (Deployment, StatefulSet, Service, PDB, VPA, ScaledObject,
HPA, ServiceMonitor, ConfigMap, Job, ESO resources). Same standard.* toggles and commonLabels
merge as uhc.labels, but instance is workload-scoped (fullName-workloadName).
Params: dict "ctx" $ctx "workloadName" $wlName
*/}}
{{- define "uhc.workloadLabels" -}}
{{- $ctx := .ctx -}}
{{- $wlName := .workloadName -}}
{{- $fullName := include "uhc.fullname" $ctx -}}
{{- $std := $ctx.Values.labels.standard | default dict -}}
{{- $stdLabels := dict -}}
{{- if $std.enabled -}}
  {{- if $std.partOf -}}{{- $_ := set $stdLabels "app.kubernetes.io/part-of" $fullName -}}{{- end -}}
  {{- if $std.name -}}{{- $_ := set $stdLabels "app.kubernetes.io/name" $wlName -}}{{- end -}}
  {{- if $std.instance -}}{{- $_ := set $stdLabels "app.kubernetes.io/instance" (printf "%s-%s" $fullName $wlName) -}}{{- end -}}
  {{- if and $std.version $ctx.Chart.AppVersion -}}{{- $_ := set $stdLabels "app.kubernetes.io/version" ($ctx.Chart.AppVersion | toString) -}}{{- end -}}
  {{- if $std.managedBy -}}{{- $_ := set $stdLabels "app.kubernetes.io/managed-by" $ctx.Release.Service -}}{{- end -}}
{{- end -}}
{{- $merged := merge $stdLabels ($ctx.Values.commonLabels | default dict) -}}
{{- if $merged -}}
{{- toYaml $merged -}}
{{- end -}}
{{- end }}

{{/*
Selector labels for a named workload (matchLabels — Service/PDB/ServiceMonitor/PodMonitor
selectors and Deployment/StatefulSet spec.selector.matchLabels). Always emits the minimal
{name, instance} pair regardless of labels.standard.* toggles — selectors are immutable on
workload resources, so they must NEVER be affected by user toggles or commonLabels.
Params: dict "ctx" $ctx "workloadName" $wlName
*/}}
{{- define "uhc.workloadSelectorLabels" -}}
{{- $fullName := include "uhc.fullname" .ctx -}}
app.kubernetes.io/name: {{ .workloadName }}
app.kubernetes.io/instance: {{ printf "%s-%s" $fullName .workloadName }}
{{- end }}

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

{{/*
Fail-fast guard: aborts rendering if any legacy job-related top-level value is present.
The dbJob/initJob/postSync/cronJobs blocks were removed in favour of jobGroups; charts
that still carry them would silently render zero Jobs. We catch that here with a clear
migration message.
Params: $ctx
*/}}
{{- define "uhc.assertNoLegacyJobKeys" -}}
{{- $ctx := . -}}
{{- range $k := list "dbJob" "initJob" "postSync" "cronJobs" -}}
  {{- if hasKey $ctx.Values $k -}}
    {{- fail (printf "Legacy values key '%s' is no longer supported. Migrate to jobGroups (see jobGroups example in values.yaml)." $k) -}}
  {{- end -}}
{{- end -}}
{{- end }}

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
{{- if or $rootSecrets $workloadSecrets $rootConfigMaps $workloadConfigMaps }}
envFrom:
  {{- range $rootSecrets }}
  - secretRef:
      name: {{ .name }}
  {{- end }}
  {{- range $workloadSecrets }}
  - secretRef:
      name: {{ .name }}
  {{- end }}
  {{- range $rootConfigMaps }}
  - configMapRef:
      name: {{ .name }}
  {{- end }}
  {{- range $workloadConfigMaps }}
  - configMapRef:
      name: {{ .name }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Reusable container spec: image, command/args, env, envFrom, ports, probes, resources,
securityContext, volumeMounts.
Params:
- dict "ctx" $ctx "wl" $wl "containerName" $wlName — for main workload container
- dict "ctx" $ctx "wl" $sidecarSpec "containerName" $sidecarSpec.name "renderDirectPorts" true "useRootVolumeMounts" false — for sidecars
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.containerSpecWithOptions" -}}
{{- $ctx := .ctx }}
{{- $wl := .wl }}
{{- $wlName := required "container name is required" .containerName }}
{{- $inheritSource := .inheritOverride | default $wl.inherit | default dict }}
{{- $envInherit := dict }}
{{- if hasKey $inheritSource "env" }}
  {{- $envInherit = (default dict $inheritSource.env) }}
{{- end }}
{{- $inheritConfigMaps := true }}
{{- if hasKey $inheritSource "configMaps" }}
  {{- $inheritConfigMaps = ne (index $inheritSource "configMaps") false }}
{{- end }}
{{- $globalCMs := $ctx.Values.envConfigMaps | default list }}
{{- if not $inheritConfigMaps }}
  {{- $globalCMs = list }}
{{- end }}
{{- /* Resolve configMapRef shorthands: {configMapRef: key} → {name: <fullname>-key} */}}
{{- $resolvedRootCMs := list }}
{{- range $globalCMs }}
  {{- if hasKey . "configMapRef" }}
    {{- $resolvedRootCMs = append $resolvedRootCMs (dict "name" (printf "%s-%s" (include "uhc.fullname" $ctx) .configMapRef)) }}
  {{- else }}
    {{- $resolvedRootCMs = append $resolvedRootCMs . }}
  {{- end }}
{{- end }}
{{- $resolvedWorkloadCMs := list }}
{{- range ($wl.envConfigMaps | default list) }}
  {{- if hasKey . "configMapRef" }}
    {{- $resolvedWorkloadCMs = append $resolvedWorkloadCMs (dict "name" (printf "%s-%s" (include "uhc.fullname" $ctx) .configMapRef)) }}
  {{- else }}
    {{- $resolvedWorkloadCMs = append $resolvedWorkloadCMs . }}
  {{- end }}
{{- end }}
- name: {{ $wlName }}
  {{- $imageOverride := $wl.image | default dict }}
  {{- $resolvedRepo := required "image.repository is required (set image.repository or per-workload image.repository)" (default $ctx.Values.image.repository $imageOverride.repository) }}
  {{- $resolvedTag := required "image.tag is required (set image.tag or per-workload image.tag)" (default $ctx.Values.image.tag $imageOverride.tag) }}
  {{- $resolvedPullPolicy := default $ctx.Values.image.pullPolicy $imageOverride.pullPolicy }}
  image: "{{ $resolvedRepo }}:{{ $resolvedTag }}"
  imagePullPolicy: {{ $resolvedPullPolicy }}
  {{- if $wl.command }}
  command:
  {{- if kindIs "slice" $wl.command }}
    {{- toYaml $wl.command | nindent 4 }}
  {{- else }}
    - sh
    - -c
    - |
{{ $wl.command | trim | indent 6 }}
  {{- end }}
  {{- end }}
  {{- if $wl.args }}
  args:
    {{- range $wl.args }}
    - {{ . | quote }}
    {{- end }}
  {{- end }}
  env:
    {{- include "uhc.envVars" (dict "ctx" $ctx "extraEnv" $wl.env "inherit" $envInherit) | nindent 4 }}
  {{- include "uhc.envFrom" (dict "rootSecrets" $ctx.Values.envSecrets "workloadSecrets" $wl.envSecrets "rootConfigMaps" $resolvedRootCMs "workloadConfigMaps" $resolvedWorkloadCMs) | nindent 2 }}
  {{- $exposeJson := include "uhc.metricsExposeService" (dict "ctx" $ctx "wl" $wl) -}}
  {{- $metricsType := ($wl.metrics | default dict).type | default (($ctx.Values.integrations.monitoring.defaults | default dict).type | default "service") -}}
  {{- $addMetricsPort := and $exposeJson (ne $metricsType "pod") -}}
  {{- $hasMetricsPortAlready := false -}}
  {{- if and $wl.service $wl.service.ports -}}
    {{- range $wl.service.ports -}}
      {{- if eq (.name | toString) "metrics" -}}{{- $hasMetricsPortAlready = true -}}{{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if and .renderDirectPorts $wl.ports }}
  ports:
    {{- toYaml $wl.ports | nindent 4 }}
    {{- if and $addMetricsPort (not $hasMetricsPortAlready) }}
    {{- $expose := $exposeJson | fromJson }}
    - name: metrics
      containerPort: {{ $expose.targetPort }}
      protocol: TCP
    {{- end }}
  {{- else if or (and $wl.service $wl.service.enabled) $addMetricsPort }}
  ports:
    {{- if and $wl.service $wl.service.enabled }}
    {{- if $wl.service.ports }}
    {{- range $wl.service.ports }}
    - name: {{ .name }}
      containerPort: {{ .targetPort }}
      protocol: {{ .protocol | default "TCP" }}
    {{- end }}
    {{- else }}
    - name: http
      containerPort: {{ $wl.service.targetPort }}
      protocol: TCP
    {{- end }}
    {{- end }}
    {{- if and $addMetricsPort (not $hasMetricsPortAlready) }}
    {{- $expose := $exposeJson | fromJson }}
    - name: metrics
      containerPort: {{ $expose.targetPort }}
      protocol: TCP
    {{- end }}
  {{- end }}
  {{- if $wl.probesEnabled }}
  {{- with $wl.readinessProbe }}
  readinessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $wl.livenessProbe }}
  livenessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $wl.startupProbe }}
  startupProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  {{- with $wl.lifecycle }}
  lifecycle:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- $resolvedSecCtx := $wl.securityContext | default $ctx.Values.securityContext }}
  {{- with $resolvedSecCtx }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $wl.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- $inheritParentMounts := ne ($wl.useRootVolumeMounts | toString) "false" }}
  {{- if hasKey . "useRootVolumeMounts" }}
  {{- $inheritParentMounts = ne (.useRootVolumeMounts | toString) "false" }}
  {{- end }}
  {{- $mountsKey := $wlName }}
  {{- if hasKey . "rootVolumeMountsKey" }}
  {{- $mountsKey = .rootVolumeMountsKey }}
  {{- end }}
  {{- $cmm := include "uhc.resolveConfigMapMount" $inheritSource | fromJson }}
  {{- $parentVolumeMounts := index $ctx.Values.volumeMounts $mountsKey }}
  {{- $workloadMounts := $wl.volumeMounts | default list }}
  {{- $hasAutoMounts := "" }}
  {{- if $cmm.enabled }}
    {{- $hasAutoMounts = include "uhc.hasConfigMapAutoVolumes" (dict "ctx" $ctx "granularDisable" $cmm.granular) }}
  {{- end }}
  {{- if or (and $inheritParentMounts $parentVolumeMounts) $workloadMounts $hasAutoMounts }}
  volumeMounts:
    {{- if $inheritParentMounts }}
    {{- with $parentVolumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- end }}
    {{- with $workloadMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if $cmm.enabled }}
    {{- range $cmName := keys ($ctx.Values.configMaps | default dict) | sortAlpha }}
    {{- $cm := index $ctx.Values.configMaps $cmName }}
    {{- if and (hasKey $cm "enabled") $cm.enabled $cm.mountPath (ne (index $cmm.granular $cmName) false) }}
    - name: cm-{{ $cmName }}
      mountPath: {{ $cm.mountPath }}
      readOnly: {{ ne $cm.readOnly false }}
    {{- end }}
    {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Full spec for the main workload container.
Params: dict "ctx" $ctx "wl" $wl "containerName" $wlName
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.containerSpec" -}}
{{- include "uhc.containerSpecWithOptions" . -}}
{{- end }}

{{/*
Renders workload-local sidecars.
Sidecars are defined as a map keyed by sidecar name (same pattern as deployments/statefulSets).
Sidecars inherit the parent workload's inherit.env settings via inheritOverride.
Params: dict "ctx" $ctx "wl" $wl
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.sidecarsSpec" -}}
{{- $ctx := .ctx }}
{{- $wl := .wl }}
{{- range $sidecarName := keys ($wl.sidecars | default dict) | sortAlpha }}
{{- $sidecarSpec := index $wl.sidecars $sidecarName }}
{{- include "uhc.containerSpecWithOptions" (dict "ctx" $ctx "wl" $sidecarSpec "containerName" $sidecarName "renderDirectPorts" true "useRootVolumeMounts" false "inheritOverride" $wl.inherit) }}
{{- end }}
{{- end }}

{{/*
Pod-level spec fields: imagePullSecrets, serviceAccountName, priorityClassName, securityContext, hostAliases.
hostAliases merge order: root + workload + sidecars. Set inheritRootHostAliases: false on a workload to skip root aliases.
Params: dict "ctx" $ctx "wl" $wl
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.podSpec" -}}
{{- $ctx := .ctx }}
{{- $wl := .wl }}
{{- with $ctx.Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
serviceAccountName: {{ default (include "uhc.serviceAccountName" $ctx) $wl.serviceAccountName }}
{{- $autoMount := $ctx.Values.automountServiceAccountToken | default false }}
{{- if hasKey $wl "automountServiceAccountToken" }}
  {{- $autoMount = index $wl "automountServiceAccountToken" }}
{{- end }}
automountServiceAccountToken: {{ $autoMount }}
{{- if or $wl.priorityClassName $ctx.Values.priorityClassName }}
priorityClassName: {{ default $ctx.Values.priorityClassName $wl.priorityClassName }}
{{- end }}
securityContext:
  {{- toYaml $ctx.Values.podSecurityContext | nindent 2 }}
{{- with ($wl.terminationGracePeriodSeconds | default $ctx.Values.terminationGracePeriodSeconds) }}
terminationGracePeriodSeconds: {{ . | int }}
{{- end }}
{{- $useRootAliases := not (eq (index $wl "inheritRootHostAliases") false) }}
{{- $rootAliases := $ctx.Values.hostAliases | default list }}
{{- $localAliases := $wl.hostAliases | default list }}
{{- $allAliases := list }}
{{- if $useRootAliases }}
  {{- $allAliases = concat $rootAliases $localAliases }}
{{- else }}
  {{- $allAliases = $localAliases }}
{{- end }}
{{- range $sidecarName, $sidecarSpec := ($wl.sidecars | default dict) }}
  {{- $allAliases = concat $allAliases ($sidecarSpec.hostAliases | default list) }}
{{- end }}
{{- if $allAliases }}
hostAliases:
  {{- toYaml $allAliases | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Scheduling: affinity (with inheritance), tolerations (merge root + local), topologySpreadConstraints.
Params: dict "ctx" $ctx "wl" $wl "releaseName" $releaseName "wlName" $wlName
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.scheduling" -}}
{{- $ctx := .ctx }}
{{- $wl := .wl }}
{{- $releaseName := .releaseName }}
{{- $wlName := .wlName }}
{{- with $ctx.Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- $schedInherit := $wl.inheritRootSchedParams | default dict }}
{{- $useParentAffinity := not (eq (index $schedInherit "affinity") false) }}
{{- $useParentTolerations := not (eq (index $schedInherit "tolerations") false) }}
{{- $useParentTSC := not (eq (index $schedInherit "tsc") false) }}
{{- if $useParentAffinity }}
{{- if or $wl.affinity $ctx.Values.affinity }}
affinity:
  {{- toYaml ($wl.affinity | default $ctx.Values.affinity) | nindent 2 }}
{{- end }}
{{- else if $wl.affinity }}
affinity:
  {{- toYaml $wl.affinity | nindent 2 }}
{{- end }}
{{- $rootTolerations := $ctx.Values.tolerations | default list }}
{{- $localTolerations := $wl.tolerations | default list }}
{{- if $useParentTolerations }}
{{- if or $rootTolerations $localTolerations }}
tolerations:
  {{- if $rootTolerations }}
  {{- toYaml $rootTolerations | nindent 2 }}
  {{- end }}
  {{- if $localTolerations }}
  {{- toYaml $localTolerations | nindent 2 }}
  {{- end }}
{{- end }}
{{- else if $localTolerations }}
tolerations:
  {{- toYaml $localTolerations | nindent 2 }}
{{- end }}
{{- $parentTSC := index $ctx.Values "topologySpreadConstraints" | default dict }}
{{- $useRootTSC := $useParentTSC }}
{{- $tscActive := false }}
{{- if $useRootTSC }}
{{- if hasKey $wl "topologySpreadConstraints" }}
  {{- if hasKey $wl.topologySpreadConstraints "enabled" }}
    {{- $tscActive = $wl.topologySpreadConstraints.enabled }}
  {{- else if (index $wl.topologySpreadConstraints "constraints") }}
    {{- $tscActive = true }}
  {{- else }}
    {{- $tscActive = index $parentTSC "enabled" }}
  {{- end }}
{{- else }}
  {{- $tscActive = index $parentTSC "enabled" }}
{{- end }}
{{- else if hasKey $wl "topologySpreadConstraints" }}
  {{- if hasKey $wl.topologySpreadConstraints "enabled" }}
    {{- $tscActive = $wl.topologySpreadConstraints.enabled }}
  {{- else if (index $wl.topologySpreadConstraints "constraints") }}
    {{- $tscActive = true }}
  {{- end }}
{{- end }}
{{- if $tscActive }}
{{- $tscRules := list }}
{{- if $useRootTSC }}
  {{- $tscRules = (index $wl "topologySpreadConstraints" | default dict).constraints | default (index $parentTSC "constraints") | default list }}
{{- else }}
  {{- $tscRules = (index $wl "topologySpreadConstraints" | default dict).constraints | default list }}
{{- end }}
{{- if $tscRules }}
topologySpreadConstraints:
  {{- range $tscRules }}
  - maxSkew: {{ .maxSkew }}
    topologyKey: {{ .topologyKey }}
    whenUnsatisfiable: {{ .whenUnsatisfiable }}
    labelSelector:
      {{- if .labelSelector }}
      {{- toYaml .labelSelector | nindent 6 }}
      {{- else }}
      matchLabels:
        {{- include "uhc.workloadSelectorLabels" (dict "ctx" $ctx "workloadName" $wlName) | nindent 8 }}
      {{- end }}
    {{- if .matchLabelKeys }}
    matchLabelKeys:
      {{- toYaml .matchLabelKeys | nindent 6 }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Combined map of all long-running workloads (Deployments + StatefulSets), enabled only.
Jobs and CronJobs are intentionally excluded — monitoring should not target short-lived pods.
Returns JSON so callers can use: include "uhc.serviceWorkloads" . | fromJson
*/}}
{{- define "uhc.serviceWorkloads" -}}
{{- $result := dict -}}
{{- range $name, $spec := (.Values.deployments | default dict) -}}
  {{- if and (hasKey $spec "enabled") $spec.enabled -}}
    {{- $_ := set $result $name $spec -}}
  {{- end -}}
{{- end -}}
{{- range $name, $spec := (.Values.statefulSets | default dict) -}}
  {{- if and (hasKey $spec "enabled") $spec.enabled -}}
    {{- $_ := set $result $name $spec -}}
  {{- end -}}
{{- end -}}
{{- $result | toJson -}}
{{- end -}}

{{/*
Resolves whether monitoring is enabled for a workload.
Per-workload metrics.enabled (if set) wins over monitoring.defaults.enabled.
Returns "true" if enabled, empty string otherwise (helm helpers return strings only).
Usage: eq (include "uhc.metricsEnabled" (dict "ctx" $ctx "wl" $wl)) "true"
*/}}
{{- define "uhc.metricsEnabled" -}}
{{- $wl := .wl -}}
{{- $defaults := .ctx.Values.integrations.monitoring.defaults | default dict -}}
{{- $metrics := $wl.metrics | default dict -}}
{{- if and (hasKey $wl "metrics") (hasKey $metrics "enabled") -}}
  {{- if $metrics.enabled -}}true{{- end -}}
{{- else if $defaults.enabled -}}
true
{{- end -}}
{{- end -}}

{{/*
Resolves the monitoring provider for a workload.
Per-workload metrics.provider wins over monitoring.defaults.provider.
Returns "prometheus" (default) or "victoriametrics".
Usage: $provider := include "uhc.metricsProvider" (dict "ctx" $ctx "wl" $wl)
*/}}
{{- define "uhc.metricsProvider" -}}
{{- $wl := .wl -}}
{{- $defaults := .ctx.Values.integrations.monitoring.defaults | default dict -}}
{{- $metrics := $wl.metrics | default dict -}}
{{- if $metrics.provider -}}{{- $metrics.provider -}}
{{- else if $defaults.provider -}}{{- $defaults.provider -}}
{{- else -}}prometheus{{- end -}}
{{- end -}}

{{/*
Resolves the discovery mode for a workload.
Per-workload metrics.discovery wins over monitoring.defaults.discovery.
Returns "crd" (default) or "annotations".
Usage: $discovery := include "uhc.metricsDiscovery" (dict "ctx" $ctx "wl" $wl)
*/}}
{{- define "uhc.metricsDiscovery" -}}
{{- $wl := .wl -}}
{{- $defaults := .ctx.Values.integrations.monitoring.defaults | default dict -}}
{{- $metrics := $wl.metrics | default dict -}}
{{- if $metrics.discovery -}}{{- $metrics.discovery -}}
{{- else if $defaults.discovery -}}{{- $defaults.discovery -}}
{{- else -}}crd{{- end -}}
{{- end -}}

{{/*
Resolves dedicated metrics-port exposure for a workload.
Per-workload metrics.exposeService.* overrides monitoring.defaults.exposeService.*.
When enabled, returns JSON {"enabled":true,"port":<num>,"targetPort":<num>}.
When disabled or unset, returns empty string. Caller does:

  {{- $exposeJson := include "uhc.metricsExposeService" (dict "ctx" $ctx "wl" $wl) -}}
  {{- if $exposeJson -}}
    {{- $expose := $exposeJson | fromJson -}}
    ... use $expose.port / $expose.targetPort ...
  {{- end -}}
*/}}
{{- define "uhc.metricsExposeService" -}}
{{- $wl := .wl -}}
{{- $defaultsExpose := (.ctx.Values.integrations.monitoring.defaults | default dict).exposeService | default dict -}}
{{- $wlExpose := ($wl.metrics | default dict).exposeService | default dict -}}
{{- $enabled := false -}}
{{- if hasKey $wlExpose "enabled" -}}
  {{- $enabled = $wlExpose.enabled -}}
{{- else -}}
  {{- $enabled = $defaultsExpose.enabled | default false -}}
{{- end -}}
{{- if $enabled -}}
{{- $port := $wlExpose.port | default ($defaultsExpose.port | default 9090) -}}
{{- $targetPort := $wlExpose.targetPort | default ($defaultsExpose.targetPort | default 9090) -}}
{{- dict "enabled" true "port" $port "targetPort" $targetPort | toJson -}}
{{- end -}}
{{- end -}}

{{/*
Renders prometheus.io/* annotations block (or nothing).
Output has no leading indent; caller controls placement via nindent.
Params: dict "ctx" $ctx "wl" $wl "kind" "service"|"pod"
  kind=service → emit when discovery=annotations AND metrics.type != pod
  kind=pod     → emit when discovery=annotations AND metrics.type == pod
*/}}
{{- define "uhc.metricsAnnotations" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $kind := .kind -}}
{{- $defaults := $ctx.Values.integrations.monitoring.defaults | default dict -}}
{{- $metrics := $wl.metrics | default dict -}}
{{- $metricsType := $metrics.type | default ($defaults.type | default "service") -}}
{{- $metricsEnabled := eq (include "uhc.metricsEnabled" (dict "ctx" $ctx "wl" $wl)) "true" -}}
{{- $discovery := include "uhc.metricsDiscovery" (dict "ctx" $ctx "wl" $wl) -}}
{{- $shouldInject := false -}}
{{- if and $metricsEnabled (eq $discovery "annotations") -}}
  {{- if and (eq $kind "service") (ne $metricsType "pod") -}}{{- $shouldInject = true -}}{{- end -}}
  {{- if and (eq $kind "pod") (eq $metricsType "pod") -}}{{- $shouldInject = true -}}{{- end -}}
{{- end -}}
{{- if $shouldInject -}}
{{- /* In annotation mode metrics.port MUST be a numeric port — Prometheus annotation
       does not support port names. Schema/values.yaml documents this constraint;
       monitoring.defaults.port is intentionally NOT used here (it's typically a name
       for CRD mode). Fallback chain: per-workload metrics.port → exposeService.port →
       service.targetPort (the actual containerPort the pod serves) → nothing.
       service.targetPort is the right default because Prometheus scrapes pod_ip:port
       and the pod listens on targetPort, not the Service's presentation port. */}}
{{- /* prometheus.io/port is an OVERRIDE, not a requirement: the standard
       Prometheus/vmagent kubernetes_sd_configs role=pod auto-discovers a
       target per declared containerPort and uses pod_ip:containerPort as
       __address__. The annotation, when present, is applied via a relabel
       'replace' rule to override the port. Pods without it are still scraped
       on their declared container ports. We therefore omit the annotation
       when no port can be resolved — the scrape will use the container's
       own port. (Some custom scrape_configs do require the annotation via
       'action: keep, regex: \d+'; if your stack uses such a config, set
       metrics.port explicitly.) */}}
{{- $annotationPort := "" -}}
{{- $exposeJson := include "uhc.metricsExposeService" (dict "ctx" $ctx "wl" $wl) -}}
{{- if $metrics.port -}}
  {{- $annotationPort = $metrics.port | toString -}}
{{- else if $exposeJson -}}
  {{- $annotationPort = ($exposeJson | fromJson).port | toString -}}
{{- else if and $wl.service $wl.service.targetPort -}}
  {{- $annotationPort = $wl.service.targetPort | toString -}}
{{- end -}}
{{- $effectiveScheme := $metrics.scheme | default ($defaults.scheme | default "http") -}}
prometheus.io/scrape: "true"
prometheus.io/path: {{ $metrics.path | default ($defaults.path | default "/metrics") | quote }}
{{- if $annotationPort }}
prometheus.io/port: {{ $annotationPort | quote }}
{{- end }}
{{- if ne $effectiveScheme "http" }}
prometheus.io/scheme: {{ $effectiveScheme | quote }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Renders a single scrape endpoint block (port/path/interval/scrapeTimeout, with optional
relabelings, basicAuth, and VM-only headers). Used by both ServiceMonitor and PodMonitor —
the field shape is identical, only the parent key differs (endpoints vs podMetricsEndpoints).
Output has no leading indent; caller controls placement via nindent.
Params: dict "ctx" $ctx "wl" $wl "provider" $provider
*/}}
{{- define "uhc.scrapeEndpoint" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $provider := .provider -}}
{{- $defaults := $ctx.Values.integrations.monitoring.defaults | default dict -}}
{{- $metrics := $wl.metrics | default dict -}}
{{- $effectiveRelabelConfigs := $metrics.relabelConfigs | default $defaults.relabelConfigs -}}
{{- $effectiveBasicAuth := $metrics.basicAuth | default $defaults.basicAuth -}}
{{- $effectiveHeaders := $metrics.headers | default $defaults.headers -}}
{{- $defaultPortName := $defaults.port | default "http" -}}
{{- if include "uhc.metricsExposeService" (dict "ctx" $ctx "wl" $wl) -}}{{- $defaultPortName = "metrics" -}}{{- end -}}
- port: {{ $metrics.port | default $defaultPortName }}
  path: {{ $metrics.path | default ($defaults.path | default "/metrics") }}
  interval: {{ $metrics.interval | default ($defaults.interval | default "60s") }}
  scrapeTimeout: {{ $metrics.scrapeTimeout | default ($defaults.scrapeTimeout | default "10s") }}
  {{- if $effectiveRelabelConfigs }}
  {{- if eq $provider "victoriametrics" }}
  relabelConfigs:
  {{- else }}
  relabelings:
  {{- end }}
  {{- toYaml $effectiveRelabelConfigs | nindent 2 }}
  {{- end }}
  {{- if $effectiveBasicAuth }}
  basicAuth:
    password:
      name: {{ $effectiveBasicAuth.password.name }}
      key: {{ $effectiveBasicAuth.password.key }}
    username:
      name: {{ $effectiveBasicAuth.username.name }}
      key: {{ $effectiveBasicAuth.username.key }}
  {{- end }}
  {{- if and $effectiveHeaders (eq $provider "victoriametrics") }}
  vm_scrape_params:
    headers:
      {{- toYaml $effectiveHeaders | nindent 6 }}
  {{- end }}
{{- end -}}

{{/*
Truncates a name segment to 8 characters when longer.
Used to keep jobGroups resource names short enough to fit the k8s 63-char DNS limit
even after the release prefix and sha8 suffix are added.
Params: name string
*/}}
{{- define "uhc.jobGroupTruncSegment" -}}
{{- $name := . -}}
{{- if gt (len $name) 8 -}}
{{- $name | trunc 8 -}}
{{- else -}}
{{- $name -}}
{{- end -}}
{{- end -}}

{{/*
Workload name for jobGroups: "{trunc-group}-{job}" used as workloadName in
uhc.workloadLabels / uhc.workloadSelectorLabels. Group is truncated to 8 chars to keep
the resource name within the k8s 63-char DNS limit; job names are kept verbatim because
they tend to be descriptive ("migrate", "cleanup-orphans") and truncating them invites
collisions ("migrations-old" and "migrations-new" both becoming "migratio").
Params: dict "groupName" $g "jobName" $j
*/}}
{{- define "uhc.jobGroupName" -}}
{{- $g := include "uhc.jobGroupTruncSegment" .groupName -}}
{{- printf "%s-%s" $g .jobName -}}
{{- end -}}

{{/*
Merges group spec with per-job spec, applying:
  - Maps merged, job wins (env, image, securityContext, podSecurityContext, resources,
    nodeSelector, affinity, metadataAnnotations, inherit, hooks.argocd, hooks.helm)
  - Lists concatenated, group then job (envSecrets, envConfigMaps, volumes, volumeMounts, tolerations)
  - Scalars: job-override-else-group (backoffLimit, ttlSecondsAfterFinished,
    activeDeadlineSeconds, restartPolicy, completionImage, serviceAccountName,
    automountServiceAccountToken, terminationGracePeriodSeconds, useRootVolumes,
    useRootVolumeMounts, hashSuffix, hashIncludePodAnnotations, schedule, timeZone,
    concurrencyPolicy, successfulJobsHistoryLimit, failedJobsHistoryLimit,
    startingDeadlineSeconds, command, args, tasks)
  - kind: from group only (per-job override intentionally not supported)
  - podAnnotations: full effective merge of root .Values.podAnnotations,
    .Values.jobPodAnnotations, group.podAnnotations and job.podAnnotations
    (job > group > jobPodAnnotations > podAnnotations). Stored on $merged.podAnnotations
    so the rendered Pod template uses it directly and uhc.jobGroupHash sees the same
    final value (controlled by hashIncludePodAnnotations, default true).
Fails fast when:
  - Job sets both `tasks` and `command`/`args`
  - kind=CronJob without `schedule` on the job
  - kind=CronJob with any non-empty hooks (ArgoCD/Helm hooks aren't applied to CronJob)
  - hashSuffix=true together with deletePolicy=HookSucceeded (argocd) or
    deletePolicy=hook-succeeded (helm) — that combination breaks idempotency.
Returns merged spec as YAML.
Params: dict "ctx" $ctx "group" $group "job" $job "groupName" $g "jobName" $j
*/}}
{{- define "uhc.jobGroupSpec" -}}
{{- $ctx := .ctx -}}
{{- $group := .group | default dict -}}
{{- $job := .job | default dict -}}
{{- $gn := .groupName -}}
{{- $jn := .jobName -}}
{{- if and ($job.tasks) (or $job.command $job.args) -}}
{{- fail (printf "jobGroups.%s.jobs.%s: cannot set both 'tasks' and 'command/args'" $gn $jn) -}}
{{- end -}}
{{- /* kind is set at the group level only — per-job override is intentionally not supported */ -}}
{{- $kind := default "Job" $group.kind -}}
{{- if and (eq $kind "CronJob") (not $job.schedule) -}}
{{- fail (printf "jobGroups.%s.jobs.%s.schedule is required when kind: CronJob" $gn $jn) -}}
{{- end -}}
{{- $merged := dict -}}
{{- $_ := set $merged "kind" $kind -}}
{{/* Maps: merge $job $group → job wins */}}
{{- $_ := set $merged "env" (merge ($job.env | default dict) ($group.env | default dict)) -}}
{{- $rootImage := dict -}}
{{- if $ctx -}}{{- $rootImage = $ctx.Values.image | default dict -}}{{- end -}}
{{- $_ := set $merged "image" (merge ($job.image | default dict) ($group.image | default dict) $rootImage) -}}
{{- $_ := set $merged "metadataAnnotations" (merge ($job.metadataAnnotations | default dict) ($group.metadataAnnotations | default dict)) -}}
{{- $_ := set $merged "securityContext" (merge ($job.securityContext | default dict) ($group.securityContext | default dict)) -}}
{{- $_ := set $merged "podSecurityContext" (merge ($job.podSecurityContext | default dict) ($group.podSecurityContext | default dict)) -}}
{{- $_ := set $merged "resources" (merge ($job.resources | default dict) ($group.resources | default dict)) -}}
{{- $_ := set $merged "nodeSelector" (merge ($job.nodeSelector | default dict) ($group.nodeSelector | default dict)) -}}
{{- $_ := set $merged "affinity" (merge ($job.affinity | default dict) ($group.affinity | default dict)) -}}
{{- $_ := set $merged "inherit" (merge ($job.inherit | default dict) ($group.inherit | default dict)) -}}
{{/* podAnnotations: full effective merge across all sources (job > group > jobPodAnnotations > podAnnotations) */}}
{{- $rootPodAnn := dict -}}
{{- $rootJobPodAnn := dict -}}
{{- if $ctx -}}
  {{- $rootPodAnn = $ctx.Values.podAnnotations | default dict -}}
  {{- $rootJobPodAnn = $ctx.Values.jobPodAnnotations | default dict -}}
{{- end -}}
{{- $effPodAnn := merge ($job.podAnnotations | default dict) ($group.podAnnotations | default dict) $rootJobPodAnn $rootPodAnn -}}
{{- if $effPodAnn -}}
{{- $_ := set $merged "podAnnotations" $effPodAnn -}}
{{- end -}}
{{/* hooks: per-provider deep merge */}}
{{- $gh := $group.hooks | default dict -}}
{{- $jh := $job.hooks | default dict -}}
{{- $mergedHooks := dict -}}
{{- $_ := set $mergedHooks "argocd" (merge ($jh.argocd | default dict) ($gh.argocd | default dict)) -}}
{{- $_ := set $mergedHooks "helm" (merge ($jh.helm | default dict) ($gh.helm | default dict)) -}}
{{- $_ := set $merged "hooks" $mergedHooks -}}
{{/* Lists: concat group then job */}}
{{- $_ := set $merged "envSecrets" (concat ($group.envSecrets | default list) ($job.envSecrets | default list)) -}}
{{- $_ := set $merged "envConfigMaps" (concat ($group.envConfigMaps | default list) ($job.envConfigMaps | default list)) -}}
{{- $_ := set $merged "volumes" (concat ($group.volumes | default list) ($job.volumes | default list)) -}}
{{- $_ := set $merged "volumeMounts" (concat ($group.volumeMounts | default list) ($job.volumeMounts | default list)) -}}
{{- $_ := set $merged "tolerations" (concat ($group.tolerations | default list) ($job.tolerations | default list)) -}}
{{/* Scalars: job-override-else-group */}}
{{- range $k := list "backoffLimit" "ttlSecondsAfterFinished" "activeDeadlineSeconds" "restartPolicy" "completionImage" "serviceAccountName" "automountServiceAccountToken" "terminationGracePeriodSeconds" "useRootVolumes" "useRootVolumeMounts" "hashSuffix" "hashIncludePodAnnotations" "schedule" "timeZone" "concurrencyPolicy" "successfulJobsHistoryLimit" "failedJobsHistoryLimit" "startingDeadlineSeconds" "command" "args" "tasks" -}}
{{- $jv := index $job $k -}}
{{- $gv := index $group $k -}}
{{- if not (kindIs "invalid" $jv) -}}
{{- $_ := set $merged $k $jv -}}
{{- else if not (kindIs "invalid" $gv) -}}
{{- $_ := set $merged $k $gv -}}
{{- end -}}
{{- end -}}
{{/* Fail-fast: CronJob doesn't support hooks (Job-only ArgoCD/Helm semantics) */}}
{{- if eq $kind "CronJob" -}}
  {{- $a := $mergedHooks.argocd | default dict -}}
  {{- $h := $mergedHooks.helm | default dict -}}
  {{- $hookSet := false -}}
  {{- range $k := list "hook" "syncWave" "deletePolicy" -}}
    {{- $v := index $a $k -}}
    {{- if and (not (kindIs "invalid" $v)) (ne ($v | toString) "") -}}{{- $hookSet = true -}}{{- end -}}
  {{- end -}}
  {{- range $k := list "hook" "weight" "deletePolicy" -}}
    {{- $v := index $h $k -}}
    {{- if and (not (kindIs "invalid" $v)) (ne ($v | toString) "") -}}{{- $hookSet = true -}}{{- end -}}
  {{- end -}}
  {{- if $hookSet -}}
    {{- fail (printf "jobGroups.%s.jobs.%s: hooks are not applicable to kind: CronJob (set hooks only on Job groups)" $gn $jn) -}}
  {{- end -}}
{{- end -}}
{{/* Fail-fast: hashSuffix=true with HookSucceeded delete policy breaks idempotency */}}
{{- $hashOn := true -}}
{{- if hasKey $merged "hashSuffix" -}}
  {{- $hashOn = ne (index $merged "hashSuffix") false -}}
{{- end -}}
{{- if $hashOn -}}
  {{- $aDel := ($mergedHooks.argocd | default dict).deletePolicy | default "" -}}
  {{- $hDel := ($mergedHooks.helm | default dict).deletePolicy | default "" -}}
  {{- if or (eq $aDel "HookSucceeded") (eq $hDel "hook-succeeded") -}}
    {{- fail (printf "jobGroups.%s.jobs.%s: hashSuffix=true is incompatible with deletePolicy that removes the Job after success (argocd HookSucceeded / helm hook-succeeded). The Job would be deleted then recreated on every sync, breaking idempotency. Use hashSuffix: false, or a different deletePolicy (e.g. BeforeHookCreation / before-hook-creation), and rely on ttlSecondsAfterFinished for cleanup" $gn $jn) -}}
  {{- end -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end -}}

{{/*
Stable 8-char sha256 of fields that affect Job/CronJob behavior. Excludes metadata-only
fields (metadataAnnotations, hooks, ttlSecondsAfterFinished, hashSuffix,
hashIncludePodAnnotations) so changes to those don't trigger a re-run.
podAnnotations are included by default (so Vault/Datadog injection changes recreate
the Job); set hashIncludePodAnnotations: false to opt out per group/job.
Params: dict "merged" $merged
*/}}
{{- define "uhc.jobGroupHash" -}}
{{- $merged := .merged -}}
{{- $includePodAnn := true -}}
{{- if hasKey $merged "hashIncludePodAnnotations" -}}
  {{- $includePodAnn = ne (index $merged "hashIncludePodAnnotations") false -}}
{{- end -}}
{{- $excludeKeys := list "metadataAnnotations" "hooks" "ttlSecondsAfterFinished" "hashSuffix" "hashIncludePodAnnotations" -}}
{{- if not $includePodAnn -}}
  {{- $excludeKeys = append $excludeKeys "podAnnotations" -}}
{{- end -}}
{{- $hashed := dict -}}
{{- range $k, $v := $merged -}}
{{- if not (has $k $excludeKeys) -}}
{{- $_ := set $hashed $k $v -}}
{{- end -}}
{{- end -}}
{{- $hashed | toYaml | sha256sum | trunc 8 -}}
{{- end -}}

{{/*
Final metadata.name for a jobGroups resource: "{fullname}-{trunc-group}-{trunc-job}[-{sha8}]".
Final string is truncated to 63 chars and trailing dashes are trimmed for k8s DNS-1123
compliance. Set merged.hashSuffix=false to omit the sha suffix.
Params: dict "ctx" $ctx "groupName" $g "jobName" $j "merged" $merged
*/}}
{{- define "uhc.jobGroupResourceName" -}}
{{- $ctx := .ctx -}}
{{- $fullname := include "uhc.fullname" $ctx -}}
{{- $wlName := include "uhc.jobGroupName" (dict "groupName" .groupName "jobName" .jobName) -}}
{{- $base := printf "%s-%s" $fullname $wlName -}}
{{- $useHash := true -}}
{{- if hasKey .merged "hashSuffix" -}}
{{- $useHash = ne (index .merged "hashSuffix") false -}}
{{- end -}}
{{- if $useHash -}}
{{- $sha := include "uhc.jobGroupHash" (dict "merged" .merged) -}}
{{- printf "%s-%s" $base $sha | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $base | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Renders ArgoCD and/or Helm hook annotations from merged.hooks. Both providers are
independent: each is rendered iff at least one of its (hook|syncWave|deletePolicy or
hook|weight|deletePolicy) fields is set to a non-empty value. Empty providers produce no output.
Params: dict "merged" $merged
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.jobGroupHookAnnotations" -}}
{{- $hooks := .merged.hooks | default dict -}}
{{- $a := $hooks.argocd | default dict -}}
{{- $h := $hooks.helm | default dict -}}
{{- $aHook := $a.hook | default "" -}}
{{- $aWave := $a.syncWave -}}
{{- $aDel := $a.deletePolicy | default "" -}}
{{- $hHook := $h.hook | default "" -}}
{{- $hWeight := $h.weight -}}
{{- $hDel := $h.deletePolicy | default "" -}}
{{- $aWaveStr := "" -}}
{{- if not (kindIs "invalid" $aWave) -}}{{- $aWaveStr = $aWave | toString -}}{{- end -}}
{{- $hWeightStr := "" -}}
{{- if not (kindIs "invalid" $hWeight) -}}{{- $hWeightStr = $hWeight | toString -}}{{- end -}}
{{- if or (ne $aHook "") (ne $aWaveStr "") (ne $aDel "") -}}
{{- if ne $aHook "" }}
"argocd.argoproj.io/hook": {{ $aHook | quote }}
{{- end }}
{{- if ne $aWaveStr "" }}
"argocd.argoproj.io/sync-wave": {{ $aWaveStr | quote }}
{{- end }}
{{- if ne $aDel "" }}
"argocd.argoproj.io/hook-delete-policy": {{ $aDel | quote }}
{{- end }}
{{- end -}}
{{- if or (ne $hHook "") (ne $hWeightStr "") (ne $hDel "") -}}
{{- if ne $hHook "" }}
"helm.sh/hook": {{ $hHook | quote }}
{{- end }}
{{- if ne $hWeightStr "" }}
"helm.sh/hook-weight": {{ $hWeightStr | quote }}
{{- end }}
{{- if ne $hDel "" }}
"helm.sh/hook-delete-policy": {{ $hDel | quote }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Renders initContainers from merged.tasks (sortAlpha). Each task is a small object:
  enabled (required), command (string sh -c heredoc, or list), args (list).
Tasks share the job's image, env, envFrom, securityContext and volumeMounts —
per-task overrides are intentionally not supported (use a separate job for that).
Params: dict "ctx" $ctx "wl" $merged
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.jobTasksContainers" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $imageOverride := $wl.image | default dict -}}
{{- $repo := required "jobGroups: image.repository is required (set jobGroups.<group>.image.repository or root image.repository)" (default $ctx.Values.image.repository $imageOverride.repository) -}}
{{- $tag := required "jobGroups: image.tag is required (set jobGroups.<group>.image.tag or root image.tag)" (default $ctx.Values.image.tag $imageOverride.tag) -}}
{{- $pullPolicy := default $ctx.Values.image.pullPolicy $imageOverride.pullPolicy -}}
{{- $secCtx := $wl.securityContext | default $ctx.Values.securityContext | default dict -}}
{{- range $taskName := keys ($wl.tasks | default dict) | sortAlpha }}
{{- $task := index $wl.tasks $taskName }}
{{- if $task.enabled }}
- name: {{ $taskName }}
  image: "{{ $repo }}:{{ $tag }}"
  imagePullPolicy: {{ $pullPolicy }}
  {{- with $secCtx }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if $task.command }}
  command:
  {{- if kindIs "slice" $task.command }}
    {{- toYaml $task.command | nindent 4 }}
  {{- else }}
    - sh
    - -c
    - |
{{ $task.command | trim | indent 6 }}
  {{- end }}
  {{- end }}
  {{- if $task.args }}
  args:
    {{- range $task.args }}
    - {{ . | quote }}
    {{- end }}
  {{- end }}
  env:
    {{- include "uhc.envVars" (dict "ctx" $ctx "extraEnv" ($wl.env | default dict) "inherit" (($wl.inherit | default dict).env | default dict)) | nindent 4 }}
  {{- $secrets := $wl.envSecrets | default list }}
  {{- $rootSecrets := $ctx.Values.envSecrets | default list }}
  {{- include "uhc.envFrom" (dict "rootSecrets" $rootSecrets "workloadSecrets" $secrets) | nindent 2 }}
  {{- /* configMap auto-mounts: same bool/map semantics as uhc.containerSpecWithOptions */ -}}
  {{- $cmm := include "uhc.resolveConfigMapMount" ($wl.inherit | default dict) | fromJson }}
  {{- $autoMounts := list }}
  {{- if $cmm.enabled }}
    {{- range $cmName := keys ($ctx.Values.configMaps | default dict) | sortAlpha }}
      {{- $cm := index $ctx.Values.configMaps $cmName }}
      {{- if and (hasKey $cm "enabled") $cm.enabled $cm.mountPath (ne (index $cmm.granular $cmName) false) }}
        {{- $autoMounts = append $autoMounts (dict "name" (printf "cm-%s" $cmName) "mountPath" $cm.mountPath "readOnly" (ne $cm.readOnly false)) }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- $taskMounts := $wl.volumeMounts | default list }}
  {{- if or $taskMounts $autoMounts }}
  volumeMounts:
    {{- with $taskMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- range $autoMounts }}
    - name: {{ .name }}
      mountPath: {{ .mountPath }}
      readOnly: {{ .readOnly }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end -}}
