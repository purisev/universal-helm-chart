{{/* vim: set filetype=mustache: */}}

{{/*
Fail-fast guard: aborts rendering if any legacy job-related top-level value is present.
The dbJob/initJob/postSync/cronJobs blocks were removed in favour of jobGroups; charts
that still carry them would silently render zero Jobs. We catch that here with a clear
migration message.
Params: $ctx
*/}}
{{- define "uhc.assertNoLegacyJobKeys" -}}
{{- $ctx := . -}}
{{- range $k := list "dbJob" "initJob" "postSync" "cronJobs" -}}
  {{- if hasKey $ctx.Values $k -}}
    {{- fail (printf "Legacy values key '%s' is no longer supported. Migrate to jobGroups (see jobGroups example in values.yaml)." $k) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Truncates a name segment to 8 characters when longer.
Used to keep jobGroups resource names short enough to fit the k8s 63-char DNS limit
even after the release prefix and sha8 suffix are added.
Params: name string
*/}}
{{- define "uhc.jobGroupTruncSegment" -}}
{{- $name := . -}}
{{- if gt (len $name) 8 -}}
{{- $name | trunc 8 -}}
{{- else -}}
{{- $name -}}
{{- end -}}
{{- end -}}

{{/*
Workload name for jobGroups: "{trunc-group}-{job}" used as workloadName in
uhc.workloadLabels / uhc.workloadSelectorLabels. Group is truncated to 8 chars to keep
the resource name within the k8s 63-char DNS limit; job names are kept verbatim because
they tend to be descriptive ("migrate", "cleanup-orphans") and truncating them invites
collisions ("migrations-old" and "migrations-new" both becoming "migratio").
Params: dict "groupName" $g "jobName" $j
*/}}
{{- define "uhc.jobGroupName" -}}
{{- $g := include "uhc.jobGroupTruncSegment" .groupName -}}
{{- printf "%s-%s" $g .jobName -}}
{{- end -}}

