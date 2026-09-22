{{/*
Expand the name of the chart.
*/}}
{{- define "confapi.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "confapi.fullname" -}}
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
Chart label.
*/}}
{{- define "confapi.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "confapi.labels" -}}
helm.sh/chart: {{ include "confapi.chart" . }}
{{ include "confapi.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — Deployment, Service, and pod template must share these.
*/}}
{{- define "confapi.selectorLabels" -}}
app.kubernetes.io/name: {{ include "confapi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "confapi.name" . }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "confapi.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "confapi.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
