{{/* vim: set filetype=mustache: */}}

{{/*
Resolves the name of a workload's client-facing Service: service.nameOverride when set,
otherwise <fullname>-<workloadName>. Every reference to that Service goes through this
helper — the Service object itself and the Gateway API backendRefs that default to it —
so an override stays consistent across the release.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
*/}}
{{- define "uhc.serviceName" -}}
{{- $svc := .wl.service | default dict -}}
{{- $name := $svc.nameOverride | default (include "uhc.workloadResourceName" (dict "ctx" .ctx "wlName" .wlName)) -}}
{{- include "uhc.assertNameLength" (dict "name" $name "kind" (printf "Service for workload %q" .wlName)) -}}
{{- $name -}}
{{- end }}

{{/*
Resolves the name of a StatefulSet's governing headless Service:
headlessService.nameOverride, then the older serviceName spelling, otherwise
<fullname>-<workloadName>-headless. With headlessService.enabled=false the resolved
value names an externally managed Service that spec.serviceName points at.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
*/}}
{{- define "uhc.headlessServiceName" -}}
{{- $hs := .wl.headlessService | default dict -}}
{{- $default := printf "%s-headless" (include "uhc.workloadResourceName" (dict "ctx" .ctx "wlName" .wlName)) -}}
{{- $name := $hs.nameOverride | default .wl.serviceName | default $default -}}
{{- include "uhc.assertNameLength" (dict "name" $name "kind" (printf "headless Service for StatefulSet workload %q" .wlName)) -}}
{{- $name -}}
{{- end }}

{{/*
Resolves the name of the metrics-only Service the chart renders for a workload that
exposes a metrics port but has no Service of its own. Returns "" when no such Service
is rendered — the workload already has a Service to carry the port, or nothing exposes
one. Both the renderer and uhc.assertUniqueServiceNames resolve the name through here,
so the two cannot disagree about which workloads claim it.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
*/}}
{{- define "uhc.metricsOnlyServiceName" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $wlName := .wlName -}}
{{- $exposeJson := include "uhc.metricsExposeService" (dict "ctx" $ctx "wl" $wl) -}}
{{- $metricsType := ($wl.metrics | default dict).type | default (($ctx.Values.integrations.monitoring.defaults | default dict).type | default "service") -}}
{{- $svcEnabled := and $wl.service (ne (index $wl.service "enabled") false) -}}
{{- if and $exposeJson (ne $metricsType "pod") (not $svcEnabled) -}}
{{- $name := printf "%s-metrics" (include "uhc.workloadResourceName" (dict "ctx" $ctx "wlName" $wlName)) -}}
{{- include "uhc.assertNameLength" (dict "name" $name "kind" (printf "standalone metrics Service for workload %q" $wlName)) -}}
{{- $name -}}
{{- end -}}
{{- end }}

