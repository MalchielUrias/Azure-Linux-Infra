variable "subscription_id" {
  type = string
  default = ""
}

variable "client_id" {
  type = string
  default = ""
}

variable "client_secret" {
  type = string
  default = ""
  sensitive = true
}

variable "tenant_id" {
  type = string
  default = ""
}
