variable "gcp_project" {
  type        = string
  description = "The GCP project ID to deploy into."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "The GCP region for deployment."
}

variable "machine_type" {
  type        = string
  default     = "e2-standard-4"
  description = "The machine type for both control plane and worker nodes."
}

variable "k8s_version" {
  type        = string
  default     = "1.32"
  description = "The version of Kubernetes to install (e.g., 1.32, 1.34)."
}

variable "os_image" {
  type        = string
  default     = "debian-cloud/debian-13"
  description = "The boot image for the instances."
}

variable "k8s_service_cidr_ipv6" {
  type        = string
  default     = "fd00:1::/112"
  description = "The IPv6 CIDR range for Kubernetes services."
}

variable "k8s_pod_cidr_ipv6" {
  type        = string
  default     = "fd00:10::/56"
  description = "The IPv6 CIDR range for Kubernetes pods."
}

variable "worker_node_count" {
  type        = number
  default     = 2
  description = "The number of worker nodes to provision."
}

resource "random_id" "rand" {
  byte_length = 4
}

locals {
  zone        = "${var.region}-a"
  rand_suffix = random_id.rand.hex
}