{{/*
Merges group spec with per-job spec, applying:
  - Maps merged, job wins (env, image, securityContext, podSecurityContext, resources,
    nodeSelector, affinity, metadataAnnotations, inherit, hooks.argocd, hooks.helm)
  - Lists concatenated, group then job (envSecrets, envConfigMaps, tolerations).
    tolerations is only set on the merged spec when group or job declares it
    (even as []); otherwise the key is left absent so uhc.scheduling falls
    back to root tolerations, same as nodeSelector/affinity.
  - Name-keyed maps merged, job wins on collisions (volumes, volumeMounts)
  - Scalars: job-override-else-group (backoffLimit, completions, parallelism, suspend,
    podFailurePolicy, ttlSecondsAfterFinished, activeDeadlineSeconds, restartPolicy, completionImage, serviceAccountName,
    automountServiceAccountToken, terminationGracePeriodSeconds, useRootVolumes,
    useRootVolumeMounts, hashSuffix, hashIncludePodAnnotations, schedule, timeZone,
    concurrencyPolicy, successfulJobsHistoryLimit, failedJobsHistoryLimit,
    startingDeadlineSeconds, command, args, tasks)
  - kind: from group only (per-job override intentionally not supported)
  - podAnnotations: full effective merge of root .Values.podAnnotations,
    .Values.jobPodAnnotations, group.podAnnotations and job.podAnnotations
    (job > group > jobPodAnnotations > podAnnotations). Stored on $merged.podAnnotations
    so the rendered Pod template uses it directly and uhc.jobGroupHash sees the same
    final value (controlled by hashIncludePodAnnotations, default true).
Fails fast when:
  - Job sets both `tasks` and `command`/`args`
  - kind=CronJob without `schedule` on the job
  - kind=CronJob with any non-empty hooks (ArgoCD/Helm hooks aren't applied to CronJob)
  - hashSuffix=true together with deletePolicy=HookSucceeded (argocd) or
    deletePolicy=hook-succeeded (helm) — that combination breaks idempotency.
Returns merged spec as YAML.
Params: dict "ctx" $ctx "group" $group "job" $job "groupName" $g "jobName" $j
*/}}
{{- define "uhc.jobGroupSpec" -}}
{{- $ctx := .ctx -}}
{{- $group := .group | default dict -}}
{{- $job := .job | default dict -}}
{{- $gn := .groupName -}}
{{- $jn := .jobName -}}
{{- if and ($job.tasks) (or $job.command $job.args) -}}
{{- fail (printf "jobGroups.%s.jobs.%s: cannot set both 'tasks' and 'command/args'" $gn $jn) -}}
{{- end -}}
{{- /* kind is set at the group level only — per-job override is intentionally not supported */ -}}
{{- $kind := default "Job" $group.kind -}}
{{- if and (eq $kind "CronJob") (not $job.schedule) -}}
{{- fail (printf "jobGroups.%s.jobs.%s.schedule is required when kind: CronJob" $gn $jn) -}}
{{- end -}}
{{- $merged := dict -}}
{{- $_ := set $merged "kind" $kind -}}
{{/* Maps: merge $job $group → job wins */}}
{{- $_ := set $merged "env" (merge ($job.env | default dict) ($group.env | default dict)) -}}
{{- $rootImage := dict -}}
{{- if $ctx -}}{{- $rootImage = $ctx.Values.image | default dict -}}{{- end -}}
{{- $_ := set $merged "image" (merge ($job.image | default dict) ($group.image | default dict) $rootImage) -}}
{{- $_ := set $merged "metadataAnnotations" (merge ($job.metadataAnnotations | default dict) ($group.metadataAnnotations | default dict)) -}}
{{- $_ := set $merged "securityContext" (merge ($job.securityContext | default dict) ($group.securityContext | default dict)) -}}
{{- $_ := set $merged "podSecurityContext" (merge ($job.podSecurityContext | default dict) ($group.podSecurityContext | default dict)) -}}
{{- $_ := set $merged "resources" (merge ($job.resources | default dict) ($group.resources | default dict)) -}}
{{- $_ := set $merged "nodeSelector" (merge ($job.nodeSelector | default dict) ($group.nodeSelector | default dict)) -}}
{{- $_ := set $merged "affinity" (merge ($job.affinity | default dict) ($group.affinity | default dict)) -}}
{{- $_ := set $merged "inherit" (merge ($job.inherit | default dict) ($group.inherit | default dict)) -}}
{{/* podAnnotations: full effective merge across all sources (job > group > jobPodAnnotations > podAnnotations) */}}
{{- $rootPodAnn := dict -}}
{{- $rootJobPodAnn := dict -}}
{{- if $ctx -}}
  {{- $rootPodAnn = $ctx.Values.podAnnotations | default dict -}}
  {{- $rootJobPodAnn = $ctx.Values.jobPodAnnotations | default dict -}}
{{- end -}}
{{- $effPodAnn := merge ($job.podAnnotations | default dict) ($group.podAnnotations | default dict) $rootJobPodAnn $rootPodAnn -}}
{{- if $effPodAnn -}}
{{- $_ := set $merged "podAnnotations" $effPodAnn -}}
{{- end -}}
{{/* hooks: per-provider deep merge */}}
{{- $gh := $group.hooks | default dict -}}
{{- $jh := $job.hooks | default dict -}}
{{- $mergedHooks := dict -}}
{{- $_ := set $mergedHooks "argocd" (merge ($jh.argocd | default dict) ($gh.argocd | default dict)) -}}
{{- $_ := set $mergedHooks "helm" (merge ($jh.helm | default dict) ($gh.helm | default dict)) -}}
{{- $_ := set $merged "hooks" $mergedHooks -}}
{{/* Lists: concat group then job */}}
{{- $_ := set $merged "envSecrets" (concat ($group.envSecrets | default list) ($job.envSecrets | default list)) -}}
{{- $_ := set $merged "envConfigMaps" (concat ($group.envConfigMaps | default list) ($job.envConfigMaps | default list)) -}}
{{- if or (hasKey $group "tolerations") (hasKey $job "tolerations") -}}
{{- $_ := set $merged "tolerations" (concat ($group.tolerations | default list) ($job.tolerations | default list)) -}}
{{- end -}}
{{/* Maps: union by name; on key collision the whole job entry replaces the group entry
     (we do NOT recurse into the inner spec — k8s volume/volumeMount kinds are mutually
     exclusive: a name can be either an emptyDir or a configMap, not both). */}}
{{- $vMerged := deepCopy ($group.volumes | default dict) -}}
{{- range $k, $v := ($job.volumes | default dict) -}}
  {{- $_ := set $vMerged $k $v -}}
{{- end -}}
{{- $_ := set $merged "volumes" $vMerged -}}
{{- $vmMerged := deepCopy ($group.volumeMounts | default dict) -}}
{{- range $k, $v := ($job.volumeMounts | default dict) -}}
  {{- $_ := set $vmMerged $k $v -}}
{{- end -}}
{{- $_ := set $merged "volumeMounts" $vmMerged -}}
{{/* Scalars: job-override-else-group */}}
{{- range $k := list "backoffLimit" "completions" "parallelism" "suspend" "podFailurePolicy" "ttlSecondsAfterFinished" "activeDeadlineSeconds" "restartPolicy" "completionImage" "serviceAccountName" "automountServiceAccountToken" "terminationGracePeriodSeconds" "useRootVolumes" "useRootVolumeMounts" "hashSuffix" "hashIncludePodAnnotations" "schedule" "timeZone" "concurrencyPolicy" "successfulJobsHistoryLimit" "failedJobsHistoryLimit" "startingDeadlineSeconds" "command" "args" "tasks" -}}
{{- $jv := index $job $k -}}
{{- $gv := index $group $k -}}
{{- if not (kindIs "invalid" $jv) -}}
{{- $_ := set $merged $k $jv -}}
{{- else if not (kindIs "invalid" $gv) -}}
{{- $_ := set $merged $k $gv -}}
{{- end -}}
{{- end -}}
{{/* Fail-fast: CronJob doesn't support hooks (Job-only ArgoCD/Helm semantics) */}}
{{- if eq $kind "CronJob" -}}
  {{- $a := $mergedHooks.argocd | default dict -}}
  {{- $h := $mergedHooks.helm | default dict -}}
  {{- $hookSet := false -}}
  {{- range $k := list "hook" "syncWave" "deletePolicy" -}}
    {{- $v := index $a $k -}}
    {{- if and (not (kindIs "invalid" $v)) (ne ($v | toString) "") -}}{{- $hookSet = true -}}{{- end -}}
  {{- end -}}
  {{- range $k := list "hook" "weight" "deletePolicy" -}}
    {{- $v := index $h $k -}}
    {{- if and (not (kindIs "invalid" $v)) (ne ($v | toString) "") -}}{{- $hookSet = true -}}{{- end -}}
  {{- end -}}
  {{- if $hookSet -}}
    {{- fail (printf "jobGroups.%s.jobs.%s: hooks are not applicable to kind: CronJob (set hooks only on Job groups)" $gn $jn) -}}
  {{- end -}}
{{- end -}}
{{/* Fail-fast: hashSuffix=true with HookSucceeded delete policy breaks idempotency */}}
{{- $hashOn := true -}}
{{- if hasKey $merged "hashSuffix" -}}
  {{- $hashOn = ne (index $merged "hashSuffix") false -}}
{{- end -}}
{{- if $hashOn -}}
  {{- $aDel := ($mergedHooks.argocd | default dict).deletePolicy | default "" -}}
  {{- $hDel := ($mergedHooks.helm | default dict).deletePolicy | default "" -}}
  {{- if or (eq $aDel "HookSucceeded") (eq $hDel "hook-succeeded") -}}
    {{- fail (printf "jobGroups.%s.jobs.%s: hashSuffix=true is incompatible with deletePolicy that removes the Job after success (argocd HookSucceeded / helm hook-succeeded). The Job would be deleted then recreated on every sync, breaking idempotency. Use hashSuffix: false, or leave deletePolicy unset (HookFailed default ensures idempotency)" $gn $jn) -}}
  {{- end -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end -}}

