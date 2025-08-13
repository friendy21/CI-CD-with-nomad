# Nomad Server Configuration (Management Server)
datacenter = "dc1"
data_dir = "/opt/nomad/data"
log_level = "INFO"

# Bind to all interfaces for management
bind_addr = "0.0.0.0"

# Advertise using private IP
advertise {
  http = "{{ GetPrivateIP }}:4646"
  rpc  = "{{ GetPrivateIP }}:4647"
  serf = "{{ GetPrivateIP }}:4648"
}

server {
  enabled = true
  bootstrap_expect = 1
  
  # Server encryption
  encrypt = "GENERATED_ENCRYPTION_KEY"
}

# Disable client on management server
client {
  enabled = false
}

# ACL configuration
acl {
  enabled = true
  token_ttl = "30s"
  policy_ttl = "60s"
  
  # Bootstrap token (set only during initial setup)
  # bootstrap_token = "BOOTSTRAP_TOKEN_HERE"
}

# Consul integration
consul {
  address = "127.0.0.1:8500"
  server_service_name = "nomad"
  auto_advertise = true
  server_auto_join = true
  
  # Consul ACL token
  token = "CONSUL_TOKEN_HERE"
}

# UI configuration
ui {
  enabled = true
  
  consul {
    ui_url = "http://{{ GetPublicIP }}:8500/ui"
  }
}

# Telemetry
telemetry {
  collection_interval = "1s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}

# TLS configuration
tls {
  http = true
  rpc  = true
  
  ca_file   = "/opt/nomad/tls/ca.crt"
  cert_file = "/opt/nomad/tls/server.crt"
  key_file  = "/opt/nomad/tls/server.key"
  
  verify_server_hostname = true
  verify_https_client    = true
}
