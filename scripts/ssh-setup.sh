#!/bin/bash

# SSH Setup Script for CI/CD Pipeline
# This script configures SSH access for automated deployments

set -euo pipefail

# Configuration
SSH_KEY_PATH="$HOME/.ssh/id_rsa_cicd"
SSH_CONFIG_PATH="$HOME/.ssh/config"
KNOWN_HOSTS_PATH="$HOME/.ssh/known_hosts"

# Server configurations
PRODUCTION_SERVERS=(
    "137.184.198.14"
    "137.184.85.0"
)

STAGING_SERVERS=(
    "137.184.85.0"  # Using secondary server for staging
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Create SSH directory if it doesn't exist
setup_ssh_directory() {
    log "Setting up SSH directory..."
    
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # Create SSH config if it doesn't exist
    touch "$SSH_CONFIG_PATH"
    chmod 600 "$SSH_CONFIG_PATH"
    
    # Create known_hosts if it doesn't exist
    touch "$KNOWN_HOSTS_PATH"
    chmod 644 "$KNOWN_HOSTS_PATH"
}

# Create SSH key for CI/CD
create_ssh_key() {
    log "Creating SSH key for CI/CD..."
    
    if [[ -f "$SSH_KEY_PATH" ]]; then
        warn "SSH key already exists at $SSH_KEY_PATH"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping SSH key creation"
            return
        fi
    fi
    
    # Generate SSH key
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "cicd-pipeline@$(hostname)"
    chmod 600 "$SSH_KEY_PATH"
    chmod 644 "$SSH_KEY_PATH.pub"
    
    log "SSH key created successfully"
    log "Public key:"
    cat "$SSH_KEY_PATH.pub"
}

# Add servers to known hosts
add_known_hosts() {
    log "Adding servers to known hosts..."
    
    local servers=("${PRODUCTION_SERVERS[@]}" "${STAGING_SERVERS[@]}")
    
    for server in "${servers[@]}"; do
        log "Adding $server to known hosts..."
        
        # Remove existing entry if it exists
        ssh-keygen -R "$server" 2>/dev/null || true
        
        # Add new entry
        ssh-keyscan -H "$server" >> "$KNOWN_HOSTS_PATH" 2>/dev/null || {
            warn "Failed to add $server to known hosts. Server might be unreachable."
        }
    done
    
    log "Known hosts updated"
}

# Configure SSH config file
configure_ssh_config() {
    log "Configuring SSH config..."
    
    # Backup existing config
    if [[ -f "$SSH_CONFIG_PATH" ]] && [[ -s "$SSH_CONFIG_PATH" ]]; then
        cp "$SSH_CONFIG_PATH" "$SSH_CONFIG_PATH.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create SSH config
    cat > "$SSH_CONFIG_PATH" << EOF
# SSH Configuration for CI/CD Pipeline
# Generated on $(date)

# Global settings
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    StrictHostKeyChecking yes
    UserKnownHostsFile ~/.ssh/known_hosts
    IdentitiesOnly yes
    AddKeysToAgent yes

# Production servers
Host prod-primary
    HostName 137.184.198.14
    User root
    IdentityFile $SSH_KEY_PATH
    Port 22
    ConnectTimeout 10

Host prod-secondary
    HostName 137.184.85.0
    User root
    IdentityFile $SSH_KEY_PATH
    Port 22
    ConnectTimeout 10

# Staging server
Host staging
    HostName 137.184.85.0
    User root
    IdentityFile $SSH_KEY_PATH
    Port 22
    ConnectTimeout 10

# Production cluster (for parallel deployment)
Host prod-cluster
    HostName 137.184.198.14
    User root
    IdentityFile $SSH_KEY_PATH
    ProxyCommand none

# Aliases for easier access
Host nomad-prod-1
    HostName 137.184.198.14
    User root
    IdentityFile $SSH_KEY_PATH

Host nomad-prod-2
    HostName 137.184.85.0
    User root
    IdentityFile $SSH_KEY_PATH
EOF
    
    chmod 600 "$SSH_CONFIG_PATH"
    log "SSH config configured successfully"
}

# Test SSH connections
test_ssh_connections() {
    log "Testing SSH connections..."
    
    local hosts=("prod-primary" "prod-secondary" "staging")
    
    for host in "${hosts[@]}"; do
        log "Testing connection to $host..."
        
        if ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "echo 'SSH connection successful'" 2>/dev/null; then
            log "✓ Connection to $host successful"
        else
            warn "✗ Connection to $host failed"
        fi
    done
}

# Deploy SSH key to servers
deploy_ssh_key() {
    log "Deploying SSH key to servers..."
    
    if [[ ! -f "$SSH_KEY_PATH.pub" ]]; then
        error "SSH public key not found. Please run create_ssh_key first."
    fi
    
    local public_key=$(cat "$SSH_KEY_PATH.pub")
    
    for server in "${PRODUCTION_SERVERS[@]}"; do
        log "Deploying SSH key to $server..."
        
        # This requires password authentication or existing key access
        if ssh-copy-id -i "$SSH_KEY_PATH.pub" "root@$server" 2>/dev/null; then
            log "✓ SSH key deployed to $server"
        else
            warn "✗ Failed to deploy SSH key to $server"
            warn "You may need to manually add the following public key to $server:/root/.ssh/authorized_keys"
            echo "$public_key"
        fi
    done
}

# Create deployment helper scripts
create_helper_scripts() {
    log "Creating deployment helper scripts..."
    
    # Create scripts directory
    mkdir -p ~/scripts
    
    # Parallel deployment script
    cat > ~/scripts/deploy-parallel.sh << 'EOF'
#!/bin/bash

# Parallel deployment script
set -euo pipefail

JOB_FILE=${1:-}
if [[ -z "$JOB_FILE" ]]; then
    echo "Usage: $0 <job_file.nomad.hcl>"
    exit 1
fi

SERVERS=("prod-primary" "prod-secondary")

echo "Deploying $JOB_FILE to production cluster..."

for server in "${SERVERS[@]}"; do
    echo "Deploying to $server..."
    (
        scp "$JOB_FILE" "$server:/tmp/"
        ssh "$server" "
            cd /tmp
            nomad job validate $(basename $JOB_FILE)
            nomad job run $(basename $JOB_FILE)
            rm $(basename $JOB_FILE)
        "
    ) &
done

wait
echo "Parallel deployment completed"
EOF
    
    # Health check script
    cat > ~/scripts/health-check-all.sh << 'EOF'
#!/bin/bash

# Health check for all servers
set -euo pipefail

SERVERS=("prod-primary" "prod-secondary" "staging")

for server in "${SERVERS[@]}"; do
    echo "=== Health check for $server ==="
    ssh "$server" "
        echo 'Nomad status:'
        nomad node status
        echo
        echo 'Consul status:'
        consul members
        echo
        echo 'System resources:'
        df -h / | tail -1
        free -h | grep Mem
        echo
    " || echo "Failed to connect to $server"
    echo
done
EOF
    
    # Log collection script
    cat > ~/scripts/collect-logs.sh << 'EOF'
#!/bin/bash

# Log collection script
set -euo pipefail

SERVER=${1:-prod-primary}
LOG_DIR="logs/$(date +%Y%m%d_%H%M%S)"

mkdir -p "$LOG_DIR"

echo "Collecting logs from $SERVER..."

# Collect Nomad logs
ssh "$SERVER" "journalctl -u nomad --since '1 hour ago' --no-pager" > "$LOG_DIR/nomad.log"

# Collect Consul logs
ssh "$SERVER" "journalctl -u consul --since '1 hour ago' --no-pager" > "$LOG_DIR/consul.log"

# Collect system logs
ssh "$SERVER" "journalctl --since '1 hour ago' --no-pager" > "$LOG_DIR/system.log"

# Collect Docker logs
ssh "$SERVER" "docker logs --since 1h \$(docker ps -q) 2>&1" > "$LOG_DIR/docker.log" || true

echo "Logs collected in $LOG_DIR"
EOF
    
    # Make scripts executable
    chmod +x ~/scripts/*.sh
    
    log "Helper scripts created in ~/scripts/"
}

# Generate GitHub Actions secrets
generate_github_secrets() {
    log "Generating GitHub Actions secrets..."
    
    echo "Add the following secrets to your GitHub repository:"
    echo "Settings → Secrets and variables → Actions → New repository secret"
    echo
    echo "DOCKERHUB_TOKEN:"
    echo "dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U"
    echo
    echo "DO_SSH_KEY:"
    if [[ -f "$SSH_KEY_PATH" ]]; then
        cat "$SSH_KEY_PATH"
    else
        echo "SSH key not found. Please run create_ssh_key first."
    fi
    echo
    echo "DO_API_TOKEN:"
    echo "dop_v1_0f43a49f6f0618370674fa79a9d8a9e2e18775196378b9c6bcd35589a99fc0a8"
    echo
    echo "DO_STAGING_HOST:"
    echo "137.184.85.0"
}

# Main menu
show_menu() {
    echo
    echo "SSH Setup for CI/CD Pipeline"
    echo "============================="
    echo "1. Setup SSH directory"
    echo "2. Create SSH key"
    echo "3. Add servers to known hosts"
    echo "4. Configure SSH config"
    echo "5. Test SSH connections"
    echo "6. Deploy SSH key to servers"
    echo "7. Create helper scripts"
    echo "8. Generate GitHub secrets"
    echo "9. Run all setup steps"
    echo "0. Exit"
    echo
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        while true; do
            show_menu
            read -p "Select an option: " choice
            
            case $choice in
                1) setup_ssh_directory ;;
                2) create_ssh_key ;;
                3) add_known_hosts ;;
                4) configure_ssh_config ;;
                5) test_ssh_connections ;;
                6) deploy_ssh_key ;;
                7) create_helper_scripts ;;
                8) generate_github_secrets ;;
                9) 
                    setup_ssh_directory
                    create_ssh_key
                    add_known_hosts
                    configure_ssh_config
                    create_helper_scripts
                    log "Setup completed! Please manually deploy SSH keys and test connections."
                    ;;
                0) exit 0 ;;
                *) warn "Invalid option" ;;
            esac
        done
    else
        case $1 in
            "setup") setup_ssh_directory ;;
            "key") create_ssh_key ;;
            "hosts") add_known_hosts ;;
            "config") configure_ssh_config ;;
            "test") test_ssh_connections ;;
            "deploy") deploy_ssh_key ;;
            "scripts") create_helper_scripts ;;
            "secrets") generate_github_secrets ;;
            "all")
                setup_ssh_directory
                create_ssh_key
                add_known_hosts
                configure_ssh_config
                create_helper_scripts
                ;;
            *) 
                echo "Usage: $0 [setup|key|hosts|config|test|deploy|scripts|secrets|all]"
                exit 1
                ;;
        esac
    fi
}

main "$@"

