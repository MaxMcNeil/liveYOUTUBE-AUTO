output "public_ip" {
  value       = oci_core_instance.livestream_vm.public_ip
  description = "Adresse IP publique du VPS — utile pour vous y connecter en SSH ensuite (ssh ubuntu@<ip>)"
}
