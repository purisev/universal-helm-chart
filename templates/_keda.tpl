{{/* vim: set filetype=mustache: */}}

{{/*
Resolves whether a workload routes HTTP through the KEDA HTTP add-on. The workload,
its keda block and keda.http each count as enabled once defined, unless they set
enabled: false — the same rule scaledobject.yaml applies to keda itself.
Returns "true" or "".
Params: dict "wl" $wl
*/}}
{{- define "uhc.kedaHttpEnabled" -}}
{{- $wl := .wl -}}
{{- if and (ne (index $wl "enabled") false) $wl.keda (ne (index $wl.keda "enabled") false) $wl.keda.http (ne (index $wl.keda.http "enabled") false) -}}
true
{{- end -}}
{{- end }}

{{/*
Resolves where the KEDA HTTP add-on runs, from integrations.keda.httpAddon. The
defaults match a stock install of the add-on's Helm chart in the keda namespace.
Returns JSON: namespace, interceptorService, port, scalerAddress, clusterDomain.
Params: $ctx (the dot)
*/}}
{{- define "uhc.kedaHttpAddon" -}}
{{- $cfg := ((.Values.integrations | default dict).keda | default dict).httpAddon | default dict -}}
{{- $ns := $cfg.namespace | default "keda" -}}
{{- dict
      "namespace" $ns
      "interceptorService" ($cfg.interceptorService | default "keda-add-ons-http-interceptor-proxy")
      "port" (int ($cfg.port | default 8080))
      "scalerAddress" ($cfg.scalerAddress | default (printf "keda-add-ons-http-external-scaler.%s:9090" $ns))
      "clusterDomain" ($cfg.clusterDomain | default "cluster.local")
    | toJson -}}
{{- end }}

{{/*
Name of the Service that selects the workload's pods while keda.http is on. The
client-facing name becomes an ExternalName for the interceptor, and the interceptor
forwards to this one.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
*/}}
{{- define "uhc.kedaHttpOriginServiceName" -}}
{{- $name := printf "%s-origin" (include "uhc.serviceName" .) -}}
{{- include "uhc.assertNameLength" (dict "name" $name "kind" (printf "origin Service for workload %q" .wlName)) -}}
{{- $name -}}
{{- end }}

{{/*
Services that carry keda.http.directPorts past the interceptor, keyed by Service port.
Each listed service.ports entry gets its own ClusterIP Service <svc>-<portName> that
selects the workload's pods. Names absent from service.ports, http and metrics are
skipped here and rejected by uhc.assertKedaHttp.
Returns JSON: {"<port>": {"portName": ..., "service": ...}}.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
*/}}
{{- define "uhc.kedaHttpDirectServices" -}}
{{- $out := dict -}}
{{- $ports := (.wl.service | default dict).ports | default dict -}}
{{- $svcName := include "uhc.serviceName" . -}}
{{- range $pName := .wl.keda.http.directPorts | default list -}}
  {{- $p := index $ports $pName -}}
  {{- if and $p (not (has $pName (list "http" "metrics"))) -}}
    {{- $name := printf "%s-%s" $svcName $pName -}}
    {{- include "uhc.assertNameLength" (dict "name" $name "kind" (printf "Service for keda.http.directPorts entry %q" $pName)) -}}
    {{- $_ := set $out (toString (int ($p.port | default $p.targetPort))) (dict "portName" $pName "service" $name) -}}
  {{- end -}}
{{- end -}}
{{- $out | toJson -}}
{{- end }}

{{/*
Renders the Services of keda.http.directPorts, one per port. They carry no
prometheus.io/* annotations: scraping stays on the origin Service.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
Emits the leading "---" document separator itself.
*/}}
{{- define "uhc.kedaHttpDirectServicesRender" -}}
{{- $ctx := .ctx }}
{{- $wl := .wl }}
{{- $wlName := .wlName }}
{{- $ports := $wl.service.ports }}
{{- $direct := include "uhc.kedaHttpDirectServices" . | fromJson }}
{{- range $portKey := keys $direct | sortAlpha }}
{{- $d := index $direct $portKey }}
{{- $p := index $ports $d.portName }}
{{- include "uhc.assertServicePortsDeclared" (dict "ports" (dict $d.portName $p) "source" (printf "service.ports for workload %q" $wlName)) }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $d.service }}
  labels:
    {{- include "uhc.workloadLabels" (dict "ctx" $ctx "workloadName" $wlName) | nindent 4 }}
  {{- $annots := include "uhc.metadataAnnotations" (dict "ctx" $ctx "kind" "service") }}
  {{- if $annots }}
  {{- $annots | nindent 2 }}
  {{- end }}
