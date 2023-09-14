output "jumpwire_api_url" {
  value = aws_apigatewayv2_api.jumpwire_api.api_endpoint
}

output "jumpwire_gateway_host" {
  value = aws_lb.jumpwire_nlb.dns_name
}