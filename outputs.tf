# Outputs file
output "catapp_ip" {
  value = "http://${alicloud_eip_address.hashicat.ip_address}"
}
