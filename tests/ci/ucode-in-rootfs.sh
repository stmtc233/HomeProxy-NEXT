#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Runs tests/ucode/run.sh inside an ImmortalWrt rootfs container (see
# .github/workflows/test.yml). The caller bind-mounts the checkout to $1 and a
# sing-box >= 1.14 binary to /usr/bin/sing-box.

ROOT="${1:-/src}"

apk update > "/dev/null" || exit 1
apk add ucode-mod-digest unshare diffutils || exit 1

# rpcd and firewall_post.ut import homeproxy.uc by its installed path, and the
# firewall template reads the config and resource lists from their installed
# locations: lay those out the way the package installs them
mkdir -p "/etc/homeproxy"
ln -sfn "$ROOT/root/etc/homeproxy/scripts" "/etc/homeproxy/scripts"
ln -sfn "$ROOT/root/etc/homeproxy/resources" "/etc/homeproxy/resources"
cp "$ROOT/root/etc/config/homeproxy" "/etc/config/homeproxy"

sing-box version | head -1
exec sh "$ROOT/tests/ucode/run.sh" "$ROOT" "/tmp/hp-ucode-tests"
