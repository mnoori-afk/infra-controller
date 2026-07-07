# Launchpad — Vault BMC/UEFI credentials (REQUIRED for ingestion)

site-explorer reads these from Vault to authenticate to the BMCs. **If any is missing OR stored with an
empty value, ingestion silently stalls** — site-explorer aborts each cycle with `Missing credential …`
(0 endpoints, 0 managed hosts). We hit exactly this: the CLI `add-uefi`/`add-bmc` had written **empty**
values, which the API reports as "already exists" (blocking re-seed) while the explorer reads them as
"Missing". So: seed them, then **verify the values are non-empty**.

GB300 creds (all password = the site BMC password Milad shares, shown below as `${BMC_PASSWORD}`): host/tray BMC = **AMI MegaRAC, user `admin`**; DPU BMC =
**OpenBMC, user `root`**; UEFI = password-only (username blank by design).

## The 5 credential paths (KV mount = `secrets`, KV-v2)

| Vault path | username | password | what |
|---|---|---|---|
| `machines/bmc/site/root` | `admin` | set | site-wide BMC default (host) |
| `machines/all_hosts/site_default/bmc-metadata-items/root` | `admin` | set | host BMC site-default |
| `machines/all_dpus/site_default/bmc-metadata-items/root` | `root` | set | DPU BMC site-default |
| `machines/all_dpus/site_default/uefi-metadata-items/auth` | "" | set | DPU UEFI |
| `machines/all_hosts/site_default/uefi-metadata-items/auth` | "" | set | host UEFI |

## Seed (preferred — via admin-cli, writes the correct format)
```bash
AC="kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli"
$AC credential add-bmc  --kind=site-wide-root --username admin --password '${BMC_PASSWORD}'
$AC credential add-uefi --kind=dpu  --password='${BMC_PASSWORD}'   # set-once
$AC credential add-uefi --kind=host --password='${BMC_PASSWORD}'   # set-once
# (the all_hosts/all_dpus bmc-metadata-items/root are seeded directly in Vault — see below)
```

## Verify the values are NON-EMPTY (do not skip)
```bash
RT=$(kubectl -n vault get secret vaultroottoken -o jsonpath='{.data.token}' | base64 -d)
VG(){ kubectl -n vault exec vault-0 -c vault -- sh -c "VAULT_SKIP_VERIFY=true VAULT_TOKEN=$RT VAULT_ADDR=https://127.0.0.1:8200 vault kv get -format=json secrets/$1" | jq -r '.data.data.UsernamePassword|"user=\(.username) pass=\(if (.password|length)>0 then "SET" else "EMPTY" end)"'; }
for p in machines/bmc/site/root \
         machines/all_hosts/site_default/bmc-metadata-items/root \
         machines/all_dpus/site_default/bmc-metadata-items/root \
         machines/all_dpus/site_default/uefi-metadata-items/auth \
         machines/all_hosts/site_default/uefi-metadata-items/auth; do echo "$p -> $(VG "$p")"; done
```

## Fix an EMPTY/wrong value (CLI is set-once for UEFI → write Vault directly)
```bash
RT=$(kubectl -n vault get secret vaultroottoken -o jsonpath='{.data.token}' | base64 -d)
VPUT(){ kubectl -n vault exec vault-0 -c vault -- sh -c "VAULT_SKIP_VERIFY=true VAULT_TOKEN=$RT VAULT_ADDR=https://127.0.0.1:8200 vault kv put secrets/$1 - <<EOF
{\"UsernamePassword\":{\"username\":\"$2\",\"password\":\"$3\"}}
EOF"; }
VPUT machines/bmc/site/root                                   admin '${BMC_PASSWORD}'
VPUT machines/all_hosts/site_default/bmc-metadata-items/root  admin '${BMC_PASSWORD}'
VPUT machines/all_dpus/site_default/bmc-metadata-items/root   root  '${BMC_PASSWORD}'
VPUT machines/all_dpus/site_default/uefi-metadata-items/auth  ""    '${BMC_PASSWORD}'
VPUT machines/all_hosts/site_default/uefi-metadata-items/auth ""    '${BMC_PASSWORD}'
```
After fixing, the next site-explorer cycle (~30s) stops logging `Missing credential` and endpoints/managed
hosts start appearing.
