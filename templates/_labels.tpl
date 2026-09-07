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
Whether constructed names drop the -<workloadName> suffix, from
naming.omitWorkloadSuffix. A release running a single workload can carry the
release name alone on every resource; the suffix only exists to keep several
workloads in one release apart, so more than one enabled workload is rejected
instead of silently collapsing them onto the same names.
Returns "true" when the suffix is dropped, empty string otherwise.
Params: $ctx (the dot)
*/}}
{{- define "uhc.omitWorkloadSuffix" -}}
{{- if (.Values.naming | default dict).omitWorkloadSuffix -}}
{{- $workloads := list -}}
{{- range $name, $spec := (.Values.deployments | default dict) -}}
  {{- if ne (index $spec "enabled") false -}}
    {{- $workloads = append $workloads (printf "deployments.%s" $name) -}}
  {{- end -}}
{{- end -}}
{{- range $name, $spec := (.Values.statefulSets | default dict) -}}
  {{- if ne (index $spec "enabled") false -}}
    {{- $workloads = append $workloads (printf "statefulSets.%s" $name) -}}
  {{- end -}}
{{- end -}}
{{- if gt (len $workloads) 1 -}}
{{- fail (printf "naming.omitWorkloadSuffix expects exactly one enabled workload, found %d (%s). Without the -<workloadName> suffix every one of them renders under the same resource names. Set naming.omitWorkloadSuffix: false, or keep a single deployments / statefulSets entry enabled." (len $workloads) (join ", " (sortAlpha $workloads))) -}}
{{- end -}}
true
{{- end -}}
{{- end }}

{{/*
Name of the resources belonging to one workload: <fullname>-<workloadName>, or
<fullname> alone under naming.omitWorkloadSuffix. Every per-workload resource name
is built from this, including the -headless / -metrics / -config variants.
Params: dict "ctx" $ctx "wlName" $wlName
*/}}
{{- define "uhc.workloadResourceName" -}}
{{- $fullName := include "uhc.fullname" .ctx -}}
{{- if eq (include "uhc.omitWorkloadSuffix" .ctx) "true" -}}
{{- $fullName -}}
{{- else -}}
{{- printf "%s-%s" $fullName .wlName -}}
{{- end -}}
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
HPA, ServiceMonitor, ConfigMap, Job, ESO resources). Always emits the minimal
{name, instance} pair so spec.selector.matchLabels keeps matching the pod template — the
labels.standard.{name,instance,enabled} flags do NOT affect this helper (changing them
would silently break Deployment/StatefulSet/Job by orphaning the selector). Toggles for
partOf, version, managedBy still apply, and commonLabels are merged with standard-wins
precedence.
Params: dict "ctx" $ctx "workloadName" $wlName
*/}}
{{- define "uhc.workloadLabels" -}}
{{- $ctx := .ctx -}}
{{- $wlName := .workloadName -}}
{{- $fullName := include "uhc.fullname" $ctx -}}
{{- $instance := include "uhc.workloadResourceName" (dict "ctx" $ctx "wlName" $wlName) -}}
{{- $nameLabel := $wlName -}}
{{- if eq (include "uhc.omitWorkloadSuffix" $ctx) "true" -}}
{{- $nameLabel = include "uhc.name" $ctx -}}
{{- end -}}
{{- include "uhc.assertNameLength" (dict "name" $instance "kind" (printf "label app.kubernetes.io/instance for workload %q" $wlName)) -}}
{{- $std := $ctx.Values.labels.standard | default dict -}}
{{- $stdLabels := dict -}}
{{- $_ := set $stdLabels "app.kubernetes.io/name" $nameLabel -}}
{{- $_ := set $stdLabels "app.kubernetes.io/instance" $instance -}}
{{- if $std.enabled -}}
  {{- if $std.partOf -}}{{- $_ := set $stdLabels "app.kubernetes.io/part-of" $fullName -}}{{- end -}}
  {{- if and $std.version $ctx.Chart.AppVersion -}}{{- $_ := set $stdLabels "app.kubernetes.io/version" ($ctx.Chart.AppVersion | toString) -}}{{- end -}}
  {{- if $std.managedBy -}}{{- $_ := set $stdLabels "app.kubernetes.io/managed-by" $ctx.Release.Service -}}{{- end -}}
{{- end -}}
{{- $merged := merge $stdLabels ($ctx.Values.commonLabels | default dict) -}}
{{- toYaml $merged -}}
{{- end }}

