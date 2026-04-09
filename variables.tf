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
