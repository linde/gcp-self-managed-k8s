# Plan: Cilium Endpoint Creation Remediation

## Problem Statement
The `cilium-agent` instances frequently log:
`Cannot create CEP` (CiliumEndpoint).
This causes intermittent delays or failures during Pod initialization, leading to `ContainerCreating` timeouts.

## Proposed Solution
1. **API Server Rate Limiting**: The Cilium agent communicates heavily with the Kubernetes API to create and update `CiliumEndpoint` CRDs. In an IPv6-only cluster, if API latency is high due to MTU or routing loops, API calls timeout. 
   - *Action*: Increase `k8s-api-qps` and `k8s-api-burst` in Cilium ConfigMap.
2. **IPAM Exhaustion**: Verify if the IPv6 pod CIDR block assigned to each Node (`/112` or similar) is heavily fragmented or exhausted prematurely due to short-lived jobs (like Sonobuoy components).
   - *Action*: Check `cilium node list` for IPAM capacity and ensure IPAM mode is `kubernetes` to align with the CCM.
3. **KVStore vs CRD**: If Cilium is relying on CRDs for identity management in a very large cluster, consider switching to an external KVStore (etcd) for identity allocation. However, for a standard deployment, CRD backed is preferred; we just need to ensure the APIServer can handle the load.

## Actionable Next Steps
- Monitor API Server latency metrics (`apiserver_request_duration_seconds_summary`).
- Update Cilium `values.yaml` to increase QPS (`k8sClientRateLimit: { qps: 50, burst: 100 }`).
- Reproduce the load by spinning up a massive Deployment (100+ replicas) and watching CEP creation times.
