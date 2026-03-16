# Automated Reachability Testing

This project includes a built-in reachability testing suite powered by a DaemonSet and a Client Pod. The suite orchestrates finding the nodes and testing pod-to-pod HTTP reachability across all nodes sequentially.

While built to showcase IPv6 pod-to-pod networking, the suite works natively across both IPv4 and IPv6-only environments.

## Running Locally with Kind

You can get a sense for how this acts by creating a local testing cluster.

1. **Deploy your Cluster**
   ```bash
   cat <<EOF | kind create cluster --name reachability --config=-
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   nodes:
     - role: control-plane
     - role: worker
     - role: worker
   EOF
   ```

2. **Deploy the Agent DaemonSet**
   This creates a namespace (`reachability-test`), a headless service, and the DaemonSet ensuring agents are running on all nodes.
   ```bash
   kubectl apply -f config/reachability-daemonset.yaml
   ```

3. **Deploy the Client Test Driver**
   Wait a moment for the DaemonSet pods to start on all nodes, then deploy the Client.
   ```bash
   kubectl apply -f config/reachability-client.yaml
   ```

4. **Retrieve Results**
   The client will wait for the agents to appear, orchestrate passing the IPs around, and conduct the full testing matrix. Check its logs:
   ```bash
   kubectl logs -n reachability-test reachability-client
   ```

### Cleanup 
Once finished, you can gracefully delete the workload or the whole mock cluster:
```bash
kubectl delete namespace reachability-test
# or more completely
kind delete cluster --name reachability
```

---

## Technical Details: Dual-Stack Design

The reachability scripts natively handle both IPv6 and IPv4 networks dynamically. 

### 1. HTTP Socket Binding
In `config/reachability-daemonset.yaml`, the Python HTTP server runs a custom wrapper:
```python
# Python's default HTTP server binds to AF_INET (IPv4).
# Forcing AF_INET6 allows the kernel to handle both natively (IPv4 maps to IPv6 space)
# preventing 'Connection Refused' for IPv6 traffic inside the container.
class DualStackServer(http.server.ThreadingHTTPServer):
    address_family = __import__('socket').AF_INET6
```
Because the agent image defaults to Alpine Linux, the classic `ThreadingHTTPServer` default binds strictly to `0.0.0.0` (IPv4). By explicitly requesting an `AF_INET6` socket (`::`), the Linux kernel operates in Dual-Stack mode, meaning it accepts IPv6 directly and routes incoming IPv4 connections into the IPv6 socket seamlessly.

### 2. URL Host Formatting
When either the Client or the Daemonset constructs URLs, they identify the IP family dynamically:
```python
url_target = f"[{target}]" if ':' in target and not target.startswith('[') else target
url = f"http://{url_target}:{PORT}/"
```
If an IP address contains a colon (`:`), it wraps the address in brackets `[]` to meet RFC 3986 URL parsing requirements. If no colon exists, it passes standard IPv4 directly.
