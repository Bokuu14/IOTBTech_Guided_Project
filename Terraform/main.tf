# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# Create a custom VPC so we control our network space
resource "aws_vpc" "my_project_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "project-vpc"
  }
}

# Create a Public Subnet inside our VPC
resource "aws_subnet" "my_public_subnet" {
  vpc_id                  = aws_vpc.my_project_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "project-public-subnet"
  }
}

# Create an Internet Gateway so our VPC can talk to the internet
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_project_vpc.id

  tags = {
    Name = "project-igw"
  }
}

# Create a Route Table to direct internet-bound traffic to the IGW
resource "aws_route_table" "my_public_rt" {
  vpc_id = aws_vpc.my_project_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "project-public-rt"
  }
}

# Associate our Route Table with our Public Subnet
resource "aws_route_table_association" "rt_association" {
  subnet_id      = aws_subnet.my_public_subnet.id
  route_table_id = aws_route_table.my_public_rt.id
}

# Create a Security Group (Firewall) allowing SSH and general web traffic
resource "aws_security_group" "my_sg" {
  name        = "project-security-group"
  description = "Allow SSH and HTTP traffic"
  vpc_id      = aws_vpc.my_project_vpc.id

  # Allow SSH from anywhere (you can lock this to your IP later if you want)
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP web traffic
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound traffic to everywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project-sg"
  }
}

resource "aws_key_pair" "my_key" {
  key_name   = "Dove-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# Master server: the Ansible control node
resource "aws_instance" "my_server" {
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.my_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.my_sg.id]
  key_name                    = aws_key_pair.my_key.key_name
  associate_public_ip_address = true

  tags = {
    Name = "ansible-master"
  }
}

# Worker server: managed by Ansible from the master above
resource "aws_instance" "worker_server" {
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.my_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.my_sg.id]
  key_name                    = aws_key_pair.my_key.key_name
  associate_public_ip_address = true

  tags = {
    Name = "ansible-worker-node"
  }
}

# Seed the master with the Ansible project and run the bootstrap
# script during `terraform apply`, so you can SSH in and immediately
# run the playbook. It re-runs automatically whenever the master or
# worker is replaced, or whenever any Ansible file changes locally.
resource "terraform_data" "seed_master" {
  triggers_replace = [
    aws_instance.my_server.id,
    aws_instance.worker_server.id,
    filesha256("${path.module}/../Ansible/setup_master.sh"),
    filesha256("${path.module}/../Ansible/playbook.yml"),
    filesha256("${path.module}/../Ansible/ansible.cfg"),
  ]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.my_server.public_ip
    private_key = file(pathexpand("~/.ssh/id_rsa"))
    timeout     = "10m"
  }

  # 1) Create the folder layout on the master
  provisioner "remote-exec" {
    inline = ["mkdir -p /home/ubuntu/ansible/inventory"]
  }

  # 2) Copy the Ansible project files
  provisioner "file" {
    source      = "${path.module}/../Ansible/setup_master.sh"
    destination = "/home/ubuntu/ansible/setup_master.sh"
  }

  provisioner "file" {
    source      = "${path.module}/../Ansible/playbook.yml"
    destination = "/home/ubuntu/ansible/playbook.yml"
  }

  provisioner "file" {
    source      = "${path.module}/../Ansible/ansible.cfg"
    destination = "/home/ubuntu/ansible/ansible.cfg"
  }

  # 3) Generate the inventory from the worker's private IP
  provisioner "file" {
    content     = "[workers]\n${aws_instance.worker_server.private_ip}\n"
    destination = "/home/ubuntu/ansible/inventory/hosts"
  }

  # 4) Copy the private key so the master can SSH into the worker
  provisioner "file" {
    source      = pathexpand("~/.ssh/id_rsa")
    destination = "/home/ubuntu/.ssh/id_rsa"
  }

  # 5) Install Ansible and check the worker is reachable
  provisioner "remote-exec" {
    inline = ["bash /home/ubuntu/ansible/setup_master.sh"]
  }
}