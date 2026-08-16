{{/* vim: set filetype=mustache: */}}

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
{{- $inheritEnvSecrets := true }}
{{- if hasKey $inheritSource "envSecrets" }}
  {{- $inheritEnvSecrets = ne (index $inheritSource "envSecrets") false }}
{{- end }}
{{- $rootSecretsForFrom := $ctx.Values.envSecrets | default list }}
{{- if not $inheritEnvSecrets }}
  {{- $rootSecretsForFrom = list }}
{{- end }}
{{- $globalCMs := $ctx.Values.envConfigMaps | default list }}
{{- if not $inheritConfigMaps }}
  {{- $globalCMs = list }}
{{- end }}
{{- /* Resolve envConfigMaps strings: chart-owned (matches a key in .Values.configMaps) → "<fullname>-<name>"; otherwise external CM name as-is. */}}
{{- $chartCMKeys := keys ($ctx.Values.configMaps | default dict) }}
{{- $resolvedRootCMs := list }}
{{- range $globalCMs }}
  {{- if has . $chartCMKeys }}
    {{- $resolvedRootCMs = append $resolvedRootCMs (printf "%s-%s" (include "uhc.fullname" $ctx) .) }}
  {{- else }}
    {{- $resolvedRootCMs = append $resolvedRootCMs . }}
  {{- end }}
{{- end }}
{{- $resolvedWorkloadCMs := list }}
{{- range ($wl.envConfigMaps | default list) }}
  {{- if has . $chartCMKeys }}
    {{- $resolvedWorkloadCMs = append $resolvedWorkloadCMs (printf "%s-%s" (include "uhc.fullname" $ctx) .) }}
  {{- else }}
    {{- $resolvedWorkloadCMs = append $resolvedWorkloadCMs . }}
  {{- end }}
{{- end }}
- name: {{ $wlName }}
  {{- $imageOverride := $wl.image | default dict }}
  {{- $resolvedRepo := required "image.repository is required (set image.repository or per-workload image.repository)" (default $ctx.Values.image.repository $imageOverride.repository) }}
  {{- $resolvedTag := required "image.tag is required (set image.tag or per-workload image.tag)" (default $ctx.Values.image.tag $imageOverride.tag) }}
  {{- $resolvedPullPolicy := default $ctx.Values.image.pullPolicy $imageOverride.pullPolicy }}
  {{- if and (eq $resolvedTag "latest") (eq $resolvedPullPolicy "IfNotPresent") }}
  {{- fail (printf "container %q: imagePullPolicy: IfNotPresent combined with tag 'latest' is unsafe — nodes that already have the image cached will not pull updates. Set imagePullPolicy: Always or use a specific image tag." $wlName) }}
  {{- end }}
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
    {{- include "uhc.envVars" (dict "ctx" $ctx "extraEnv" $wl.env "inherit" $envInherit) | trim | nindent 4 }}
  {{- $envFromYaml := include "uhc.envFrom" (dict "rootSecrets" $rootSecretsForFrom "workloadSecrets" $wl.envSecrets "rootConfigMaps" $resolvedRootCMs "workloadConfigMaps" $resolvedWorkloadCMs) | trim }}
  {{- if $envFromYaml }}
  {{- $envFromYaml | nindent 2 }}
  {{- end }}
  {{- $exposeJson := include "uhc.metricsExposeService" (dict "ctx" $ctx "wl" $wl) -}}
  {{- $metricsType := ($wl.metrics | default dict).type | default (($ctx.Values.integrations.monitoring.defaults | default dict).type | default "service") -}}
  {{- $addMetricsPort := and $exposeJson (ne $metricsType "pod") -}}
  {{- $hasMetricsPortAlready := or (and $wl.service $wl.service.ports (hasKey ($wl.service.ports | default dict) "metrics")) (hasKey ($wl.ports | default dict) "metrics") -}}
  {{- if and .renderDirectPorts $wl.ports }}
  ports:
    {{- range $pName := include "uhc.orderedPortNames" $wl.ports | fromJsonArray }}
    {{- $p := index $wl.ports $pName }}
    - name: {{ $pName }}
      {{- toYaml $p | nindent 6 }}
    {{- end }}
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
    {{- range $pName := include "uhc.orderedPortNames" $wl.service.ports | fromJsonArray }}
    {{- $p := index $wl.service.ports $pName }}
    - name: {{ $pName }}
      containerPort: {{ $p.targetPort }}
      protocol: {{ $p.protocol | default "TCP" }}
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
  {{- if and .excludeProbesAndLifecycle $wl.probesEnabled }}
  {{- fail (printf "%s.%s: probes are not supported on standard init containers (Kubernetes only allows probes on native sidecar-init with restartPolicy: Always — not yet exposed by the chart). Remove probesEnabled / readinessProbe / livenessProbe / startupProbe from this entry." (.pathPrefix | default "container") $wlName) }}
  {{- end }}
  {{- if not .excludeProbesAndLifecycle }}
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
  {{- end }}
  {{- if and .excludeProbesAndLifecycle $wl.lifecycle }}
  {{- fail (printf "%s.%s: lifecycle is not supported on standard init containers. Remove the lifecycle block from this entry." (.pathPrefix | default "container") $wlName) }}
  {{- end }}
  {{- if not .excludeProbesAndLifecycle }}
  {{- with $wl.lifecycle }}
  lifecycle:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  {{- $resolvedSecCtx := $wl.securityContext | default $ctx.Values.securityContext }}
  {{- with $resolvedSecCtx }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- $resolvedResources := $wl.resources | default $ctx.Values.resources }}
  {{- with $resolvedResources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $wl.resizePolicy }}
  resizePolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- $inheritParentMounts := true }}
  {{- if hasKey $wl "useRootVolumeMounts" }}
  {{- $inheritParentMounts = $wl.useRootVolumeMounts }}
  {{- end }}
  {{- if hasKey . "useRootVolumeMounts" }}
  {{- $inheritParentMounts = .useRootVolumeMounts }}
  {{- end }}
  {{- $mountsKey := $wlName }}
  {{- if hasKey . "rootVolumeMountsKey" }}
  {{- $mountsKey = .rootVolumeMountsKey }}
  {{- end }}
  {{- $cmm := include "uhc.resolveConfigMapMount" $inheritSource | fromJson }}
  {{- $parentVolumeMounts := index ($ctx.Values.volumeMounts | default dict) $mountsKey | default dict }}
  {{- $workloadMounts := $wl.volumeMounts | default dict }}
  {{- $hasAutoMounts := "" }}
  {{- if $cmm.enabled }}
    {{- $hasAutoMounts = include "uhc.hasConfigMapAutoVolumes" (dict "ctx" $ctx "granularDisable" $cmm.granular) }}
  {{- end }}
  {{- if or (and $inheritParentMounts $parentVolumeMounts) $workloadMounts $hasAutoMounts }}
  volumeMounts:
    {{- if $inheritParentMounts }}
    {{- range $mName := keys $parentVolumeMounts | sortAlpha }}
    - name: {{ $mName }}
      {{- toYaml (index $parentVolumeMounts $mName) | nindent 6 }}
    {{- end }}
    {{- end }}
    {{- range $mName := keys $workloadMounts | sortAlpha }}
    - name: {{ $mName }}
      {{- toYaml (index $workloadMounts $mName) | nindent 6 }}
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
Renders workload-local initContainers.
Init containers are a map keyed by container name (sortAlpha render order — prefix
names with 01-/02- when execution order matters; Kubernetes runs initContainers
sequentially in declared order).
Init containers inherit the parent workload's inherit.env / inherit.configMaps /
inherit.configMapMount settings via inheritOverride, like sidecars.
volumeMounts.<initContainerName> at root level is NOT inherited (define mounts
locally, same as sidecars). ConfigMap auto-mounts still apply unless disabled
via inherit.configMapMount on the parent workload.
Reloader does not re-trigger init containers — they run only on Pod creation.
Params: dict "ctx" $ctx "wl" $wl
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.initContainersSpec" -}}
{{- $ctx := .ctx }}
{{- $wl := .wl }}
{{- range $name := keys ($wl.initContainers | default dict) | sortAlpha }}
{{- $spec := index $wl.initContainers $name }}
{{- include "uhc.containerSpecWithOptions" (dict "ctx" $ctx "wl" $spec "containerName" $name "renderDirectPorts" true "useRootVolumeMounts" false "inheritOverride" $wl.inherit "excludeProbesAndLifecycle" true "pathPrefix" "initContainers") }}
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
  {{- range . }}
  - name: {{ . }}
  {{- end }}
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
{{- $podSec := $wl.podSecurityContext | default $ctx.Values.podSecurityContext }}
securityContext:
  {{- toYaml $podSec | nindent 2 }}
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
{{- with $wl.resourceClaims }}
resourceClaims:
  {{- toYaml . | nindent 2 }}
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
{{- $ns := $wl.nodeSelector | default $ctx.Values.nodeSelector }}
{{- with $ns }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- $affinity := $wl.affinity | default $ctx.Values.affinity }}
{{- with $affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- $tolerations := $ctx.Values.tolerations | default list }}
{{- if hasKey $wl "tolerations" }}
  {{- $tolerations = $wl.tolerations | default list }}
{{- end }}
{{- with $tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- $tsc := $ctx.Values.topologySpreadConstraints | default list }}
{{- if hasKey $wl "topologySpreadConstraints" }}
  {{- $tsc = $wl.topologySpreadConstraints | default list }}
{{- end }}
{{- if $tsc }}
topologySpreadConstraints:
  {{- range $tsc }}
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
