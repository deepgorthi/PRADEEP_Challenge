provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "server_ami" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*-x86_64-gp2"]
  }
}

data "aws_availability_zones" "available" {}

resource "aws_key_pair" "tf_auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

data "template_file" "user-init" {
  count    = 2
  template = "${file("${path.module}/userdata.tpl")}"
}

resource "aws_instance" "webserver" {
  count         = var.instance_count 
  instance_type = var.server_instance_type
  ami           = data.aws_ami.server_ami.id

  tags = {
    Name = "tf_webserver-${count.index + 1}"
  }

  key_name               = aws_key_pair.tf_auth.id
  vpc_security_group_ids = [aws_security_group.tf_public_sg.id]
  subnet_id              = aws_subnet.tf_subnet[count.index].id
  user_data              = data.template_file.user-init[count.index].rendered
}


resource "aws_vpc" "tf_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "tf_vpc"
  }
}

resource "aws_internet_gateway" "tf_internet_gateway" {
  vpc_id = aws_vpc.tf_vpc.id

  tags = {
    Name = "tf_igw"
  }
}

resource "aws_route_table" "tf_rt" {
  vpc_id = aws_vpc.tf_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tf_internet_gateway.id
  }

  tags = {
    Name = "tf_rt"
  }
}

resource "aws_default_route_table" "tf_private_rt" {
  default_route_table_id  = aws_vpc.tf_vpc.default_route_table_id

  tags = {
    Name = "tf_private"
  }
}

resource "aws_subnet" "tf_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.tf_vpc.id
  cidr_block              = var.cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "tf_subnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "tf_assoc" {
  count          = length(aws_subnet.tf_subnet)
  subnet_id      = aws_subnet.tf_subnet[count.index].id
  route_table_id = aws_route_table.tf_rt.id
}

resource "aws_security_group" "tf_public_sg" {
  name        = "tf_public_sg"
  description = "Used for access to webserver"
  vpc_id      = aws_vpc.tf_vpc.id

#SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.accessip]
  }

#HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.accessip]
  }

#HTTPS 
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.accessip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"      # Allow all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_server_certificate" "ss_cert" {
  name_prefix      = "tf-ss-cert"
  certificate_body = file("tf_cert/certs/ss_ca.pem")
  private_key      = file("tf_cert/certs/ss_ca_private_key.pem")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "web_elb" {
  name               = "tf-web-elb"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)

  # subnets            = aws_subnet.tf_subnet[*].id

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id = aws_iam_server_certificate.ss_cert.arn
  }

  instances                   = aws_instance.webserver[*].id
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "tf-web-elb"
  }
}
