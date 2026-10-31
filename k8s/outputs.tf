output "node_ips" {
  description = "노드 이름 → IP"
  value       = { for k, v in local.nodes : k => v.ip }
}