{{/*
Stable 8-char sha256 of fields that affect Job/CronJob behavior. Excludes metadata-only
fields (metadataAnnotations, hooks, ttlSecondsAfterFinished, hashSuffix,
hashIncludePodAnnotations) so changes to those don't trigger a re-run.
Also excludes suspend: it's meant to pause/resume the same Job or CronJob in place —
including it in the hash would rename the resource on every toggle, defeating the point.
podAnnotations are included by default (so Vault/Datadog injection changes recreate
the Job); set hashIncludePodAnnotations: false to opt out per group/job.
Params: dict "merged" $merged
*/}}
{{- define "uhc.jobGroupHash" -}}
{{- $merged := .merged -}}
{{- $includePodAnn := true -}}
{{- if hasKey $merged "hashIncludePodAnnotations" -}}
  {{- $includePodAnn = ne (index $merged "hashIncludePodAnnotations") false -}}
{{- end -}}
{{- $excludeKeys := list "metadataAnnotations" "hooks" "ttlSecondsAfterFinished" "hashSuffix" "hashIncludePodAnnotations" "suspend" -}}
{{- if not $includePodAnn -}}
  {{- $excludeKeys = append $excludeKeys "podAnnotations" -}}
{{- end -}}
{{- $hashed := dict -}}
{{- range $k, $v := $merged -}}
{{- if not (has $k $excludeKeys) -}}
{{- $_ := set $hashed $k $v -}}
{{- end -}}
{{- end -}}
{{- $hashed | toYaml | sha256sum | trunc 8 -}}
{{- end -}}

