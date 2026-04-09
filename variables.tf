# Dummy variable declarations — values come from a project/workspace-level
# variable set that also feeds other workspaces. Declared here purely to
# silence "Value for undeclared variable" warnings on plan.
variable "admin_password" {
  type      = string
  sensitive = true
  default   = null
}

variable "domain_admin_user" {
  type    = string
  default = null
}

variable "domain_admin_password" {
  type      = string
  sensitive = true
  default   = null
}

variable "ad_domain_name" {
  type    = string
  default = null
}

variable "ad_domain" {
  type    = string
  default = null
}

variable "vm_config" {
  description = "Configuration for multiple VMs"
  type = map(object({
    hostname           = string
    ad_domain          = string
    backup_policy      = string
    environment        = string
    os_type            = string
    linux_distribution = string
    security_profile   = string
    site               = string
    size               = string
    storage_profile    = string
    tier               = string
  }))
}