spec:
  type: ClusterIP
  ports:
    - name: {{ $d.portName }}
      port: {{ $p.port | default $p.targetPort }}
      targetPort: {{ $p.targetPort | default $p.port }}
      protocol: {{ $p.protocol | default "TCP" }}
      {{- with $p.appProtocol }}
      appProtocol: {{ . }}
      {{- end }}
  selector:
    {{- include "uhc.workloadSelectorLabels" (dict "ctx" $ctx "workloadName" $wlName) | nindent 4 }}
{{- end }}
{{- end }}

{{/*
Rejects a workload whose Service cannot be put behind the interceptor. Once keda.http
is on, every port of the client-facing Service resolves to the interceptor, which
serves one HTTP port, so the Service may carry only the http port plus metrics (scraped
from pod IPs, never through the Service name). Other ports leave it through
keda.http.directPorts. Ingress paths and HTTPRoute rules that reach the Service by name
must use the interceptor's port, because an ExternalName cannot remap it.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName "kind" "deployments" / "statefulSets"
*/}}
{{- define "uhc.assertKedaHttp" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $path := printf "%s.%s" .kind .wlName -}}
{{- $addon := include "uhc.kedaHttpAddon" $ctx | fromJson -}}
{{- $addonPort := int $addon.port -}}
{{- $svc := $wl.service | default dict -}}
{{- if or (empty $wl.service) (eq (index $svc "enabled") false) -}}
  {{- fail (printf "%s.keda.http puts the workload's Service behind the KEDA HTTP add-on interceptor, but the workload renders no Service. Declare service.ports.http, or service.port / service.targetPort." $path) -}}
{{- end -}}
{{- $type := $svc.type | default "ClusterIP" -}}
{{- if ne $type "ClusterIP" -}}
  {{- fail (printf "%s.keda.http needs a ClusterIP Service, but service.type is %s. The interceptor forwards to a ClusterIP Service only, and a %s Service would carry traffic past it. Remove service.type or set it to ClusterIP." $path $type $type) -}}
{{- end -}}
{{- if eq ($svc.clusterIP | default "") "None" -}}
  {{- fail (printf "%s.keda.http needs a Service with a cluster IP, but service.clusterIP is None. Remove service.clusterIP." $path) -}}
{{- end -}}
{{- $directPorts := $wl.keda.http.directPorts | default list -}}
{{- range $pName := $directPorts -}}
  {{- if has $pName (list "http" "metrics") -}}
    {{- fail (printf "%s.keda.http.directPorts lists %s, which stays on the workload Service: http goes through the interceptor and metrics is scraped from pod IPs. Remove it from directPorts." $path $pName) -}}
  {{- end -}}
  {{- if not (hasKey ($svc.ports | default dict) $pName) -}}
    {{- fail (printf "%s.keda.http.directPorts lists %s, but service.ports has no %s entry. Declare the port under service.ports or remove it from directPorts." $path $pName $pName) -}}
  {{- end -}}
{{- end -}}
{{- if $svc.ports -}}
  {{- if not (hasKey $svc.ports "http") -}}
    {{- fail (printf "%s.keda.http sends the Service port named http through the interceptor, but service.ports has no http entry." $path) -}}
  {{- end -}}
  {{- $extra := list -}}
  {{- range $pName := keys $svc.ports | sortAlpha -}}
    {{- if not (has $pName (concat (list "http" "metrics") $directPorts)) -}}
      {{- $extra = append $extra $pName -}}
    {{- end -}}
  {{- end -}}
  {{- if $extra -}}
    {{- fail (printf "%s.keda.http: service.ports.%s would resolve to the interceptor too, which serves only the http port. List them in keda.http.directPorts to serve them from a Service of their own, past the interceptor, or remove them." $path (join ", service.ports." $extra)) -}}
  {{- end -}}
  {{- $direct := include "uhc.kedaHttpDirectServices" (dict "ctx" $ctx "wl" $wl "wlName" .wlName) | fromJson -}}
  {{- with index $direct (toString $addonPort) -}}
    {{- fail (printf "%s.keda.http.directPorts: service.ports.%s uses port %d, the interceptor port, so a route or Ingress path on that port could mean either. Give it another port." $path .portName $addonPort) -}}
  {{- end -}}
  {{- $httpPort := (index $svc.ports "http" | default dict).port -}}
  {{- if and $httpPort (ne (int $httpPort) $addonPort) -}}
    {{- fail (printf "%s.keda.http: service.ports.http.port is %d, but clients reach the interceptor on port %d (integrations.keda.httpAddon.port). Omit service.ports.http.port to take %d, or make the two equal." $path (int $httpPort) $addonPort $addonPort) -}}
  {{- end -}}
{{- else if and $svc.port (ne (int $svc.port) $addonPort) -}}
  {{- fail (printf "%s.keda.http: service.port is %d, but clients reach the interceptor on port %d (integrations.keda.httpAddon.port). Omit service.port to take %d, or make the two equal." $path (int $svc.port) $addonPort $addonPort) -}}
{{- end -}}
{{- if and $wl.httpRoute (ne (index $wl.httpRoute "enabled") false) -}}
  {{- $direct := include "uhc.kedaHttpDirectServices" (dict "ctx" $ctx "wl" $wl "wlName" .wlName) | fromJson -}}
  {{- range $i, $rule := $wl.httpRoute.rules | default list -}}
    {{- if and (not $rule.backendRefs) (not $rule.serviceName) $rule.servicePort (ne (int $rule.servicePort) $addonPort) (not (hasKey $direct (toString (int $rule.servicePort)))) (ne (include "uhc.httpRouteRuleRedirects" $rule) "true") -}}
      {{- fail (printf "%s.httpRoute.rules[%d].servicePort is %d, but with keda.http the rule goes to the interceptor, which listens on port %d. Remove servicePort or set it to %d; the port of a service.ports entry listed in keda.http.directPorts goes to that entry's own Service." $path $i (int $rule.servicePort) $addonPort $addonPort) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- range $route := list "grpcRoute" "tlsRoute" -}}
  {{- $r := index $wl $route -}}
  {{- if and $r (ne (index $r "enabled") false) -}}
    {{- fail (printf "%s.keda.http and %s.%s cannot be combined: the interceptor serves the http port only. Disable %s on this workload." $path $path $route $route) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Host names the workload's InterceptorRoute answers to. The interceptor picks a route by
the Host header with any port removed, so the list holds every name a caller can use:
the in-cluster forms of the Service name, the root httpRoute.hostnames when the workload
has an httpRoute, the hosts of every Ingress path that targets the Service by name, and
keda.http.hosts. Each Ingress path found here must use the interceptor's port.
Returns a JSON array without duplicates.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName "kind" "deployments" / "statefulSets"
*/}}
{{- define "uhc.kedaHttpHosts" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $path := printf "%s.%s" .kind .wlName -}}
{{- $addon := include "uhc.kedaHttpAddon" $ctx | fromJson -}}
{{- $addonPort := int $addon.port -}}
{{- $svcName := include "uhc.serviceName" (dict "ctx" $ctx "wl" $wl "wlName" .wlName) -}}
{{- $ns := $ctx.Release.Namespace -}}
{{- $releaseName := include "uhc.fullname" $ctx -}}
{{- $hosts := list $svcName (printf "%s.%s" $svcName $ns) (printf "%s.%s.svc" $svcName $ns) (printf "%s.%s.svc.%s" $svcName $ns $addon.clusterDomain) -}}
{{- $direct := include "uhc.kedaHttpDirectServices" (dict "ctx" $ctx "wl" $wl "wlName" .wlName) | fromJson -}}
{{- if and $wl.httpRoute (ne (index $wl.httpRoute "enabled") false) -}}
  {{- range ($ctx.Values.httpRoute.hostnames | default list) -}}
    {{- $hosts = append $hosts (tpl . $ctx | trim) -}}
  {{- end -}}
{{- end -}}
{{- $ingresses := list -}}
{{- if ne (index ($ctx.Values.ingress | default dict) "enabled") false -}}
  {{- $ingresses = append $ingresses (dict "where" "ingress" "spec" $ctx.Values.ingress) -}}
{{- end -}}
{{- range $ingName := keys ($ctx.Values.ingresses | default dict) | sortAlpha -}}
  {{- $ing := index $ctx.Values.ingresses $ingName -}}
  {{- if ne (index $ing "enabled") false -}}
    {{- $ingresses = append $ingresses (dict "where" (printf "ingresses.%s" $ingName) "spec" $ing) -}}
  {{- end -}}
{{- end -}}
{{- range $ingresses -}}
  {{- $where := .where -}}
  {{- $ingHosts := .spec.hosts | default dict -}}
  {{- range $host := keys $ingHosts | sortAlpha -}}
    {{- range $i, $p := (index $ingHosts $host).paths | default list -}}
      {{- if eq ($p.serviceName | default $releaseName) $svcName -}}
        {{- $port := int ($p.servicePort | default 80) -}}
        {{- with index $direct (toString $port) -}}
          {{- fail (printf "%s.hosts.%s.paths[%d] sends traffic to Service %q on port %d, but %s.keda.http serves that port from Service %q. Set serviceName to %q." $where $host $i $svcName $port $path .service .service) -}}
        {{- end -}}
        {{- if ne $port $addonPort -}}
          {{- fail (printf "%s.hosts.%s.paths[%d] sends traffic to Service %q on port %d, but %s.keda.http turns that Service into an ExternalName for the interceptor, which listens on port %d. Set servicePort to %d." $where $host $i $svcName $port $path $addonPort $addonPort) -}}
        {{- end -}}
        {{- $hosts = append $hosts (tpl $host $ctx | trim) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- range ($wl.keda.http.hosts | default list) -}}
  {{- $hosts = append $hosts (tpl . $ctx | trim) -}}
{{- end -}}
{{- $hosts | uniq | toJson -}}
{{- end }}

