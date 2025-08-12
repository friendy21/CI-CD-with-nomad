job "traefik" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 90  # High priority for load balancer
  
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  
  # Ensure Traefik runs on nodes with public IP
  constraint {
    attribute = "${meta.public_ip}"
    operator  = "is_set"
  }
  
  update {
    max_parallel      = 1
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    stagger           = "30s"
  }
  
  group "traefik" {
    count = 1  # Single instance, can be scaled if needed
    
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }
    
    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "1h"
      unlimited      = true
    }
    
    ephemeral_disk {
      size = 200
    }
    
    network {
      port "http" {
        static = 80
        to     = 80
      }
      
      port "https" {
        static = 443
        to     = 443
      }
      
      port "api" {
        static = 8080
        to     = 8080
      }
    }
    
    # Traefik service registration
    service {
      name = "traefik"
      port = "http"
      
      tags = [
        "traefik",
        "load-balancer",
        "reverse-proxy",
      ]
      
      check {
        name     = "traefik-health"
        type     = "http"
        path     = "/ping"
        port     = "api"
        interval = "10s"
        timeout  = "3s"
      }
    }
    
    # Traefik API service
    service {
      name = "traefik-api"
      port = "api"
      
      tags = [
        "traefik-api",
        "dashboard",
      ]
      
      check {
        name     = "traefik-api-health"
        type     = "http"
        path     = "/api/rawdata"
        interval = "30s"
        timeout  = "5s"
      }
    }
    
    task "traefik" {
      driver = "docker"
      
      config {
        image = "traefik:v3.0"
        ports = ["http", "https", "api"]
        
        args = [
          "--api.dashboard=true",
          "--api.insecure=true",
          "--entrypoints.web.address=:80",
          "--entrypoints.websecure.address=:443",
          "--providers.consul.endpoints=${NOMAD_IP}:8500",
          "--providers.consul.exposedByDefault=false",
          "--certificatesresolvers.letsencrypt.acme.tlschallenge=true",
          "--certificatesresolvers.letsencrypt.acme.email=friendykaliman@gmail.com",
          "--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json",
          "--log.level=INFO",
          "--accesslog=true",
          "--ping=true",
          "--global.sendAnonymousUsage=false",
        ]
        
        volumes = [
          "local/data:/data",
        ]
        
        labels {
          service = "traefik"
          version = "3.0"
        }
        
        logging {
          type = "json-file"
          config {
            max-files = "10"
            max-size  = "10m"
          }
        }
      }
      
      env {
        TRAEFIK_LOG_LEVEL = "INFO"
      }
      
      # Traefik configuration file
      template {
        data = <<EOF
# Traefik static configuration
global:
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  consul:
    endpoints:
      - "{{ env "NOMAD_IP" }}:8500"
    exposedByDefault: false
    
certificatesResolvers:
  letsencrypt:
    acme:
      email: friendykaliman@gmail.com
      storage: /data/acme.json
      tlsChallenge: {}

log:
  level: INFO
  
accessLog: {}

ping: {}

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
EOF
        destination = "local/traefik.yml"
        change_mode = "restart"
      }
      
      # Dynamic configuration for middleware
      template {
        data = <<EOF
# Dynamic configuration
http:
  middlewares:
    default-headers:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        
    secure-headers:
      headers:
        accessControlAllowMethods:
          - GET
          - OPTIONS
          - PUT
        accessControlAllowOriginList:
          - "https://your-domain.com"
        accessControlMaxAge: 100
        hostsProxyHeaders:
          - "X-Forwarded-Host"
        referrerPolicy: "same-origin"
        
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
EOF
        destination = "local/dynamic.yml"
        change_mode = "restart"
      }
      
      resources {
        cpu    = 500
        memory = 256
      }
      
      kill_timeout = "30s"
      
      logs {
        max_files     = 10
        max_file_size = 15
      }
    }
  }
}

