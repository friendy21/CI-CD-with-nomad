# Consul Server Configuration (Management Server)
datacenter = "dc1"
data_dir = "/opt/consul/data"
log_level = "INFO"
server = true
bootstrap_expect = 1

bind_addr = "{{ GetPrivateIP }}"
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

# Encryption
encrypt = "GENERATED_ENCRYPTION_KEY"

# ACL configuration
acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  
  tokens {
    # Set during bootstrap
    # initial_management = "BOOTSTRAP_TOKEN_HERE"
    agent = "AGENT_TOKEN_HERE"
  }
}

# TLS configuration
verify_incoming = false
verify_outgoing = true
verify_server_hostname = true

ca_file = "/opt/consul/tls/ca.crt"
cert_file = "/opt/consul/tls/server.crt"
key_file = "/opt/consul/tls/server.key"

auto_encrypt {
  allow_tls = true
}
