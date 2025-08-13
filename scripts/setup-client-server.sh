#!/bin/bash
set -euo pipefail

# Client Server Setup Script
echo "Setting up Nomad/Consul Client Server..."

# Variables - UPDATE THESE
MANAGEMENT_SERVER_IP="YOUR_MANAGEMENT_SERVER_PRIVATE_IP"
CONSUL_ENCRYPT="YOUR_CONSUL_ENCRYPTION_KEY"
NOMAD_ENCRYPT="YOUR_NOMAD_ENCRYPTION_KEY"
CONSUL_TOKEN="YOUR_CONSUL_CLIENT_TOKEN"
DOCKER_CONFIG_JSON=$(echo -n 'friendy21:dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U' | base64 -w 0)

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
ufw allow from $MANAGEMENT_SERVER_IP comment 'Management Server'
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
      "auth": "$DOCKER_CONFIG_JSON"
    }
  }
}
EOF
chmod 600 /root/.docker/config.json

# Copy TLS certificates from management server
scp root@$MANAGEMENT_SERVER_IP:/opt/consul/tls/ca.crt /opt/consul/tls/
scp root@$MANAGEMENT_SERVER_IP:/opt/nomad/tls/ca.crt /opt/nomad/tls/

# Generate client certificates
cd /opt/nomad/tls
nomad tls cert create -client
cd /opt/consul/tls
consul tls cert create -client

# Configure Consul client (with proper tokens and encryption)
# Place consul-client.hcl here

# Configure Nomad client (with proper tokens and encryption)
# Place nomad-client.hcl here

# Start services
systemctl enable consul nomad
systemctl start consul
sleep 10
systemctl start nomad

echo "Client server setup complete!"
