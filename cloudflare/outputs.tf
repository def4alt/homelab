output "hostnames" {
  value = sort(tolist(local.hostnames))
}

