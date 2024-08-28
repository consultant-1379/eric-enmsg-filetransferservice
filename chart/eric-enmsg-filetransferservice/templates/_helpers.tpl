{{- define "eric-enmsg-filetransferservice.service-ipv6" -}}
metadata:
  labels:
    service: {{ .Values.service.name }}-ipv6
  name: {{ .Values.service.name  }}-ipv6
{{- end -}}