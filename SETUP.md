# Quick Setup Guide

This guide provides step-by-step instructions to get your CI/CD pipeline running quickly.

## 1. Server Setup

### On each DigitalOcean server (137.184.198.14 and 137.184.85.0):

```bash
# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/your-username/CI-CD-with-nomad/main/scripts/setup-server.sh -o setup-server.sh
chmod +x setup-server.sh
sudo ./setup-server.sh
```

## 2. GitHub Secrets Configuration

Add these secrets to your GitHub repository (Settings → Secrets and variables → Actions):

| Secret Name | Value |
|-------------|-------|
| `DOCKERHUB_TOKEN` | `dckr_pat_TrLIn2QLrbBwY77IsPlkudXFK6U` |
| `DO_SSH_KEY` | Your private SSH key (see below) |
| `DO_API_TOKEN` | `dop_v1_0f43a49f6f0618370674fa79a9d8a9e2e18775196378b9c6bcd35589a99fc0a8` |
| `DO_STAGING_HOST` | `137.184.85.0` |

### SSH Key Format:
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDwAAAKDCQdK8wkHS
vAAAAAtzcmgtZWQyNTUxOQAAACCEgJx0/b//KgjPHTluPPhZHXlHLQsRiTlVTJ1S+qZYDw
AAAAEA3wko/j62bhyK/XNYHWCrtOUS13VaekeqQDZaTYqixeYSAnHT9v/8qCM8dOW48+Fkd
eUctCxGJOVVMnVL6plgPAAAAGGZyaWVuZHlrYWxpbWFuQGdtYWlsLmNvbQECAwQF
-----END OPENSSH PRIVATE KEY-----
```

## 3. SSH Configuration

Run the SSH setup script locally:

```bash
./scripts/ssh-setup.sh all
```

## 4. Deploy Your First Application

1. Update the Nomad job files in the `nomad/` directory with your application details
2. Commit and push to the main branch
3. Watch the GitHub Actions workflow deploy your application

## 5. Access Your Services

- **Nomad UI**: http://137.184.198.14:4646
- **Consul UI**: http://137.184.198.14:8500
- **Your Application**: http://137.184.198.14 (after Traefik deployment)

## 6. Set Up Monitoring (Optional)

```bash
# On the primary server
sudo ./scripts/monitoring-setup.sh
sudo /opt/scripts/start-monitoring.sh
```

Access monitoring:
- **Prometheus**: http://137.184.198.14:9090
- **Grafana**: http://137.184.198.14:3000 (admin/admin)

## Troubleshooting

### Common Issues:

1. **SSH Connection Failed**: Ensure your SSH key is properly added to the servers
2. **Docker Login Failed**: Verify your Docker Hub token is correct
3. **Nomad Job Failed**: Check the Nomad UI for error details
4. **Service Not Accessible**: Verify firewall rules and service health

### Useful Commands:

```bash
# Check service status
nomad job status app
consul catalog services

# View logs
nomad alloc logs <allocation-id>
journalctl -u nomad -f

# Restart services
sudo systemctl restart nomad
sudo systemctl restart consul
```

## Next Steps

1. Configure your domain name and SSL certificates
2. Set up monitoring alerts
3. Implement backup procedures
4. Review security settings for production use

For detailed information, see the main [README.md](README.md) file.

