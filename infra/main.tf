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

# resource "aws_acm_certificate" "ssl_cert" {
#   domain_name               = var.root_domain_name
#   validation_method         = "EMAIL"
#   subject_alternative_names = ["*.${var.root_domain_name}"]

#   tags = {
#     Environment = "test"
#   }

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# data "aws_route53_zone" "zone" {
#   name         = "deepgorthi.com."
#   private_zone = false
# }

# resource "aws_route53_record" "cert_validation" {
#   name    = aws_acm_certificate.ssl_cert.domain_validation_options.0.resource_record_name
#   type    = aws_acm_certificate.ssl_cert.domain_validation_options.0.resource_record_type
#   zone_id = data.aws_route53_zone.zone.id
#   records = [aws_acm_certificate.ssl_cert.domain_validation_options.0.resource_record_value]
#   ttl     = 60
# }

# resource "aws_acm_certificate_validation" "cert" {
#   certificate_arn         = aws_acm_certificate.ssl_cert.arn
#   validation_record_fqdns = [
#       aws_route53_record.cert_validation.fqdn,
#     ]
# }






# resource "tls_private_key" "ss_key" {
#   algorithm = "ECDSA"
# }

# resource "tls_self_signed_cert" "ss_cert" {
#   key_algorithm   = tls_private_key.ss_key.algorithm
#   private_key_pem = tls_private_key.ss_key.private_key_pem
#   validity_period_hours = 3600
#   early_renewal_hours = 2400
#   allowed_uses = [
#       "key_encipherment",
#       "digital_signature",
#       "server_auth",
#   ]
#   dns_names = ["test_deep.com"]
#   subject {
#       common_name  = "test_deep.com"
#       organization = "Deep Gorthi, Inc"
#   }
# }





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
  subnets            = aws_subnet.tf_subnet[*].id

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

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
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





###################################################################
# resource "aws_lb" "web_lb" {
#   name               = "tf-web-lb"
#   internal           = false
#   load_balancer_type = "application"
#   subnets            = aws_subnet.tf_subnet[*].id
#   security_groups    = aws_security_group.tf_public_sg[*].id

#   tags = {
#     Name = "tf_web_lb"
#   }
# }

# resource "aws_lb_target_group" "web_lb_target" {
#   name     = "web-loadbalancer-target"
#   port     = "80"
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.tf_vpc.id
# }

# resource "aws_lb_target_group_attachment" "web_lb_attachment" {
#   count    = length(aws_subnet.tf_subnet)
#   target_group_arn = aws_lb_target_group.web_lb_target.arn
#   target_id = aws_instance.webserver[count.index].id
#   port = "80"
# }

# resource "aws_lb_listener" "front_end" {
#   load_balancer_arn = aws_lb.web_lb.arn
#   port = "80"
#   protocol = "HTTP"

#   default_action {
#     type = "forward"
#     target_group_arn = aws_lb_target_group.web_lb_target.arn
#   }
# }

# resource "aws_lb_listener_rule" "redirect_http_to_https" {
#   listener_arn = aws_lb_listener.front_end.arn

#   action {
#     type = "redirect"

#     redirect {
#       port        = "443"
#       protocol    = "HTTPS"
#       status_code = "HTTP_301"
#     }
#   }

#   condition {
#     http_header {
#       http_header_name = "X-Forwarded-For"
#       values           = ["*"]
#     }
#   }
# }

# resource "aws_lb_listener_certificate" "lb_listener_cert" {
#   listener_arn    = aws_lb_listener.front_end.arn
#   certificate_arn = aws_iam_server_certificate.ss_cert.arn
# }

###################################################################


# resource "aws_route53_record" "test" {
#   zone_id = data.aws_route53_zone.zone.zone_id
#   name = "test.deepgorthi.com"
#   type = "A"

#   alias {
#     name = aws_lb.web_lb.dns_name
#     zone_id = aws_lb.web_lb.zone_id
#     evaluate_target_health = true
#   }
# }
