#!/usr/bin/env bash
# Published from the glifocat/nanoclaw-proxmox fork, not community-scripts.
# Both roots are pinned so the script, its install step, the engine and the
# container's later `update` all run the tested revision.
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/glifocat/nanoclaw-proxmox/nanoclaw-helper-v2}"
COMMUNITY_SCRIPTS_CORE_URL="${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/6f9088594d1541019858da37b864e610c568daf2}"
export COMMUNITY_SCRIPTS_URL COMMUNITY_SCRIPTS_CORE_URL
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: glifocat
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nanocoai/nanoclaw

APP="NanoClaw"
var_tags="${var_tags:-ai;agent;bots}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-40}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

header_info "$APP"
variables
color
catch_errors

# var_nanoclaw_ref=main installs upstream main instead of the latest release.
case "${var_nanoclaw_ref:-}" in
"" | release) ;;
main)
  if [[ -n "${var_appversion:-}" ]]; then
    msg_error "var_nanoclaw_ref=main and var_appversion cannot be combined."
    exit 1
  fi
  export var_nanoclaw_ref
  ;;
*)
  msg_error "var_nanoclaw_ref must be 'main', or unset for the latest release."
  exit 1
  ;;
esac

# Setup copies payloads into the tree without committing them, and the
# transaction refuses to start from a dirty checkout.
function nanoclaw_record_payloads() {
  if [[ -n "$("${NANOCLAW_USER[@]}" git status --porcelain)" ]]; then
    # The startup gate pins the upgrade marker to HEAD, so a marker that was
    # current must follow this commit; otherwise a deferred or failed update
    # would leave a service that refuses to restart.
    NANOCLAW_MARKER=$("${NANOCLAW_USER[@]}" pnpm exec tsx scripts/upgrade-state.ts get 2>/dev/null | jq -r '.commit // empty' 2>/dev/null)
    NANOCLAW_HEAD=$("${NANOCLAW_USER[@]}" git rev-parse HEAD)
    $STD "${NANOCLAW_USER[@]}" git add --all
    $STD "${NANOCLAW_USER[@]}" git commit -q -m "chore: record installed NanoClaw payloads"
    if [[ -n "$NANOCLAW_MARKER" && "$NANOCLAW_MARKER" == "$NANOCLAW_HEAD" ]]; then
      $STD "${NANOCLAW_USER[@]}" pnpm exec tsx scripts/upgrade-state.ts set "" proxmox-helper
    fi
  fi
}

