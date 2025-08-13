# Consul Client Configuration (Worker Node)
datacenter = "dc1"
data_dir = "/opt/consul/data"
log_level = "INFO"
server = false

bind_addr = "{{ GetPrivateIP }}"
client_addr = "0.0.0.0"

# Join management server
retry_join = ["MANAGEMENT_SERVER_PRIVATE_IP"]

# Encryption
encrypt = "GENERATED_ENCRYPTION_KEY"

# ACL configuration
acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  
  tokens {
    agent = "AGENT_TOKEN_HERE"
  }
}

# TLS configuration
verify_incoming = false
verify_outgoing = true
verify_server_hostname = true

auto_encrypt {
  tls = true
}
