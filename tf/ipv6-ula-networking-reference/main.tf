terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

variable "project_id" {
  type    = string
  default = "stevenlinde-tf-gcek8sipv6-018"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

variable "forwarded_ports" {
  description = "Map of ports to forward, where key is name and value is port number"
  type        = map(number)
  default = {
    "http" = 80
    "ssh"  = 22
  }
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}


resource "google_project_service" "services" {
  project = var.project_id
  for_each = toset([
    "compute.googleapis.com",
    "dns.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}



# Network
resource "google_compute_network" "ipv6_network" {
  name                     = "ipv6-ula-network-${random_string.suffix.result}"
  auto_create_subnetworks  = false
  routing_mode             = "REGIONAL"
  project                  = var.project_id
  enable_ula_internal_ipv6 = true
}

# DNS64 Policy (Required for ULA VM to reach IPv4 destinations via NAT64)
resource "google_dns_policy" "dns64" {
  name                      = "ipv6-ula-dns64-${random_string.suffix.result}"
  project                   = var.project_id
  enable_inbound_forwarding = false
  enable_logging            = false

  dns64_config {
    scope {
      all_queries = true
    }
  }

  networks {
    network_url = google_compute_network.ipv6_network.id
  }
}

# Subnet (IPv6 Only, Internal/ULA)
resource "google_compute_subnetwork" "ipv6_subnet" {
  name             = "ipv6-ula-subnet-${random_string.suffix.result}"
  network          = google_compute_network.ipv6_network.id
  region           = var.region
  project          = var.project_id
  stack_type       = "IPV6_ONLY"
  ipv6_access_type = "INTERNAL"
}

# Cloud Router (Needed for NAT)
resource "google_compute_router" "router" {
  name    = "ipv6-ula-router-${random_string.suffix.result}"
  project = var.project_id
  network = google_compute_network.ipv6_network.id
  region  = var.region
}

# Cloud NAT (Provides NAT64 so the IPv6-only VM can reach IPv4 internet like apt repos)
resource "google_compute_router_nat" "nat" {
  name                                 = "ipv6-ula-nat-${random_string.suffix.result}"
  project                              = var.project_id
  router                               = google_compute_router.router.name
  region                               = var.region
  nat_ip_allocate_option               = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat   = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  source_subnetwork_ip_ranges_to_nat64 = "ALL_IPV6_SUBNETWORKS"
}

# IPv6 Default Route (Required for ULA VMs to reach the Cloud NAT64 gateway)
resource "google_compute_route" "ipv6_default" {
  name             = "ipv6-ula-default-route-${random_string.suffix.result}"
  project          = var.project_id
  network          = google_compute_network.ipv6_network.id
  dest_range       = "64:ff9b::/96"
  next_hop_gateway = "default-internet-gateway"
}

# Firewall rules for Health Checks & GFE Proxies
resource "google_compute_firewall" "allow_gfe_healthcheck_ipv6" {
  name    = "allow-gfe-healthcheck-ipv6-${random_string.suffix.result}"
  network = google_compute_network.ipv6_network.id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = [for port in var.forwarded_ports : tostring(port)]
  }

  # GCP GFEs and Health Checks probe via these IPv6 ranges
  source_ranges = [
    "2600:1901:8001::/48",
    "2600:2d00:1:b029::/64",
    "2600:2d00:1:1::/64"
  ]
}

# SSH Key generation
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/.tmp/id_ed25519"
  file_permission = "0600"
}

# Compute Instance (IPv6 ULA ONLY)
resource "google_compute_instance" "ipv6_vm" {
  name         = "ipv6-ula-vm-${random_string.suffix.result}"
  machine_type = "e2-micro"
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.ipv6_network.id
    subnetwork = google_compute_subnetwork.ipv6_subnet.id
    stack_type = "IPV6_ONLY"
  }

  metadata = {
    ssh-keys       = "admin:${tls_private_key.ssh.public_key_openssh}"
    startup-script = <<-EOF
      #!/bin/bash
      
      mkdir -p /var/www/html
      cat << 'EOF_INDEX' > /var/www/html/index.html
      <html><body><h1>Hello from the IPv6-Only ULA Backend!</h1></body></html>
      EOF_INDEX
      
      # apt-get over NAT64 fails for debian repos on ULA instances because the repos have native AAAA records 
      # and ULA can't route to public IPv6 internet. Standard DNS64 skips translating records that already have AAAA.
      # Workaround: Use Python 3 'http.server' which is pre-installed, instead of Nginx.
      
      cat << 'EOF_PYTHON' > /usr/local/bin/serve_ipv6.py
      import http.server
      import socketserver
      import socket
      import os
      
      os.chdir('/var/www/html')
      class IPv6Server(socketserver.TCPServer):
          address_family = socket.AF_INET6
      
      httpd = IPv6Server(('::', 80), http.server.SimpleHTTPRequestHandler)
      httpd.serve_forever()
      EOF_PYTHON
      
      nohup python3 /usr/local/bin/serve_ipv6.py > /var/log/python_http.log 2>&1 &
    EOF
  }

  tags = ["ipv6-web", "ipv6-ssh"]
}

# Unmanaged Instance Group (Required for IPv6-only backend behind LB)
resource "google_compute_instance_group" "ipv6_group" {
  name        = "ipv6-ula-group-${random_string.suffix.result}"
  description = "Instance group for IPv6-only ULA VM"
  zone        = var.zone
  project     = var.project_id
  instances = [
    google_compute_instance.ipv6_vm.self_link
  ]
  dynamic "named_port" {
    for_each = var.forwarded_ports
    content {
      name = named_port.key
      port = named_port.value
    }
  }
}



# Global External IPv6 Address
resource "google_compute_global_address" "lb_external_ipv6" {
  name         = "lb-external-ipv6-${random_string.suffix.result}"
  project      = var.project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV6"
}


# ==========================================
# Load Balancer Components (Dynamic loops)
# ==========================================
resource "google_compute_health_check" "tcp" {
  for_each = var.forwarded_ports
  name     = "${each.key}-health-check-${random_string.suffix.result}"
  project  = var.project_id
  tcp_health_check {
    port = tostring(each.value)
  }
}

resource "google_compute_backend_service" "tcp" {
  for_each                    = var.forwarded_ports
  name                        = "${each.key}-backend-${random_string.suffix.result}"
  project                     = var.project_id
  protocol                    = "TCP"
  port_name                   = each.key
  load_balancing_scheme       = "EXTERNAL_MANAGED"
  health_checks               = [google_compute_health_check.tcp[each.key].id]
  ip_address_selection_policy = "IPV6_ONLY" # Force GFEs to connect to backend via IPv6

  backend {
    group          = google_compute_instance_group.ipv6_group.id
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_target_tcp_proxy" "tcp" {
  for_each        = var.forwarded_ports
  name            = "${each.key}-proxy-${random_string.suffix.result}"
  project         = var.project_id
  backend_service = google_compute_backend_service.tcp[each.key].id
}


resource "google_compute_global_forwarding_rule" "tcp_ipv6" {
  for_each              = var.forwarded_ports
  name                  = "${each.key}-forwarding-rule-ipv6-${random_string.suffix.result}"
  project               = var.project_id
  target                = google_compute_target_tcp_proxy.tcp[each.key].id
  ip_address            = google_compute_global_address.lb_external_ipv6.id
  port_range            = tostring(each.value)
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

output "lb_external_ip" {
  value = google_compute_global_address.lb_external_ipv6.address
}

locals {
  ssh_opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${local_file.ssh_private_key.filename}"
}

output "ssh_command" {
  value = "ssh ${local.ssh_opts} admin@${google_compute_global_address.lb_external_ipv6.address}"
}

output "http_test_command" {
  value = "curl -6 http://[${google_compute_global_address.lb_external_ipv6.address}]"
}
