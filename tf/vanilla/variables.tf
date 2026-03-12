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

variable "k8s_subnet_cidr" {
  type        = string
  default     = "10.0.0.0/24"
  description = "The CIDR range for the Kubernetes subnet."
}


resource "random_id" "rand" {
  byte_length = 4
}

locals {
  zone        = "${var.region}-a"
  rand_suffix = random_id.rand.hex
}
