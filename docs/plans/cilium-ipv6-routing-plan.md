# Plan: Cilium IPv6 Direct Routing Fix

## Problem Statement
The Sonobuoy e2e tests revealed massive log spam and potential dataplane degradation in `cilium-agent` logs showing:
`Unable to install direct node route module=agent.datapath`

In an IPv6-only cluster running on GCP, direct routing between nodes relies on proper VPC route entries and IPv6 Neighbor Discovery (NDP).

## Proposed Solution
1. **Verify GCP VPC Routing**: Ensure that the VPC network has `Enable IPv6` turned on for the subnets, and that custom routes are being properly programmed by the Cloud Controller Manager (CCM).
2. **Cilium Configuration**:
   - Verify that `routingMode: native` is correctly picking up the IPv6 topology.
   - If using `native` routing, `ipv4NativeRoutingCIDR` should be unset, and `ipv6NativeRoutingCIDR` must be appropriately configured.
3. **Cilium BGP Control Plane / Kube-Router**: In GCP, using BGP to advertise PodCIDRs directly to the Cloud Router might bypass the need for static direct node routes. Check if BGP is a viable alternative for this environment.
4. **Node IP Allocation**: Ensure nodes are receiving valid IPv6 `/112` or `/119` pod allocations and that they are routable.

## Actionable Next Steps
- Review the `terraform/gcp` configuration for VPC routing.
- Check the Cilium Helm values regarding `ipv6` native routing CIDR.
- Deploy a test DaemonSet that attempts IPv6 ND to other nodes and verify ICMPv6 reachability.
