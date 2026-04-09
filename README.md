# terraform-vsphere-ephemeral-vault-demo

Minimal demo repo to test two things against the standard `single-virtual-machine` module pattern:

1. **Feeding provider config from an ephemeral Vault secret** at the root module, so child modules called with `for_each` can inherit the provider — without any secret touching state.
2. **A Sentinel policy that blocks `local-exec` provisioners** on plan/apply, to stop accidental secret-leak vectors.

## Phase 1 — baseline (this commit)

- Calls `app.terraform.io/tfo-apj-demos/single-virtual-machine/vsphere` with `for_each` over a map of two VMs (`demo-server-01`, `demo-server-02`).
- vSphere / HCP provider creds come from the HCP Terraform project-level variable set (dynamic credentials via workload identity).
- No Vault ephemeral lookup yet, no Sentinel yet, no AAP integration.
- Goal: get `terraform plan` / `apply` green on HCP Terraform first.

## Phase 2 — ephemeral Vault for provider creds (planned)

Add at the root module:

```hcl
ephemeral "vault_kv_secret_v2" "vsphere_creds" {
  mount = "secret"
  name  = "vsphere-admin"
}

provider "vsphere" {
  user                 = ephemeral.vault_kv_secret_v2.vsphere_creds.data["username"]
  password             = ephemeral.vault_kv_secret_v2.vsphere_creds.data["password"]
  vsphere_server       = ephemeral.vault_kv_secret_v2.vsphere_creds.data["server"]
  allow_unverified_ssl = true
}
```

The `single-virtual-machine` module (and its downstream `terraform-vsphere-virtual-machine` module) already declare no `provider {}` config block — they only declare `required_providers` — so they will inherit this provider cleanly under `for_each`.

## Phase 3 — Sentinel block on local-exec (planned)

Attach a Sentinel policy set to this workspace that fails any plan containing a `local-exec` provisioner.

## Workspace

- HCP Terraform org: `tfo-apj-demos`
- Project: `Demo Better Together Project`
- Workspace: `terraform-vsphere-ephemeral-vault-demo` (auto-created on first `terraform init`)
