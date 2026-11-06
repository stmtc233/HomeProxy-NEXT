#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2025 ImmortalWrt.org

NAME="homeproxy"

SCRIPTS_DIR="/etc/$NAME/scripts"
. "$SCRIPTS_DIR/defaults.sh"

RESOURCES_DIR="/etc/$NAME/resources"
mkdir -p "$RESOURCES_DIR"

RUN_DIR="/var/run/$NAME"
LOG_PATH="$RUN_DIR/$NAME.log"
mkdir -p "$RUN_DIR"

log() {
	echo -e "$(date "+%Y-%m-%d %H:%M:%S") $*" >> "$LOG_PATH"
}

to_upper() {
	echo -e "$1" | tr "[a-z]" "[A-Z]"
}

WGET="wget --timeout=10 -q"

UPDATE_VIA_PROXY="$(uci -q get "$NAME.subscription.update_via_proxy" || echo "$HP_DEFAULT_UPDATE_VIA_PROXY")"
UPDATE_FALLBACK_DIRECT="$(uci -q get "$NAME.subscription.update_fallback_direct" || echo "$HP_DEFAULT_UPDATE_FALLBACK_DIRECT")"

# The client's direct-in as a proxy URL, empty when the client is not running
# with it: then nothing intercepts the downloads, they go direct anyway.
direct_proxy() {
	[ "$(ubus call service list '{"name":"homeproxy"}' 2>"/dev/null" | \
		jsonfilter -qe "@.homeproxy.instances['sing-box-c'].running")" = "true" ] || return 0
	grep -q '"direct-in"' "$RUN_DIR/sing-box-c.json" 2>"/dev/null" || return 0
	echo "http://127.0.0.1:$(uci -q get "$NAME.infra.direct_port" || echo "$HP_DEFAULT_DIRECT_PORT")"
}
DIRECT_PROXY="$(direct_proxy)"

# fetch <listtype> <url> <output> [wget options]: through the routing rules,
# then past them when that fails (update_via_proxy, update_fallback_direct).
fetch() {
	local listtype="$1" url="$2" output="$3"
	shift 3

	if [ "$UPDATE_VIA_PROXY" = "1" ]; then
		$WGET "$@" -O "$output" "$url" && return 0
		local wget_exit=$?
		rm -f "$output"
		[ "$UPDATE_FALLBACK_DIRECT" = "1" ] && [ -n "$DIRECT_PROXY" ] || return $wget_exit
		log "[$(to_upper "$listtype")] Failed to fetch ${url%%\?*} through the proxy (wget exit $wget_exit), retrying directly."
	fi

	if [ -n "$DIRECT_PROXY" ]; then
		http_proxy="$DIRECT_PROXY" https_proxy="$DIRECT_PROXY" $WGET "$@" -O "$output" "$url"
	else
		$WGET "$@" -O "$output" "$url"
	fi
}

# Tried in order; the URL pins the commit, so every mirror serves the same file.
MIRRORS="fastly.jsdelivr.net gcore.jsdelivr.net cdn.jsdelivr.net raw.githubusercontent.com"

# download_list <listtype> <repo> <sha> <file> <output>
download_list() {
	local listtype="$1" listrepo="$2" list_sha="$3" listname="$4" output="$5"
	local mirror url

	for mirror in $MIRRORS; do
		if [ "$mirror" = "raw.githubusercontent.com" ]; then
			url="https://$mirror/$listrepo/$list_sha/$listname"
		else
			url="https://$mirror/gh/$listrepo@$list_sha/$listname"
		fi

		if fetch "$listtype" "$url" "$output" && [ -s "$output" ]; then
			log "[$(to_upper "$listtype")] Downloaded from $mirror."
			return 0
		fi
		rm -f "$output"
		log "[$(to_upper "$listtype")] Download from $mirror failed."
	done

	return 1
}