{{/*
Selector labels for a named workload (matchLabels — Service/PDB/ServiceMonitor/PodMonitor
selectors and Deployment/StatefulSet spec.selector.matchLabels). Always emits the minimal
{name, instance} pair regardless of labels.standard.* toggles — selectors are immutable on
workload resources, so they must NEVER be affected by user toggles or commonLabels.
Params: dict "ctx" $ctx "workloadName" $wlName
*/}}
{{- define "uhc.workloadSelectorLabels" -}}
{{- $instance := include "uhc.workloadResourceName" (dict "ctx" .ctx "wlName" .workloadName) -}}
{{- $nameLabel := .workloadName -}}
{{- if eq (include "uhc.omitWorkloadSuffix" .ctx) "true" -}}
{{- $nameLabel = include "uhc.name" .ctx -}}
{{- end -}}
{{- include "uhc.assertNameLength" (dict "name" $instance "kind" (printf "selector label app.kubernetes.io/instance for workload %q" .workloadName)) -}}
app.kubernetes.io/name: {{ $nameLabel }}
app.kubernetes.io/instance: {{ $instance }}
{{- end }}

{{/*
Fail fast when a constructed name or label value would exceed 63 characters.
Two k8s rules collapse into a single ceiling here: label values are limited
to 63 chars, and Service object names must be DNS-1123 labels (also 63).
Other k8s name kinds (ConfigMap, Deployment, …) accept up to 253 chars as
DNS-1123 subdomains, but the chart constrains *every* constructed name to
63 so it remains usable as the value of `app.kubernetes.io/instance` (which
this helper is wired into via uhc.workloadLabels and
uhc.workloadSelectorLabels). Apply explicitly at name-with-suffix sites
(`<release>-<wl>-headless`, `-metrics`, `-config`) and at top-level plural
maps where the chart-singleton labels skip the workload-instance value.

The error message names the kind / context, the offending value, its
length, and the values keys to shorten (Helm release name,
.Values.fullnameOverride, or the workload / entry key in values.yaml).

Params: dict "name" "<built-name>" "kind" "<resource-kind-or-context>"
*/}}
{{- define "uhc.assertNameLength" -}}
{{- $name := .name -}}
{{- if gt (len $name) 63 -}}
{{- fail (printf "%s value %q exceeds 63 characters (length=%d). The chart enforces a 63-char ceiling on every constructed name so the value remains a valid k8s DNS-1123 label (used in spec.selector.matchLabels and as the app.kubernetes.io/instance label value). Shorten the Helm release name, .Values.fullnameOverride, or the workload / entry key in values.yaml." .kind $name (len $name)) -}}
{{- end -}}
{{- end }}

{{/*
Fail fast when a constructed name would exceed 253 characters (DNS-1123 subdomain limit).
Used for resource kinds that are not constrained to the stricter 63-char DNS label limit:
ConfigMap, Ingress, HTTPRoute, GRPCRoute, TLSRoute, ReferenceGrant, ServiceMonitor, PodMonitor.
Params: dict "name" "<built-name>" "kind" "<resource-kind-or-context>"
*/}}
{{- define "uhc.assertSubdomainLength" -}}
{{- $name := .name -}}
{{- if gt (len $name) 253 -}}
{{- fail (printf "%s name %q exceeds 253 characters (length=%d). Kubernetes enforces a 253-char ceiling on DNS-1123 subdomain names. Shorten the Helm release name, .Values.fullnameOverride, or the entry key in values.yaml." .kind $name (len $name)) -}}
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
