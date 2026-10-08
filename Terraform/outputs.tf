output "master_public_ip" {
  description = "Public IP of the Ansible master server - SSH here to run the playbook"
  value       = aws_instance.my_server.public_ip
}

output "worker_public_ip" {
  description = "Public IP of the Docker worker server"
  value       = aws_instance.worker_server.public_ip
}
