job "app-staging" {
  # Job metadata
  datacenters = ["dc1"]
  type        = "service"
  priority    = 60  # Lower priority than production
  
  # Job constraints
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  
  constraint {
    attribute = "${attr.driver.docker}"
    value     = "1"
  }
  
  # Update strategy - more aggressive for staging
  update {
    max_parallel      = 2
    min_healthy_time  = "15s"
    healthy_deadline  = "3m"
    progress_deadline = "5m"
    auto_revert       = false  # Don't auto-revert in staging
    canary            = 0      # No canary in staging
    stagger           = "10s"
  }
  
  group "web" {
    count = 1  # Single instance for staging
    
    # Rolling restart policy
    restart {
      attempts = 2
      interval = "3m"
      delay    = "15s"
      mode     = "delay"
    }
    
    # Reschedule policy
    reschedule {
      delay          = "15s"
      delay_function = "constant"
      max_delay      = "30m"
      unlimited      = true
    }
    
    # Ephemeral disk
    ephemeral_disk {
      size    = 300  # Smaller disk for staging
      migrate = false
      sticky  = false
    }
    
    # Network configuration
    network {
      port "http" {
        to = 3000
      }
    }
    
    # Service registration with Consul
    service {
      name = "app-staging"
      port = "http"
      
      tags = [
        "app",
        "web",
        "staging",
        "traefik.enable=true",
        "traefik.http.routers.app-staging.rule=Host(`staging.your-domain.com`)",
        "traefik.http.routers.app-staging.tls=true",
        "traefik.http.routers.app-staging.tls.certresolver=letsencrypt",
        "traefik.http.services.app-staging.loadbalancer.server.port=3000",
      ]
      
      # Health check
      check {
        name     = "app-staging-health"
        type     = "http"
        path     = "/health"
        interval = "15s"
        timeout  = "5s"
        
        check_restart {
          limit = 2
          grace = "60s"
        }
      }
    }
    
    task "app" {
      driver = "docker"
      
      config {
        image = "DOCKER_IMAGE:IMAGE_TAG"
        ports = ["http"]
        
        labels {
          service     = "app"
          version     = "IMAGE_TAG"
          environment = "staging"
        }
        
        logging {
          type = "json-file"
          config {
            max-files = "5"
            max-size  = "5m"
          }
        }
        
        # Health check
        healthcheck {
          test     = ["CMD", "curl", "-f", "http://localhost:3000/health"]
          interval = "30s"
          timeout  = "5s"
          retries  = 2
        }
      }
      
      # Environment variables for staging
      env {
        NODE_ENV = "staging"
        PORT     = "3000"
        LOG_LEVEL = "debug"  # More verbose logging in staging
        
        # Consul configuration
        CONSUL_HOST = "${NOMAD_IP}"
        CONSUL_PORT = "8500"
      }
      
      # Staging secrets
      template {
        data = <<EOF
DATABASE_URL="{{ key "app-staging/database/url" }}"
REDIS_URL="{{ key "app-staging/redis/url" }}"
API_SECRET_KEY="{{ key "app-staging/secrets/api_key" }}"
EOF
        destination = "secrets/env"
        env         = true
        change_mode = "restart"
      }
      
      # Resource allocation - smaller for staging
      resources {
        cpu    = 500   # MHz
        memory = 256   # MB
      }
      
      kill_timeout = "20s"
      
      logs {
        max_files     = 5
        max_file_size = 10
      }
    }
  }
}

