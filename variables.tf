variable "tenancy_ocid" {
  description = "OCID of the tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment for all resources. Defaults to the tenancy (root compartment)."
  type        = string
  default     = null
}

variable "region" {
  description = "OCI region, e.g. us-ashburn-1"
  type        = string
}

variable "oci_profile" {
  description = "Profile name in ~/.oci/config"
  type        = string
  default     = "DEFAULT"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key installed for the opc user"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ocpus" {
  type    = number
  default = 4
}

variable "memory_gbs" {
  type    = number
  default = 24
}

variable "boot_volume_gbs" {
  description = "Boot volume size. Always Free covers 200 GB total."
  type        = number
  default     = 100
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to reach SSH. Narrow this to your own IP."
  type        = string
  default     = "0.0.0.0/0"
}

variable "availability_domain_index" {
  description = "Which availability domain to use. Change it if A1 capacity is short."
  type        = number
  default     = 0
}
