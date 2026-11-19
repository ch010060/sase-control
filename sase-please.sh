#!/bin/bash
# Local SASE 4.9.7 installation inspected on 2026-11-19. Requires macOS Bash 3.2+.
set -u
set -o pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin

SERVICES=(
  net.speerity.monagent
  net.speerity.saseapp
  net.speerity.comagent
  net.speerity.agent
  com.velocidex.velociraptor
  com.wazuh.agent
)
DRY_RUN=0
ERRORS=0
TUNNEL_NAME_FILE=/var/run/wireguard/speerity.name
TUNNEL_CONFIG=/opt/homebrew/etc/wireguard/speerity.conf

usage() {
  echo "Usage: $0 [--dry-run] {down|up|status}"
  echo 'down: disable six launchd services, stop their processes and the SASE tunnel.'
  echo 'up: enable/reload the same services; VPN authentication remains in SASE.'
  echo 'status: read-only service/process/tunnel check; no sudo required.'
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if (( DRY_RUN )); then return 0; fi
  if "$@"; then return 0; fi
  echo "ERROR: command failed; the operation may be incomplete." >&2
  ERRORS=$((ERRORS + 1))
  return 1
}

loaded() {
  /bin/launchctl print "system/$1" >/dev/null 2>&1
}

target_pids() {
  # Anchored paths avoid matching unrelated VPNs or this control script.
  {
    /usr/bin/pgrep -x SaseClient || :
    /usr/bin/pgrep -f '^(/usr/local/sbin/velociraptor|/Library/Ossec/bin/wazuh-[^ /]+|(/bin/(ba)?sh )?(/Library/StartupItems/WAZUH/Wazuh-launcher|(/opt/homebrew/bin|/usr/local/bin)/speerity-[^ /]+[.]sh))([[:space:]]|$)' || :
  } | /usr/bin/sort -nu
}

status() {
  local label detail pids
  echo '--- launchd services (loaded does not necessarily mean running)'
  for label in "${SERVICES[@]}"; do
    if detail=$(/bin/launchctl print "system/$label" 2>/dev/null); then
      printf '%s: loaded\n' "$label"
      printf '%s\n' "$detail" | /usr/bin/awk '/^\t(state|pid) =/ {print}'
    else
      printf '%s: not loaded or not readable\n' "$label"
    fi
  done
  echo '--- persistent disabled overrides (missing entry uses the plist default)'
  /bin/launchctl print-disabled system | /usr/bin/awk '/"(net\.speerity\.(monagent|saseapp|comagent|agent)|com\.velocidex\.velociraptor|com\.wazuh\.agent)" =>/'
  echo '--- related processes'
  pids=$(target_pids)
  if [[ -n "$pids" ]]; then
    /bin/ps -p "$(printf '%s\n' "$pids" | /usr/bin/paste -sd, -)" -o pid=,user=,comm=
  else
    echo 'No matching processes.'
  fi
  echo '--- SASE tunnel name mapping'
  if [[ -r "$TUNNEL_NAME_FILE" ]]; then
    /bin/cat "$TUNNEL_NAME_FILE"
  else
    echo 'No readable speerity.name mapping; this alone does not prove all VPNs are off.'
  fi
}

stop_processes() {
  local pids pid attempt
  pids=$(target_pids)
  for pid in $pids; do
    # A process can exit between the query and signal; final verification catches survivors.
    if (( DRY_RUN )); then run /bin/kill -TERM "$pid"; else /bin/kill -TERM "$pid" 2>/dev/null || :; fi
  done
  if (( DRY_RUN )); then return; fi
  for attempt in 1 2 3 4 5; do
    [[ -n "$(target_pids)" ]] || return 0
    /bin/sleep 1
  done
  for pid in $(target_pids); do /bin/kill -KILL "$pid" 2>/dev/null || :; done
  /bin/sleep 1
}

