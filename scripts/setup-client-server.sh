#!/bin/bash
# Complete Client Setup Script
# This should be run on the client server after management server is set up

set -euo pipefail

# THESE VALUES WILL BE FILLED BY THE MANAGEMENT SERVER SETUP
# Or you can manually set them from the management server output
MANAGEMENT_SERVER_PRIVATE_IP="FILL_FROM_MANAGEMENT_SERVER"
CONSUL_ENCRYPT="FILL_FROM_MANAGEMENT_SERVER"
NOMAD_ENCRYPT="FILL_FROM_MANAGEMENT_SERVER"
CONSUL_CLIENT_TOKEN="FILL_FROM_MANAGEMENT_SERVER"
NOMAD_CLIENT_TOKEN="FILL_FROM_MANAGEMENT_SERVER"

# Docker credentials
DOCKER_USERNAME="friendy21"
DOCKER_TOKEN="dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U"

echo "Setting up Nomad/Consul Client Node..."

# Update system
apt-get update && apt-get upgrade -y
apt-get install -y curl unzip jq docker.io ufw

# Configure firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow from $MANAGEMENT_SERVER_PRIVATE_IP comment 'Management Server'
ufw --force enable

# Install HashiCorp tools
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update
apt-get install -y nomad consul

# Create directories
mkdir -p /opt/{nomad,consul}/{data,tls}
mkdir -p /etc/{nomad,consul}.d

# Setup Docker
systemctl enable docker
systemctl start docker

# Setup Docker authentication
mkdir -p /root/.docker
cat > /root/.docker/config.json << EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$(echo -n "${DOCKER_USERNAME}:${DOCKER_TOKEN}" | base64 -w 0)"
    }
  }
}
EOF
chmod 600 /root/.docker/config.json

# Get client IP
CLIENT_PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Configure Consul client
cat > /etc/consul.d/consul.hcl << EOF
datacenter = "dc1"
data_dir = "/opt/consul/data"
log_level = "INFO"
server = false

bind_addr = "${CLIENT_PRIVATE_IP}"
client_addr = "0.0.0.0"

retry_join = ["${MANAGEMENT_SERVER_PRIVATE_IP}"]

encrypt = "${CONSUL_ENCRYPT}"

acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  
  tokens {
    agent = "${CONSUL_CLIENT_TOKEN}"
    default = "${CONSUL_CLIENT_TOKEN}"
  }
}

verify_incoming = false
verify_outgoing = true
verify_server_hostname = false

auto_encrypt {
  tls = true
}
EOF

# Configure Nomad client
cat > /etc/nomad.d/nomad.hcl << EOF
datacenter = "dc1"
data_dir = "/opt/nomad/data"
log_level = "INFO"

bind_addr = "0.0.0.0"

advertise {
  http = "${CLIENT_PRIVATE_IP}:4646"
  rpc  = "${CLIENT_PRIVATE_IP}:4647"
  serf = "${CLIENT_PRIVATE_IP}:4648"
}

server {
  enabled = false
}

client {
  enabled = true
  servers = ["${MANAGEMENT_SERVER_PRIVATE_IP}:4647"]
  
  node_class = "worker"
  
  reserved {
    cpu    = 500
    memory = 512
    disk   = 1024
  }
  
  options {
    "docker.auth.config" = "/root/.docker/config.json"
    "docker.volumes.enabled" = true
    "docker.privileged.enabled" = false
  }
}

acl {
  enabled = true
  token_ttl = "30s"
  policy_ttl = "60s"
}

consul {
  address = "127.0.0.1:8500"
  client_service_name = "nomad-client"
  auto_advertise = true
  client_auto_join = true
  token = "${CONSUL_CLIENT_TOKEN}"
}

tls {
  http = false
  rpc  = true
  verify_server_hostname = false
}

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
    allow_privileged = false
  }
}
EOF

# Set Nomad client token as environment variable
cat > /etc/systemd/system/nomad.service.d/override.conf << EOF
[Service]
Environment="NOMAD_TOKEN=${NOMAD_CLIENT_TOKEN}"
EOF

# Start services
systemctl daemon-reload
systemctl enable consul nomad
systemctl start consul
sleep 10
systemctl start nomad

echo "Client setup complete!"
echo "Verify with: nomad node status"
