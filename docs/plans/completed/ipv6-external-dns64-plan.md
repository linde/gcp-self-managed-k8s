# IPv6 External DNS64 Plan

**Status:** Completed

## Goal Description
> in the tf/ipv6-external-dns64 lets start a new terraform project that takes as parameters similar to the tf/ipv6-ula-networking-reference and similarly has a single tf file example. this example should be of a vm instance in a ipv6 external address network/subnet -- it should not be a dual stack network, just ipv6 only. and NOT ULA, we should have routable external ips.  we will want that because we will allow the fire wall to be open for an array of ports which will start with 22 and 80.  the latter will be for ngninx which i would have installed on the vm bootstrap via apt install.  we should lock down the instances but allow access from the client for these two ports.  as with the other example, please document all this in a readme with a diagram of the pieces
> also, please be sure to enable DNS64 within the vm instance. we should be able to "curl -6is https://github.com" and get content

The goal is to create a new Terraform project in `tf/ipv6-external-dns64` that provisions a single Google Compute Engine VM in an IPv6-only, external network (no dual-stack, no ULA). The VM will have a routable external IPv6 address. To allow the VM to download packages from IPv4-only sources via `apt`, we will configure DNS64 and NAT64. The firewall will be configured to allow inbound traffic on ports 22 (SSH) and 80 (HTTP) from any IPv6 client. A `README.md` will be created with an architectural diagram explaining the setup.

## Proposed Changes

### Terraform Configuration
#### tf/ipv6-external-dns64/main.tf
A single Terraform file that sets up:
- **google_project_service**: Enabling required APIs (`compute.googleapis.com`, `dns.googleapis.com`).
- **google_compute_network**: A regional VPC network without ULA enabled, as we rely on external IPv6.
- **google_compute_subnetwork**: A subnet configured to be IPv6-only with `ipv6_access_type = "EXTERNAL"`.
- **google_compute_router & google_compute_router_nat**: Configured for NAT64 to allow the IPv6-only VM to communicate with IPv4 destinations.
- **google_compute_route**: An IPv6 default route required to reach the NAT64 gateway for `64:ff9b::/96`.
- **google_dns_policy**: A DNS64 policy attached to the network to synthesize IPv6 addresses for IPv4-only hosts.
- **google_compute_firewall**: A firewall rule allowing inbound TCP ports 22 and 80 from `::/0` (or a variable restricted range) to instances with a specific network tag.
- **tls_private_key & local_file**: Automatically generates an ED25519 SSH keypair into `.tmp/id_ed25519` for easy SSH access and adds it to the instance metadata.
- **google_compute_instance**: An `e2-micro` Debian 12 VM with an `IPV6_ONLY` network interface. The startup script executes `apt-get update && apt-get install -y nginx`, starts Nginx, and ensures the VM's DNS resolver is properly set up using Google Public DNS64 servers `2001:4860:4860::6464` and `2001:4860:4860::64`.
- **Outputs**: Outputting the external IPv6 address of the VM, an HTTP test `curl` command for Nginx (using brackets `[]` for IPv6), an HTTPS test `curl` command inside SSH for github.com via NAT64, and an SSH connection command (without brackets, as `ssh` does not support them).

#### tf/ipv6-external-dns64/README.md
A markdown file containing:
- Project description and requirements.
- A Mermaid.js diagram illustrating the architecture (VPC, Subnet, VM, Cloud NAT64, DNS64, Firewall).
- Instructions on how to run `terraform init`, `plan`, and `apply`.
- Instructions for validating the setup using `curl` and `ssh`.

## Verification Plan
### Automated Tests
- Run `terraform init` and `terraform validate` within the `tf/ipv6-external-dns64` directory to ensure the configuration is syntactically valid.

### Manual Verification
- The user can run `terraform apply` to provision the infrastructure.
- The user can verify that `curl -6 http://[VM_EXTERNAL_IPV6]` returns the default Nginx page or a custom HTML page populated by the startup script.
- The user can verify SSH access to the VM using the provided output command.
- The user can log into the VM and verify DNS64/NAT64 is functioning by running `curl -6is https://github.com` and confirming it returns web content.
