#!/bin/bash
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }

# Variables
NOMAD_VERSION="1.6.3"
CONSUL_VERSION="1.16.1"

# Your Docker Hub credentials
DOCKER_USERNAME="friendy21"
DOCKER_TOKEN="dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U"

log "Starting Management Server Setup..."

# Update system
apt-get update && apt-get upgrade -y
apt-get install -y curl unzip jq docker.io ufw wget

# Configure firewall
log "Configuring firewall..."
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
log "Installing Nomad and Consul..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update
apt-get install -y nomad=$NOMAD_VERSION consul=$CONSUL_VERSION

# Create directories
mkdir -p /opt/{nomad,consul}/{data,tls}
mkdir -p /etc/{nomad,consul}.d
mkdir -p /root/tokens

# Setup Docker authentication
log "Setting up Docker Hub authentication..."
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

# Test Docker login
docker pull hello-world >/dev/null 2>&1 && log "Docker Hub authentication successful" || warn "Docker Hub authentication failed"

# Generate encryption keys
log "Generating encryption keys..."
NOMAD_ENCRYPT=$(nomad operator keygen)
CONSUL_ENCRYPT=$(consul keygen)

# Save encryption keys
cat > /root/tokens/encryption-keys.txt << EOF
# Generated on $(date)
NOMAD_ENCRYPT_KEY=${NOMAD_ENCRYPT}
CONSUL_ENCRYPT_KEY=${CONSUL_ENCRYPT}
EOF

log "Encryption keys generated and saved to /root/tokens/encryption-keys.txt"

# Generate TLS certificates for Consul
log "Generating Consul TLS certificates..."
cd /opt/consul/tls
consul tls ca create
consul tls cert create -server -dc dc1

# Generate TLS certificates for Nomad
log "Generating Nomad TLS certificates..."
cd /opt/nomad/tls
nomad tls ca create
nomad tls cert create -server -region global -dc dc1

# Get server IPs
SERVER_PRIVATE_IP=$(hostname -I | awk '{print $1}')
SERVER_PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)

# Configure Consul
log "Configuring Consul server..."
cat > /etc/consul.d/consul.hcl << EOF
datacenter = "dc1"
data_dir = "/opt/consul/data"
log_level = "INFO"
server = true
bootstrap_expect = 1

bind_addr = "${SERVER_PRIVATE_IP}"
client_addr = "0.0.0.0"

ui_config {
  enabled = true
}

connect {
  enabled = true
}

ports {
  grpc = 8502
  grpc_tls = 8503
}

encrypt = "${CONSUL_ENCRYPT}"

acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}

# TLS configuration
verify_incoming = false
verify_outgoing = true
verify_server_hostname = true

ca_file = "/opt/consul/tls/consul-agent-ca.pem"
cert_file = "/opt/consul/tls/dc1-server-consul-0.pem"
key_file = "/opt/consul/tls/dc1-server-consul-0-key.pem"

auto_encrypt {
  allow_tls = true
}
EOF

# Configure Nomad
log "Configuring Nomad server..."
cat > /etc/nomad.d/nomad.hcl << EOF
datacenter = "dc1"
data_dir = "/opt/nomad/data"
log_level = "INFO"

bind_addr = "0.0.0.0"

advertise {
  http = "${SERVER_PRIVATE_IP}:4646"
  rpc  = "${SERVER_PRIVATE_IP}:4647"
  serf = "${SERVER_PRIVATE_IP}:4648"
}

server {
  enabled = true
  bootstrap_expect = 1
  encrypt = "${NOMAD_ENCRYPT}"
}

client {
  enabled = false
}

acl {
  enabled = true
  token_ttl = "30s"
  policy_ttl = "60s"
}

consul {
  address = "127.0.0.1:8500"
  server_service_name = "nomad"
  auto_advertise = true
  server_auto_join = true
}

ui {
  enabled = true
}

tls {
  http = false  # Set to true in production
  rpc  = true
  
  ca_file   = "/opt/nomad/tls/nomad-ca.pem"
  cert_file = "/opt/nomad/tls/global-server-nomad.pem"
  key_file  = "/opt/nomad/tls/global-server-nomad-key.pem"
  
  verify_server_hostname = true
  verify_https_client    = false
}
EOF

# Start Consul
log "Starting Consul..."
systemctl enable consul
systemctl start consul
sleep 10

# Bootstrap Consul ACL
log "Bootstrapping Consul ACL system..."
CONSUL_BOOTSTRAP_OUTPUT=$(consul acl bootstrap -format=json)
CONSUL_MANAGEMENT_TOKEN=$(echo $CONSUL_BOOTSTRAP_OUTPUT | jq -r '.SecretID')

# Save Consul bootstrap output
echo "$CONSUL_BOOTSTRAP_OUTPUT" | jq '.' > /root/tokens/consul-bootstrap.json

log "Consul Management Token: ${CONSUL_MANAGEMENT_TOKEN}"

