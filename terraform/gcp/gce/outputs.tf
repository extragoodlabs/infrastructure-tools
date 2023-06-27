output "instances" {
  description = "Instance name => address map."
  value       = zipmap(google_compute_instance.jumpwire.*.name, google_compute_address.jumpwire.*.address)
}

output "names" {
  description = "List of instance names."
  value       = [google_compute_instance.jumpwire.*.name]
}

output "external_addresses" {
  description = "List of instance external addresses."
  value       = google_compute_address.jumpwire.*.address
}
