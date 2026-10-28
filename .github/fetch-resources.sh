#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Refreshes root/etc/homeproxy/resources of the checkout at $1 (default /src)
# with the latest resource lists, so a package ships them current. Run inside
# an ImmortalWrt rootfs container (see .github/workflows/build.yml): it uses
# the router's own update_resources.sh, which needs busybox sh, uclient-fetch,
# jsonfilter and uci, and so writes the .ver files the router expects.
# $GITHUB_TOKEN, if set, authenticates the GitHub API calls.

ROOT="${1:-/src}"
WORK="/tmp/hp-fetch-resources"

rm -rf "$WORK"
mkdir -p "$WORK/run" "/etc/config"

# update_resources.sh reads the token from the HomeProxy config
printf "config homeproxy 'config'\n\toption github_token '%s'\n" "$GITHUB_TOKEN" > "/etc/config/homeproxy"

sed -e "s#^RESOURCES_DIR=.*#RESOURCES_DIR=\"$ROOT/root/etc/homeproxy/resources\"#" \
    -e "s#^RUN_DIR=.*#RUN_DIR=\"$WORK/run\"#" \
    "$ROOT/root/etc/homeproxy/scripts/update_resources.sh" > "$WORK/update_resources.sh"

FAILED=0
for type in china_ip4 china_ip6 geoip_cn geosite_cn; do
	sh "$WORK/update_resources.sh" "$type"
	# 3: already at the latest version
	case "$?" in
	0|3) ;;
	*) FAILED=1 ;;
	esac
done

cat "$WORK/run/homeproxy.log"
exit $FAILED