{{/*
Fail fast when two workloads resolve to the same Service name. Defaults never collide,
so a duplicate always comes from service.nameOverride or headlessService.nameOverride
(or the older serviceName spelling) — and it renders two Service documents under one
name, which Kubernetes rejects on apply and a server-side-apply controller turns into
two owners fighting over one object's selector.

Covers every Service name the chart puts on the cluster: each workload's own Service,
the metrics-only Service a Deployment gets when it exposes metrics without a Service of
its own, and, for StatefulSets, the governing headless Service while the chart renders
it.

A headless name under headlessService.enabled: false names a Service the chart does not
render, so it claims nothing — but it still has to resolve to a headless Service that
selects this StatefulSet's own pods, or stable per-pod DNS silently never works. Inside
the release only one shape qualifies: the workload's own client Service with
clusterIP: None. Every other claim it lands on is rejected once all of them are known.
Params: $ctx (the dot)
*/}}
{{- define "uhc.assertUniqueServiceNames" -}}
{{- $ctx := . -}}
{{- $seen := dict -}}
{{- range $kind := (list "deployments" "statefulSets") -}}
  {{- $specs := index $ctx.Values $kind | default dict -}}
  {{- range $wlName := keys $specs | sortAlpha -}}
    {{- $wl := index $specs $wlName -}}
    {{- if ne (index $wl "enabled") false -}}
      {{- $claims := dict -}}
      {{- if and $wl.service (ne (index $wl.service "enabled") false) -}}
        {{- $_ := set $claims (include "uhc.serviceName" (dict "ctx" $ctx "wl" $wl "wlName" $wlName)) (printf "%s.%s.service" $kind $wlName) -}}
      {{- end -}}
      {{- if eq $kind "deployments" -}}
        {{- $metricsName := include "uhc.metricsOnlyServiceName" (dict "ctx" $ctx "wl" $wl "wlName" $wlName) -}}
        {{- if $metricsName -}}
          {{- $_ := set $claims $metricsName (printf "%s.%s.metrics.exposeService" $kind $wlName) -}}
        {{- end -}}
      {{- end -}}
      {{- if and (eq $kind "statefulSets") (ne (index ($wl.headlessService | default dict) "enabled") false) -}}
        {{- $hsName := include "uhc.headlessServiceName" (dict "ctx" $ctx "wl" $wl "wlName" $wlName) -}}
        {{- if hasKey $claims $hsName -}}
          {{- fail (printf "Service name %q is claimed by both statefulSets.%s.service and statefulSets.%s.headlessService. A StatefulSet's client Service and its governing headless Service are two separate objects and cannot share a name." $hsName $wlName $wlName) -}}
        {{- end -}}
        {{- $_ := set $claims $hsName (printf "%s.%s.headlessService" $kind $wlName) -}}
      {{- end -}}
      {{- range $name, $origin := $claims -}}
        {{- if hasKey $seen $name -}}
          {{- fail (printf "Service name %q is claimed by both %s and %s. Two Services cannot share a name in one namespace; give one of them a different service.nameOverride / headlessService.nameOverride." $name (index $seen $name) $origin) -}}
        {{- end -}}
        {{- $_ := set $seen $name $origin -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $statefulSets := $ctx.Values.statefulSets | default dict -}}
{{- range $wlName := keys $statefulSets | sortAlpha -}}
  {{- $wl := index $statefulSets $wlName -}}
  {{- if and (ne (index $wl "enabled") false) (eq (index ($wl.headlessService | default dict) "enabled") false) -}}
    {{- $hsName := include "uhc.headlessServiceName" (dict "ctx" $ctx "wl" $wl "wlName" $wlName) -}}
    {{- /* A client Service with clusterIP: None is a headless Service selecting this
       workload's own pods, so pointing spec.serviceName at it is the one in-release
       target that carries per-pod DNS. Any other claim is not. */ -}}
    {{- $ownSvc := $wl.service | default dict -}}
    {{- $reusesOwnHeadless := and (eq (index $seen $hsName | default "") (printf "statefulSets.%s.service" $wlName)) (eq ($ownSvc.clusterIP | default "") "None") -}}
    {{- if and (hasKey $seen $hsName) (not $reusesOwnHeadless) -}}
      {{- fail (printf "statefulSets.%s.headlessService is disabled, so spec.serviceName points at %q — but that name belongs to %s, a Service this chart renders itself. A governing Service has to be headless and select this StatefulSet's own pods, or per-pod DNS never resolves. Enable headlessService, or point the override at an externally managed headless Service." $wlName $hsName (index $seen $hsName)) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Renders one complete, independent Service document from a workload's $wl.service
block. Used by Deployment and StatefulSet — for StatefulSet this is always a
second, separate object alongside the headless Service (never merged into it);
see uhc.headlessService for the governing-service counterpart.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
        "injectMetricsPort" bool "exposeJson" (JSON string or "")
Emits the leading "---" document separator itself.
*/}}
{{- define "uhc.plainService" -}}
{{- $ctx := .ctx }}
{{- $wl := .wl }}
{{- $wlName := .wlName }}
{{- $svc := $wl.service }}
{{- $promAnnots := include "uhc.metricsAnnotations" (dict "ctx" $ctx "wl" $wl "kind" "service") }}
{{- $extra := mergeOverwrite (deepCopy ($svc.annotations | default dict)) (($promAnnots | fromYaml) | default dict) }}
{{- $svcName := include "uhc.serviceName" (dict "ctx" $ctx "wl" $wl "wlName" $wlName) }}
{{- include "uhc.assertServicePortsDeclared" (dict "ports" $svc.ports "source" (printf "service.ports for workload %q" $wlName)) }}
{{- if and $svc.targetPort (not $svc.port) }}
{{- include "uhc.assertServicePortsDeclared" (dict "ports" (dict "http" (dict "targetPort" $svc.targetPort)) "source" (printf "service for workload %q" $wlName)) }}
{{- end }}
{{- $hasPorts := or $svc.ports $svc.port $svc.targetPort .injectMetricsPort }}
{{- /* ExternalName resolves to a DNS name and carries no virtual IP, so Kubernetes
     treats its ports as optional and ignores them. Every other type needs at least one:
     unlike headlessService, a client-facing Service has no port to fall back on. */ -}}
{{- if and (not $hasPorts) (ne ($svc.type | default "ClusterIP") "ExternalName") }}
{{- fail (printf "Service for workload %q declares no port. Set service.ports.<name>.port for the map form, or service.port / service.targetPort for the single-port form." $wlName) }}
{{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $svcName }}
  labels:
    {{- include "uhc.workloadLabels" (dict "ctx" $ctx "workloadName" $wlName) | nindent 4 }}
  {{- $annots := include "uhc.metadataAnnotations" (dict "ctx" $ctx "kind" "service" "extra" $extra) }}
  {{- if $annots }}
  {{- $annots | nindent 2 }}
  {{- end }}
