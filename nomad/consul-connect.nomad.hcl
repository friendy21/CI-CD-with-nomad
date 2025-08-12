job "consul-connect" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 70
  
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  
  update {
    max_parallel      = 1
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    stagger           = "30s"
  }
  
  group "database" {
    count = 1
    
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }
    
    network {
      port "db" {
        to = 5432
      }
    }
    
    service {
      name = "database"
      port = "db"
      
      tags = [
        "database",
        "postgresql",
      ]
      
      connect {
        sidecar_service {}
      }
      
      check {
        name     = "database-health"
        type     = "tcp"
        interval = "10s"
        timeout  = "3s"
      }
    }
    
    task "postgres" {
      driver = "docker"
      
      config {
        image = "postgres:15-alpine"
        ports = ["db"]
        
        volumes = [
          "local/data:/var/lib/postgresql/data",
        ]
      }
      
      env {
        POSTGRES_DB       = "appdb"
        POSTGRES_USER     = "postgres"
        POSTGRES_PASSWORD = "secure_password"
      }
      
      template {
        data = <<EOF
POSTGRES_PASSWORD="{{ key "database/postgres/password" }}"
EOF
        destination = "secrets/env"
        env         = true
      }
      
      resources {
        cpu    = 1000
        memory = 512
      }
    }
  }
  
  group "redis" {
    count = 1
    
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }
    
    network {
      port "redis" {
        to = 6379
      }
    }
    
    service {
      name = "redis"
      port = "redis"
      
      tags = [
        "cache",
        "redis",
      ]
      
      connect {
        sidecar_service {}
      }
      
      check {
        name     = "redis-health"
        type     = "tcp"
        interval = "10s"
        timeout  = "3s"
      }
    }
    
    task "redis" {
      driver = "docker"
      
      config {
        image = "redis:7-alpine"
        ports = ["redis"]
        
        args = [
          "redis-server",
          "--appendonly", "yes",
          "--requirepass", "${REDIS_PASSWORD}",
        ]
        
        volumes = [
          "local/data:/data",
        ]
      }
      
      env {
        REDIS_PASSWORD = "secure_redis_password"
      }
      
      template {
        data = <<EOF
REDIS_PASSWORD="{{ key "redis/password" }}"
EOF
        destination = "secrets/env"
        env         = true
      }
      
      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
  
  group "monitoring" {
    count = 1
    
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }
    
    network {
      port "prometheus" {
        to = 9090
      }
      
      port "grafana" {
        to = 3000
      }
    }
    
    # Prometheus service
    service {
      name = "prometheus"
      port = "prometheus"
      
      tags = [
        "monitoring",
        "prometheus",
        "traefik.enable=true",
        "traefik.http.routers.prometheus.rule=Host(`prometheus.your-domain.com`)",
        "traefik.http.routers.prometheus.tls=true",
        "traefik.http.services.prometheus.loadbalancer.server.port=9090",
      ]
      
      check {
        name     = "prometheus-health"
        type     = "http"
        path     = "/-/healthy"
        interval = "30s"
        timeout  = "5s"
      }
    }
    
    # Grafana service
    service {
      name = "grafana"
      port = "grafana"
      
      tags = [
        "monitoring",
        "grafana",
        "traefik.enable=true",
        "traefik.http.routers.grafana.rule=Host(`grafana.your-domain.com`)",
        "traefik.http.routers.grafana.tls=true",
        "traefik.http.services.grafana.loadbalancer.server.port=3000",
      ]
      
      check {
        name     = "grafana-health"
        type     = "http"
        path     = "/api/health"
        interval = "30s"
        timeout  = "5s"
      }
    }
    
    task "prometheus" {
      driver = "docker"
      
      config {
        image = "prom/prometheus:latest"
        ports = ["prometheus"]
        
        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--web.console.libraries=/etc/prometheus/console_libraries",
          "--web.console.templates=/etc/prometheus/consoles",
          "--storage.tsdb.retention.time=200h",
          "--web.enable-lifecycle",
        ]
        
        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml",
          "local/data:/prometheus",
        ]
      }
      
      template {
        data = <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'nomad'
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP" }}:8500'
        services: ['nomad-client', 'nomad']
    relabel_configs:
      - source_labels: [__meta_consul_tags]
        regex: '(.*)http(.*)'
        action: keep

  - job_name: 'consul'
    static_configs:
      - targets: ['{{ env "NOMAD_IP" }}:8500']

  - job_name: 'app'
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP" }}:8500'
        services: ['app-metrics']
    relabel_configs:
      - source_labels: [__meta_consul_service]
        target_label: job
EOF
        destination = "local/prometheus.yml"
        change_mode = "restart"
      }
      
      resources {
        cpu    = 500
        memory = 512
      }
    }
    
    task "grafana" {
      driver = "docker"
      
      config {
        image = "grafana/grafana:latest"
        ports = ["grafana"]
        
        volumes = [
          "local/data:/var/lib/grafana",
        ]
      }
      
      env {
        GF_SECURITY_ADMIN_PASSWORD = "admin"
        GF_USERS_ALLOW_SIGN_UP     = "false"
      }
      
      template {
        data = <<EOF
GF_SECURITY_ADMIN_PASSWORD="{{ key "grafana/admin/password" }}"
EOF
        destination = "secrets/env"
        env         = true
      }
      
      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}

