{{/*
Expand the name of the chart.
*/}}
{{- define "transip-ddns.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "transip-ddns.fullname" -}}
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
{{- define "transip-ddns.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "transip-ddns.labels" -}}
helm.sh/chart: {{ include "transip-ddns.chart" . }}
{{ include "transip-ddns.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "transip-ddns.selectorLabels" -}}
app.kubernetes.io/name: {{ include "transip-ddns.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Secret name for private key
*/}}
{{- define "transip-ddns.secretName" -}}
{{- if .Values.transip.privateKey.existingSecret }}
{{- .Values.transip.privateKey.existingSecret }}
{{- else }}
{{- include "transip-ddns.fullname" . }}-key
{{- end }}
{{- end }}

{{/*
Secret key name for private key
*/}}
{{- define "transip-ddns.secretKey" -}}
{{- .Values.transip.privateKey.existingSecretKey | default "transip.key" }}
{{- end }}
