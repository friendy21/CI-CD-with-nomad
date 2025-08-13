#!/bin/bash
set -euo pipefail

# Management Server Setup Script
echo "Setting up Nomad/Consul Management Server..."

# Variables
NOMAD_VERSION="1.6.3"
CONSUL_VERSION="1.16.1"
DOCKER_CONFIG_JSON=$(echo -n 'friendy21:dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U' | base64 -w 0)

# Update system
apt-get update && apt-get upgrade -y
apt-get install -y curl unzip jq docker.io ufw

# Configure firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 4646/tcp comment 'Nomad HTTP'
ufw allow 4647/tcp comment 'Nomad RPC'
ufw allow 4648/tcp comment 'Nomad Serf'
ufw allow 8500/tcp comment 'Consul HTTP'
ufw allow 8300/tcp comment 'Consul Server RPC'
ufw allow 8301/tcp comment 'Consul Serf LAN'
ufw allow 8302/tcp comment 'Consul Serf WAN'
ufw allow 8600/udp comment 'Consul DNS'
ufw --force enable

# Install HashiCorp tools
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update
apt-get install -y nomad=$NOMAD_VERSION consul=$CONSUL_VERSION

# Create directories
mkdir -p /opt/{nomad,consul}/{data,tls}
mkdir -p /etc/{nomad,consul}.d

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

# Generate encryption keys
NOMAD_ENCRYPT=$(nomad operator keygen)
CONSUL_ENCRYPT=$(consul keygen)

echo "Nomad Encryption Key: $NOMAD_ENCRYPT"
echo "Consul Encryption Key: $CONSUL_ENCRYPT"

# Generate TLS certificates
cd /opt/nomad/tls
nomad tls ca create
nomad tls cert create -server -region global -dc dc1

cd /opt/consul/tls
consul tls ca create
consul tls cert create -server -dc dc1

# Copy configurations (update with generated keys)
# Place nomad-server.hcl and consul-server.hcl here with proper keys

# Start services
systemctl enable consul nomad
systemctl start consul

# Wait for Consul
sleep 10

# Bootstrap Consul ACL
consul acl bootstrap > /tmp/consul-bootstrap.json
CONSUL_TOKEN=$(jq -r '.SecretID' /tmp/consul-bootstrap.json)
echo "Consul Management Token: $CONSUL_TOKEN"

# Start Nomad
systemctl start nomad

# Wait for Nomad
sleep 10

# Bootstrap Nomad ACL
nomad acl bootstrap > /tmp/nomad-bootstrap.json
NOMAD_TOKEN=$(grep 'Secret ID' /tmp/nomad-bootstrap.json | awk '{print $4}')
echo "Nomad Management Token: $NOMAD_TOKEN"

# Create deployment tokens
export CONSUL_HTTP_TOKEN=$CONSUL_TOKEN
export NOMAD_TOKEN=$NOMAD_TOKEN

# Create Consul policy for Nomad
cat > /tmp/nomad-consul-policy.hcl << 'EOF'
agent_prefix "" {
  policy = "read"
}
node_prefix "" {
  policy = "read"
}
service_prefix "" {
  policy = "write"
}
key_prefix "" {
  policy = "write"
}
EOF

consul acl policy create -name nomad-auto-join -rules @/tmp/nomad-consul-policy.hcl
NOMAD_CONSUL_TOKEN=$(consul acl token create -description "Token for Nomad" -policy-name nomad-auto-join -format json | jq -r '.SecretID')

# Create Nomad deployment policy
cat > /tmp/deployment-policy.hcl << 'EOF'
namespace "*" {
  policy = "write"
  capabilities = ["submit-job", "dispatch-job", "read-logs", "alloc-exec", "alloc-lifecycle"]
}
node {
  policy = "read"
}
agent {
  policy = "read"
}
EOF

nomad acl policy apply -description "Deployment policy" deployment /tmp/deployment-policy.hcl
DEPLOYMENT_TOKEN=$(nomad acl token create -name="deployment" -policy="deployment" -type="client" | grep 'Secret ID' | awk '{print $4}')

echo "=== IMPORTANT: Save these tokens ==="
echo "Consul Management Token: $CONSUL_TOKEN"
echo "Nomad Management Token: $NOMAD_TOKEN"
echo "Nomad Consul Token: $NOMAD_CONSUL_TOKEN"
echo "Deployment Token: $DEPLOYMENT_TOKEN"
echo "Nomad Encryption: $NOMAD_ENCRYPT"
echo "Consul Encryption: $CONSUL_ENCRYPT"
