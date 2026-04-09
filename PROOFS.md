# Proving Ephemeral Vault Credentials — Demo Runbook

This runbook walks through concrete proof points showing that ephemeral Vault credentials feeding a provider config:

1. **Never persist** to state or plan files
2. **Are short-lived** — issued at operation start, revoked at operation end
3. **Cannot be exfiltrated** — Terraform's type system enforces the boundary at compile time

Use these in order during a customer walkthrough. Each proof builds on the previous.

---

## Prerequisites

- Terraform >= 1.14 installed locally
- Authenticated to HCP Terraform (`TF_TOKEN_app_terraform_io` set or `terraform login`)
- Vault CLI authenticated (for Vault-side proofs)
- The workspace has a successful apply (VMs exist in state)

---

## Proof 1 — Ephemeral resources do not appear in state

```bash
# Ephemeral resources are never written to state — confirm with state list
terraform state list | grep -i ephemeral
# Expected: no output (empty)

# Full state JSON search for any trace of ephemeral data
terraform show -json | grep -iE 'ephemeral|v_token_|password' || echo "PASS: no credentials found in state"
```

**What to tell the customer:**
> "State is the primary attack surface for credential leakage in Terraform. Ephemeral resources are architecturally excluded from state — there is no code path that writes them there. This isn't a flag or a setting, it's a fundamental property of the resource type."

---

## Proof 2 — Plan files contain zero credentials

```bash
# Generate a saved plan
terraform plan -out=tfplan

# Search the plan file for any credential material
terraform show -json tfplan | grep -iE 'password|v_token_|cn=|secret' || echo "PASS: no credentials found in plan file"

# Clean up
rm tfplan
```

**What to tell the customer:**
> "Plan files are what get stored in CI artifacts, attached to PRs for review, and uploaded to TFC for policy evaluation. Even if someone extracts the raw plan file, the credentials are not in it."

---

## Proof 3 — Ephemeral lifecycle in run output

Look at the TFC run output (or local terminal output) from the most recent apply. You will see three distinct phases:

```
ephemeral.vault_generic_secret.vsphere: Opening...
ephemeral.vault_generic_secret.vsphere: Opening complete after 1s

  ... VM creation happens here using the dynamic credentials ...

ephemeral.vault_generic_secret.vsphere: Closing...
ephemeral.vault_generic_secret.vsphere: Closing complete after 0s
```

**What to tell the customer:**
> "Opening means Terraform asked Vault to issue a dynamic LDAP user. Closing means Terraform explicitly told Vault to revoke that user — not 'wait for TTL expiry', but active revocation. The credential's lifetime is bounded to exactly this single plan or apply operation."

---

## Proof 4 — Vault-side: watch the dynamic lease appear and disappear

Run these commands in a separate terminal **during** and **after** an apply.

### During the apply

```bash
# List active leases under the LDAP role
vault list sys/leases/lookup/ldap/creds/vsphere_access

# Pick one of the lease IDs and inspect it
vault write sys/leases/lookup lease_id="ldap/creds/vsphere_access/<lease_id>"
# Note: issue_time, expire_time, ttl
```

### After the apply completes

```bash
# Same list — the lease from the apply is gone
vault list sys/leases/lookup/ldap/creds/vsphere_access
# The lease ID that existed during the apply is no longer present.
# It was revoked by Terraform's "Closing" phase, not expired via TTL.
```

### Vault audit log (optional, strongest proof)

```bash
# Filter audit log for the LDAP creds path during the apply window
# (exact command depends on audit device — file, syslog, socket)
grep "ldap/creds/vsphere_access" /var/log/vault/audit.log | tail -5
```

The audit log shows: a `read` (credential issuance) at apply start, and a `revoke` at apply end, both tied to the TFC workload identity JWT.

**What to tell the customer:**
> "This is the Vault perspective. The credential existed for exactly the duration of the Terraform operation — about 90 seconds in our case. After that, the LDAP user is deleted from Active Directory. Even if someone intercepted the username and password mid-operation, they would be useless after the apply finishes."

---

## Proof 5 — vCenter session log

In the vCenter UI during an apply:

