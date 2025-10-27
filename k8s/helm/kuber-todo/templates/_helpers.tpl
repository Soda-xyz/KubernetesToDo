{{- define "kuber-todo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /*
Common labels helper. Use by calling:
	{{ include "kuber-todo.labels" (dict "root" . "component" "api" "version" .Values.image.tag) | nindent 4 }}
The helper expects a dict with keys:
	root: the original context (usually .)
	component: string (eg. "api", "mongodb", "ingress")
	version: string value for app.kubernetes.io/version
*/ -}}
{{- define "kuber-todo.labels" -}}
{{- $root := .root -}}
app: {{ include "kuber-todo.name" $root }}
app.kubernetes.io/name: {{ include "kuber-todo.name" $root }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/version: "{{ .version }}"
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/managed-by: Helm
helm.sh/chart: "{{ $root.Chart.Name }}-{{ $root.Chart.Version }}"
{{- end -}}


{{- define "kuber-todo.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
