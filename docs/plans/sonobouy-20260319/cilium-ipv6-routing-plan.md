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
- Check the Cilium Helm values regarding `ipv6` native routing CIDR. Currently, `autoDirectNodeRoutes=true` is set alongside `routingMode=native`, which may be failing if GCP VPC doesn't route the PodCIDRs intrinsically without BGP.

## Verification Workload
To concretely test if cross-node direct routing is fixed, use the `reachability-test` workload provided in `docs/examples/config/`:
1. **Deploy the Agent DaemonSet**:
   ```bash
   kubectl apply -f docs/examples/config/reachability-daemonset.yaml
   ```
   This deploys an HTTP agent on every node that reports its node/pod IP and can execute requests to other target IPs.
2. **Run the Client Mesh Test**:
   ```bash
   kubectl apply -f docs/examples/config/reachability-client.yaml
   ```
   This deploys a single client Pod which automatically discovers all Agent IPs and commands every agent to ping every other agent.
3. **Verify Results**:
   ```bash
   kubectl logs reachability-client -n reachability-test
   ```
   If direct routing is functioning correctly, all cross-node requests will succeed with `HTTP 200` responses and no `Connection Timeout` or `No route to host` errors.
