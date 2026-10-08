output "public_ip" {
  value = oci_core_instance.main.public_ip
}

output "ssh_command" {
  value = "ssh opc@${oci_core_instance.main.public_ip}"
}

output "image_id" {
  description = "Image the instance was created from (not the newest published one)."
  value       = oci_core_instance.main.source_details[0].source_id
}
