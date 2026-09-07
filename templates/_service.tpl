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
    {{- else }}
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
