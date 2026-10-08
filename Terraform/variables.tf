variable "aws_region" {
  description = "The AWS region where we are deploying our server"
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the AWS SSH key pair you created in your console"
  type        = string
}

variable "vpc_name" {
  description = "Name of the custom VPC"
  type        = string
  default     = "main-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}
variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}