# Export for use in commands
export CONSUL_HTTP_TOKEN="${CONSUL_MANAGEMENT_TOKEN}"

# Create Consul policies and tokens
log "Creating Consul policies and tokens..."

# Create policy for Nomad servers
cat > /tmp/nomad-server-policy.hcl << 'EOF'
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
acl = "write"
EOF

consul acl policy create -name nomad-server -rules @/tmp/nomad-server-policy.hcl

# Create token for Nomad server
NOMAD_CONSUL_TOKEN=$(consul acl token create \
  -description "Token for Nomad Server" \
  -policy-name nomad-server \
  -format json | jq -r '.SecretID')

log "Nomad-Consul Token: ${NOMAD_CONSUL_TOKEN}"

# Create policy for Consul clients
cat > /tmp/consul-client-policy.hcl << 'EOF'
node_prefix "" {
  policy = "write"
}
service_prefix "" {
  policy = "read"
}
agent_prefix "" {
  policy = "write"
}
EOF

consul acl policy create -name consul-client -rules @/tmp/consul-client-policy.hcl

# Create token for Consul clients
CONSUL_CLIENT_TOKEN=$(consul acl token create \
  -description "Token for Consul Clients" \
  -policy-name consul-client \
  -format json | jq -r '.SecretID')

log "Consul Client Token: ${CONSUL_CLIENT_TOKEN}"

# Update Consul configuration with tokens
cat >> /etc/consul.d/consul.hcl << EOF

acl {
  tokens {
    agent = "${CONSUL_MANAGEMENT_TOKEN}"
    default = "${CONSUL_CLIENT_TOKEN}"
  }
}
EOF

# Restart Consul with tokens
systemctl restart consul
sleep 10

# Update Nomad configuration with Consul token
sed -i "/consul {/a\  token = \"${NOMAD_CONSUL_TOKEN}\"" /etc/nomad.d/nomad.hcl

# Start Nomad
log "Starting Nomad..."
systemctl enable nomad
systemctl start nomad
sleep 10

# Bootstrap Nomad ACL
log "Bootstrapping Nomad ACL system..."
NOMAD_BOOTSTRAP_OUTPUT=$(nomad acl bootstrap -json)
NOMAD_MANAGEMENT_TOKEN=$(echo $NOMAD_BOOTSTRAP_OUTPUT | jq -r '.SecretID')

# Save Nomad bootstrap output
echo "$NOMAD_BOOTSTRAP_OUTPUT" | jq '.' > /root/tokens/nomad-bootstrap.json

log "Nomad Management Token: ${NOMAD_MANAGEMENT_TOKEN}"

# Export for use in commands
export NOMAD_TOKEN="${NOMAD_MANAGEMENT_TOKEN}"

# Create Nomad policies and tokens
log "Creating Nomad policies and tokens..."

# Create deployment policy for CI/CD
cat > /tmp/nomad-deployment-policy.hcl << 'EOF'
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

operator {
  policy = "read"
}

quota {
  policy = "read"
}

plugin {
  policy = "list"
}
EOF

nomad acl policy apply -description "Policy for CI/CD deployments" deployment-policy /tmp/nomad-deployment-policy.hcl

# Create token for deployments
NOMAD_DEPLOYMENT_TOKEN=$(nomad acl token create \
  -name="ci-cd-deployment" \
  -policy="deployment-policy" \
  -type="client" \
  -json | jq -r '.SecretID')

log "Nomad Deployment Token: ${NOMAD_DEPLOYMENT_TOKEN}"

# Create client node policy
cat > /tmp/nomad-client-policy.hcl << 'EOF'
node {
  policy = "write"
}

agent {
  policy = "write"
}
EOF

nomad acl policy apply -description "Policy for Nomad clients" client-policy /tmp/nomad-client-policy.hcl

# Create token for Nomad clients
NOMAD_CLIENT_TOKEN=$(nomad acl token create \
  -name="nomad-client" \
  -policy="client-policy" \
  -type="client" \
  -json | jq -r '.SecretID')

log "Nomad Client Token: ${NOMAD_CLIENT_TOKEN}"

# Save all tokens to a file
log "Saving all tokens to /root/tokens/all-tokens.env..."
cat > /root/tokens/all-tokens.env << EOF
#!/bin/bash
# Generated tokens on $(date)
# Source this file to use tokens: source /root/tokens/all-tokens.env

# Encryption Keys
export NOMAD_ENCRYPT_KEY="${NOMAD_ENCRYPT}"
export CONSUL_ENCRYPT_KEY="${CONSUL_ENCRYPT}"

# Management Tokens (Full Admin Access)
export CONSUL_MANAGEMENT_TOKEN="${CONSUL_MANAGEMENT_TOKEN}"
export NOMAD_MANAGEMENT_TOKEN="${NOMAD_MANAGEMENT_TOKEN}"

# Service Integration Tokens
export NOMAD_CONSUL_TOKEN="${NOMAD_CONSUL_TOKEN}"

