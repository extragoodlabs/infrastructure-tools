output "jumpwire_gateway_host" {
  value = aws_route53_record.jumpwire_hostname.fqdn
}