spec:
  type: {{ $svc.type | default "ClusterIP" }}
  {{- with $svc.clusterIP }}
  clusterIP: {{ . }}
  {{- end }}
  {{- with $svc.clusterIPs }}
  clusterIPs:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $svc.externalName }}
  externalName: {{ . }}
  {{- end }}
  {{- with $svc.externalIPs }}
  externalIPs:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $svc.loadBalancerIP }}
  loadBalancerIP: {{ . }}
  {{- end }}
  {{- with $svc.loadBalancerClass }}
  loadBalancerClass: {{ . }}
  {{- end }}
  {{- with $svc.loadBalancerSourceRanges }}
  loadBalancerSourceRanges:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if hasKey $svc "allocateLoadBalancerNodePorts" }}
  allocateLoadBalancerNodePorts: {{ $svc.allocateLoadBalancerNodePorts }}
  {{- end }}
  {{- with $svc.healthCheckNodePort }}
  healthCheckNodePort: {{ . }}
  {{- end }}
  {{- with $svc.externalTrafficPolicy }}
  externalTrafficPolicy: {{ . }}
  {{- end }}
  {{- with $svc.internalTrafficPolicy }}
  internalTrafficPolicy: {{ . }}
  {{- end }}
  {{- with $svc.sessionAffinity }}
  sessionAffinity: {{ . }}
  {{- end }}
  {{- with $svc.sessionAffinityConfig }}
  sessionAffinityConfig:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $svc.ipFamilies }}
  ipFamilies:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $svc.ipFamilyPolicy }}
  ipFamilyPolicy: {{ . }}
  {{- end }}
  {{- with $svc.trafficDistribution }}
  trafficDistribution: {{ . }}
  {{- end }}
  {{- if hasKey $svc "publishNotReadyAddresses" }}
  publishNotReadyAddresses: {{ $svc.publishNotReadyAddresses }}
  {{- end }}
  {{- if $hasPorts }}
  ports:
    {{- if $svc.ports }}
    {{- range $pName := include "uhc.orderedPortNames" $svc.ports | fromJsonArray }}
    {{- $p := index $svc.ports $pName }}
    - name: {{ $pName }}
      port: {{ $p.port | default $p.targetPort }}
      targetPort: {{ $p.targetPort | default $p.port }}
      protocol: {{ $p.protocol | default "TCP" }}
      {{- with $p.appProtocol }}
      appProtocol: {{ . }}
      {{- end }}
    {{- end }}
    {{- else if or $svc.port $svc.targetPort }}
    - port: {{ $svc.port | default $svc.targetPort }}
      targetPort: {{ $svc.targetPort | default $svc.port }}
      protocol: TCP
      name: http
      {{- with $svc.appProtocol }}
      appProtocol: {{ . }}
      {{- end }}
    {{- end }}
    {{- if .injectMetricsPort }}
    {{- $expose := .exposeJson | fromJson }}
    - name: metrics
      port: {{ $expose.port }}
      targetPort: {{ $expose.targetPort }}
      protocol: TCP
    {{- end }}
  {{- end }}
  selector:
    {{- include "uhc.workloadSelectorLabels" (dict "ctx" $ctx "workloadName" $wlName) | nindent 4 }}
{{- end }}

