variable "org_id" {
  description = "GCP organization ID"
  type        = string
  default     = "705380188382"
}

variable "billing_account" {
  description = "三個 project 要連結的 Billing Account ID"
  type        = string
}

variable "region" {
  description = "所有資源使用的 region"
  type        = string
  default     = "asia-east1"
}

variable "vpn_tunnel_1_shared_secret" {
  description = "host-vpn-tunnel-1 / onprem-tunnel-1 這組配對用的 IKE pre-shared key,兩邊必須一致"
  type        = string
  sensitive   = true
}

variable "vpn_tunnel_2_shared_secret" {
  description = "host-vpn-tunnel-2 / onprem-tunnel-2 這組配對用的 IKE pre-shared key,兩邊必須一致"
  type        = string
  sensitive   = true
}
