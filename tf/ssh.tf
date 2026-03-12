resource "tls_private_key" "vm_ssh_key" {
  algorithm = "ED25519"
}

resource "local_file" "private_key" {
  content         = tls_private_key.vm_ssh_key.private_key_openssh
  filename        = "${path.module}/.tmp/vm_key"
  file_permission = "0600" # Crucial: SSH requires strict permissions on private keys
}