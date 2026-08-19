{{/* vim: set filetype=mustache: */}}

{{/*
Asserts the cluster's Gateway API CRDs accept HTTPRouteRule.name.
The field was added in Gateway API v1.2.0 in the Experimental channel and graduated to
the Standard channel in v1.4.0. To detect either of those installations:
  - v1.4+ Standard: BackendTLSPolicy graduated to gateway.networking.k8s.io/v1 in v1.4.0.
  - Experimental (any version since v1.2): TCPRoute is still in v1alpha2 as of v1.5.1.
Skipped when gateway.networking.k8s.io/v1 is absent (offline helm template run) —
the API server will enforce the field requirement on apply.
*/}}
{{- define "uhc.assertGatewayApiSupportsRuleName" -}}
{{- if .Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1" -}}
  {{- $hasV14Standard := .Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1/BackendTLSPolicy" -}}
  {{- $hasExperimental := .Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1alpha2/TCPRoute" -}}
  {{- if and (not $hasV14Standard) (not $hasExperimental) -}}
    {{- fail "HTTPRoute rule.name requires Gateway API v1.4+ Standard CRDs (graduated in v1.4.0) or Experimental channel CRDs (since v1.2.0). The cluster has gateway.networking.k8s.io/v1 but neither marker is present (BackendTLSPolicy v1, TCPRoute v1alpha2). Upgrade Standard CRDs to v1.4+ or install the Experimental channel, or remove rule.name." -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Asserts the cluster has Gateway API Experimental channel CRDs when a rule uses retry.
HTTPRouteRule.retry is in the Experimental channel as of Gateway API v1.5.1 — Standard
CRDs reject the field. Detected via TCPRoute (still v1alpha2 / Experimental in v1.5.1).
Skipped when gateway.networking.k8s.io/v1 is absent (offline helm template run).
*/}}
{{- define "uhc.assertGatewayApiSupportsRetry" -}}
{{- if .Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1" -}}
  {{- if not (.Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1alpha2/TCPRoute") -}}
    {{- fail "HTTPRoute rule.retry requires Gateway API Experimental channel CRDs (still Experimental as of v1.5.1). The cluster has gateway.networking.k8s.io/v1 but no Experimental marker (TCPRoute v1alpha2) is present. Install the Experimental channel — see https://gateway-api.sigs.k8s.io/concepts/versioning/#release-channels — or remove rule.retry." -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Asserts the cluster has Gateway API Experimental channel CRDs when a rule uses
sessionPersistence. HTTPRouteRule.sessionPersistence is in the Experimental channel
as of Gateway API v1.5.1 — Standard CRDs reject the field. Detected via TCPRoute
(still v1alpha2 / Experimental in v1.5.1).
Skipped when gateway.networking.k8s.io/v1 is absent (offline helm template run).
*/}}
{{- define "uhc.assertGatewayApiSupportsSessionPersistence" -}}
{{- if .Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1" -}}
  {{- if not (.Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1alpha2/TCPRoute") -}}
    {{- fail "HTTPRoute rule.sessionPersistence requires Gateway API Experimental channel CRDs (still Experimental as of v1.5.1). The cluster has gateway.networking.k8s.io/v1 but no Experimental marker (TCPRoute v1alpha2) is present. Install the Experimental channel — see https://gateway-api.sigs.k8s.io/concepts/versioning/#release-channels — or remove rule.sessionPersistence." -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Normalizes a Gateway API parentRefs list by filling group/kind with the values
the API server itself defaults them to when omitted (group:
gateway.networking.k8s.io, kind: Gateway). Existing fields always win.

Without this, a sync using ServerSideApply=true perpetually reports parentRefs
as OutOfSync: it's an atomic list (no merge key), so once ArgoCD's field
manager owns the whole list, the API server filling in group/kind on an entry
we already "fully" specified computes as a pending patch back to our
(shorter) version — forever OutOfSync even though nothing meaningful differs.

Input: a parentRefs list (list of dicts).
*/}}
{{- define "uhc.gatewayParentRefs" -}}
{{- $out := list -}}
{{- range $ref := . -}}
{{- $out = append $out (merge (deepCopy $ref) (dict "group" "gateway.networking.k8s.io" "kind" "Gateway")) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}

{{/*
Normalizes a Gateway API backendRefs list the same way uhc.gatewayParentRefs
does for parentRefs (see that comment for why): group: "" (core API group),
kind: Service, weight: 1 — the defaults the API server itself fills in.
*/}}
{{- define "uhc.gatewayBackendRefs" -}}
{{- $out := list -}}
{{- range $ref := . -}}
{{- $out = append $out (merge (deepCopy $ref) (dict "group" "" "kind" "Service" "weight" 1)) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}

{{/*
Renders a single HTTPRoute rule body (without the leading `-`). Centralises the
field order — name, matches, filters, timeouts, retry, sessionPersistence,
backendRefs — across the three render sites in httproute.yaml (root rules,
per-workload rules, plural map).

Input dict:
  ctx              — root template context (for capability assertions)
  rule             — the rule entry (map)
  defaultBackend   — fallback backend name (string, used when rule.backendRefs is empty)
  defaultPort      — fallback backend port (int)

Output is the joined rule fields as multi-line YAML with no leading or trailing
newline. The caller wraps it under a list-item dash via the standard
`nindent N | trimPrefix "\n<N spaces>"` idiom so the first key sits inline with
the dash (e.g. `- name: foo` rather than an orphan dash on its own line).
*/}}
{{- define "uhc.httpRouteRuleSpec" -}}
{{- $ctx := .ctx -}}
{{- $rule := .rule -}}
{{- $defaultBackend := .defaultBackend -}}
{{- $defaultPort := .defaultPort -}}
{{- $blocks := list -}}
{{- if $rule.name -}}
{{- include "uhc.assertGatewayApiSupportsRuleName" $ctx -}}
{{- $blocks = append $blocks (printf "name: %s" ($rule.name | quote)) -}}
{{- end -}}
{{- with $rule.matches -}}
{{- $blocks = append $blocks (printf "matches:\n%s" (toYaml . | indent 2 | trimSuffix "\n")) -}}
{{- end -}}
{{- with $rule.filters -}}
{{- $blocks = append $blocks (printf "filters:\n%s" (toYaml . | indent 2 | trimSuffix "\n")) -}}
{{- end -}}
{{- with $rule.timeouts -}}
{{- $blocks = append $blocks (printf "timeouts:\n%s" (toYaml . | indent 2 | trimSuffix "\n")) -}}
{{- end -}}
{{- if $rule.retry -}}
{{- include "uhc.assertGatewayApiSupportsRetry" $ctx -}}
{{- $blocks = append $blocks (printf "retry:\n%s" (toYaml $rule.retry | indent 2 | trimSuffix "\n")) -}}
{{- end -}}
{{- if $rule.sessionPersistence -}}
{{- include "uhc.assertGatewayApiSupportsSessionPersistence" $ctx -}}
{{- $blocks = append $blocks (printf "sessionPersistence:\n%s" (toYaml $rule.sessionPersistence | indent 2 | trimSuffix "\n")) -}}
{{- end -}}
{{- $backendRefs := $rule.backendRefs | default (list (dict "name" ($rule.serviceName | default $defaultBackend) "port" ($rule.servicePort | default $defaultPort))) -}}
{{- $blocks = append $blocks (printf "backendRefs:\n%s" (include "uhc.gatewayBackendRefs" $backendRefs | indent 2 | trimSuffix "\n")) -}}
{{- join "\n" $blocks -}}
{{- end }}

{{/*
Renders a single GRPCRoute rule body (without the leading `-`). Mirrors
uhc.httpRouteRuleSpec but for GRPCRouteRule, whose Gateway API spec defines
only: name, matches, filters, backendRefs, sessionPersistence (no timeouts,
no retry — those are HTTPRoute-only fields).

Input dict:
  ctx              — root template context (for capability assertions)
  rule             — the rule entry (map)
  defaultBackend   — fallback backend name (string, used when rule.backendRefs is empty)
  defaultPort      — fallback backend port (int, typically 50051 for gRPC)

Output is the joined rule fields as multi-line YAML with no leading or trailing
newline. The caller wraps it under a list-item dash via the standard
`nindent N | trimPrefix "\n<N spaces>"` idiom.
*/}}
{{- define "uhc.grpcRouteRuleSpec" -}}
{{- $ctx := .ctx -}}
{{- $rule := .rule -}}
{{- $defaultBackend := .defaultBackend -}}
{{- $defaultPort := .defaultPort -}}
{{- $blocks := list -}}
{{- if $rule.name -}}
{{- include "uhc.assertGatewayApiSupportsRuleName" $ctx -}}
{{- $blocks = append $blocks (printf "name: %s" ($rule.name | quote)) -}}
{{- end -}}
{{- with $rule.matches -}}
{{- /* GRPCRouteMatch.method.type defaults to "Exact" server-side when a
method match is set without one — normalize it here for the same reason
uhc.gatewayParentRefs normalizes group/kind (see that comment). */ -}}
{{- $matches := list -}}
{{- range $m := . -}}
{{- if $m.method -}}
{{- $m = merge (deepCopy $m) (dict "method" (merge (deepCopy $m.method) (dict "type" "Exact"))) -}}
{{- end -}}
{{- $matches = append $matches $m -}}
{{- end -}}
{{- $blocks = append $blocks (printf "matches:\n%s" (toYaml $matches | indent 2 | trimSuffix "\n")) -}}
{{- end -}}
{{- with $rule.filters -}}
{{- $blocks = append $blocks (printf "filters:\n%s" (toYaml . | indent 2 | trimSuffix "\n")) -}}
{{- end -}}
{{- if $rule.sessionPersistence -}}
{{- include "uhc.assertGatewayApiSupportsSessionPersistence" $ctx -}}
{{- $blocks = append $blocks (printf "sessionPersistence:\n%s" (toYaml $rule.sessionPersistence | indent 2 | trimSuffix "\n")) -}}
{{- end -}}
{{- $backendRefs := $rule.backendRefs | default (list (dict "name" ($rule.serviceName | default $defaultBackend) "port" ($rule.servicePort | default $defaultPort))) -}}
{{- $blocks = append $blocks (printf "backendRefs:\n%s" (include "uhc.gatewayBackendRefs" $backendRefs | indent 2 | trimSuffix "\n")) -}}
{{- join "\n" $blocks -}}
{{- end }}

{{/*
Renders a single TLSRoute rule body (without the leading `-`). TLSRouteRule
in the Gateway API spec is minimal: only name and backendRefs. TLS is L4 —
matches/filters/timeouts/retry/sessionPersistence are not defined.

TLSRoute itself is Experimental-only (still v1alpha2 in Gateway API v1.5.x),
so any use of TLSRoute presupposes the Experimental channel; no separate
field-level capability guard is needed for `name`.

Input dict:
  rule             — the rule entry (map)
  defaultBackend   — fallback backend name (string, used when rule.backendRefs is empty)
  defaultPort      — fallback backend port (int, typically 443 for TLS passthrough)
*/}}
{{- define "uhc.tlsRouteRuleSpec" -}}
{{- $rule := .rule -}}
{{- $defaultBackend := .defaultBackend -}}
{{- $defaultPort := .defaultPort -}}
{{- $blocks := list -}}
{{- if $rule.name -}}
{{- $blocks = append $blocks (printf "name: %s" ($rule.name | quote)) -}}
{{- end -}}
{{- $backendRefs := $rule.backendRefs | default (list (dict "name" ($rule.serviceName | default $defaultBackend) "port" ($rule.servicePort | default $defaultPort))) -}}
{{- $blocks = append $blocks (printf "backendRefs:\n%s" (include "uhc.gatewayBackendRefs" $backendRefs | indent 2 | trimSuffix "\n")) -}}
{{- join "\n" $blocks -}}
{{- end }}
