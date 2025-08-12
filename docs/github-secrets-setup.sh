#!/bin/bash

# GitHub Secrets Configuration Script
# This script helps configure the required secrets for the CI/CD pipeline

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   GitHub Secrets Configuration Setup   ${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Function to check if GitHub CLI is installed
check_gh_cli() {
    if command -v gh &> /dev/null; then
        echo -e "${GREEN}✓ GitHub CLI is installed${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ GitHub CLI is not installed${NC}"
        echo "Install it from: https://cli.github.com/"
        return 1
    fi
}

# Function to check GitHub authentication
check_gh_auth() {
    if gh auth status &> /dev/null; then
        echo -e "${GREEN}✓ GitHub CLI is authenticated${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ GitHub CLI is not authenticated${NC}"
        echo "Run: gh auth login"
        return 1
    fi
}

# Create the secrets using GitHub CLI
setup_with_gh_cli() {
    echo -e "${GREEN}Setting up secrets using GitHub CLI...${NC}"
    
    # DOCKERHUB_TOKEN
    echo -e "${YELLOW}Setting DOCKERHUB_TOKEN...${NC}"
    echo "dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U" | gh secret set DOCKERHUB_TOKEN
    echo -e "${GREEN}✓ DOCKERHUB_TOKEN configured${NC}"
    
    # DO_SSH_PRIVATE_KEY
    echo -e "${YELLOW}Setting DO_SSH_PRIVATE_KEY...${NC}"
    cat << 'EOF' | gh secret set DO_SSH_PRIVATE_KEY
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDwAAAKDCQdK8wkHS
vAAAAAtzcmgtZWQyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDw
AAAAEA3wko/j62bhyK/XNYHWCrtOUS13VaekeqQDZaTYqixeYSAnHT9v/8qCM8dOW48+Fkd
eUctCxGJOVVMnVL6plgPAAAAGGZyaWVuZHlrYWxpbWFuQGdtYWlsLmNvbQECAwQF
-----END OPENSSH PRIVATE KEY-----
EOF
    echo -e "${GREEN}✓ DO_SSH_PRIVATE_KEY configured${NC}"
    
    echo
    echo -e "${GREEN}✓ All secrets have been configured successfully!${NC}"
}

# Manual setup instructions
manual_setup() {
    echo -e "${YELLOW}Manual Setup Instructions${NC}"
    echo -e "${YELLOW}=========================${NC}"
    echo
    echo "1. Go to your GitHub repository"
    echo "2. Click on 'Settings' tab"
    echo "3. In the left sidebar, click 'Secrets and variables' → 'Actions'"
    echo "4. Click 'New repository secret' and add the following:"
    echo
    echo -e "${BLUE}Secret 1: DOCKERHUB_TOKEN${NC}"
    echo "Name: DOCKERHUB_TOKEN"
    echo "Value: dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U"
    echo
    echo -e "${BLUE}Secret 2: DO_SSH_PRIVATE_KEY${NC}"
    echo "Name: DO_SSH_PRIVATE_KEY"
    echo "Value: (copy the entire block below including BEGIN and END lines)"
    cat << 'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDwAAAKDCQdK8wkHS
vAAAAAtzcmgtZWQyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDw
AAAAEA3wko/j62bhyK/XNYHWCrtOUS13VaekeqQDZaTYqixeYSAnHT9v/8qCM8dOW48+Fkd
eUctCxGJOVVMnVL6plgPAAAAGGZyaWVuZHlrYWxpbWFuQGdtYWlsLmNvbQECAwQF
-----END OPENSSH PRIVATE KEY-----
EOF
    echo
}

# Test SSH connection
test_ssh_connection() {
    echo -e "${YELLOW}Testing SSH connection to servers...${NC}"
    
    # Create temporary SSH key file
    TEMP_KEY=$(mktemp)
    cat << 'EOF' > "$TEMP_KEY"
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDwAAAKDCQdK8wkHS
vAAAAAtzcmgtZWQyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDw
AAAAEA3wko/j62bhyK/XNYHWCrtOUS13VaekeqQDZaTYqixeYSAnHT9v/8qCM8dOW48+Fkd
eUctCxGJOVVMnVL6plgPAAAAGGZyaWVuZHlrYWxpbWFuQGdtYWlsLmNvbQECAwQF
-----END OPENSSH PRIVATE KEY-----
EOF
    chmod 600 "$TEMP_KEY"
    
    # Test connection to primary server
    echo -n "Testing connection to 137.184.198.14... "
    if ssh -i "$TEMP_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@137.184.198.14 "echo 'OK'" 2>/dev/null; then
        echo -e "${GREEN}✓ Success${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    # Clean up
    rm -f "$TEMP_KEY"
}

# Verify workflow file
verify_workflow() {
    echo -e "${YELLOW}Verifying workflow file...${NC}"
    
    if [ -f ".github/workflows/main.yml" ]; then
        echo -e "${GREEN}✓ Workflow file exists${NC}"
        
        # Check for common issues
        if grep -q '\${{ secrets.DOCKERHUB_USERNAME }}' .github/workflows/main.yml; then
            echo -e "${RED}✗ Workflow uses secrets.DOCKERHUB_USERNAME instead of env.DOCKERHUB_USERNAME${NC}"
            echo "  This will be fixed automatically..."
        fi
    else
        echo -e "${RED}✗ Workflow file not found at .github/workflows/main.yml${NC}"
    fi
}

# Main menu
main() {
    echo "This script will help you configure GitHub secrets for the CI/CD pipeline."
    echo
    
    # Check prerequisites
    if check_gh_cli && check_gh_auth; then
        echo
        echo -e "${GREEN}GitHub CLI is ready!${NC}"
        echo
        read -p "Do you want to automatically configure secrets using GitHub CLI? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_with_gh_cli
        else
            manual_setup
        fi
    else
        echo
        echo -e "${YELLOW}GitHub CLI is not available. Showing manual setup instructions...${NC}"
        echo
        manual_setup
    fi
    
    echo
    echo -e "${BLUE}Additional Steps:${NC}"
    echo "1. Replace .github/workflows/main.yml with the fixed version"
    echo "2. Commit and push the changes to trigger the workflow"
    echo "3. Monitor the Actions tab in GitHub for deployment status"
    echo
    
    read -p "Do you want to test SSH connectivity now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_ssh_connection
    fi
    
    echo
    echo -e "${GREEN}Setup instructions complete!${NC}"
    echo "After configuring the secrets, push to main branch to trigger deployment."
}

# Run main function
main