# Nomad Client Configuration (Worker Node)
datacenter = "dc1"
data_dir = "/opt/nomad/data"
log_level = "INFO"

bind_addr = "0.0.0.0"

advertise {
  http = "{{ GetPrivateIP }}:4646"
  rpc  = "{{ GetPrivateIP }}:4647"
  serf = "{{ GetPrivateIP }}:4648"
}

# Disable server on client nodes
server {
  enabled = false
}

client {
  enabled = true
  
  # Join management server
  servers = ["MANAGEMENT_SERVER_PRIVATE_IP:4647"]
  
  node_class = "worker"
  
  # Reserve resources for system
  reserved {
    cpu    = 500
    memory = 512
    disk   = 1024
  }
  
  # Docker configuration
  options {
    "docker.auth.config" = "/root/.docker/config.json"
    "docker.volumes.enabled" = true
    "docker.privileged.enabled" = false
  }
}

# ACL configuration
acl {
  enabled = true
  token_ttl = "30s"
  policy_ttl = "60s"
}

# Consul integration
consul {
  address = "127.0.0.1:8500"
  client_service_name = "nomad-client"
  auto_advertise = true
  client_auto_join = true
  
  # Consul ACL token
  token = "CONSUL_TOKEN_HERE"
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
  cert_file = "/opt/nomad/tls/client.crt"
  key_file  = "/opt/nomad/tls/client.key"
  
  verify_server_hostname = true
  verify_https_client    = true
}

plugin "docker" {
  config {
    gc {
      image       = true
      image_delay = "3m"
      container   = true
    }
    
    volumes {
      enabled = true
    }
    
    allow_privileged = false
    
    # Docker Hub authentication
    auth {
      config = "/root/.docker/config.json"
    }
  }
}