{{/*
Renders the headless (governing) Service for a StatefulSet workload:
clusterIP: None, fields sourced from $wl.headlessService (not $wl.service —
those two blocks are independent; see uhc.plainService for the client-facing
Service). Only ports, annotations, publishNotReadyAddresses, ipFamilies, and
ipFamilyPolicy are exposed here — type, the loadBalancer fields, the traffic
policy fields, and the sessionAffinity fields have no meaning without a
virtual IP, which a headless Service never has.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
        "injectMetricsPort" bool "exposeJson" (JSON string or "")
Emits the leading "---" document separator itself.
*/}}
{{- define "uhc.headlessService" -}}
{{- $ctx := .ctx }}
{{- $wl := .wl }}
{{- $wlName := .wlName }}
{{- $hs := $wl.headlessService | default dict }}
{{- $promAnnots := include "uhc.metricsAnnotations" (dict "ctx" $ctx "wl" $wl "kind" "service") }}
{{- $extra := mergeOverwrite (deepCopy ($hs.annotations | default dict)) (($promAnnots | fromYaml) | default dict) }}
{{- $headlessName := include "uhc.headlessServiceName" (dict "ctx" $ctx "wl" $wl "wlName" $wlName) }}
{{- include "uhc.assertServicePortsDeclared" (dict "ports" $hs.ports "source" (printf "headlessService.ports for workload %q" $wlName)) }}
{{- if and $hs.targetPort (not $hs.port) }}
{{- include "uhc.assertServicePortsDeclared" (dict "ports" (dict "http" (dict "targetPort" $hs.targetPort)) "source" (printf "headlessService for workload %q" $wlName)) }}
{{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $headlessName }}
  labels:
    {{- include "uhc.workloadLabels" (dict "ctx" $ctx "workloadName" $wlName) | nindent 4 }}
  {{- $annots := include "uhc.metadataAnnotations" (dict "ctx" $ctx "kind" "service" "extra" $extra) }}
  {{- if $annots }}
  {{- $annots | nindent 2 }}
  {{- end }}
spec:
  clusterIP: None
  {{- with $hs.ipFamilies }}
  ipFamilies:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $hs.ipFamilyPolicy }}
  ipFamilyPolicy: {{ . }}
  {{- end }}
  {{- if hasKey $hs "publishNotReadyAddresses" }}
  publishNotReadyAddresses: {{ $hs.publishNotReadyAddresses }}
  {{- end }}
  ports:
    {{- if $hs.ports }}
    {{- range $pName := include "uhc.orderedPortNames" $hs.ports | fromJsonArray }}
    {{- $p := index $hs.ports $pName }}
    - name: {{ $pName }}
      port: {{ $p.port | default $p.targetPort }}
      targetPort: {{ $p.targetPort | default $p.port }}
      protocol: {{ $p.protocol | default "TCP" }}
      {{- with $p.appProtocol }}
      appProtocol: {{ . }}
      {{- end }}
    {{- end }}
    {{- else if or $hs.port $hs.targetPort }}
    - name: http
      port: {{ $hs.port | default $hs.targetPort }}
      targetPort: {{ $hs.targetPort | default $hs.port }}
      protocol: TCP
      {{- with $hs.appProtocol }}
      appProtocol: {{ . }}
      {{- end }}
    {{- else }}
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
    {{- end }}
    {{- if .injectMetricsPort }}
    {{- $expose := .exposeJson | fromJson }}
    - name: metrics
      port: {{ $expose.port }}
      targetPort: {{ $expose.targetPort }}
      protocol: TCP
    {{- end }}
  selector:
    {{- include "uhc.workloadSelectorLabels" (dict "ctx" $ctx "workloadName" $wlName) | nindent 4 }}
{{- end }}
