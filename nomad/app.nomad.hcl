job "app" {
  # Job metadata
  datacenters = ["dc1"]
  type        = "service"
  priority    = 80
  
  # Job constraints
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  
  constraint {
    attribute = "${attr.driver.docker}"
    value     = "1"
  }
  
  # Update strategy for zero-downtime deployments
  update {
    max_parallel      = 1
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    canary            = 1
    stagger           = "30s"
  }
  
  # Migrate strategy for node failures
  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "30s"
    healthy_deadline = "5m"
  }
  
  group "web" {
    count = 3  # Number of instances for high availability
    
    # Spread across different nodes for resilience
    spread {
      attribute = "${node.unique.id}"
      weight    = 100
    }
    
    # Rolling restart policy
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }
    
    # Reschedule policy for failed allocations
    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "1h"
      unlimited      = true
    }
    
    # Ephemeral disk for temporary data
    ephemeral_disk {
      size    = 500  # MB
      migrate = true
      sticky  = true
    }
    
    # Network configuration
    network {
      port "http" {
        to = 3000
      }
      
      port "metrics" {
        to = 9090
      }
    }
    
    # Service registration with Consul
    service {
      name = "app"
      port = "http"
      
      tags = [
        "app",
        "web",
        "production",
        "traefik.enable=true",
        "traefik.http.routers.app.rule=Host(`your-domain.com`)",
        "traefik.http.routers.app.tls=true",
        "traefik.http.routers.app.tls.certresolver=letsencrypt",
        "traefik.http.services.app.loadbalancer.server.port=3000",
        "traefik.http.services.app.loadbalancer.healthcheck.path=/health",
        "traefik.http.services.app.loadbalancer.healthcheck.interval=30s",
      ]
      
      # Health check configuration
      check {
        name     = "app-health"
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "3s"
        
        check_restart {
          limit = 3
          grace = "90s"
          ignore_warnings = false
        }
      }
      
      # Readiness check
      check {
        name     = "app-ready"
        type     = "http"
        path     = "/ready"
        interval = "5s"
        timeout  = "2s"
      }
      
      # Connect service mesh configuration (optional)
      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "database"
              local_bind_port  = 5432
            }
            upstreams {
              destination_name = "redis"
              local_bind_port  = 6379
            }
          }
        }
      }
    }
    
    # Metrics service for monitoring
    service {
      name = "app-metrics"
      port = "metrics"
      
      tags = [
        "metrics",
        "prometheus",
      ]
      
      check {
        name     = "metrics-health"
        type     = "http"
        path     = "/metrics"
        interval = "30s"
        timeout  = "5s"
      }
    }
    
    task "app" {
      driver = "docker"
      
      # Task lifecycle
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }
      
      config {
        image = "DOCKER_IMAGE:IMAGE_TAG"
        ports = ["http", "metrics"]
        
        # Docker labels for monitoring and management
        labels {
          service     = "app"
          version     = "IMAGE_TAG"
          environment = "production"
          build       = "BUILD_VERSION"
        }
        
        # Logging configuration
        logging {
          type = "json-file"
          config {
            max-files = "10"
            max-size  = "10m"
            labels    = "service,version,environment"
          }
        }
        
        # Security options
        security_opt = [
          "no-new-privileges:true"
        ]
        
        # Resource limits
        ulimit {
          nofile = "65536:65536"
          nproc  = "32768:32768"
        }
        
        # Mount points for persistent data
        mount {
          type   = "bind"
          source = "local/app"
          target = "/app/data"
        }
        
        # Health check from Docker
        healthcheck {
          test     = ["CMD", "curl", "-f", "http://localhost:3000/health"]
          interval = "30s"
          timeout  = "10s"
          retries  = 3
          start_period = "60s"
        }
      }
      
      # Environment variables
      env {
        NODE_ENV = "production"
        PORT     = "3000"
        METRICS_PORT = "9090"
        
        # Consul configuration
        CONSUL_HOST = "${NOMAD_IP}"
        CONSUL_PORT = "8500"
        
        # Service discovery
        SERVICE_NAME = "${NOMAD_JOB_NAME}"
        SERVICE_ID   = "${NOMAD_ALLOC_ID}"
        
        # Logging
        LOG_LEVEL = "info"
        LOG_FORMAT = "json"
      }
      
      # Secrets from Consul KV or Vault
      template {
        data = <<EOF
# Database configuration
DATABASE_URL="{{ key "app/database/url" }}"
DATABASE_POOL_SIZE="{{ key "app/database/pool_size" | default "10" }}"

# Redis configuration  
REDIS_URL="{{ key "app/redis/url" }}"
REDIS_PASSWORD="{{ key "app/redis/password" }}"

# API keys and secrets
API_SECRET_KEY="{{ key "app/secrets/api_key" }}"
JWT_SECRET="{{ key "app/secrets/jwt" }}"

# External service URLs
EXTERNAL_API_URL="{{ key "app/external/api_url" }}"
EXTERNAL_API_KEY="{{ key "app/external/api_key" }}"
EOF
        destination = "secrets/env"
        env         = true
        change_mode = "restart"
        perms       = "600"
      }
      
      # Configuration file template
      template {
        data = <<EOF
{
  "server": {
    "port": {{ env "PORT" }},
    "host": "0.0.0.0"
  },
  "database": {
    "url": "{{ key "app/database/url" }}",
    "pool": {
      "min": 2,
      "max": {{ key "app/database/pool_size" | default "10" }}
    }
  },
  "redis": {
    "url": "{{ key "app/redis/url" }}",
    "password": "{{ key "app/redis/password" }}"
  },
  "logging": {
    "level": "{{ env "LOG_LEVEL" }}",
    "format": "{{ env "LOG_FORMAT" }}"
  },
  "metrics": {
    "enabled": true,
    "port": {{ env "METRICS_PORT" }}
  }
}
EOF
        destination = "local/config.json"
        change_mode = "restart"
        perms       = "644"
      }
      
      # Resource allocation
      resources {
        cpu    = 1000  # MHz
        memory = 512   # MB
      }
      
      # Kill timeout
      kill_timeout = "30s"
      
      # Kill signal
      kill_signal = "SIGTERM"
      
      # Logging configuration
      logs {
        max_files     = 10
        max_file_size = 15
      }
      
      # Artifact for downloading additional files
      artifact {
        source      = "https://releases.example.com/config.tar.gz"
        destination = "local/"
        mode        = "file"
        options {
          checksum = "sha256:abc123..."
        }
      }
    }
    
    # Sidecar task for log shipping (optional)
    task "log-shipper" {
      driver = "docker"
      
      lifecycle {
        hook    = "poststart"
        sidecar = true
      }
      
      config {
        image = "fluent/fluent-bit:latest"
        
        mount {
          type   = "bind"
          source = "alloc/logs"
          target = "/var/log/app"
          readonly = true
        }
      }
      
      template {
        data = <<EOF
[INPUT]
    Name tail
    Path /var/log/app/*.log
    Tag app.*
    
[OUTPUT]
    Name forward
    Match *
    Host {{ key "logging/fluentd/host" }}
    Port {{ key "logging/fluentd/port" | default "24224" }}
EOF
        destination = "local/fluent-bit.conf"
      }
      
      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
  
  # Parameterized job for batch processing (optional)
  parameterized {
    payload       = "optional"
    meta_required = ["task_type"]
    meta_optional = ["priority", "timeout"]
  }
  
  # Periodic job configuration (if needed)
  # periodic {
  #   cron             = "0 2 * * *"
  #   prohibit_overlap = true
  #   time_zone        = "UTC"
  # }
}

