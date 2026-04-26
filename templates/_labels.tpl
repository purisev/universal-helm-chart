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
{{- $instance := printf "%s-%s" $fullName $wlName -}}
{{- include "uhc.assertNameLength" (dict "name" $instance "kind" (printf "label app.kubernetes.io/instance for workload %q" $wlName)) -}}
{{- $std := $ctx.Values.labels.standard | default dict -}}
{{- $stdLabels := dict -}}
{{- $_ := set $stdLabels "app.kubernetes.io/name" $wlName -}}
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
{{- $fullName := include "uhc.fullname" .ctx -}}
{{- $instance := printf "%s-%s" $fullName .workloadName -}}
{{- include "uhc.assertNameLength" (dict "name" $instance "kind" (printf "selector label app.kubernetes.io/instance for workload %q" .workloadName)) -}}
app.kubernetes.io/name: {{ .workloadName }}
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
