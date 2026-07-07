# admin-cli quick reference (launchpad)

How to drive the NICo operator CLI on this site. The CLI lives **inside the `admincli` pod** in
namespace `nico-system`.

```bash
export KUBECONFIG=/Users/mnoori/go/src/stardrive/sites/launchpad/kubeconfig
AC="kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli"

$AC machine show              # managed hosts + states
$AC expected-machine show     # expected machines (serial / BMC MAC / IP / dpu mode)
$AC --help                    # all command groups;  add --help to any subcommand for flags
```
Interactive: `kubectl -n nico-system exec -it deploy/admincli -- bash` then `carbide-admin-cli ...`.

Most-used:
- `machine show [--extended]` — managed hosts + states
- `expected-machine show | add | patch --bmc-mac-address <MAC> [--chassis-serial-number S] | update | replace-all | delete | erase`
- `site-explorer get-report all` (discovery report JSON) · `site-explorer clear-error <IP>` (clear stuck error)
- `power-shelf show` · `expected-power-shelf show`
- `component-manager component-power-control {compute-tray|switch|power-shelf} --action {on|force-off|force-restart|ac-powercycle} [--bypass-state-controller]`

Notes:
- Discovery is **expected-machine-gated** (only listed BMC MACs get ingested).
- `patch` is partial + **live** — e.g. fixing `--chassis-serial-number` clears the
  `SerialNumberMismatch` health alert on the next ~30s explore cycle, no re-ingestion.
- Read commands are safe; `patch/update/replace-all/erase/component-power-control` mutate shared state.

Fuller cheat sheet: `~/Desktop/AgeSS/dsx-mcps/docs/nico-admin-cli-commands.md`.