check_list_update() {
	local listtype="$1"
	local listrepo="$2"
	local listref="$3"
	local listname="$4"
	local lock="$RUN_DIR/update_resources-$listtype.lock"
	local github_token="$(uci -q get homeproxy.config.github_token)"

	exec 200>"$lock"
	if ! flock -n 200 &> "/dev/null"; then
		log "[$(to_upper "$listtype")] A task is already running."
		return 2
	fi

	local api_url="https://api.github.com/repos/$listrepo/commits?sha=$listref&path=$listname&per_page=1"
	local info_file="$RUN_DIR/update_resources-$listtype.json"
	if [ -n "$github_token" ]; then
		fetch "$listtype" "$api_url" "$info_file" --header="Authorization: Bearer $github_token"
	else
		fetch "$listtype" "$api_url" "$info_file"
	fi
	local wget_exit=$?
	local list_info="$(cat "$info_file" 2>"/dev/null")"
	rm -f "$info_file"

	if [ $wget_exit -ne 0 ]; then
		log "[$(to_upper "$listtype")] Failed to fetch version info (wget exit $wget_exit)."
		return 1
	fi
	local list_sha="$(echo -e "$list_info" | jsonfilter -qe "@[0].sha")"
	local list_date="$(echo -e "$list_info" | jsonfilter -qe "@[0].commit.committer.date" | cut -d 'T' -f1)"
	if [ -z "$list_sha" ]; then
		log "[$(to_upper "$listtype")] Failed to get the latest version, please retry later."
		return 1
	fi
	local list_ver="${list_date:+$list_date }$list_sha"

	local local_list_ver="$(cat "$RESOURCES_DIR/$listtype.ver" 2>"/dev/null" || echo "NOT_FOUND")"
	local local_list_sha="${local_list_ver##* }"
	local local_list_disp="${local_list_ver%% *}"
	if [ "$local_list_sha" = "$list_sha" ]; then
		[ "$local_list_ver" = "$local_list_sha" ] && [ -n "$list_date" ] && \
			echo -e "$list_ver" > "$RESOURCES_DIR/$listtype.ver"
		log "[$(to_upper "$listtype")] Current version: ${list_ver%% *}."
		log "[$(to_upper "$listtype")] You're already at the latest version."
		return 3
	else
		log "[$(to_upper "$listtype")] Local version: $local_list_disp, latest version: ${list_ver%% *}."
	fi

	if ! download_list "$listtype" "$listrepo" "$list_sha" "$listname" "$RUN_DIR/$listname"; then
		log "[$(to_upper "$listtype")] Download failed on every mirror."
		return 1
	fi

	if mv -f "$RUN_DIR/$listname" "$RESOURCES_DIR/$listtype.${listname##*.}"; then
		echo -e "$list_ver" > "$RESOURCES_DIR/$listtype.ver"
		log "[$(to_upper "$listtype")] Successfully updated."
	else
		rm -f "$RUN_DIR/$listname"
		log "[$(to_upper "$listtype")] Failed to install update (mv failed)."
		return 1
	fi

	return 0
}

case "$1" in
"china_ip4")
	check_list_update "$1" "1715173329/IPCIDR-CHINA" "master" "ipv4.txt"
	;;
"china_ip6")
	check_list_update "$1" "1715173329/IPCIDR-CHINA" "master" "ipv6.txt"
	;;
"geoip_cn")
	check_list_update "$1" "SagerNet/sing-geoip" "rule-set" "geoip-cn.srs"
	;;
"geosite_cn")
	check_list_update "$1" "SagerNet/sing-geosite" "rule-set" "geosite-geolocation-cn.srs"
	;;
"geosite_ads")
	check_list_update "$1" "SagerNet/sing-geosite" "rule-set" "geosite-category-ads-all.srs"
	;;
*)
	echo -e "Usage: $0 <china_ip4 / china_ip6 / geoip_cn / geosite_cn / geosite_ads>"
	exit 1
	;;
esac
