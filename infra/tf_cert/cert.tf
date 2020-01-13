###############################################################
#################  Self Signed Cert Creation  #################

provider "tls" {
  version = "~> 2.0"
}

provider "local" {
  version = "~> 1.1"
}

resource "tls_private_key" "ss_ca" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "local_file" "ss_ca_key" {
  content  = "${tls_private_key.ss_ca.private_key_pem}"
  filename = "${path.module}/certs/ss_ca_private_key.pem"
}

resource "tls_self_signed_cert" "ss_ca" {
  key_algorithm     = "RSA"
  private_key_pem   = "${tls_private_key.ss_ca.private_key_pem}"
  is_ca_certificate = true

  subject {
    common_name         = "Deep Self Signed CA"
    organization        = "Deep Self Signed"
    organizational_unit = "deep"
  }

  validity_period_hours = 86000

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "local_file" "ss_ca_cert" {
  content  = "${tls_self_signed_cert.ss_ca.cert_pem}"
  filename = "${path.module}/certs/ss_ca.pem"
}

resource "tls_private_key" "ss_deep_com" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "local_file" "ss_deep_com_key" {
  content  = "${tls_private_key.ss_deep_com.private_key_pem}"
  filename = "${path.module}/certs/ss_deep_com_private_key.pem"
}

resource "tls_cert_request" "ss_deep_com" {
  key_algorithm   = "RSA"
  private_key_pem = "${tls_private_key.ss_deep_com.private_key_pem}"

  dns_names = ["ss_deep.com"]

  subject {
    common_name         = "ss_deep.com"
    organization        = "Deep Self Signed"
    country             = "US"
    organizational_unit = "ss_deep.com"
  }
}

resource "tls_locally_signed_cert" "ss_deep_com" {
  cert_request_pem   = "${tls_cert_request.ss_deep_com.cert_request_pem}"
  ca_key_algorithm   = "RSA"
  ca_private_key_pem = "${tls_private_key.ss_ca.private_key_pem}"
  ca_cert_pem        = "${tls_self_signed_cert.ss_ca.cert_pem}"

  validity_period_hours = 86000

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

resource "local_file" "ss_deep_com_cert_pem" {
  content  = "${tls_locally_signed_cert.ss_deep_com.cert_pem}"
  filename = "${path.module}/certs/ss_deep_com_cert.pem"
}

###############################################################