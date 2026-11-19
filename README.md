# SASE Control for macOS

[繁體中文](README.zh-TW.md)

A Bash script to stop and restore NETGEAR SASE and its associated background services on macOS, including Velociraptor and Wazuh.

`down` disables the services across reboots. `up` enables and starts them again. The script does not uninstall the software or change executable permissions.

**Stopping these services also stops endpoint monitoring and can interrupt access to private network resources.** Restoring them enables those capabilities again.

## Supported installation

Built for an installation with:

- NETGEAR SASE 4.9.7 on Apple Silicon macOS.
- Homebrew under `/opt/homebrew`.
- SASE at `/Applications/SASE.app`.
- The six launchd services listed below.
- macOS `/bin/bash` 3.2 or later.

Check the paths and service labels before use. This is not a universal controller for every NETGEAR SASE release or deployment.

## Usage

```bash
git clone https://github.com/ch010060/sase-control.git
cd sase-control
```

Check the current services and processes without changing anything:

```bash
bash ./sase-please.sh status
```

Preview an operation without running privileged commands:

```bash
bash ./sase-please.sh --dry-run down
bash ./sase-please.sh --dry-run up
```

Stop SASE and the associated services:

```bash
bash ./sase-please.sh down
```

Restore the services:

```bash
bash ./sase-please.sh up
```

Actual `up` and `down` operations request administrator privileges through `sudo`. No installation step or `chmod` is required when using `bash`.

`up` restores the services without overriding the application's existing manual-disconnect or authentication settings. Use the SASE menu to connect or sign in if needed. Allow time for services to start; a loaded service does not guarantee VPN connectivity.

## Managed services

| launchd label | Component |
|---|---|
| `net.speerity.monagent` | Scheduled network monitoring and agent repair |
| `net.speerity.saseapp` | SASE.app background launcher |
| `net.speerity.comagent` | Local command service |
| `net.speerity.agent` | VPN service |
| `com.velocidex.velociraptor` | Velociraptor agent |
| `com.wazuh.agent` | Wazuh launcher and agent processes |

`down` first disables all six launchd labels, then unloads them, starting with the scheduled repair monitor. It uses `wazuh-control stop` when applicable and terminates remaining matching processes. Processes receive TERM first, followed by KILL if they remain after five seconds.

If `/var/run/wireguard/speerity.name` exists, it runs the installed `wg-quick down /opt/homebrew/etc/wireguard/speerity.conf`. WireGuard handles the tunnel's route and DNS cleanup. The script does not stop all `wireguard-go` processes or operate on other WireGuard VPN profiles.

`up` enables and loads the six services, starts the non-scheduled services, and restores the repair monitor's existing schedule last.

## Limitations and recovery

- Disabled launchd labels remain disabled across reboots until enabled again. `up` enables all six labels; it does not restore a saved snapshot of their previous individual states.
- A missing or unreadable `speerity.name` mapping does not prove that every VPN is disconnected. `status` reports service and process state, not end-to-end connectivity.
- A failed operation or failed shutdown verification returns a nonzero exit status. Check the errors before treating shutdown as complete. If disabling a label fails, unloading does not proceed; use `up` to re-enable labels already disabled.
- Run `up` to restore the managed services after a partial stop. Missing service plists are reported rather than downloaded or reinstalled.
- VPN routes and DNS may change during normal service operations. Active-tunnel teardown, DNS restoration, persistence after reboot, and long-running behavior have not been fully verified.
- MDM, administrative tools, updates, or manually reopening the app can re-enable services or change the installation. Newly added services are outside this script's fixed scope.
- The script does not modify application binaries, service plists, VPN configuration files, sudoers, or macOS privacy permissions. The managed software may update its own state and logs during normal operation.

## Acknowledgment

Inspired by the reversible stop/start interface of [Zscaler please](https://gist.github.com/christopher-hopper/c8033839ef927a201feb8a8e8d256ed7). This implementation uses the service labels and paths of the supported SASE installation.

## License

[MIT](LICENSE).
