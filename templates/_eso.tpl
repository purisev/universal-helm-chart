{{/* vim: set filetype=mustache: */}}

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
