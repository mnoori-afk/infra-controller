# ssh-console-rs — cert-based SSH serial console (launchpad)

`nico-ssh-console-rs` gives operators a **cert-authenticated SSH serial console (SOL)** to the machines
NICo manages (GB300 host consoles + BMCs / power-shelves / switches). It runs in `nico-system`, fronted by
the MetalLB VIP **`172.16.2.49`** (port 22).

This doc is the full playbook: how it's configured here, the one gotcha that will waste your afternoon, how
to reach it, and how to use it. **For a new site: the two auth values below are fleet-wide — reuse them
verbatim; only the VIP is site-specific.**

---

## 1. What it is / how auth works

An incoming SSH connection is admitted only if it presents an **OpenSSH user certificate** that is
(a) signed by a trusted CA, and (b) carries an admin role in its Key ID. This is the same cert your
`nvcert`/`nvinit` login uses to get into scout and the DPU-OS. Two config keys drive it:

| Key | Meaning |
|---|---|
| `openssh_certificate_ca_fingerprints` | **Trust anchor** — SHA256 fingerprint(s) of the CA(s) allowed to sign user certs. On connect, ssh-console computes the fingerprint of the CA that signed your cert and requires it to be in this list. Empty list ⇒ every cert rejected. |
| `admin_certificate_role` | **Authorization** — after the signature is trusted, ssh-console parses the cert's Key ID `roles=` list and requires this exact role string. This role grants direct-console (admin) access. |

So: fingerprint = *whose signature I trust*; role = *what the cert must carry*.

**The values used here (fleet-wide NVIDIA Forge, not per-site):**
```toml
openssh_certificate_ca_fingerprints = ["SHA256:sPKzOUJwvkR3aCFf2oCyHnc+JoMtFcow2UxcEz+cXo4"]
admin_certificate_role = "swngc-forge-admins"
```
- The fingerprint is the **NVIDIA Forge nvcert/nvinit SSH *user* CA** — issued centrally from
  `prod.vault.nvidia.com` (mount `sshca-usercert/issue/ngc`) by the `nvinit` tool. It is the **same CA that
  scout and the DPU-OS already trust**, and it is identical across forge sites (ytl, demo1, launchpad).
- `swngc-forge-admins` is the role stamped into forge admins' cert Key IDs.

Verify your own cert's CA + roles any time:
```bash
ssh-add -L | grep -- '-cert-v01@openssh.com' > /tmp/agent-certs.pub
ssh-keygen -L -f /tmp/agent-certs.pub | grep -E 'Signing CA|Key ID'
# "Signing CA: RSA SHA256:sPKz…"  and  "roles=…,swngc-forge-admins,…"
```

---

## 2. Where the config lives (and why it's a full TOML override)

The `nico-ssh-console-rs` chart exposes **no per-key value** — the only override path is a whole
`config.toml` string via `configFiles.config` (see `helm/charts/nico-ssh-console-rs/templates/configmap.yaml`;
the chart default ships both cert keys **empty**). So the config is a full config.toml embedded in
`launchpad-deploy/nico/nico-core.launchpad.yaml` under:

```yaml
nico-ssh-console-rs:
  imagePullSecrets:
    - name: imagepullsecret
  externalService:
    enabled: true
    annotations:
      metallb.universe.tf/loadBalancerIPs: "172.16.2.49"
  configFiles:
    config: |
      listen_address = "[::]:22"
      metrics_address = "[::]:9009"
      nico_url = "https://nico-api.nico-system.svc.cluster.local:1079"
      carbide_url = "https://nico-api.nico-system.svc.cluster.local:1079"
      nico_root_ca_path = "/var/run/secrets/spiffe.io/ca.crt"
      forge_root_ca_path = "/var/run/secrets/spiffe.io/ca.crt"
      client_cert_path = "/var/run/secrets/spiffe.io/tls.crt"
      client_key_path = "/var/run/secrets/spiffe.io/tls.key"
      host_key = "/etc/ssh/ssh_host_ed25519_key"
      dpus = true
      insecure = false
      openssh_certificate_ca_fingerprints = ["SHA256:sPKzOUJwvkR3aCFf2oCyHnc+JoMtFcow2UxcEz+cXo4"]
      admin_certificate_role = "swngc-forge-admins"
      insecure_ipmi_ciphers = false
      force_deactivate_conflicting_ipmi_sol_sessions = false
      api_poll_interval = "180s"
      console_logging_enabled = true
      console_logs_path = "/var/log/consoles"
```
(`nico_*` and `carbide_*` are both set so the config works whether the image ships the `nico` or the
`carbide` binary — the deployment `exec`s whichever exists.)

