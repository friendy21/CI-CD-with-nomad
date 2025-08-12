#!/bin/bash

# Server Setup Script for Nomad and Consul on DigitalOcean
# This script sets up a complete Nomad and Consul cluster on Ubuntu 22.04

set -euo pipefail

# Configuration variables
NOMAD_VERSION="1.6.3"
CONSUL_VERSION="1.16.1"
DOCKER_COMPOSE_VERSION="2.21.0"
TRAEFIK_VERSION="3.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."
    apt-get update && apt-get upgrade -y
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        unzip \
        wget \
        jq \
        htop \
        vim \
        git \
        ufw \
        fail2ban \
        tree \
        net-tools
}

# Configure firewall
setup_firewall() {
    log "Configuring UFW firewall..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH
    ufw allow 22/tcp comment 'SSH'
    
    # HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    # Nomad
    ufw allow 4646/tcp comment 'Nomad HTTP API'
    ufw allow 4647/tcp comment 'Nomad RPC'
    ufw allow 4648/tcp comment 'Nomad Serf WAN'
    
    # Consul
    ufw allow 8500/tcp comment 'Consul HTTP API'
    ufw allow 8300/tcp comment 'Consul Server RPC'
    ufw allow 8301/tcp comment 'Consul Serf LAN'
    ufw allow 8302/tcp comment 'Consul Serf WAN'
    ufw allow 8600/udp comment 'Consul DNS'
    
    # Docker Swarm (if needed)
    ufw allow 2376/tcp comment 'Docker daemon'
    ufw allow 2377/tcp comment 'Docker Swarm'
    ufw allow 7946/tcp comment 'Docker Swarm'
    ufw allow 7946/udp comment 'Docker Swarm'
    ufw allow 4789/udp comment 'Docker overlay'
    
    # Enable firewall
    ufw --force enable
    
    log "Firewall configured successfully"
}

# Install Docker
install_docker() {
    log "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group (if not root)
    if [[ $SUDO_USER ]]; then
        usermod -aG docker $SUDO_USER
    fi
    
    # Configure Docker daemon
    cat > /etc/docker/daemon.json << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "metrics-addr": "127.0.0.1:9323",
    "default-address-pools": [
        {
            "base": "172.17.0.0/12",
            "size": 20
        },
        {
            "base": "192.168.0.0/16",
            "size": 24
        }
    ]
}
EOF
    
    systemctl restart docker
    
    log "Docker installed successfully"
}

# Install HashiCorp tools
install_hashicorp_tools() {
    log "Installing HashiCorp tools..."
    
    # Add HashiCorp GPG key
    curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
    
    # Add HashiCorp repository
    apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    
    # Update package list
    apt-get update
    
    # Install Nomad and Consul
    apt-get install -y nomad=$NOMAD_VERSION consul=$CONSUL_VERSION
    
    # Hold packages to prevent automatic updates
    apt-mark hold nomad consul
    
    log "HashiCorp tools installed successfully"
}

# Create necessary directories
create_directories() {
    log "Creating necessary directories..."
    
    # Nomad directories
    mkdir -p /etc/nomad.d
    mkdir -p /opt/nomad/data
    mkdir -p /opt/nomad/logs
    
    # Consul directories
    mkdir -p /etc/consul.d
    mkdir -p /opt/consul/data
    mkdir -p /opt/consul/logs
    
    # Application directories
    mkdir -p /opt/apps
    mkdir -p /opt/scripts
    mkdir -p /var/log/apps
    
    # Set permissions
    chown -R nomad:nomad /opt/nomad
    chown -R consul:consul /opt/consul
    
    log "Directories created successfully"
}

