#!/bin/bash

# Monitoring and Logging Setup Script
# This script sets up comprehensive monitoring for Nomad and Consul clusters

set -euo pipefail

# Configuration
PROMETHEUS_VERSION="2.47.0"
GRAFANA_VERSION="10.1.0"
ALERTMANAGER_VERSION="0.26.0"
NODE_EXPORTER_VERSION="1.6.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Create monitoring directories
create_monitoring_directories() {
    log "Creating monitoring directories..."
    
    mkdir -p /opt/monitoring/{prometheus,grafana,alertmanager}
    mkdir -p /opt/monitoring/prometheus/{data,config,rules}
    mkdir -p /opt/monitoring/grafana/{data,dashboards,provisioning/{datasources,dashboards}}
    mkdir -p /opt/monitoring/alertmanager/{data,config}
    mkdir -p /var/log/monitoring
    
    # Create monitoring user
    useradd --no-create-home --shell /bin/false monitoring || true
    
    # Set permissions
    chown -R monitoring:monitoring /opt/monitoring
    chown -R monitoring:monitoring /var/log/monitoring
}

# Install Prometheus
install_prometheus() {
    log "Installing Prometheus..."
    
    cd /tmp
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    
    # Copy binaries
    cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
    cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/
    
    # Copy console files
    cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles" /opt/monitoring/prometheus/
    cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries" /opt/monitoring/prometheus/
    
    # Cleanup
    rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64"*
    
    # Set permissions
    chown monitoring:monitoring /usr/local/bin/prometheus /usr/local/bin/promtool
    chown -R monitoring:monitoring /opt/monitoring/prometheus/
}

