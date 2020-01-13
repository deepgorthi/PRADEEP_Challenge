variable "aws_region" {}
variable "key_name" {}
variable "public_key_path" {}
variable "server_instance_type" {}
variable "vpc_cidr" {}
variable "cidrs" {
    type = list(string)
}
variable "accessip" {}
variable "instance_count" {}
variable "root_domain_name" {}