# Configure Nomad
configure_nomad() {
    log "Configuring Nomad..."
    
    # Get server IP
    SERVER_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
    PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
    
    # Generate encryption key
    NOMAD_ENCRYPT_KEY=$(nomad operator keygen)
    
    cat > /etc/nomad.d/nomad.hcl << EOF
datacenter = "dc1"
data_dir = "/opt/nomad/data"
log_level = "INFO"
log_file = "/opt/nomad/logs/nomad.log"
log_rotate_duration = "24h"
log_rotate_max_files = 5

bind_addr = "$PRIVATE_IP"

server {
    enabled = true
    bootstrap_expect = 1
    
    # Server encryption
    encrypt = "$NOMAD_ENCRYPT_KEY"
    
    # Server join
    server_join {
        retry_join = ["$PRIVATE_IP"]
        retry_max = 3
        retry_interval = "15s"
    }
}

client {
    enabled = true
    
    # Client configuration
    node_class = "compute"
    
    # Reserve resources for system
    reserved {
        cpu    = 500
        memory = 512
        disk   = 1024
    }
    
    # Host volumes
    host_volume "docker-sock" {
        path = "/var/run/docker.sock"
        read_only = false
    }
    
    # Client options
    options {
        "docker.auth.config" = "/root/.docker/config.json"
        "docker.volumes.enabled" = true
        "docker.privileged.enabled" = true
    }
}

# ACL configuration
acl {
    enabled = false
    token_ttl = "30s"
    policy_ttl = "60s"
}

# Consul integration
consul {
    address = "127.0.0.1:8500"
    server_service_name = "nomad"
    client_service_name = "nomad-client"
    auto_advertise = true
    server_auto_join = true
    client_auto_join = true
}

# UI configuration
ui {
    enabled = true
    
    consul {
        ui_url = "http://$SERVER_IP:8500/ui"
    }
}

# Telemetry
telemetry {
    collection_interval = "1s"
    disable_hostname = true
    prometheus_metrics = true
    publish_allocation_metrics = true
    publish_node_metrics = true
}

# TLS configuration (disabled for now)
tls {
    http = false
    rpc  = false
}

# Plugin configuration
plugin "docker" {
    config {
        gc {
            image       = true
            image_delay = "3m"
            container   = true
        }
        volumes {
            enabled = true
        }
        allow_privileged = true
    }
}

# Vault integration (optional)
# vault {
#     enabled = true
#     address = "https://vault.service.consul:8200"
# }
EOF
    
    # Set permissions
    chown nomad:nomad /etc/nomad.d/nomad.hcl
    chmod 640 /etc/nomad.d/nomad.hcl
    
    log "Nomad configured successfully"
}

# Configure Consul
configure_consul() {
    log "Configuring Consul..."
    
    # Get server IP
    PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
    
    # Generate encryption key
    CONSUL_ENCRYPT_KEY=$(consul keygen)
    
    cat > /etc/consul.d/consul.hcl << EOF
datacenter = "dc1"
data_dir = "/opt/consul/data"
log_level = "INFO"
log_file = "/opt/consul/logs/consul.log"
log_rotate_duration = "24h"
log_rotate_max_files = 5

server = true
bootstrap_expect = 1

bind_addr = "$PRIVATE_IP"
client_addr = "0.0.0.0"

# Encryption
encrypt = "$CONSUL_ENCRYPT_KEY"

# UI configuration
ui_config {
    enabled = true
}

# Connect service mesh
connect {
    enabled = true
}

# Ports configuration
ports {
    grpc = 8502
    grpc_tls = 8503
}

# Performance
performance {
    raft_multiplier = 1
}

# Logging
enable_syslog = false

# ACL configuration (disabled for now)
acl = {
    enabled = false
    default_policy = "allow"
    enable_token_persistence = true
}

# Autopilot
autopilot {
    cleanup_dead_servers = true
    last_contact_threshold = "200ms"
    max_trailing_logs = 250
    server_stabilization_time = "10s"
}
EOF
    
    # Set permissions
    chown consul:consul /etc/consul.d/consul.hcl
    chmod 640 /etc/consul.d/consul.hcl
    
    log "Consul configured successfully"
}

# Configure systemd services
configure_services() {
    log "Configuring systemd services..."
    
    # Enable and start Consul first
    systemctl enable consul
    systemctl start consul
    
    # Wait for Consul to be ready
    sleep 10
    
    # Enable and start Nomad
    systemctl enable nomad
    systemctl start nomad
    
    # Wait for services to stabilize
    sleep 15
    
    log "Services configured and started successfully"
}

