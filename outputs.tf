output "ssh" {
    value = tls_private_key.flux
    sensitive = true
}