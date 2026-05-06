variable "db_password" {
  description = "db_password"
  type        = string
  sensitive   = true
}

variable "ssh_key" {
  description = "ssh_key"
  type        = string
  sensitive = true
}

variable "admin_IP" {
  description = "admin_IP"
  type        = list(string)
  sensitive   = true
}

variable "instance_keycloak" {
    description = "instance_keycloak"
    type = string
    sensitive = true
}

variable "region" {
    description = "region"
    type = string
    sensitive = true
}

variable "db_username" {
    description = "db_username"
    type = string
    sensitive = true
}

variable "key_name" {
    description = "key_name"
    type = string
    sensitive = true
}

variable "keycloak_admin" {
  description = "keycloak_admin"
  type = string
  sensitive = true
}

variable "keycloak_admin_password" {
  description = "keycloak_admin_password"
  type = string
  sensitive = true

}