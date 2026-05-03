{{/* vim: set filetype=mustache: */}}

{{/*
Combined map of all long-running workloads (Deployments + StatefulSets), enabled only.
Jobs and CronJobs are intentionally excluded — monitoring should not target short-lived pods.
Returns JSON so callers can use: include "uhc.serviceWorkloads" . | fromJson
*/}}
{{- define "uhc.serviceWorkloads" -}}
{{- $result := dict -}}
{{- range $name, $spec := (.Values.deployments | default dict) -}}
  {{- if ne (index $spec "enabled") false -}}
    {{- $_ := set $result $name $spec -}}
  {{- end -}}
{{- end -}}
{{- range $name, $spec := (.Values.statefulSets | default dict) -}}
  {{- if ne (index $spec "enabled") false -}}
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
{{- if hasKey $wl "metrics" -}}
  {{- if ne (index $metrics "enabled") false -}}true{{- end -}}
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