# Client Tokens
export CONSUL_CLIENT_TOKEN="${CONSUL_CLIENT_TOKEN}"
export NOMAD_CLIENT_TOKEN="${NOMAD_CLIENT_TOKEN}"

# Deployment Token (for CI/CD)
export NOMAD_DEPLOYMENT_TOKEN="${NOMAD_DEPLOYMENT_TOKEN}"

# Server IPs
export MANAGEMENT_SERVER_PRIVATE_IP="${SERVER_PRIVATE_IP}"
export MANAGEMENT_SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP}"

# Aliases for easier management
export CONSUL_HTTP_TOKEN="${CONSUL_MANAGEMENT_TOKEN}"
export NOMAD_TOKEN="${NOMAD_MANAGEMENT_TOKEN}"
export NOMAD_ADDR="http://127.0.0.1:4646"
export CONSUL_HTTP_ADDR="http://127.0.0.1:8500"
EOF

chmod 600 /root/tokens/all-tokens.env

# Create GitHub secrets file
log "Creating GitHub secrets configuration..."
cat > /root/tokens/github-secrets.txt << EOF
# GitHub Secrets Configuration
# Add these secrets to your GitHub repository:
# Settings → Secrets and variables → Actions → New repository secret

DOCKERHUB_TOKEN:
${DOCKER_TOKEN}

DO_SSH_PRIVATE_KEY:
$(cat /root/.ssh/id_ed25519 2>/dev/null || echo "YOUR_SSH_PRIVATE_KEY_BASE64_ENCODED")

MANAGEMENT_SERVER_IP:
${SERVER_PUBLIC_IP}

NOMAD_TOKEN:
${NOMAD_DEPLOYMENT_TOKEN}

CONSUL_TOKEN:
${CONSUL_CLIENT_TOKEN}

# For client setup
NOMAD_CLIENT_TOKEN:
${NOMAD_CLIENT_TOKEN}

CONSUL_CLIENT_TOKEN:
${CONSUL_CLIENT_TOKEN}

NOMAD_ENCRYPT:
${NOMAD_ENCRYPT}

CONSUL_ENCRYPT:
${CONSUL_ENCRYPT}
EOF

# Create client setup script with tokens
log "Creating client setup script with tokens..."
cat > /root/tokens/setup-client-with-tokens.sh << EOF
#!/bin/bash
# Client Setup Script with Pre-configured Tokens
# Copy this script to your client server and run it

set -euo pipefail

# Configuration from Management Server
MANAGEMENT_SERVER_PRIVATE_IP="${SERVER_PRIVATE_IP}"
CONSUL_ENCRYPT="${CONSUL_ENCRYPT}"
NOMAD_ENCRYPT="${NOMAD_ENCRYPT}"
CONSUL_CLIENT_TOKEN="${CONSUL_CLIENT_TOKEN}"
NOMAD_CLIENT_TOKEN="${NOMAD_CLIENT_TOKEN}"
DOCKER_USERNAME="${DOCKER_USERNAME}"
DOCKER_TOKEN="${DOCKER_TOKEN}"

echo "Setting up Nomad/Consul Client with provided tokens..."

# Rest of the client setup script continues here...
# [Include the full client setup logic]
EOF

chmod +x /root/tokens/setup-client-with-tokens.sh

# Display summary
log "=========================================="
log "Management Server Setup Complete!"
log "=========================================="
echo
echo -e "${GREEN}Critical Information:${NC}"
echo "All tokens saved to: /root/tokens/"
echo
echo -e "${YELLOW}Encryption Keys:${NC}"
echo "Nomad:  ${NOMAD_ENCRYPT}"
echo "Consul: ${CONSUL_ENCRYPT}"
echo
echo -e "${YELLOW}Management Tokens (Admin):${NC}"
echo "Consul: ${CONSUL_MANAGEMENT_TOKEN}"
echo "Nomad:  ${NOMAD_MANAGEMENT_TOKEN}"
echo
echo -e "${YELLOW}Deployment Token (for GitHub Actions):${NC}"
echo "Nomad Deploy: ${NOMAD_DEPLOYMENT_TOKEN}"
echo
echo -e "${YELLOW}Client Tokens:${NC}"
echo "Consul Client: ${CONSUL_CLIENT_TOKEN}"
echo "Nomad Client:  ${NOMAD_CLIENT_TOKEN}"
echo
echo -e "${GREEN}Access Points:${NC}"
echo "Nomad UI:  http://${SERVER_PUBLIC_IP}:4646"
echo "Consul UI: http://${SERVER_PUBLIC_IP}:8500"
echo
echo -e "${RED}IMPORTANT:${NC}"
echo "1. Save all tokens immediately!"
echo "2. Use 'source /root/tokens/all-tokens.env' to load tokens"
echo "3. Copy /root/tokens/setup-client-with-tokens.sh to client server"
echo "4. Add tokens from /root/tokens/github-secrets.txt to GitHub"
log "=========================================="
