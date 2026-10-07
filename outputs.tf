output "public_ip" {
  value = oci_core_instance.main.public_ip
}

output "ssh_command" {
  value = "ssh opc@${oci_core_instance.main.public_ip}"
}

output "image_name" {
  value = data.oci_core_images.ol10.images[0].display_name
}
