#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: glifocat
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nanocoai/nanoclaw

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  python3 \
  git \
  dbus-user-session \
  libpam-systemd \
  systemd-container
msg_ok "Installed Dependencies"

NODE_VERSION="22" NODE_MODULE="corepack" setup_nodejs

# NanoClaw itself runs natively. Docker is the sandbox its agents and the
# OneCLI credential gateway run in; NanoClaw has no Docker-free mode.
setup_docker

# NanoClaw's wizard installs a systemd user service and warns against running
# as root, so it gets its own account. Docker group membership is
# root-equivalent inside the LXC.
msg_info "Creating NanoClaw Account"
$STD useradd --create-home --shell /bin/bash nanoclaw
$STD usermod -aG docker nanoclaw
$STD loginctl enable-linger nanoclaw
msg_ok "Created NanoClaw Account"

if [[ "${var_nanoclaw_ref:-}" == "main" ]]; then
  # Opt-in: track upstream main instead of a release. Same layout as a release
  # install (full history, upstream remote, local main branch), so `update`
  # and /update-nanoclaw can move it forward from upstream/main.
  msg_info "Fetching NanoClaw main"
  mkdir -p /home/nanoclaw/nanoclaw
  cd /home/nanoclaw/nanoclaw || exit
  $STD git init -q -b main
  $STD git remote add upstream https://github.com/nanocoai/nanoclaw.git
  $STD git fetch -q upstream "+refs/heads/main:refs/remotes/upstream/main"
  $STD git reset -q --hard upstream/main
  echo "main" >~/.nanoclaw-ref
  msg_ok "Fetched NanoClaw main ($(git rev-parse --short=8 HEAD))"
  msg_info "Preparing NanoClaw Checkout"
else
  fetch_and_deploy_gh_release "nanoclaw" "nanocoai/nanoclaw" "tarball" "latest" "/home/nanoclaw/nanoclaw"

  # NanoClaw identifies its code, refreshes installed channel, provider and
  # gateway payloads and runs its transactional updater through Git, so the
  # release tarball is paired with the matching tag history. `git reset` points
  # the index at the tag without touching the extracted files and
  # `git checkout -- .` restores anything the archive left out. The updater
  # commits refreshed payloads and stages new releases in
  # /home/nanoclaw/.nanoclaw-updates, next to the checkout.
  msg_info "Preparing NanoClaw Checkout"
  NANOCLAW_TAG="v$(cat ~/.nanoclaw)"
  cd /home/nanoclaw/nanoclaw || exit
  $STD git init -q -b main
  $STD git remote add upstream https://github.com/nanocoai/nanoclaw.git
  $STD git fetch -q upstream "refs/tags/${NANOCLAW_TAG}:refs/tags/${NANOCLAW_TAG}"
  $STD git reset -q "$NANOCLAW_TAG"
  $STD git checkout -q -- .
fi
$STD git config user.name "NanoClaw"
$STD git config user.email "nanoclaw@localhost"
chown -R nanoclaw:nanoclaw /home/nanoclaw/nanoclaw
msg_ok "Prepared NanoClaw Checkout"

msg_info "Installing Node Dependencies"
$STD runuser -u nanoclaw -- pnpm install --frozen-lockfile
msg_ok "Installed Node Dependencies"

msg_info "Building NanoClaw"
$STD runuser -u nanoclaw -- pnpm run build
msg_ok "Built NanoClaw"

motd_ssh
customize
cleanup_lxc