{{/*
Renders the client-facing Service of a workload with keda.http on: an ExternalName for
the interceptor, keeping the name clients already use. It carries no prometheus.io/*
annotations and selects no pods; scraping goes to the origin Service.
Params: dict "ctx" $ctx "wl" $wl "wlName" $wlName
Emits the leading "---" document separator itself.
*/}}
{{- define "uhc.kedaHttpProxyService" -}}
{{- $ctx := .ctx }}
{{- $addon := include "uhc.kedaHttpAddon" $ctx | fromJson }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "uhc.serviceName" . }}
  labels:
    {{- include "uhc.workloadLabels" (dict "ctx" $ctx "workloadName" .wlName) | nindent 4 }}
  {{- $annots := include "uhc.metadataAnnotations" (dict "ctx" $ctx "kind" "interceptorRoute") }}
  {{- if $annots }}
  {{- $annots | nindent 2 }}
  {{- end }}
spec:
  type: ExternalName
  externalName: {{ printf "%s.%s.svc.%s" $addon.interceptorService $addon.namespace $addon.clusterDomain }}
  ports:
    - name: http
      port: {{ int $addon.port }}
      targetPort: {{ int $addon.port }}
      protocol: TCP
{{- end }}

{{/*
NetworkPolicy ingress rule that admits the interceptor pods, which connect to the
workload's pod IPs directly. Pod labels are those of the add-on's Helm chart.
Params: $ctx (the dot)
*/}}
{{- define "uhc.kedaHttpInterceptorPeer" -}}
{{- $addon := include "uhc.kedaHttpAddon" . | fromJson -}}
from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: {{ $addon.namespace }}
    podSelector:
      matchLabels:
        app.kubernetes.io/component: interceptor
        app.kubernetes.io/name: http-add-on
{{- end }}
