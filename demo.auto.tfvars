vm_config = {
  demo-server-01 = {
    hostname           = "demo-server-01"
    os_type            = "linux"
    linux_distribution = "rhel"
    site               = "sydney"
    size               = "small"
    security_profile   = "web-server"
    environment        = "dev"
    ad_domain          = "hashicorp.local"
    backup_policy      = "daily"
    storage_profile    = "standard"
    tier               = "gold"
  },
  demo-server-02 = {
    hostname           = "demo-server-02"
    os_type            = "linux"
    linux_distribution = "rhel"
    site               = "sydney"
    size               = "small"
    security_profile   = "web-server"
    environment        = "dev"
    ad_domain          = "hashicorp.local"
    backup_policy      = "daily"
    storage_profile    = "standard"
    tier               = "gold"
  }
}