# Setup Docker Hub authentication
setup_docker_auth() {
    log "Setting up Docker Hub authentication..."
    
    # Create Docker config directory
    mkdir -p /root/.docker
    
    # Login to Docker Hub (will be configured via environment variables)
    cat > /root/.docker/config.json << EOF
{
    "auths": {
        "https://index.docker.io/v1/": {
            "auth": "$(echo -n 'friendy21:dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U' | base64 -w 0)"
        }
    }
}
EOF
    
    chmod 600 /root/.docker/config.json
    
    log "Docker Hub authentication configured"
}

# Install monitoring tools
install_monitoring() {
    log "Installing monitoring tools..."
    
    # Install Node Exporter
    wget -q https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
    tar xzf node_exporter-1.6.1.linux-amd64.tar.gz
    mv node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
    rm -rf node_exporter-1.6.1.linux-amd64*
    
    # Create node_exporter user
    useradd --no-create-home --shell /bin/false node_exporter
    
    # Create systemd service for node_exporter
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    
    log "Monitoring tools installed successfully"
}

# Create deployment scripts
create_deployment_scripts() {
    log "Creating deployment scripts..."
    
    cat > /opt/scripts/deploy.sh << 'EOF'
#!/bin/bash

# Deployment script for Nomad jobs
set -euo pipefail

JOB_FILE=${1:-}
if [[ -z "$JOB_FILE" ]]; then
    echo "Usage: $0 <job_file.nomad.hcl>"
    exit 1
fi

if [[ ! -f "$JOB_FILE" ]]; then
    echo "Error: Job file $JOB_FILE not found"
    exit 1
fi

echo "Validating job file: $JOB_FILE"
nomad job validate "$JOB_FILE"

echo "Planning deployment..."
nomad job plan "$JOB_FILE"

echo "Running deployment..."
nomad job run "$JOB_FILE"

echo "Checking job status..."
JOB_NAME=$(grep -E '^job\s+"[^"]+"' "$JOB_FILE" | sed 's/job "\([^"]*\)".*/\1/')
nomad job status "$JOB_NAME"
EOF
    
    cat > /opt/scripts/rollback.sh << 'EOF'
#!/bin/bash

# Rollback script for Nomad jobs
set -euo pipefail

JOB_NAME=${1:-}
VERSION=${2:-1}

if [[ -z "$JOB_NAME" ]]; then
    echo "Usage: $0 <job_name> [version]"
    exit 1
fi

echo "Rolling back job $JOB_NAME to version $VERSION"
nomad job revert "$JOB_NAME" "$VERSION"

echo "Checking job status after rollback..."
nomad job status "$JOB_NAME"
EOF
    
    cat > /opt/scripts/health-check.sh << 'EOF'
#!/bin/bash

# Health check script for services
set -euo pipefail

echo "=== Nomad Cluster Status ==="
nomad node status

echo -e "\n=== Consul Cluster Status ==="
consul members

echo -e "\n=== Running Jobs ==="
nomad job status

echo -e "\n=== Service Health ==="
consul catalog services

echo -e "\n=== System Resources ==="
df -h
free -h
EOF
    
    # Make scripts executable
    chmod +x /opt/scripts/*.sh
    
    log "Deployment scripts created successfully"
}

# Setup log rotation
setup_log_rotation() {
    log "Setting up log rotation..."
    
    cat > /etc/logrotate.d/nomad << EOF
/opt/nomad/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 nomad nomad
    postrotate
        systemctl reload nomad
    endscript
}
EOF
    
    cat > /etc/logrotate.d/consul << EOF
/opt/consul/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 consul consul
    postrotate
        systemctl reload consul
    endscript
}
EOF
    
    log "Log rotation configured successfully"
}

# Main execution
main() {
    log "Starting server setup for Nomad and Consul..."
    
    check_root
    update_system
    setup_firewall
    install_docker
    install_hashicorp_tools
    create_directories
    configure_consul
    configure_nomad
    setup_docker_auth
    configure_services
    install_monitoring
    create_deployment_scripts
    setup_log_rotation
    
    log "Server setup completed successfully!"
    log "Nomad UI: http://$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address):4646"
    log "Consul UI: http://$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address):8500"
    
    warn "Please reboot the server to ensure all changes take effect"
}

# Run main function
main "$@"

