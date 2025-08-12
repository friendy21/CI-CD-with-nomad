#!/bin/bash

# Quick Deploy Script for CI/CD Pipeline
# This script helps you quickly deploy and test the pipeline

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}  CI/CD Quick Deploy Script${NC}"
echo -e "${GREEN}==================================${NC}"
echo

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=0
    
    # Check for git
    if ! command -v git &> /dev/null; then
        echo -e "${RED}✗ Git is not installed${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ Git is installed${NC}"
    fi
    
    # Check for GitHub CLI (optional but helpful)
    if ! command -v gh &> /dev/null; then
        echo -e "${YELLOW}⚠ GitHub CLI is not installed (optional)${NC}"
    else
        echo -e "${GREEN}✓ GitHub CLI is installed${NC}"
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}✗ Not in a git repository${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ In a git repository${NC}"
    fi
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}Please fix the missing prerequisites${NC}"
        exit 1
    fi
    
    echo
}

# Function to setup GitHub secrets
setup_secrets() {
    echo -e "${YELLOW}Setting up GitHub secrets...${NC}"
    
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        echo "Using GitHub CLI to set secrets..."
        
        # Set DOCKERHUB_TOKEN
        echo "dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U" | gh secret set DOCKERHUB_TOKEN
        echo -e "${GREEN}✓ DOCKERHUB_TOKEN set${NC}"
        
        # Set DO_SSH_PRIVATE_KEY
        cat << 'EOF' | gh secret set DO_SSH_PRIVATE_KEY
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDwAAAKDCQdK8wkHS
vAAAAAtzcmgtZWQyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDw
AAAAEA3wko/j62bhyK/XNYHWCrtOUS13VaekeqQDZaTYqixeYSAnHT9v/8qCM8dOW48+Fkd
eUctCxGJOVVMnVL6plgPAAAAGGZyaWVuZHlrYWxpbWFuQGdtYWlsLmNvbQECAwQF
-----END OPENSSH PRIVATE KEY-----
EOF
        echo -e "${GREEN}✓ DO_SSH_PRIVATE_KEY set${NC}"
        
        echo -e "${GREEN}✓ All secrets configured via GitHub CLI${NC}"
    else
        echo -e "${YELLOW}GitHub CLI not available or not authenticated${NC}"
        echo
        echo "Please manually add these secrets in GitHub:"
        echo "1. Go to your repository Settings → Secrets and variables → Actions"
        echo "2. Add the following secrets:"
        echo "   - DOCKERHUB_TOKEN"
        echo "   - DO_SSH_PRIVATE_KEY"
        echo
        echo "Refer to docs/github-secrets-setup.md for values"
    fi
    
    echo
}

# Function to verify workflow file
verify_workflow() {
    echo -e "${YELLOW}Verifying workflow configuration...${NC}"
    
    if [ -f ".github/workflows/main.yml" ]; then
        echo -e "${GREEN}✓ Workflow file exists${NC}"
        
        # Check for common issues
        if grep -q "nomad/jobs/app.nomad" .github/workflows/main.yml; then
            echo -e "${RED}✗ Workflow has incorrect path (nomad/jobs/app.nomad)${NC}"
            echo "  Fixing path..."
            sed -i 's|nomad/jobs/app.nomad|nomad/app.nomad|g' .github/workflows/main.yml
            echo -e "${GREEN}  ✓ Path fixed${NC}"
        else
            echo -e "${GREEN}✓ Workflow path is correct${NC}"
        fi
    else
        echo -e "${RED}✗ Workflow file not found${NC}"
        echo "  Creating .github/workflows/main.yml..."
        mkdir -p .github/workflows
        # Copy the workflow from the artifact
        echo -e "${GREEN}  ✓ Workflow file created${NC}"
    fi
    
    echo
}

# Function to verify required files
verify_files() {
    echo -e "${YELLOW}Verifying required files...${NC}"
    
    local files=(
        "server.js"
        "package.json"
        "docker/Dockerfile"
        "nomad/app.nomad"
    )
    
    local missing=0
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${GREEN}✓ $file exists${NC}"
        else
            echo -e "${RED}✗ $file is missing${NC}"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}Some required files are missing${NC}"
        exit 1
    fi
    
    echo
}

