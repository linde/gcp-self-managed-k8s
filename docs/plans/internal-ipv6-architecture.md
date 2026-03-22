# Internal IPv6 Architecture & Access Plan

> *STATUS*: rolledback

> **Reason for Rollback**: While internal-only nodes correctly force egress traffic through NAT64, securely exposing the internal-only Control Plane via a Regional Proxy Network Load Balancer (IPv4) requires mapping IPv6 addresses in Zonal NEGs. As documented in `docs/ipv6-internal-network-gcp-load-balancer-limitation.md`, the Terraform `google` provider lacks the `ipv6_address` parameter to do this natively, forcing non-idiomatic `null_resource` local-exec hacks using `gcloud`. To preserve clean Infrastructure-as-Code principles, this plan is abandoned and we are reverting to assigning public/external IPv6 addresses natively to all cluster instances.

This document originally outlined the internal-only architecture of the IPv6 cluster, NAT64 implementation details, and the strategy for exposing the control plane securely to the internet via a Regional Proxy Load Balancer.

## The Architecture Dilemma
In an IPv6-only environment, nodes cannot reach IPv4-only services (like GitHub) directly. We enabled DNS64 on the VPC, and the metadata server successfully synthesizes `64:ff9b::/96` NAT64 addresses.

However, we discovered two architectural blockers:
1. **NAT64 Egress Bypass**: GCP Cloud NAT64 explicitly ignores VMs that have an *external* IPv6 address (`ipv6_access_config`). Because our nodes have external IPv6 addresses, traffic to the NAT64 prefix is forced out to the default internet gateway and dropped.
2. **Kubelet resolv.conf Limitation**: The host's `/etc/resolv.conf` directs queries to `169.254.169.254` (an IPv4 address). Kubelet injects this into IPv6-only CoreDNS pods, causing them to fail completely because they cannot reach IPv4.

## Proposed Strategy (Internal-Only + IAP)
To fix the NAT64 egress bypass, we will strip the external IPv6 addresses from the nodes, making them strictly internal. This forces all their outbound internet traffic to be processed by Cloud NAT, instantly enabling NAT64 (and fixing `git clone`). 

We will regain SSH access via **Google Cloud Identity-Aware Proxy (IAP)**, which securely tunnels directly to the internal interfaces of the VMs without needing public IPs.

## Execution Steps

### 1. Infrastructure (GCP VPC & Compute)
- [x] Add `google_dns_policy` in `tf/ipv6-only/network.tf` to enable DNS64 synthesis.
- [x] **Remove** `ipv6_access_config` blocks from both `k8s_control_plane.tf` and `k8s_worker_node.tf` to make the nodes internal-only.
- [x] **Add** an ingress firewall rule in `network.tf` allowing IAP TCP forwarding (IPv4 `35.235.240.0/20` and IPv6 `2600:2d00:1:7::/64`) to TCP port 22.

### 2. Bootstrap Script
~~- **Remove** the custom CoreDNS patching logic. Since the host's `/etc/resolv.conf` will now natively resolve IPv4 domains to NAT64 addresses, CoreDNS's default `forward . /etc/resolv.conf` will work correctly without any custom template.~~
- *Update:* We **cannot** remove the custom CoreDNS patch because Kubelet injects the host's IPv4 metadata IP (`169.254.169.254`) into the pods. We must retain the patch mapping `forward .` to Google Public DNS.

## Verification
- Connect via IAP: `gcloud compute ssh admin@cp-ipv6 --tunnel-through-iap`
- Node test: `git clone https://github.com/...` should work via NAT64.
- Pod test: DNS continues to work using the restored CoreDNS config map patch.

## Public Access via Regional External Proxy Network Load Balancer
To allow secure, public entry into the internal Control Plane (for API server port 6443 and SSH port 22), we will deploy a **Regional External Proxy Network Load Balancer**.
Unlike passthrough load balancers, Proxy Network Load Balancers:
1. Provide an external IPv4 frontend address.
2. Fully terminate the connection and proxy it over internal IPv6 directly to the VM.
3. Support any arbitrary TCP ports (like 22 and 6443).

### Load Balancer Implementation Steps:
- [ ] Add a new variable `controlplane_loadbalancer_ports` to `variables.tf` defaulting to `["22", "6443"]`.
- [ ] Create an Unmanaged Instance Group (`google_compute_instance_group`) containing the `cp_node`.
- [ ] Provision a proxy-only subnet (`google_compute_subnetwork` with `purpose = "REGIONAL_MANAGED_PROXY"`).
- [ ] Create the Regional External IPv4 address.
- [ ] Deploy a Backend Service (`google_compute_region_backend_service`) referencing the Instance Group.
- [ ] Deploy a Target TCP Proxy (`google_compute_region_target_tcp_proxy`).
- [ ] Deploy a Forwarding Rule (`google_compute_forwarding_rule`) for the ports defined in the `controlplane_loadbalancer_ports` variable, attaching the public IP to the Target Proxy.
- [ ] Update `bootstrap.sh.tftpl` to inject the new Load Balancer public IP into the `kubeadm init` SANs (`apiserver-cert-extra-sans`).
- [ ] Output the final `control_plane_public_ip` for the user.