# $1 = git ref to merge, $2 = its name in messages.
function nanoclaw_apply_update() {
  local ref="$1" label="$2"

  msg_info "Staging NanoClaw ${label}"
  NANOCLAW_UPDATE=$("${NANOCLAW_USER[@]}" pnpm exec tsx scripts/update-nanoclaw.ts prepare --upstream-ref "$ref" --strategy merge 2>/dev/null) || {
    msg_error "NanoClaw could not stage ${label}; the running install is unchanged. Run /update-nanoclaw as the nanoclaw user in /opt/nanoclaw for details."
    exit
  }
  NANOCLAW_UPDATE_ID=$(jq -r '.id' <<<"$NANOCLAW_UPDATE")
  msg_ok "Staged NanoClaw ${label}"

  if [[ "$(jq -r '.requirements | length' <<<"$NANOCLAW_UPDATE")" != "0" ]]; then
    $STD "${NANOCLAW_USER[@]}" pnpm exec tsx scripts/update-nanoclaw.ts abandon --id "$NANOCLAW_UPDATE_ID"
    msg_warn "NanoClaw ${label} has breaking changes that need manual steps; the running install is unchanged:"
    jq -r '.requirements[] | "  - \(.description | ltrimstr("- "))"' <<<"$NANOCLAW_UPDATE"
    msg_custom "ℹ️" "${YW}" "Finish this update with /update-nanoclaw from a coding agent, as the nanoclaw user in /opt/nanoclaw."
    exit
  fi

  msg_info "Validating NanoClaw ${label}"
  $STD "${NANOCLAW_USER[@]}" pnpm exec tsx scripts/update-nanoclaw.ts validate --id "$NANOCLAW_UPDATE_ID" || {
    $STD "${NANOCLAW_USER[@]}" pnpm exec tsx scripts/update-nanoclaw.ts abandon --id "$NANOCLAW_UPDATE_ID"
    msg_error "NanoClaw ${label} failed validation; the running install is unchanged."
    exit
  }
  msg_ok "Validated NanoClaw ${label}"

  msg_info "Updating NanoClaw"
  $STD "${NANOCLAW_USER[@]}" pnpm exec tsx scripts/update-nanoclaw.ts cutover --id "$NANOCLAW_UPDATE_ID"
  $STD "${NANOCLAW_USER[@]}" pnpm exec tsx scripts/update-nanoclaw.ts finish --id "$NANOCLAW_UPDATE_ID"
  $STD "${NANOCLAW_USER[@]}" pnpm exec tsx scripts/update-nanoclaw.ts cleanup --id "$NANOCLAW_UPDATE_ID"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/nanoclaw ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # NanoClaw keeps installed channel, provider and gateway payloads inside
  # its checkout and updates through its own transaction
  # (scripts/update-nanoclaw.ts): stage and validate the target, then stop
  # the service and agents, snapshot state, rebuild, stamp the upgrade
  # marker and restart. Replacing the tree from a tarball would drop those
  # payloads and trip NanoClaw's startup gate.
  NANOCLAW_USER=(runuser -u nanoclaw -- env "XDG_RUNTIME_DIR=/run/user/$(id -u nanoclaw)")

  if [[ "$(cat ~/.nanoclaw-ref 2>/dev/null)" == "main" ]]; then
    # Main installs follow upstream main through the same transaction; a
    # [BREAKING] entry still stops the update for /update-nanoclaw.
    cd /opt/nanoclaw || exit
    ensure_dependencies jq
    # Cutover moves HEAD before it records its phase, so an interrupted update
    # can look current to the ancestry check below. Any unfinished transaction
    # for this checkout stops here; files are read one by one so a bad one
    # cannot hide the rest.
    NANOCLAW_PENDING=""
    for NANOCLAW_STATE in /opt/.nanoclaw-updates/*/*/state.json; do
      [[ -f "$NANOCLAW_STATE" ]] || continue
      NANOCLAW_PENDING=$(jq -r 'select(.projectRoot == "/opt/nanoclaw" and (.phase | IN("complete", "rolled-back", "abandoned") | not)) | "\(.id) (\(.phase))"' "$NANOCLAW_STATE" 2>/dev/null || true)
      if [[ -n "$NANOCLAW_PENDING" ]]; then
        break
      fi
    done
    if [[ -n "$NANOCLAW_PENDING" ]]; then
      msg_error "NanoClaw update ${NANOCLAW_PENDING} did not finish. Finish, roll back or abandon it with /update-nanoclaw as the nanoclaw user in /opt/nanoclaw, then run update again."
      exit
    fi
    msg_info "Fetching NanoClaw main"
    $STD "${NANOCLAW_USER[@]}" git fetch -q upstream "+refs/heads/main:refs/remotes/upstream/main"
    NANOCLAW_TARGET=$("${NANOCLAW_USER[@]}" git rev-parse upstream/main)
    if "${NANOCLAW_USER[@]}" git merge-base --is-ancestor "$NANOCLAW_TARGET" HEAD; then
      msg_ok "No update available: NanoClaw main (${NANOCLAW_TARGET:0:8})"
      exit
    fi
    nanoclaw_record_payloads
    msg_ok "Fetched NanoClaw main (${NANOCLAW_TARGET:0:8})"

    nanoclaw_apply_update "$NANOCLAW_TARGET" "main (${NANOCLAW_TARGET:0:8})"
    msg_ok "Updated NanoClaw to main (${NANOCLAW_TARGET:0:8})"
  elif check_for_gh_release "nanoclaw" "nanocoai/nanoclaw"; then
    cd /opt/nanoclaw || exit

    msg_info "Fetching NanoClaw ${CHECK_UPDATE_RELEASE}"
    $STD "${NANOCLAW_USER[@]}" git fetch -q upstream "refs/tags/${CHECK_UPDATE_RELEASE}:refs/tags/${CHECK_UPDATE_RELEASE}"
    nanoclaw_record_payloads
    msg_ok "Fetched NanoClaw ${CHECK_UPDATE_RELEASE}"

    nanoclaw_apply_update "$CHECK_UPDATE_RELEASE" "$CHECK_UPDATE_RELEASE"
    echo "${CHECK_UPDATE_RELEASE#v}" >~/.nanoclaw
    msg_ok "Updated NanoClaw to ${CHECK_UPDATE_RELEASE}"
  fi
  exit
}

# build_container exports MODE=default for the install phase, also after an
# interactive choice of default settings, so the caller's mode is read first.
nanoclaw_setup_interactive=false
if [[ -t 0 && -t 1 ]] && ! is_unattended; then
  nanoclaw_setup_interactive=true
fi

start
build_container
description

msg_ok "Completed Successfully!\n"
if [[ "${var_nanoclaw_ref:-}" == "main" ]]; then
  echo -e "${CREATING}${GN}${APP} main is installed at /opt/nanoclaw; \`update\` follows upstream main.${CL}"
else
  echo -e "${CREATING}${GN}${APP} is installed at /opt/nanoclaw.${CL}"
fi
echo -e "${INFO}${YW}NanoClaw's setup wizard completes authentication, agent setup and the service.${CL}"

if [[ "$nanoclaw_setup_interactive" == true ]] && MODE='' mode='' prompt_confirm "Start NanoClaw setup now?" "n"; then
  if ! pct exec "$CT_ID" --keep-env 0 -- machinectl shell nanoclaw@ /usr/bin/bash -lc 'cd /opt/nanoclaw && exec bash nanoclaw.sh'; then
    msg_warn "NanoClaw setup exited with an error. Resume it with the command below."
  fi
fi

echo -e "${INFO}${YW}To open NanoClaw setup from the Proxmox host:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct exec ${CT_ID} --keep-env 0 -- machinectl shell nanoclaw@ /usr/bin/bash -lc 'cd /opt/nanoclaw && exec bash nanoclaw.sh'${CL}"
