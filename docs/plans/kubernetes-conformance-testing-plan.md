# Kubernetes Conformance Testing Plan

## Overview
This plan outlines the steps necessary to run the official Kubernetes Certified Conformance tests against the deployed cluster. We will use [Sonobuoy](https://sonobuoy.io/), the standard diagnostic tool created by Heptio (now VMware Tanzu) and maintained by the CNCF, to orchestrate the conformance tests.

## Prerequisites
- A running Kubernetes cluster (e.g., deployed via this repository's Terraform/kubeadm scripts).
- `kubectl` installed and configured with the cluster's `kubeconfig` (e.g., `export KUBECONFIG=$(pwd)/.tmp/kubeconfig.yaml`).
- Internet access from the client machine to download the Sonobuoy binary.

## Step 1: Get the Sonobuoy Testing Tool
Sonobuoy is distributed as a highly portable Go binary.

1. Find the latest release of Sonobuoy from the [official GitHub releases page](https://github.com/vmware-tanzu/sonobuoy/releases).
2. Download and extract the binary for your operating system:
   ```bash
   # Example for Linux AMD64
   VERSION=0.57.1 # Adjust as needed based on your Kubernetes version
   wget https://github.com/vmware-tanzu/sonobuoy/releases/download/v${VERSION}/sonobuoy_${VERSION}_linux_amd64.tar.gz
   tar -xzf sonobuoy_${VERSION}_linux_amd64.tar.gz
   chmod +x sonobuoy
   sudo mv sonobuoy /usr/local/bin/
   ```
3. Verify the installation:
   ```bash
   sonobuoy version
   ```

## Step 2: Run the Conformance Tests
Sonobuoy runs tests by deploying a DaemonSet and several Pods into your cluster (primarily in the `sonobuoy` namespace). The certified conformance mode runs the CNCF-mandated end-to-end (E2E) tests.

1. Trigger the conformance tests. This operates asynchronously, spinning up testing pods on your cluster.
   ```bash
   sonobuoy run --mode=certified-conformance
   ```
   *Note: Conformance tests are comprehensive. Ensure your nodes meet the minimum resource requirements. For IPv6-only or restricted clusters, ensure the Sonobuoy container images can be actively pulled from registries.*

2. Check the status of the run at any time. The tests typically take around 1 to 2 hours to complete depending on cluster size and performance.
   ```bash
   sonobuoy status
   ```
   *Wait until the status reports that the plugins have completed successfully.*

## Step 3: Collect and Inspect the Output
Once `sonobuoy status` reports that the run is complete, extract the results from the cluster.

1. Retrieve the results tarball from the cluster to your local machine:
   ```bash
   outfile=$(sonobuoy retrieve)
   ```
2. The `outfile` variable now holds the name of the downloaded `.tar.gz` results file. You can summarize the results directly using the CLI:
   ```bash
   sonobuoy results $outfile
   ```
   *This will print a high-level summary indicating passed, failed, and skipped tests.*

3. **Detailed Inspection**: To view specific failed tests, you can use the detailed mode:
   ```bash
   sonobuoy results $outfile --mode=detailed
   ```

## Step 4: Cleanup
To clean up and completely remove all Sonobuoy resources (namespaces, pods, and daemonsets) from your cluster once you have secured your results:
```bash
sonobuoy delete --wait
```
