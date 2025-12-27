{{/*
Common name helper - uses release name
*/}}
{{- define "platform.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "platform.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
