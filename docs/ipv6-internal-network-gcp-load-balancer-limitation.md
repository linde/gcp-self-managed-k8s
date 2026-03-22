# IPv6 Internal Network GCP Load Balancer Limitation

This document outlines a significant limitation encountered when attempting to provision a publicly exposed **Regional External Proxy Network Load Balancer (IPv4)** routing traffic to an internal, **IPv6-Only** Google Compute Engine (GCE) backend instance entirely via Terraform.

## The Goal

We architected our Kubernetes cluster to be strictly **IPv6-Only** internally, stripping all external instances of their default IPv4 addresses. 

To provide secure external CLI access (e.g., `kubectl` on port `6443`), our intention was to deploy a managed **TCP Proxy Network Load Balancer**. Because it operates as an intelligent proxy, it seamlessly bridging a standard, premium **IPv4** frontend address dynamically into our private **IPv6** internal Subnet Network. 

To connect an IPv6 backend instance to a Google Cloud Proxy Load Balancer, Google Cloud's API explicitly requires swapping out standard Unmanaged Instance Groups for **Zonal Network Endpoint Groups (NEGs)**.

## The Terraform Limitation

When attempting to declare a Zonal NEG with the type `GCE_VM_IP_PORT` pointing to our IPv6 backend, the Google Cloud API requires the explicit registration of the instance's IPv6 address.

However, the official Terraform `hashicorp/google` (and `hashicorp/google-beta`) provider completely lacks support for binding IPv6 addresses to this NEG type. Specifically:

1. The `google_compute_network_endpoint` resource natively exposes an `ip_address` field, but strictly validates it as an **IPv4-only** address natively in its provider schema parser. If we pass the generated instance's IPv6 ULA address into this field, the provider throws a hard HTTP `400 Bad Request: Must be a valid IPV4 address` API error.
2. The `google_compute_network_endpoint` resource natively lacks an `ipv6_address` parameter entirely. Supplying this parameter throws an `Unsupported argument: An argument named "ipv6_address" is not expected here` validation error.

The underlying Google Cloud API fully supports registering an endpoint with an `ipv6` parameter via `gcloud`, but Terraform simply hasn't mapped or exposed this field downstream for developers utilizing `google_compute_network_endpoint` resources. 

## The Current Non-Idiomatic Hack
Because the core infrastructure-as-code layer fails to abstract this configuration, the only workaround to keep the architecture fully automated is to bypass Terraform's typed resource completely and manually bridge the CLI using a non-idiomatic `null_resource` local-exec provisioner.

Instead of declaring a clean `google_compute_network_endpoint`, we execute raw inline bash referencing local shell tools during the `terraform apply` sequence:

```hcl
resource "null_resource" "cp_endpoint" {
  ...
  provisioner "local-exec" {
    command = <<EOF
gcloud compute network-endpoint-groups update ... \
  --add-endpoint="instance=...,port=...,ipv6=..."
EOF
  }
}
```

This violates infrastructure drift detection, pollutes the terraform execution dependencies, and requires the user to have valid `gcloud` credentials installed and authenticated in the deployment environment. Once Hashicorp introduces native `ipv6_address` definitions within `google_compute_network_endpoint`, this gross workaround should immediately be reverted.