# Configure Prometheus
configure_prometheus() {
    log "Configuring Prometheus..."
    
    cat > /opt/monitoring/prometheus/config/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'nomad-cluster'
    environment: 'production'

rule_files:
  - "/opt/monitoring/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter
  - job_name: 'node-exporter'
    static_configs:
      - targets: 
        - '137.184.198.14:9100'
        - '137.184.85.0:9100'
    relabel_configs:
      - source_labels: [__address__]
        regex: '([^:]+):\d+'
        target_label: instance
        replacement: '\${1}'

  # Nomad servers
  - job_name: 'nomad'
    consul_sd_configs:
      - server: 'localhost:8500'
        services: ['nomad']
    relabel_configs:
      - source_labels: [__meta_consul_tags]
        regex: '(.*)http(.*)'
        action: keep
      - source_labels: [__meta_consul_service]
        target_label: job
      - source_labels: [__meta_consul_node]
        target_label: instance

  # Consul servers
  - job_name: 'consul'
    static_configs:
      - targets:
        - '137.184.198.14:8500'
        - '137.184.85.0:8500'
    metrics_path: /v1/agent/metrics
    params:
      format: ['prometheus']

  # Application metrics
  - job_name: 'app-metrics'
    consul_sd_configs:
      - server: 'localhost:8500'
        services: ['app-metrics']
    relabel_configs:
      - source_labels: [__meta_consul_service]
        target_label: job
      - source_labels: [__meta_consul_node]
        target_label: instance

  # Docker metrics
  - job_name: 'docker'
    static_configs:
      - targets:
        - '137.184.198.14:9323'
        - '137.184.85.0:9323'

  # Traefik metrics
  - job_name: 'traefik'
    consul_sd_configs:
      - server: 'localhost:8500'
        services: ['traefik']
    relabel_configs:
      - source_labels: [__meta_consul_service_port]
        regex: '8080'
        action: keep
      - source_labels: [__address__]
        regex: '([^:]+):\d+'
        target_label: __address__
        replacement: '\${1}:8080'
    metrics_path: /metrics
EOF
    
    # Create alerting rules
    cat > /opt/monitoring/prometheus/rules/alerts.yml << EOF
groups:
  - name: nomad.rules
    rules:
      - alert: NomadNodeDown
        expr: up{job="nomad"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Nomad node is down"
          description: "Nomad node {{ \$labels.instance }} has been down for more than 5 minutes."

      - alert: NomadJobFailed
        expr: nomad_nomad_job_summary_failed > 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Nomad job has failed allocations"
          description: "Job {{ \$labels.job }} has {{ \$value }} failed allocations."

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage on {{ \$labels.instance }} is above 80% for more than 5 minutes."

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage on {{ \$labels.instance }} is above 85% for more than 5 minutes."

      - alert: DiskSpaceLow
        expr: (1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space"
          description: "Disk usage on {{ \$labels.instance }} mount {{ \$labels.mountpoint }} is above 85%."

  - name: consul.rules
    rules:
      - alert: ConsulNodeDown
        expr: up{job="consul"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Consul node is down"
          description: "Consul node {{ \$labels.instance }} has been down for more than 5 minutes."

      - alert: ConsulServiceUnhealthy
        expr: consul_health_service_status{status!="passing"} > 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Consul service is unhealthy"
          description: "Service {{ \$labels.service_name }} on {{ \$labels.node }} is in {{ \$labels.status }} state."

  - name: application.rules
    rules:
      - alert: ApplicationDown
        expr: up{job="app-metrics"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Application is down"
          description: "Application instance {{ \$labels.instance }} has been down for more than 2 minutes."

      - alert: HighResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High response time"
          description: "95th percentile response time is above 1 second for more than 5 minutes."
EOF
    
    # Set permissions
    chown -R monitoring:monitoring /opt/monitoring/prometheus/
}

# Create Prometheus systemd service
create_prometheus_service() {
    log "Creating Prometheus systemd service..."
    
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=monitoring
Group=monitoring
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/opt/monitoring/prometheus/config/prometheus.yml \\
    --storage.tsdb.path=/opt/monitoring/prometheus/data \\
    --web.console.templates=/opt/monitoring/prometheus/consoles \\
    --web.console.libraries=/opt/monitoring/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.enable-lifecycle \\
    --storage.tsdb.retention.time=30d \\
    --storage.tsdb.retention.size=10GB

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable prometheus
}

# Install and configure Alertmanager
install_alertmanager() {
    log "Installing Alertmanager..."
    
    cd /tmp
    wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
    tar xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
    
    # Copy binary
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /usr/local/bin/
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool" /usr/local/bin/
    
    # Cleanup
    rm -rf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64"*
    
    # Set permissions
    chown monitoring:monitoring /usr/local/bin/alertmanager /usr/local/bin/amtool
    
    # Configure Alertmanager
    cat > /opt/monitoring/alertmanager/config/alertmanager.yml << EOF
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@your-domain.com'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    email_configs:
      - to: 'friendykaliman@gmail.com'
        subject: 'Alert: {{ .GroupLabels.alertname }}'
        body: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          {{ end }}

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
    
    chown -R monitoring:monitoring /opt/monitoring/alertmanager/
    
    # Create systemd service
    cat > /etc/systemd/system/alertmanager.service << EOF
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=monitoring
Group=monitoring
Type=simple
ExecStart=/usr/local/bin/alertmanager \\
    --config.file=/opt/monitoring/alertmanager/config/alertmanager.yml \\
    --storage.path=/opt/monitoring/alertmanager/data \\
    --web.listen-address=0.0.0.0:9093

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable alertmanager
}

# Create Grafana configuration
configure_grafana() {
    log "Configuring Grafana..."
    
    # Create Grafana datasource
    cat > /opt/monitoring/grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
EOF
    
    # Create dashboard provisioning
    cat > /opt/monitoring/grafana/provisioning/dashboards/default.yml << EOF
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /opt/monitoring/grafana/dashboards
EOF
    
    # Create Nomad dashboard
    cat > /opt/monitoring/grafana/dashboards/nomad-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Nomad Cluster Overview",
    "tags": ["nomad"],
    "style": "dark",
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Nomad Nodes",
        "type": "stat",
        "targets": [
          {
            "expr": "count(up{job=\"nomad\"})",
            "legendFormat": "Total Nodes"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Running Jobs",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(nomad_nomad_job_summary_running)",
            "legendFormat": "Running Jobs"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF
    
    chown -R monitoring:monitoring /opt/monitoring/grafana/
}

# Create log aggregation setup
setup_log_aggregation() {
    log "Setting up log aggregation..."
    
    # Install Loki
    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v2.9.0/loki-linux-amd64.zip"
    unzip -q loki-linux-amd64.zip
    mv loki-linux-amd64 /usr/local/bin/loki
    chmod +x /usr/local/bin/loki
    rm loki-linux-amd64.zip
    
    # Create Loki directories
    mkdir -p /opt/loki/{data,config}
    chown -R monitoring:monitoring /opt/loki/
    
    # Configure Loki
    cat > /opt/loki/config/loki.yml << EOF
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 1h
  max_chunk_age: 1h
  chunk_target_size: 1048576
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /opt/loki/data/boltdb-shipper-active
    cache_location: /opt/loki/data/boltdb-shipper-cache
    shared_store: filesystem
  filesystem:
    directory: /opt/loki/data/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOF
    
    # Create Loki systemd service
    cat > /etc/systemd/system/loki.service << EOF
[Unit]
Description=Loki
Wants=network-online.target
After=network-online.target

[Service]
User=monitoring
Group=monitoring
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/opt/loki/config/loki.yml

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable loki
}

# Create monitoring startup script
create_monitoring_startup() {
    log "Creating monitoring startup script..."
    
    cat > /opt/scripts/start-monitoring.sh << 'EOF'
#!/bin/bash

# Start all monitoring services
set -euo pipefail

echo "Starting monitoring services..."

# Start Prometheus
systemctl start prometheus
echo "✓ Prometheus started"

# Start Alertmanager
systemctl start alertmanager
echo "✓ Alertmanager started"

# Start Loki
systemctl start loki
echo "✓ Loki started"

# Wait for services to be ready
sleep 10

# Check service status
echo "Checking service status..."
systemctl is-active prometheus && echo "✓ Prometheus is running"
systemctl is-active alertmanager && echo "✓ Alertmanager is running"
systemctl is-active loki && echo "✓ Loki is running"

echo "Monitoring stack started successfully!"
echo "Access URLs:"
echo "- Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo "- Alertmanager: http://$(hostname -I | awk '{print $1}'):9093"
echo "- Grafana: http://$(hostname -I | awk '{print $1}'):3000"
EOF
    
    chmod +x /opt/scripts/start-monitoring.sh
}

# Main execution
main() {
    log "Setting up monitoring and logging for Nomad cluster..."
    
    create_monitoring_directories
    install_prometheus
    configure_prometheus
    create_prometheus_service
    install_alertmanager
    configure_grafana
    setup_log_aggregation
    create_monitoring_startup
    
    log "Monitoring setup completed successfully!"
    log "To start monitoring services, run: /opt/scripts/start-monitoring.sh"
    
    warn "Don't forget to:"
    warn "1. Configure email settings in Alertmanager"
    warn "2. Set up Grafana admin password"
    warn "3. Import additional dashboards as needed"
}

main "$@"

