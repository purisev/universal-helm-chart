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
Create chart name and version as used by the chart label.
*/}}
{{- define "uhc.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels for chart-level singleton resources (ServiceAccount, Ingress).
*/}}
{{- define "uhc.labels" -}}
helm.sh/chart: {{ include "uhc.chart" . }}
app.kubernetes.io/part-of: {{ include "uhc.fullname" . }}
app.kubernetes.io/name: {{ include "uhc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Labels for init job.
*/}}
{{- define "uhc.initJobLabels" -}}
{{- $fullName := include "uhc.fullname" . -}}
helm.sh/chart: {{ include "uhc.chart" . }}
app.kubernetes.io/part-of: {{ $fullName }}
app.kubernetes.io/name: {{ include "uhc.name" . }}-init
app.kubernetes.io/instance: {{ printf "%s-init" $fullName }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Labels for PostSync jobs.
*/}}
{{- define "uhc.postSyncLabels" -}}
{{- $fullName := include "uhc.fullname" . -}}
helm.sh/chart: {{ include "uhc.chart" . }}
app.kubernetes.io/part-of: {{ $fullName }}
app.kubernetes.io/name: {{ include "uhc.name" . }}-postsync
app.kubernetes.io/instance: {{ printf "%s-postsync" $fullName }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Labels for database job.
*/}}
{{- define "uhc.dbJobLabels" -}}
{{- $fullName := include "uhc.fullname" . -}}
helm.sh/chart: {{ include "uhc.chart" . }}
app.kubernetes.io/part-of: {{ $fullName }}
app.kubernetes.io/name: {{ include "uhc.name" . }}-db
app.kubernetes.io/instance: {{ printf "%s-db" $fullName }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "uhc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "uhc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Full labels for a named workload (Deployment, StatefulSet, Service, PDB, VPA, ScaledObject, HPA, ServiceMonitor, ConfigMap, Job).
Params: dict "ctx" $ctx "workloadName" $wlName
*/}}
{{- define "uhc.workloadLabels" -}}
{{- $fullName := include "uhc.fullname" .ctx -}}
helm.sh/chart: {{ include "uhc.chart" .ctx }}
app.kubernetes.io/part-of: {{ $fullName }}
app.kubernetes.io/name: {{ .workloadName }}
app.kubernetes.io/instance: {{ printf "%s-%s" $fullName .workloadName }}
{{- if .ctx.Chart.AppVersion }}
app.kubernetes.io/version: {{ .ctx.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
{{- end }}

{{/*
Selector labels for a named workload (matchLabels, Service/PDB/ServiceMonitor selectors).
Params: dict "ctx" $ctx "workloadName" $wlName
*/}}
{{- define "uhc.workloadSelectorLabels" -}}
{{- $fullName := include "uhc.fullname" .ctx -}}
app.kubernetes.io/name: {{ .workloadName }}
app.kubernetes.io/instance: {{ printf "%s-%s" $fullName .workloadName }}
{{- end }}

{{/*
Auto-generated volumes for all configMaps entries that have mountPath set.
Opt-in per entry: only rendered when entry.enabled and entry.mountPath are both set.
Params: $ctx
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.configMapAutoVolumes" -}}
{{- $ctx := . }}
{{- range $cmName := keys ($ctx.Values.configMaps | default dict) | sortAlpha }}
{{- $cm := index $ctx.Values.configMaps $cmName }}
{{- if and (hasKey $cm "enabled") $cm.enabled $cm.mountPath }}
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
Environment variables: NAMESPACE fieldRef → global.application.env → global.env → envDev → envProd → extraEnv.
Params:
- dict "ctx" $ctx
- dict "extraEnv" $wl.env
- optional dict "inherit" $wl.inherit.env with keys:
  - application: false → exclude global.application.env
  - global: false      → exclude global.env
  - dev: false         → exclude envDev.env
  - prod: false        → exclude envProd.env
  All keys default to true (inherit everything).
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.envVars" -}}
{{- $ctx := .ctx }}
{{- $extraEnv := .extraEnv | default dict }}
{{- $inherit := .inherit | default dict }}
{{- $wantApplication := true }}
{{- if hasKey $inherit "application" }}
  {{- $wantApplication = ne (index $inherit "application") false }}
{{- end }}
{{- $wantGlobal := true }}
{{- if hasKey $inherit "global" }}
  {{- $wantGlobal = ne (index $inherit "global") false }}
{{- end }}
{{- $wantDev := true }}
{{- if hasKey $inherit "dev" }}
  {{- $wantDev = ne (index $inherit "dev") false }}
{{- end }}
{{- $wantProd := true }}
{{- if hasKey $inherit "prod" }}
  {{- $wantProd = ne (index $inherit "prod") false }}
{{- end }}
- name: NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- if and $wantApplication $ctx.Values.global.application }}
{{- range $envName, $value := $ctx.Values.global.application.env }}
- name: {{ $envName }}
  {{- toYaml $value | nindent 2 }}
{{- end }}
{{- end }}
{{- if $wantGlobal }}
{{- range $envName, $value := $ctx.Values.global.env }}
- name: {{ $envName }}
  {{- toYaml $value | nindent 2 }}
{{- end }}
{{- end }}
{{- if and $wantDev $ctx.Values.envDev.enabled }}
{{- range $envName, $value := $ctx.Values.envDev.env }}
- name: {{ $envName }}
  {{- toYaml $value | nindent 2 }}
{{- end }}
{{- end }}
{{- if and $wantProd $ctx.Values.envProd.enabled }}
{{- range $envName, $value := $ctx.Values.envProd.env }}
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
  {{- $metricsType := ($wl.metrics | default dict).type | default (($ctx.Values.monitoring.defaults | default dict).type | default "service") -}}
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
  {{- /* inherit.configMapMount: true/false disables all; map disables specific keys */}}
  {{- $wantConfigMapMount := true }}
  {{- $granularDisable := dict }}
  {{- if hasKey $inheritSource "configMapMount" }}
    {{- $cmMountVal := index $inheritSource "configMapMount" }}
    {{- if kindIs "bool" $cmMountVal }}
      {{- $wantConfigMapMount = ne $cmMountVal false }}
    {{- else if kindIs "map" $cmMountVal }}
      {{- $granularDisable = $cmMountVal }}
    {{- end }}
  {{- end }}
  {{- $parentVolumeMounts := index $ctx.Values.volumeMounts $mountsKey }}
  {{- $workloadMounts := $wl.volumeMounts | default list }}
  {{- $hasAutoMounts := false }}
  {{- if $wantConfigMapMount }}
    {{- range $cmName := keys ($ctx.Values.configMaps | default dict) | sortAlpha }}
      {{- $cm := index $ctx.Values.configMaps $cmName }}
      {{- if and (hasKey $cm "enabled") $cm.enabled $cm.mountPath (ne (index $granularDisable $cmName) false) }}
        {{- $hasAutoMounts = true }}
      {{- end }}
    {{- end }}
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
    {{- if $wantConfigMapMount }}
    {{- range $cmName := keys ($ctx.Values.configMaps | default dict) | sortAlpha }}
    {{- $cm := index $ctx.Values.configMaps $cmName }}
    {{- if and (hasKey $cm "enabled") $cm.enabled $cm.mountPath (ne (index $granularDisable $cmName) false) }}
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
serviceAccountName: {{ include "uhc.serviceAccountName" $ctx }}
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
{{- $defaults := .ctx.Values.monitoring.defaults | default dict -}}
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
{{- $defaults := .ctx.Values.monitoring.defaults | default dict -}}
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
{{- $defaults := .ctx.Values.monitoring.defaults | default dict -}}
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
{{- $defaultsExpose := (.ctx.Values.monitoring.defaults | default dict).exposeService | default dict -}}
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
{{- $defaults := $ctx.Values.monitoring.defaults | default dict -}}
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
{{- $defaults := $ctx.Values.monitoring.defaults | default dict -}}
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
