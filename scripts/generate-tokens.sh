#!/bin/bash
# Script to generate additional tokens if needed

set -euo pipefail

# Source existing tokens
source /root/tokens/all-tokens.env

# Function to create a new Nomad deployment token
create_nomad_deployment_token() {
    local token_name=$1
    local description=$2
    
    echo "Creating Nomad deployment token: $token_name"
    
    token=$(nomad acl token create \
        -name="$token_name" \
        -policy="deployment-policy" \
        -type="client" \
        -json | jq -r '.SecretID')
    
    echo "Token created: $token"
    echo "$token_name=$token" >> /root/tokens/additional-tokens.env
}

# Function to create a new Consul service token
create_consul_service_token() {
    local token_name=$1
    local service_name=$2
    
    echo "Creating Consul service token for: $service_name"
    
    # Create service-specific policy
    cat > /tmp/service-policy.hcl << EOF
service "${service_name}" {
  policy = "write"
}
service_prefix "" {
  policy = "read"
}
node_prefix "" {
  policy = "read"
}
EOF
    
    consul acl policy create -name "${service_name}-policy" -rules @/tmp/service-policy.hcl
    
    token=$(consul acl token create \
        -description "Token for ${service_name} service" \
        -policy-name "${service_name}-policy" \
        -format json | jq -r '.SecretID')
    
    echo "Token created: $token"
    echo "${service_name}_CONSUL_TOKEN=$token" >> /root/tokens/additional-tokens.env
}

# Display current tokens
display_tokens() {
    echo "=========================================="
    echo "Current Token Configuration"
    echo "=========================================="
    
    if [ -f /root/tokens/all-tokens.env ]; then
        echo "Main Tokens:"
        grep "TOKEN=" /root/tokens/all-tokens.env | sed 's/export //'
    fi
    
    if [ -f /root/tokens/additional-tokens.env ]; then
        echo ""
        echo "Additional Tokens:"
        cat /root/tokens/additional-tokens.env
    fi
}

# Main menu
case ${1:-display} in
    nomad-deploy)
        create_nomad_deployment_token "$2" "${3:-New deployment token}"
        ;;
    consul-service)
        create_consul_service_token "$2" "$3"
        ;;
    display)
        display_tokens
        ;;
    *)
        echo "Usage: $0 [nomad-deploy|consul-service|display]"
        echo "  nomad-deploy <name> <description>"
        echo "  consul-service <name> <service-name>"
        echo "  display - Show all tokens"
        ;;
esac
