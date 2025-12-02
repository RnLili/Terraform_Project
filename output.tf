output "server_public_ip" {
  value = resource.azurerm_public_ip.server-pub-ip.ip_address
}
output "client_public_ip" {
  value = resource.azurerm_public_ip.client-pub-ip.ip_address
}
output "password" {
  sensitive = true
  value     = random_password.password.result
}