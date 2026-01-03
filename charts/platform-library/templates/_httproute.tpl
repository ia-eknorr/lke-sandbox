{{/*
HTTPRoute template for Gateway API
Usage: {{ include "platform.httproute" . }}
*/}}
{{- define "platform.httproute" -}}
{{- if .Values.httpRoute.enabled }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "platform.name" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
  {{- with .Values.httpRoute.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  parentRefs:
    - name: {{ .Values.httpRoute.gateway.name | default "traefik-gateway" }}
      namespace: {{ .Values.httpRoute.gateway.namespace | default "traefik" }}
  hostnames:
    {{- if .Values.httpRoute.hostnames }}
    {{- toYaml .Values.httpRoute.hostnames | nindent 4 }}
    {{- else if .Values.httpRoute.hostname }}
    - {{ .Values.httpRoute.hostname | quote }}
    {{- end }}
  rules:
    {{- if .Values.httpRoute.rules }}
    {{- range .Values.httpRoute.rules }}
    - matches:
        {{- toYaml .matches | nindent 8 }}
      {{- with .filters }}
      filters:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      backendRefs:
        - name: {{ $.Values.httpRoute.service.name | default (include "platform.name" $) }}
          port: {{ $.Values.httpRoute.service.port }}
    {{- end }}
    {{- else }}
    - matches:
        - path:
            type: PathPrefix
            value: {{ .Values.httpRoute.path | default "/" }}
      backendRefs:
        - name: {{ .Values.httpRoute.service.name | default (include "platform.name" .) }}
          port: {{ .Values.httpRoute.service.port }}
    {{- end }}
{{- end }}
{{- end }}
