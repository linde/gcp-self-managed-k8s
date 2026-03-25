terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
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

provider "google" {}

variable "gcp_project" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

variable "allowed_ports" {
  description = "Array of ports to allow via firewall"
  type        = list(number)
  default     = [22, 80]
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "google_project_service" "services" {
  project = var.gcp_project
  for_each = toset([
    "compute.googleapis.com",
    "dns.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# Network
resource "google_compute_network" "ipv6_ext_network" {
  name                    = "ipv6-ext-network-${random_string.suffix.result}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  project                 = var.gcp_project
}

# DNS64 Policy (Required for IPv6-only VM to resolve and reach IPv4 destinations via NAT64)
resource "google_dns_policy" "dns64" {
  name                      = "ipv6-ext-dns64-${random_string.suffix.result}"
  project                   = var.gcp_project
  enable_inbound_forwarding = false
  enable_logging            = false

  dns64_config {
    scope {
      all_queries = true
    }
  }

  networks {
    network_url = google_compute_network.ipv6_ext_network.id
  }
}

# Subnet (IPv6 Only, External, Routable IPs)
resource "google_compute_subnetwork" "ipv6_ext_subnet" {
  name             = "ipv6-ext-subnet-${random_string.suffix.result}"
  network          = google_compute_network.ipv6_ext_network.id
  region           = var.region
  project          = var.gcp_project
  stack_type       = "IPV6_ONLY"
  ipv6_access_type = "EXTERNAL"
}

# Cloud Router (Needed for NAT)
resource "google_compute_router" "router" {
  name    = "ipv6-ext-router-${random_string.suffix.result}"
  project = var.gcp_project
  region  = var.region
  network = google_compute_network.ipv6_ext_network.id
}

# Cloud NAT (Provides NAT64 so the IPv6-only VM can reach IPv4 internet like github.com)
resource "google_compute_router_nat" "nat" {
  name                                 = "ipv6-ext-nat-${random_string.suffix.result}"
  project                              = var.gcp_project
  router                               = google_compute_router.router.name
  region                               = var.region
  nat_ip_allocate_option               = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat   = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  source_subnetwork_ip_ranges_to_nat64 = "ALL_IPV6_SUBNETWORKS"
}

# IPv6 Default Route (Required to reach the NAT64 gateway for 64:ff9b::/96)
resource "google_compute_route" "ipv6_default" {
  name             = "ipv6-ext-default-route-${random_string.suffix.result}"
  project          = var.gcp_project
  network          = google_compute_network.ipv6_ext_network.id
  dest_range       = "64:ff9b::/96"
  next_hop_gateway = "default-internet-gateway"
}

# Firewall rule allowing ports 22 and 80 from any IPv6 client
resource "google_compute_firewall" "allow_client_ipv6" {
  name    = "allow-client-ipv6-${random_string.suffix.result}"
  network = google_compute_network.ipv6_ext_network.id
  project = var.gcp_project

  allow {
    protocol = "tcp"
    ports    = [for port in var.allowed_ports : tostring(port)]
  }

  # Allow from any IPv6 address
  source_ranges = ["::/0"]
  target_tags   = ["ipv6-ext-web"]
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

# Compute Instance (IPv6 EXTERNAL ONLY)
resource "google_compute_instance" "ipv6_vm" {
  name         = "ipv6-ext-vm-${random_string.suffix.result}"
  machine_type = "e2-micro"
  zone         = var.zone
  project      = var.gcp_project

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.ipv6_ext_network.id
    subnetwork = google_compute_subnetwork.ipv6_ext_subnet.id
    stack_type = "IPV6_ONLY"

    ipv6_access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    ssh-keys       = "admin:${tls_private_key.ssh.public_key_openssh}"
    startup-script = <<-EOF
      #!/bin/bash
      
      # Explicitly ensure DNS64 resolution is available. 
      # While Google Cloud DNS Policy should handle this, some Debian images and systemd-resolved 
      # can be finicky in pure IPv6-only environments without DHCPv6 DNS.
      # We add Google's Public DNS64 servers as a fallback just in case the VPC metadata server fails.
      echo "nameserver 2001:4860:4860::6464" >> /etc/resolv.conf
      echo "nameserver 2001:4860:4860::64" >> /etc/resolv.conf
      
      # Wait a moment for network to fully initialize
      sleep 10
      
      # Install Nginx via NAT64 (apt repos will be resolved using DNS64)
      apt-get update
      apt-get install -y nginx

      # Verify Github curl via DNS64 inside the VM log
      curl -6is https://github.com > /var/log/dns64_github_test_inside_vm.log 2>&1

      # Set up a default index.html
      cat << 'EOF_INDEX' > /var/www/html/index.html
      <html>
      <head><title>External IPv6-Only VM</title></head>
      <body>
          <h1>Hello from the IPv6-Only External Backend!</h1>
          <p>This VM has a publicly routable IPv6 address and is using NAT64 and DNS64 to reach IPv4 services.</p>
      </body>
      </html>
      EOF_INDEX
      
      systemctl restart nginx
    EOF
  }

  tags = ["ipv6-ext-web"]
}

locals {
  ssh_opts      = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${local_file.ssh_private_key.filename}"
  external_ipv6 = google_compute_instance.ipv6_vm.network_interface[0].ipv6_access_config[0].external_ipv6
}

output "vm_external_ipv6" {
  value = local.external_ipv6
}

output "ssh_command" {
  value = "ssh ${local.ssh_opts} admin@${local.external_ipv6}"
}

output "http_test_command" {
  value = "curl -6 http://[${local.external_ipv6}]"
}

output "github_dns64_test_command" {
  value = "ssh ${local.ssh_opts} admin@${local.external_ipv6} 'curl -6is https://github.com'"
}
