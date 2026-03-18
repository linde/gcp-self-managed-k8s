# Plan: Addressing IPv6 External LoadBalancer Limitation

## The Issue
Currently, the `ipv6-only` kubeadm cluster cannot natively provision an external IPv6 LoadBalancer using the standard `type: LoadBalancer` Kubernetes Service. 

When attempting to provision a LoadBalancer with the required GCP annotation (`cloud.google.com/l4-rbs: "enabled"`) to utilize the newer Backend Service-based Network Load Balancer (L4 RBS)—which supports IPv6—the LoadBalancer remains in a `<pending>` state infinitely.

The Google Cloud Controller Manager (CCM) logs reveal the following error:
`Failed to EnsureLoadBalancer(...), err: implemented by alternate to cloud provider`

### Root Cause
This happens because the base open-source `cloud-provider-gcp` delegates the `l4-rbs` implementation to an "alternate" controller—specifically, the proprietary GKE L4 load balancer controller (`gke-l4-controller` / `ingress-gce`) used in managed GKE. Because this secondary controller is not installed in our custom `kubeadm` cluster, the CCM skips the request. 

Conversely, omitting the annotation causes the CCM to fallback to GCP's legacy Target Pool Load Balancers, which **do not support IPv6**.

## Proposed Solutions / Workarounds

To reliably support external IPv6 ingress on this custom Kubernetes cluster, we need to evaluate and implement one of the following approaches:

1. **Host-Network Ingress Controller (Recommended)**
   Deploy an Ingress controller (e.g., `ingress-nginx` or `traefik`) directly via a DaemonSet bound to the host network (`hostNetwork: true`). This bypasses the need for a GCP LoadBalancer outright, routing external IPv6 traffic directly from the VM interfaces into the cluster.

2. **Manual GCP Routing (Infrastructure as Code)**
   Define the external IPv6 IP, Forwarding Rules, Backend Services, and Health Checks directly within Terraform. These resources would point to the unmanaged instance group of the cluster nodes, which then route traffic via `NodePort` Services.

3. **Install the Custom GKE Controller (If Possible)**
   Investigate if the `ingress-gce` controller can be reliably deployed as open source to our cluster so that it can intercept the `l4-rbs` annotation and natively provision the Google Cloud load balancing resources.

## Next Steps
- Consider updating the `nginx-loadbalancer-ipv6.yaml` example to use a `NodePort` or `DaemonSet` workaround so that the out-of-the-box experience works.
- Test deploying `ingress-nginx` bound to `hostNetwork` to verify end-to-end IPv6 reachability.
- Evaluate the overhead of maintaining manual Terraform GCP load balancer configurations versus a cluster-native ingress controller.