down() {
  local label pids
  # Disable every repair/restart path before unloading any service.
  for label in "${SERVICES[@]}"; do run /bin/launchctl disable "system/$label" || :; done
  if (( ERRORS )); then
    echo 'Disable failed. Nothing was unloaded; use up to re-enable services already disabled.' >&2
    return 1
  fi
  for label in "${SERVICES[@]}"; do
    if (( DRY_RUN )) || loaded "$label"; then run /bin/launchctl bootout "system/$label" || :; fi
  done
  # Wazuh forks separate daemons; unloading its launcher alone is insufficient.
  if (( DRY_RUN )) || { [[ -x /Library/Ossec/bin/wazuh-control ]] && /usr/bin/pgrep -f '^/Library/Ossec/bin/wazuh-' >/dev/null; }; then
    run /Library/Ossec/bin/wazuh-control stop || :
  fi
  stop_processes
  # wg-quick owns this mapping and performs its route/DNS cleanup; never kill all wireguard-go.
  if (( DRY_RUN )); then
    echo '# Only if speerity.name exists on execution:'
    run /opt/homebrew/bin/wg-quick down "$TUNNEL_CONFIG"
  elif [[ -e "$TUNNEL_NAME_FILE" ]]; then
    run /opt/homebrew/bin/wg-quick down "$TUNNEL_CONFIG" || :
    /bin/sleep 2
    if [[ -e "$TUNNEL_NAME_FILE" ]]; then
      echo 'ERROR: SASE tunnel mapping remains; tunnel shutdown is not confirmed.' >&2
      ERRORS=$((ERRORS + 1))
    fi
  fi
  if (( DRY_RUN )); then return 0; fi
  for label in "${SERVICES[@]}"; do
    if loaded "$label"; then
      echo "ERROR: service still loaded: $label" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done
  pids=$(target_pids)
  if [[ -n "$pids" ]]; then
    printf 'ERROR: related processes remain: %s\n' "$pids" >&2
    ERRORS=$((ERRORS + 1))
  fi
  if (( ERRORS )); then return 1; fi
  echo 'DOWN: six services unloaded and disabled; no matching processes remain.'
}

up() {
  local label plist
  # Restore the scheduled repair monitor last, after the managed services.
  for label in net.speerity.comagent net.speerity.agent com.velocidex.velociraptor com.wazuh.agent net.speerity.saseapp net.speerity.monagent; do
    plist="/Library/LaunchDaemons/$label.plist"
    if [[ ! -f "$plist" ]]; then
      echo "ERROR: missing installed service: $plist" >&2
      ERRORS=$((ERRORS + 1))
      continue
    fi
    run /bin/launchctl enable "system/$label" || continue
    if (( DRY_RUN )) || ! loaded "$label"; then run /bin/launchctl bootstrap system "$plist" || continue; fi
    if [[ "$label" != net.speerity.monagent ]]; then run /bin/launchctl kickstart "system/$label" || :; fi
    if (( ! DRY_RUN )) && ! loaded "$label"; then
      echo "ERROR: service did not load: $label" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done
  if (( ERRORS )); then return 1; fi
  if (( DRY_RUN )); then echo 'DRY RUN complete; no services changed.'; return 0; fi
  echo 'UP requested: services enabled/loaded; allow startup time and check status.'
  echo 'Use the SASE menu to authenticate/connect if needed. VPN connectivity is not verified.'
}

main() {
  if [[ "${1:-}" == --dry-run ]]; then DRY_RUN=1; shift; fi
  if [[ $# != 1 ]]; then usage >&2; return 2; fi
  case "$1" in
    help|-h|--help) usage; return 0 ;;
    status) status; return $? ;;
    up|down) ;;
    *) usage >&2; return 2 ;;
  esac
  if [[ $(/usr/bin/uname -s) != Darwin ]]; then echo 'macOS only.' >&2; return 1; fi
  if (( ! DRY_RUN && EUID != 0 )); then
    exec /usr/bin/sudo /bin/bash "${BASH_SOURCE[0]}" "$1"
  fi
  "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
