job "app" {
  datacenters = ["dc1"]
  type = "service"
  
  # Target client nodes
  constraint {
    attribute = "${node.class}"
    value     = "worker"
  }

  update {
    max_parallel      = 1
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    canary            = 0
  }

  group "web" {
    count = 1

    network {
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
      ]
      
      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
      
      # Consul Connect sidecar
      connect {
        sidecar_service {}
      }
    }

    task "app" {
      driver = "docker"

      config {
        image = "REPLACE_IMAGE"
        ports = ["http"]
        force_pull = true
        
        # Authentication for Docker Hub
        auth {
          username = "friendy21"
          password = "dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U"
        }
      }

      env {
        PORT = "3000"
        NODE_ENV = "production"
        VERSION = "${NOMAD_META_VERSION}"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      logs {
        max_files     = 10
        max_file_size = 15
      }
    }
  }
}