1. Go to **Administration → Sessions** (or **Monitoring → Sessions** depending on version)
2. Observe a session from a user like `v_token_tfc_vsphere_access_xxxxx` — this is the dynamic LDAP user
3. After the apply completes and the Vault lease is revoked, that user no longer exists in Active Directory
4. The session is terminated and the user cannot be reused

**What to tell the customer:**
> "In vCenter you can see the actual dynamic user that was created for this single Terraform run. After the run, that user is deleted from AD by Vault. There is no standing credential, no service account password to rotate, no shared secret."

---

## Proof 6 — Each apply uses a different dynamic user

Run two consecutive plans and compare the Opening lines:

```bash
# First plan
terraform plan 2>&1 | grep "Opening"
# Output: ephemeral.vault_generic_secret.vsphere: Opening complete after 1s

# Second plan
terraform plan 2>&1 | grep "Opening"
# Output: ephemeral.vault_generic_secret.vsphere: Opening complete after 0s
```

To see the actual username difference, temporarily check Vault leases during each plan (per Proof 4) — each one shows a different `v_token_*` username.

**What to tell the customer:**
> "Every single Terraform operation gets a unique, short-lived credential. There is no credential reuse across runs, no rotation schedule to manage, no window where a compromised credential could be replayed."

---

## Proof 7 — Terraform refuses to leak ephemeral values to outputs

This is the most powerful live demo. Create a file `leak_test.tf`:

```hcl
output "leak_test" {
  value = ephemeral.vault_generic_secret.vsphere.data["password"]
}
```

Then run:

```bash
terraform plan
```

Expected error:

```
Error: Ephemeral value not allowed

  on leak_test.tf line 2, in output "leak_test":

Ephemeral values are not valid in output blocks because output values are
persisted in state and plan files.
```

Clean up:

```bash
rm leak_test.tf
```

**What to tell the customer:**
> "This is not a runtime check — Terraform catches this at compile time, before any API call is made. The language type system knows this value is ephemeral and will not allow it to flow anywhere that persists. You cannot accidentally output it, assign it to a non-ephemeral variable, or store it in a local that feeds a resource argument (unless that argument is explicitly marked write-only by the provider)."

---

## Proof 8 — Terraform refuses to leak ephemeral values via local-exec

Create a file `leak_exec.tf`:

```hcl
resource "terraform_data" "leak" {
  provisioner "local-exec" {
    command = "echo ${ephemeral.vault_generic_secret.vsphere.data["password"]}"
  }
}
```

Then run:

```bash
terraform plan
```

Expected error:

```
Error: Ephemeral value not allowed

  on leak_exec.tf line 3, in resource "terraform_data" "leak":

Ephemeral values are not valid in provisioner blocks.
```

Clean up:

```bash
rm leak_exec.tf
```

**What to tell the customer:**
> "Even if someone tries to exfiltrate the credential through a local-exec provisioner — which is the classic attack vector for leaking sensitive values from a Terraform run — the compiler rejects it. And on top of this language-level protection, we can layer a Sentinel policy that blocks local-exec provisioners from existing at all, so the attempt never even reaches this error."

This is a natural segue into the Sentinel `local-exec` block policy if you have that ready.

---

## Summary table

| Proof | What it shows | Effort |
|-------|---------------|--------|
| 1. State inspection | Credentials not in state | 10 sec |
| 2. Plan file inspection | Credentials not in plan artifacts | 15 sec |
| 3. Run output lifecycle | Opening → operation → Closing | Visual |
| 4. Vault lease tracking | Dynamic user created and revoked | 2 min |
| 5. vCenter session log | Dynamic user visible during apply | Visual |
| 6. Multiple applies | Different credential each run | 3 min |
| 7. Output leak attempt | Terraform compiler refuses | 30 sec |
| 8. local-exec leak attempt | Terraform compiler refuses | 30 sec |

**Recommended demo order for maximum impact:** Start with **7** (the "aha" moment — Terraform refuses to compile a leak), then **1** and **2** (no creds in state/plan), then **3** (lifecycle in the logs). Use **4** and **5** for customers who want the Vault/vCenter perspective. Close with **8** to segue into Sentinel.
