{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "beam-etl.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "beam-etl.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "beam-etl.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "beam-etl.labels" -}}
helm.sh/chart: {{ include "beam-etl.chart" . }}
{{ include "beam-etl.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ (print .Chart.AppVersion ((eq .Chart.AppVersion (default .Chart.AppVersion .Values.image.tag)) | ternary "" (print "-" .Values.image.tag))) | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "beam-etl.selectorLabels" -}}
app.kubernetes.io/name: {{ include "beam-etl.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Match labels
*/}}
{{- define "beam-etl.matchLabels" -}}
app.kubernetes.io/app: {{ include "beam-etl.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "beam-etl.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "beam-etl.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the pipeline environment
*/}}
{{- define "beam-etl.jvmArgs" -}}
{{-   $jvmArgs := (list) }}
{{-   if .Values.defaultJvmArgs -}}
{{-     $jvmArgs = (append $jvmArgs (print "-Xmx" .Values.memory.jvm)) }}
{{-     $jvmArgs = (append $jvmArgs (print "-Dkafkita.jvm.zk.Xmx" .Values.memory.zkJvm "=")) }}
{{-     $jvmArgs = (append $jvmArgs (print "-Dkafkita.jvm.kafka.Xmx" .Values.memory.kafkaJvm "=")) }}
{{-     $jvmArgs = (append $jvmArgs (print "-Dlog4j.configuration=log4j." .Values.logLevel ".k8s.properties")) }}
{{-   end  -}}
{{-  $jvmArgs := (concat $jvmArgs .Values.jvmArgs) -}}
{{   join " " $jvmArgs }}
{{- end }}

{{/*
Create the pipeline arguments
*/}}
{{- define "beam-etl.containerArgs" -}}
{{-   if .Values.dryRun -}}
- "--versionAndWait"

{{    end -}}
{{-   if eq (len .Values.pipeline.source) 0 -}}
{{-     range $arg := .Values.args }}
- {{      quote $arg }}
{{-     end }}
{{-   else  -}}
- {{    quote (print "--runner=" .Values.pipeline.runner.class) }}
{{-     $jobName := (coalesce .Values.pipeline.runner.jobName .Release.Name) }}
- {{    quote (print "--jobName=" $jobName) }}
{{-     range $k, $v := .Values.pipeline.runner }}
{{-       if not (kindIs "invalid" $v) }}
{{-         if not (eq $k "class") }}
{{-           if not (eq $k "metadataRoot") }}
- {{            quote (print "--" (join "=" (list $k $v))) }}
{{-           else }}
- {{            quote (print "--metadataPath=" $v "/job/" $jobName) }}
{{-           end }}
{{-         end }}
{{-       end }}
{{-     end }}

- {{    quote (print "--sourceClass=" .Values.pipeline.source.class) }}
{{-     range $k, $v := .Values.pipeline.source }}
{{-       if not (kindIs "invalid" $v) }}
{{-         if not (eq $k "class") }}
- {{          quote (print "--" (join "=" (list $k $v))) }}
{{-         end }}
{{-       end }}
{{-     end }}

{{- range $transform := .Values.pipeline.transforms }}
- {{    quote (print "--transformClass=" $transform.class) }}
{{-     range $k, $v := $transform }}
{{-       if not (kindIs "invalid" $v) }}
{{-         if not (eq $k "class") }}
- {{          quote (print "--" (join "=" (list $k $v))) }}
{{-         end }}
{{-       end }}
{{-     end }}
{{- end }}

- {{    quote (print "--sinkClass=" .Values.pipeline.sink.class) }}
{{-     range $k, $v := .Values.pipeline.sink }}
{{-       if not (kindIs "invalid" $v) }}
{{-         if not (eq $k "class") }}
- {{          quote (print "--" (join "=" (list $k $v))) }}
{{-         end }}
{{-       end }}
{{-     end }}
{{-   end }}
{{- end }}
