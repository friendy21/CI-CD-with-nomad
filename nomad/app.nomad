job "app" {
  datacenters = ["dc1"]
  type = "service"

  group "web" {
    count = 1

    network {
      port "http" {
        to = 3000
      }
    }

    task "app" {
      driver = "docker"

      config {
        image = "REPLACE_IMAGE"
        ports = ["http"]
        force_pull = true
      }

      env {
        PORT = "3000"
        NODE_ENV = "production"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "app"
        port = "http"
        
        check {
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
