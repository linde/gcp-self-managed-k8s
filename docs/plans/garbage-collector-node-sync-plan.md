# Plan: Garbage Collector Node Sync Resolution

## Problem Statement
The `kube-controller-manager` shows frequent garbage collection errors, specifically:
`Unhandled Error err="error syncing item &garbagecollector.node{identity:garbagecollector.objectRef...`

During cluster scaling or teardown in this IPv6-only environment, Node objects are becoming orphaned or lingering in a `NotReady` state. The Garbage Collector struggles to clear out dependent resources (like Pods) because the Node deletion process gets stuck.

## Proposed Solution
1. **CCM Node Lifecycle**: The GCE Cloud Controller Manager is responsible for removing nodes from the Kubernetes API when the underlying Compute Engine instance goes away. In an IPv6-only setup, if the webhook or communication back to the APIServer fails, the CCM might fail to delete the Node.
   - *Action*: Ensure the CCM deployment has hostNetwork bindings properly configured for IPv6 so it can communicate natively with the API server.
2. **Graceful Node Shutdown**: The Kubelet's Graceful Node Shutdown feature relies on systemd inhibitor locks. If this is not functioning, Pod eviction doesn't complete.
   - *Action*: Review `kubelet` configuration for `shutdownGracePeriod` and `shutdownGracePeriodCriticalPods`.
3. **Delete Strategies**: If nodes must be removed, the teardown scripts should `kubectl drain` and `kubectl delete node` explicitly to clear out finalizers *before* destroying the VM in GCP.

## Actionable Next Steps
- Update the teardown script to do a `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` and then `kubectl delete node <node>`.
- Audit the GCE CCM logs for node deletion failures.
