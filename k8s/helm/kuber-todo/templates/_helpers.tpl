{{- define "kuber-todo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /*
Common labels helper.
Usage:
	{{ include "kuber-todo.labels" (dict "root" . "component" "api" "version" .Values.image.tag) | nindent 4 }}

The helper accepts a dict with keys:
	root: the original context (usually .)
	component: string (eg. "api", "mongodb", "ingress") — optional, defaults to "app"
	version: string for app.kubernetes.io/version — optional, defaults to Chart.AppVersion when available
*/ -}}
{{- define "kuber-todo.labels" -}}
{{- $root := .root -}}
{{- $component := default "app" .component -}}
{{- $version := default $root.Chart.AppVersion .version -}}
{{- $labels := dict
		"app" (include "kuber-todo.name" $root)
		"app.kubernetes.io/name" (include "kuber-todo.name" $root)
		"app.kubernetes.io/instance" $root.Release.Name
		"app.kubernetes.io/version" $version
		"app.kubernetes.io/component" $component
		"app.kubernetes.io/managed-by" "Helm"
		"helm.sh/chart" (printf "%s-%s" $root.Chart.Name $root.Chart.Version)
	-}}
{{ toYaml $labels | nindent 0 }}
{{- end -}}


{{- define "kuber-todo.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
