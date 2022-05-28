job "nginx" {
  datacenters = ["davnet"]

  # TODO: Strictly speaking, this doesn't NEED to live on the Nomad server..
  # That's just where the *.nomad.davnet.lmhd.me DNS record is currently pointing
  #
  # In reeality, we would probably want this on all clients so we don't need to
  # know which client it's running on
  constraint {
    attribute = "${meta.nomad_server}"
    value     = true
  }

  group "nginx" {
    count = 1

    network {
      port "http" {
        static = 80
      }

      /*
      # TODO: hold off on this for now
      # We would want to pull down a TLS cert from Vault for this
      port "https" {
        static = 443
      }
*/
    }

    service {
      name     = "nginx"
      provider = "nomad"
      port     = "http"
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx"

        ports = ["http"]

        volumes = [
          "local:/etc/nginx/conf.d",
        ]
      }

      template {
        data = <<EOF
upstream nomad {
  server nomad.davnet.lmhd.me:4646;
}
server {
   listen 80;

   location / {
      proxy_pass https://nomad;
   }
}

{{ range nomadServices }}
{{ if .Tags | contains "nginx" }}

upstream {{ .Name }} {
{{- range nomadService .Name }}
  server {{ .Address }}:{{ .Port }};
{{- end }}
}

server {
   listen 80;
   server_name {{ .Name }}.nomad.davnet.lmhd.me;

   location / {
      proxy_pass http://{{ .Name }};
   }
}
{{ end }}
{{ end -}}
EOF

        destination   = "local/load-balancer.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
    }
  }
}
