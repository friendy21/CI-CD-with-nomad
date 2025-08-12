# GitHub Secrets Configuration Guide

## Required Secrets for CI/CD Pipeline

To set up the CI/CD pipeline, you need to configure the following secrets in your GitHub repository:

**Navigation:** Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

## Production Secrets

### 1. DOCKERHUB_TOKEN
- **Value:** `dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U`
- **Description:** Docker Hub personal access token for friendy21 account
- **Usage:** Authenticates with Docker Hub to push container images

### 2. DO_SSH_KEY
- **Value:** 
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDwAAAKDCQdK8wkHS
vAAAAAtzcmgtZWQyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDw
AAAAEA3wko/j62bhyK/XNYHWCrtOUS13VaekeqQDZaTYqixeYSAnHT9v/8qCM8dOW48+Fkd
eUctCxGJOVVMnVL6plgPAAAAGGZyaWVuZHlrYWxpbWFuQGdtYWlsLmNvbQECAwQF
-----END OPENSSH PRIVATE KEY-----
```
- **Description:** Private SSH key for accessing DigitalOcean droplets
- **Usage:** Enables secure SSH connection to deploy applications

### 3. DO_API_TOKEN
- **Value:** `dop_v1_0f43a49f6f0618370674fa79a9d8a9e2e18775196378b9c6bcd35589a99fc0a8`
- **Description:** DigitalOcean API token for management operations
- **Usage:** Allows automated management of DigitalOcean resources

### 4. DO_STAGING_HOST (Optional)
- **Value:** `137.184.85.0` (or your staging server IP)
- **Description:** IP address of staging environment
- **Usage:** Deploys to staging environment for testing

## Server Configuration

### Primary Production Server
- **IP:** `137.184.198.14`
- **SSH User:** `root`
- **Services:** Nomad, Consul, Docker

### Secondary Production Server  
- **IP:** `137.184.85.0`
- **SSH User:** `root`
- **Services:** Nomad, Consul, Docker

## Security Best Practices

### SSH Key Security
1. **Never commit SSH keys to repository**
2. **Use dedicated deployment keys** - Create separate SSH keys for CI/CD
3. **Rotate keys regularly** - Update SSH keys every 90 days
4. **Limit key permissions** - Use keys only for deployment purposes

### Docker Hub Security
1. **Use Personal Access Tokens** - Never use passwords in CI/CD
2. **Scope token permissions** - Limit to specific repositories
3. **Monitor token usage** - Review access logs regularly

### DigitalOcean API Security
1. **Use scoped tokens** - Limit API permissions to required operations
2. **Monitor API usage** - Review API access logs
3. **Rotate tokens regularly** - Update API tokens every 90 days

## Environment Variables in Workflow

The workflow uses these environment variables:

```yaml
env:
  DOCKER_BUILDKIT: 1
  COMPOSE_DOCKER_CLI_BUILD: 1
  REGISTRY: docker.io
  IMAGE_NAME: friendy21/nomad-app
```

## Verification Steps

After setting up secrets, verify the configuration:

1. **Test SSH Connection:**
   ```bash
   ssh -i ~/.ssh/id_rsa root@137.184.198.14 "echo 'SSH connection successful'"
   ```

2. **Test Docker Hub Authentication:**
   ```bash
   echo $DOCKERHUB_TOKEN | docker login --username friendy21 --password-stdin
   ```

3. **Test DigitalOcean API:**
   ```bash
   curl -X GET \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $DO_API_TOKEN" \
     "https://api.digitalocean.com/v2/account"
   ```

## Troubleshooting

### Common Issues

1. **SSH Permission Denied**
   - Verify SSH key format and permissions
   - Check if key is added to server's authorized_keys

2. **Docker Push Failed**
   - Verify Docker Hub token is valid
   - Check repository permissions

3. **API Authentication Failed**
   - Verify DigitalOcean API token
   - Check token permissions and scope

### Debug Commands

```bash
# Check SSH key fingerprint
ssh-keygen -lf ~/.ssh/id_rsa.pub

# Test Docker Hub connection
docker info

# Verify DigitalOcean API access
curl -H "Authorization: Bearer $DO_API_TOKEN" \
  "https://api.digitalocean.com/v2/droplets"
```

## Additional Security Considerations

1. **Enable 2FA** on all accounts (GitHub, Docker Hub, DigitalOcean)
2. **Use branch protection rules** to require PR reviews
3. **Enable security scanning** in GitHub repository settings
4. **Monitor deployment logs** for suspicious activity
5. **Implement proper RBAC** in Nomad and Consul clusters

