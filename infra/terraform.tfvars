key_name = "tf_key"
public_key_path = "/Users/pradeepgorthi/.ssh/id_rsa.pub"
server_instance_type = "t2.micro"
accessip    = "0.0.0.0/0"
vpc_cidr     = "10.123.0.0/16"
cidrs = [
  "10.123.1.0/24",
  "10.123.2.0/24"
]
aws_region   = "us-east-1"
instance_count = 2
root_domain_name = "deepgorthi.com"