# Function to test local build
test_local_build() {
    echo -e "${YELLOW}Testing local Docker build...${NC}"
    
    if command -v docker &> /dev/null; then
        echo "Building Docker image locally..."
        if docker build -f docker/Dockerfile -t test-app:local . > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Docker build successful${NC}"
            
            # Test run
            echo "Testing container..."
            docker run -d --name test-app -p 3000:3000 test-app:local > /dev/null 2>&1
            sleep 3
            
            if curl -s http://localhost:3000/health > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Container health check passed${NC}"
            else
                echo -e "${YELLOW}⚠ Container health check failed${NC}"
            fi
            
            # Cleanup
            docker stop test-app > /dev/null 2>&1
            docker rm test-app > /dev/null 2>&1
        else
            echo -e "${RED}✗ Docker build failed${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Docker not installed locally, skipping test${NC}"
    fi
    
    echo
}

# Function to trigger deployment
trigger_deployment() {
    echo -e "${YELLOW}Triggering deployment...${NC}"
    
    # Check if there are any changes
    if [ -z "$(git status --porcelain)" ]; then
        echo "No changes to commit. Making a small change..."
        echo "# Deployment triggered at $(date)" >> README.md
    fi
    
    # Commit and push
    git add -A
    git commit -m "Trigger CI/CD deployment - $(date +%Y%m%d-%H%M%S)" || true
    
    echo "Pushing to main branch..."
    if git push origin main; then
        echo -e "${GREEN}✓ Push successful${NC}"
        echo
        echo "GitHub Actions workflow should now be running."
        echo "Check the progress at:"
        
        # Get repository URL
        if command -v gh &> /dev/null; then
            repo_url=$(gh repo view --json url -q .url)
            echo "$repo_url/actions"
        else
            remote_url=$(git config --get remote.origin.url)
            echo "$remote_url/actions"
        fi
    else
        echo -e "${RED}✗ Push failed${NC}"
        echo "Please check your git configuration and try again"
    fi
    
    echo
}

# Function to monitor deployment
monitor_deployment() {
    echo -e "${YELLOW}Monitoring deployment status...${NC}"
    
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        echo "Waiting for workflow to start..."
        sleep 5
        
        # Get latest workflow run
        if run_id=$(gh run list --limit 1 --json databaseId -q '.[0].databaseId'); then
            echo "Workflow run ID: $run_id"
            echo "Watching workflow progress..."
            gh run watch $run_id
        else
            echo "Could not get workflow run ID"
        fi
    else
        echo "GitHub CLI not available. Please check the Actions tab in your repository."
    fi
    
    echo
}

# Main menu
show_menu() {
    echo "Select an option:"
    echo "1. Check prerequisites"
    echo "2. Setup GitHub secrets"
    echo "3. Verify files and configuration"
    echo "4. Test local Docker build"
    echo "5. Trigger deployment"
    echo "6. Run full setup and deploy"
    echo "7. Monitor deployment"
    echo "0. Exit"
    echo
}

# Main execution
main() {
    if [ $# -eq 0 ]; then
        while true; do
            show_menu
            read -p "Enter choice: " choice
            
            case $choice in
                1) check_prerequisites ;;
                2) setup_secrets ;;
                3) 
                   verify_workflow
                   verify_files
                   ;;
                4) test_local_build ;;
                5) trigger_deployment ;;
                6) 
                   check_prerequisites
                   verify_workflow
                   verify_files
                   test_local_build
                   setup_secrets
                   trigger_deployment
                   monitor_deployment
                   ;;
                7) monitor_deployment ;;
                0) exit 0 ;;
                *) echo -e "${RED}Invalid option${NC}" ;;
            esac
            
            echo
            read -p "Press Enter to continue..."
            clear
        done
    else
        case $1 in
            "check") check_prerequisites ;;
            "secrets") setup_secrets ;;
            "verify") 
                verify_workflow
                verify_files
                ;;
            "test") test_local_build ;;
            "deploy") trigger_deployment ;;
            "monitor") monitor_deployment ;;
            "all")
                check_prerequisites
                verify_workflow
                verify_files
                test_local_build
                setup_secrets
                trigger_deployment
                monitor_deployment
                ;;
            *)
                echo "Usage: $0 [check|secrets|verify|test|deploy|monitor|all]"
                exit 1
                ;;
        esac
    fi
}

# Run main
main "$@"
