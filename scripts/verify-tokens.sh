#!/bin/bash
# Script to verify all tokens are working

set -euo pipefail

# Source tokens
source /root/tokens/all-tokens.env

echo "Verifying token configuration..."

# Test Consul token
echo -n "Testing Consul Management Token... "
if consul members >/dev/null 2>&1; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi

# Test Nomad token
echo -n "Testing Nomad Management Token... "
if nomad node status >/dev/null 2>&1; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi

# Test deployment token
echo -n "Testing Nomad Deployment Token... "
export NOMAD_TOKEN="${NOMAD_DEPLOYMENT_TOKEN}"
if nomad job status >/dev/null 2>&1; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi

# Show cluster status
echo ""
echo "Cluster Status:"
echo "==============="
echo "Consul Members:"
consul members

echo ""
echo "Nomad Nodes:"
nomad node status

echo ""
echo "Token verification complete!"
