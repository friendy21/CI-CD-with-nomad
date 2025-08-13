job "app" {
  datacenters = ["dc1"]
  type = "service"
  
  # Target client nodes only
  constraint {
    attribute = "${node.class}"
    value     = "worker"
  }

  # Rolling update strategy with automatic rollback
  update {
    max_parallel      = 1
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }

  # Spread allocations across nodes for HA
  spread {
    attribute = "${node.unique.id}"
    weight    = 100
  }

  group "web" {
    count = 2  # Run 2 instances for redundancy

    # Restart policy
    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    # Ephemeral disk for logs
    ephemeral_disk {
      size    = 300
      sticky  = false
      migrate = false
    }

    network {
      mode = "bridge"
      
      port "http" {
        to = 3000
      }
    }

    service {
      name = "app"
      port = "http"
      
      tags = [
        "web",
        "api",
        "traefik.enable=true",
        "traefik.http.routers.app.rule=Host(`app.local`)",
      ]
      
      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
        
        check_restart {
          limit = 3
          grace = "90s"
          ignore_warnings = false
        }
      }
      
      # Consul Connect sidecar for service mesh
      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "redis"
              local_bind_port  = 6379
            }
          }
        }
      }
    }

    task "app" {
      driver = "docker"

      config {
        image = "REPLACE_IMAGE"
        ports = ["http"]
        force_pull = true
        
        # Security options
        readonly_rootfs = false  # Set to true if app doesn't need to write
        cap_drop = ["ALL"]
        cap_add = ["NET_BIND_SERVICE"]
        
        # Resource limits
        memory_hard_limit = 512
        
        # Logging configuration
        logging {
          type = "json-file"
          config {
            max-size = "10m"
            max-file = "3"
          }
        }
        
        # Health check at container level
        healthcheck {
          test     = ["CMD", "curl", "-f", "http://localhost:3000/health"]
          interval = "30s"
          timeout  = "3s"
          retries  = 3
        }
      }

      # Environment variables from Consul KV or Vault
      template {
        data = <<EOH
PORT=3000
NODE_ENV=production
VERSION={{ env "NOMAD_JOB_VERSION" }}
ALLOCATION_ID={{ env "NOMAD_ALLOC_ID" }}
EOH
        destination = "local/env.txt"
        env         = true
      }

      # Application configuration from Consul
      template {
        data = <<EOH
{{ key "config/app/settings" }}
EOH
        destination   = "local/app-config.json"
        change_mode   = "signal"
        change_signal = "SIGUSR1"
      }

      resources {
        cpu    = 500  # MHz
        memory = 256  # MB
      }

      # Kill timeout
      kill_timeout = "30s"

      # Log configuration
      logs {
        max_files     = 10
        max_file_size = 15
      }

      # Vault integration for secrets (optional)
      # vault {
      #   policies = ["app-policy"]
      # }
    }

    # Sidecar task for monitoring (optional)
    task "promtail" {
      driver = "docker"
      
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      config {
        image = "grafana/promtail:latest"
        
        args = [
          "-config.file=/etc/promtail/config.yml"
        ]
        
        volumes = [
          "local/promtail.yml:/etc/promtail/config.yml:ro",
          "/var/log:/var/log:ro"
        ]
      }

      template {
        data = <<EOH
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki.service.consul:3100/loki/api/v1/push

scrape_configs:
  - job_name: app
    static_configs:
      - targets:
          - localhost
        labels:
          job: app
          __path__: /alloc/logs/*.std*.log
EOH
        destination = "local/promtail.yml"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
