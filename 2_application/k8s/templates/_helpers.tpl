{{- define "deployment.name" -}}
{{- default .Values.application_name | trunc 63 -}}
{{- end -}}

{{- define "service.name" -}}
{{- printf "%s-%s" .Values.application_name "svc" |trunc 63 -}}
{{- end -}}

{{- define "ingress.name" -}}
{{- printf "%s-%s" .Values.application_name "ing" |trunc 63 -}}
{{- end -}}

{{- define "secret.name" -}}
{{- printf "%s-%s" .Values.application_name "secret" |trunc 63 -}}
{{- end -}}

