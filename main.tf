# Minimal demo: call the single-virtual-machine module with for_each over a
# map of VM definitions. Purpose is to test two things later:
#   1. Feeding provider config (vsphere creds) from an ephemeral Vault secret
#      at root level, inherited by the for_each'd module.
#   2. A Sentinel policy that blocks local-exec on plan/apply.

module "single_virtual_machine" {
  for_each               = var.vm_config
  source                 = "app.terraform.io/tfo-apj-demos/single-virtual-machine/vsphere"
  version                = "1.6.2"
  fallback_template_name = "base-rhel-9-20250501083042_vtpm"

  hostname           = each.value.hostname
  ad_domain          = each.value.ad_domain
  backup_policy      = each.value.backup_policy
  environment        = each.value.environment
  os_type            = each.value.os_type
  linux_distribution = each.value.linux_distribution
  security_profile   = each.value.security_profile
  site               = each.value.site
  size               = each.value.size
  storage_profile    = each.value.storage_profile
  tier               = each.value.tier
}
