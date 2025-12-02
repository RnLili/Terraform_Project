variable "location" {
  type    = string
  default = "West Europe"
}
variable "subscription_id" {
  type    = string
  default = ""
}
variable "tenant_id" {
  type    = string
  default = ""
}
variable "protocols" {
  default = {
    http  = 80
    https = 443

  }
}
variable "user" {
  description = "User"
  default     = "admin@default.gs"
}
variable "base" {
  description = "Base URL"
  default     = "https://api.openai.com/v1"
}
variable "key" {
  description = "API key"
  default     = ""
}