{{/*
Final metadata.name for a jobGroups resource: "{fullname}-{trunc-group}-{trunc-job}[-{sha8}]".
Final string is truncated to 63 chars and trailing dashes are trimmed for k8s DNS-1123
compliance. Set merged.hashSuffix=false to omit the sha suffix.
Params: dict "ctx" $ctx "groupName" $g "jobName" $j "merged" $merged
*/}}
{{- define "uhc.jobGroupResourceName" -}}
{{- $ctx := .ctx -}}
{{- $fullname := include "uhc.fullname" $ctx -}}
{{- $wlName := include "uhc.jobGroupName" (dict "groupName" .groupName "jobName" .jobName) -}}
{{- $base := printf "%s-%s" $fullname $wlName -}}
{{- $useHash := true -}}
{{- if hasKey .merged "hashSuffix" -}}
{{- $useHash = ne (index .merged "hashSuffix") false -}}
{{- end -}}
{{- if $useHash -}}
{{- $sha := include "uhc.jobGroupHash" (dict "merged" .merged) -}}
{{- printf "%s-%s" $base $sha | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $base | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Renders ArgoCD and/or Helm hook annotations from merged.hooks. Both providers are
independent: each is rendered iff at least one of its (hook|syncWave|deletePolicy or
hook|weight|deletePolicy) fields is set to a non-empty value. Empty providers produce no output.
Params: dict "merged" $merged
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.jobGroupHookAnnotations" -}}
{{- $hooks := .merged.hooks | default dict -}}
{{- $a := $hooks.argocd | default dict -}}
{{- $h := $hooks.helm | default dict -}}
{{- $aHook := $a.hook | default "" -}}
{{- $aWave := $a.syncWave -}}
{{- /* Default to HookFailed when hook is set: succeeded jobs stay (idempotent re-sync), failed jobs are deleted (retry on next sync) */ -}}
{{- $aDel := $a.deletePolicy | default (ternary "HookFailed" "" (ne $aHook "")) -}}
{{- $hHook := $h.hook | default "" -}}
{{- $hWeight := $h.weight -}}
{{- $hDel := $h.deletePolicy | default "" -}}
{{- $aWaveStr := "" -}}
{{- if not (kindIs "invalid" $aWave) -}}{{- $aWaveStr = $aWave | toString -}}{{- end -}}
{{- $hWeightStr := "" -}}
{{- if not (kindIs "invalid" $hWeight) -}}{{- $hWeightStr = $hWeight | toString -}}{{- end -}}
{{- if or (ne $aHook "") (ne $aWaveStr "") (ne $aDel "") -}}
{{- if ne $aHook "" }}
"argocd.argoproj.io/hook": {{ $aHook | quote }}
{{- end }}
{{- if ne $aWaveStr "" }}
"argocd.argoproj.io/sync-wave": {{ $aWaveStr | quote }}
{{- end }}
{{- if ne $aDel "" }}
"argocd.argoproj.io/hook-delete-policy": {{ $aDel | quote }}
{{- end }}
{{- end -}}
{{- if or (ne $hHook "") (ne $hWeightStr "") (ne $hDel "") -}}
{{- if ne $hHook "" }}
"helm.sh/hook": {{ $hHook | quote }}
{{- end }}
{{- if ne $hWeightStr "" }}
"helm.sh/hook-weight": {{ $hWeightStr | quote }}
{{- end }}
{{- if ne $hDel "" }}
"helm.sh/hook-delete-policy": {{ $hDel | quote }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Renders initContainers from merged.tasks (sortAlpha). Each task is a small object:
  enabled (required), command (string sh -c heredoc, or list), args (list).
Tasks share the job's image, env, envFrom, securityContext and volumeMounts —
per-task overrides are intentionally not supported (use a separate job for that).
Params: dict "ctx" $ctx "wl" $merged
Output at zero indent; caller controls nindent.
*/}}
{{- define "uhc.jobTasksContainers" -}}
{{- $ctx := .ctx -}}
{{- $wl := .wl -}}
{{- $imageOverride := $wl.image | default dict -}}
{{- $repo := required "jobGroups: image.repository is required (set jobGroups.<group>.image.repository or root image.repository)" (default $ctx.Values.image.repository $imageOverride.repository) -}}
{{- $tag := required "jobGroups: image.tag is required (set jobGroups.<group>.image.tag or root image.tag)" (default $ctx.Values.image.tag $imageOverride.tag) -}}
{{- $pullPolicy := default $ctx.Values.image.pullPolicy $imageOverride.pullPolicy -}}
{{- if and (eq $tag "latest") (eq $pullPolicy "IfNotPresent") }}
{{- fail (printf "jobGroups tasks: imagePullPolicy: IfNotPresent combined with tag 'latest' is unsafe — nodes that already have the image cached will not pull updates. Set imagePullPolicy: Always or use a specific image tag.") }}
{{- end }}
{{- $secCtx := $wl.securityContext | default $ctx.Values.securityContext | default dict -}}
{{- range $taskName := keys ($wl.tasks | default dict) | sortAlpha }}
{{- $task := index $wl.tasks $taskName }}
- name: {{ $taskName }}
  image: "{{ $repo }}:{{ $tag }}"
  imagePullPolicy: {{ $pullPolicy }}
  {{- with $secCtx }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if $task.command }}
  command:
  {{- if kindIs "slice" $task.command }}
    {{- toYaml $task.command | nindent 4 }}
  {{- else }}
    - sh
    - -c
    - |
{{ $task.command | trim | indent 6 }}
  {{- end }}
  {{- end }}
  {{- if $task.args }}
  args:
    {{- range $task.args }}
    - {{ . | quote }}
    {{- end }}
  {{- end }}
  env:
    {{- include "uhc.envVars" (dict "ctx" $ctx "extraEnv" ($wl.env | default dict) "inherit" (($wl.inherit | default dict).env | default dict)) | trim | nindent 4 }}
  {{- $secrets := $wl.envSecrets | default list }}
  {{- $rootSecrets := $ctx.Values.envSecrets | default list }}
  {{- $envFromYaml := include "uhc.envFrom" (dict "rootSecrets" $rootSecrets "workloadSecrets" $secrets) | trim }}
  {{- if $envFromYaml }}
  {{- $envFromYaml | nindent 2 }}
  {{- end }}
  {{- /* configMap auto-mounts: same bool/map semantics as uhc.containerSpecWithOptions */ -}}
  {{- $cmm := include "uhc.resolveConfigMapMount" ($wl.inherit | default dict) | fromJson }}
  {{- $autoMounts := list }}
  {{- if $cmm.enabled }}
    {{- range $cmName := keys ($ctx.Values.configMaps | default dict) | sortAlpha }}
      {{- $cm := index $ctx.Values.configMaps $cmName }}
      {{- if and (hasKey $cm "enabled") $cm.enabled $cm.mountPath (ne (index $cmm.granular $cmName) false) }}
        {{- $autoMounts = append $autoMounts (dict "name" (printf "cm-%s" $cmName) "mountPath" $cm.mountPath "readOnly" (ne $cm.readOnly false)) }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- $taskMounts := $wl.volumeMounts | default dict }}
  {{- if or $taskMounts $autoMounts }}
  volumeMounts:
    {{- range $mName := keys $taskMounts | sortAlpha }}
    - name: {{ $mName }}
      {{- toYaml (index $taskMounts $mName) | nindent 6 }}
    {{- end }}
    {{- range $autoMounts }}
    - name: {{ .name }}
      mountPath: {{ .mountPath }}
      readOnly: {{ .readOnly }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end -}}
