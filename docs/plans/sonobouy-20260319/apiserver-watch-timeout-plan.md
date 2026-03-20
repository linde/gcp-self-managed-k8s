# Plan: APIServer Watchstream Stability

## Problem Statement
Components such as `kube-controller-manager`, `kubelet`, and `kube-proxy` (if used, although Cilium usually replaces it) are throwing errors indicating watchstreams are being broken:
`The watchlist request ended with an error, falling back to the standard LIST semantics`.

Falling back to LIST semantics on large clusters causes massive CPU and network spikes on the API server.

## Proposed Solution
1. **IPv6 MTU Issues**: Watchstreams are long-lived TCP connections. If Path MTU Discovery (PMTUD) fails in an IPv6 environment (because ICMPv6 Packet Too Big messages are dropped by firewalls), large updates passing through the stream will silently drop, leading to HTTP/2 timeouts.
   - *Action*: Verify that GCP Firewall rules explicitly allow ICMPv6 (`ipv6-icmp`) both within the VPC and between the nodes and the control plane.
2. **TCP Keepalives**: Long-lived idle connections might be dropped by GCP's transparent load balancers or NATs if keepalives are not aggressive enough.
   - *Action*: Ensure `kube-apiserver` and kubelet have appropriately tuned `--tls-min-version` and TCP keepalive settings.
3. **HTTP/2 Ping timeouts**: Kube-apiserver has flags to adjust the HTTP/2 ping timeout (`--goaway-chance`, `--endpoint-reconciler-type`). Ensure they are tuned for high-latency or dropped-packet environments.

## Actionable Next Steps
- Add ICMPv6 allow rules in Terraform (`google_compute_firewall`).
- Execute a long-running `kubectl get pods -w` on a node and monitor `tcpdump` for ICMPv6 PTB (Packet Too Big) errors.
