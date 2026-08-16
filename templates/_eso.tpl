{{/* vim: set filetype=mustache: */}}

{{/*
ESO API version: v1 (ESO >= 0.10) or v1beta1 (ESO < 0.10, removed entirely
in ESO >= 0.17.0).
Detected via .Capabilities.APIVersions.Has — works on live cluster.
Falls back to v1 when rendering offline (helm template without
--kube-version): v1beta1 no longer exists in any current ESO release, so it
would be the wrong guess.
*/}}
{{- define "uhc.esoApiVersion" -}}
{{- if .Capabilities.APIVersions.Has "external-secrets.io/v1" -}}
external-secrets.io/v1
{{- else if .Capabilities.APIVersions.Has "external-secrets.io/v1beta1" -}}
external-secrets.io/v1beta1
{{- else -}}
external-secrets.io/v1
{{- end -}}
{{- end }}
