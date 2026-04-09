terraform {
  required_version = ">= 1.14"

  cloud {
    organization = "tfo-apj-demos"
    workspaces {
      name    = "terraform-vsphere-ephemeral-vault-demo"
      project = "Demo Better Together Project"
    }
  }

  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.15"
    }
    # Vault provider — used for phase 2 ephemeral secret lookup of vSphere creds.
    # Requires hashicorp/vault >= 4.3.0 for ephemeral resource support.
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    # Required by single-virtual-machine module
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.111"
    }
    ad = {
      source  = "hashicorp/ad"
      version = "~> 0.5"
    }
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault provider
# -----------------------------------------------------------------------------
# Auth assumption: HCP Terraform workload identity → Vault JWT auth.
# When workload identity is configured at the workspace/project level the
# Vault provider picks up:
#   - VAULT_ADDR              (Vault endpoint)
#   - TFC_VAULT_PROVIDER_AUTH (set to true)
#   - TFC_VAULT_ADDR / TFC_VAULT_NAMESPACE / TFC_VAULT_AUTH_PATH / TFC_VAULT_RUN_ROLE
# ...from the dynamic-credentials env vars injected into the run.
#
# TODO (user): confirm the workspace is attached to a variable set that enables
# dynamic Vault provider credentials. No static token should be needed here.
provider "vault" {}

# -----------------------------------------------------------------------------
# Ephemeral lookup of vSphere credentials from Vault LDAP secrets engine
# -----------------------------------------------------------------------------
# The Vault provider does not expose a purpose-built ephemeral resource for
# the LDAP secrets engine, so we use `vault_generic_secret` which performs a
# raw Vault read against any path. Reading `ldap/creds/<role>` on an LDAP
# secrets engine returns a short-lived dynamic LDAP user whose `username` and
# `password` are exposed in the response `data` map.
#
# Ephemeral resources never persist to state or plan files — the generated
# credentials are only valid for the duration of the current plan/apply
# operation, and can be safely fed into a provider block (provider blocks
# are themselves ephemeral in nature).
#
# Role UI reference:
#   https://vault.hashicorp.local:8200/ui/vault/secrets/ldap/ldap/roles/dynamic/vsphere_access/details
ephemeral "vault_generic_secret" "vsphere" {
  path = "ldap/creds/vsphere_access"
}

# -----------------------------------------------------------------------------
# vSphere provider — fed from the ephemeral Vault LDAP credentials
# -----------------------------------------------------------------------------
# This is the whole point of the demo: the Vault lookup happens at the ROOT
# module, the provider is configured at the root, and the single-virtual-machine
# module (called with for_each) inherits this provider without containing any
# provider config of its own. Secret values never touch state.
#
# `vsphere_server` is not considered sensitive and comes from the VSPHERE_SERVER
# env var supplied by the project-level variable set (same as phase 1).
provider "vsphere" {
  user                 = ephemeral.vault_generic_secret.vsphere.data["username"]
  password             = ephemeral.vault_generic_secret.vsphere.data["password"]
  allow_unverified_ssl = true
}

# HCP provider configuration
provider "hcp" {
  project_id = "11eb56d6-0f95-3a99-a33c-0242ac110007"
}