---

## 3. ⚠️ THE GOTCHA — you must restart the pod after a config change

**The chart has no `checksum/config` (or reloader) annotation, and the binary reads `config.toml` once at
startup.** So changing the ConfigMap — whether by `helm upgrade` or by editing the CM — does **not** restart
the pod. It keeps running the config it booted with.

Symptom of a stale pod: auth fails with
```
WARN ssh_console::frontend: openssh certificate CA certificate not trusted, rejecting authentication
```
even though the CM already has the correct fingerprint (the *process* still holds the old empty list).

**Always finish a config change with:**
```bash
CTX=nv-stg-dgxc.teleport.sh-rg-forge-launchpad
kubectl --context "$CTX" -n nico-system rollout restart deploy/nico-ssh-console-rs
kubectl --context "$CTX" -n nico-system rollout status  deploy/nico-ssh-console-rs --timeout=120s
```

> Optional durable fix (chart improvement, benefits every site): add a config checksum to the pod template
> in `helm/charts/nico-ssh-console-rs/templates/deployment.yaml`:
> ```yaml
> annotations:
>   checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
> ```
> Then any `configFiles.config` change auto-rolls the pod.

---

## 4. Deploy / apply

The config is part of the Core siteConfig, so it lands with any Core `helm upgrade`. Two ways:

**A. Full Core upgrade** (also heals a stuck release — see README §12):
```bash
helm --kube-context "$CTX" upgrade nico ./helm -n nico-system \
  -f launchpad-deploy/nico/nico-core.launchpad.yaml \
  --set global.image.repository=nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide \
  --set global.image.tag=v2.0.0-pr-503-g49a48a69d \
  --force-conflicts --timeout 10m
kubectl --context "$CTX" -n nico-system rollout restart deploy/nico-ssh-console-rs   # <-- required (§3)
```

**B. Surgical (just this CM), if you don't want to touch the whole umbrella:**
```bash
helm template nico ./helm -n nico-system \
  -f launchpad-deploy/nico/nico-core.launchpad.yaml \
  --set global.image.repository=nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide \
  --set global.image.tag=v2.0.0-pr-503-g49a48a69d \
  --show-only charts/nico-ssh-console-rs/templates/configmap.yaml \
  | kubectl --context "$CTX" -n nico-system apply --server-side --force-conflicts -f -
kubectl --context "$CTX" -n nico-system rollout restart deploy/nico-ssh-console-rs
```

Verify the live CM + service:
```bash
kubectl --context "$CTX" -n nico-system get cm nico-ssh-console-rs-config-files \
  -o jsonpath='{.data.config\.toml}' | grep -E 'openssh_certificate_ca_fingerprints|admin_certificate_role'
kubectl --context "$CTX" -n nico-system get svc nico-ssh-console-rs-external      # EXTERNAL-IP 172.16.2.49
```

---

## 5. Reaching it (VIP is internal — tunnel in)

`172.16.2.49` lives on the internal management net `172.16.2.0/24`; it is **not routable from your laptop**
(a direct `ssh` just hangs — no route). Reach it via a tunnel:

```bash
# A) tsh local-forward through a control-plane node to the VIP (exercises the real MetalLB path):
tsh ssh -L 2249:172.16.2.49:22 launchpad-control-plane-1
#    then, in another terminal (nvcert cert loaded in your ssh-agent):
ssh -p 2249 <machine_id>@localhost

# B) kubectl port-forward straight to the service (simplest; bypasses the VIP):
kubectl --context "$CTX" -n nico-system port-forward svc/nico-ssh-console-rs-external 2249:22
ssh -p 2249 <machine_id>@localhost
```
(User certs aren't bound to hostname, so connecting via `localhost` still presents/validates your cert fine.)

---

## 6. Using it — username = the target machine, not you

**The SSH username is the machine_id (or instance ID) you want a console on** — your identity/authorization
comes entirely from the cert. So `ssh mnoori@…` fails with
`Could not get BMC connection for mnoori: mnoori is not a valid machine_id or instance ID`.

Use a real machine_id:
```bash
ssh -p 2249 fm100htio3rbu8uv5ntieetc1giua6ilqdkgvoe4ackngm05psnaf7skhk0@localhost
```
On success ssh-console logs `certificate auth succeeded … in role swngc-forge-admins` and attaches you to
that machine's serial console. Escape sequences (shown in the banner): `~.` terminate, `~?` help.

List valid machine_ids:
```bash
kubectl --context "$CTX" -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli machine show
# or harvest what ssh-console already polls:
kubectl --context "$CTX" -n nico-system logs deploy/nico-ssh-console-rs \
  | grep -oE 'machine_id=fm100[a-z0-9]+' | sort -u
```
> Note: a `fm100…` id may be a host, a BMC, a switch, or a power-shelf (e.g. a LiteOn power shelf shows the
> `>> SMASHLITE Scorpio Console <<` prompt). Pick a GB300 host id for the Grace boot console.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ssh` hangs, no prompt | VIP `.49` not routable from your machine | Tunnel in (§5) |
| `openssh certificate CA certificate not trusted` | **Stale pod** (config changed, pod not restarted) — most common | `rollout restart deploy/nico-ssh-console-rs` (§3) |
| `openssh certificate CA certificate not trusted` (after restart) | Wrong fingerprint for your cert's CA | `ssh-keygen -L` your cert → put its `Signing CA` SHA256 in `openssh_certificate_ca_fingerprints` (array — can list several) |
| `skipping ssh certificate auth, no admin role is configured` (debug) | `admin_certificate_role` empty | set it to `swngc-forge-admins` + restart |
| `certificate auth failed … not in role X` | Your cert's Key ID doesn't carry that role | pick a role your cert has (`ssh-keygen -L` → `roles=`), or get the role granted |
| `… is not a valid machine_id or instance ID` | You used your name as the username | `ssh <machine_id>@…` (§6) |
| Only `peer_addr=172.16.2.1x` in logs, no auth attempts | That's the node's TCP readiness probe, not you | your connection isn't arriving — check the tunnel |

**Debug note (so nobody re-chases this):** the crate stack in pr-503 (`ssh-key 0.7.0-rc.10`) **does**
validate RSA-CA-signed nvcert certs correctly — proven with a standalone reproducer against the real cert
(`verify_signature()=Ok`, `validate()=Ok`). Every "CA not trusted" we hit was the **stale pod**, not a
library/cert problem. No code change is needed.

---

## 8. New-site checklist
1. Keep both cert values verbatim (`SHA256:sPKz…` + `swngc-forge-admins`) — they're fleet-wide.
2. Set the site's own VIP in `externalService.annotations` (a free IP from that site's MetalLB pool).
3. Land the config (Core `helm upgrade`), then **`rollout restart deploy/nico-ssh-console-rs`** (§3).
4. Tunnel in and test with a real `machine_id` (§5–6); confirm the `certificate auth succeeded … in role
   swngc-forge-admins` log line.
