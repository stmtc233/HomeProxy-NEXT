#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2025 ImmortalWrt.org

NAME="homeproxy"

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

		if $WGET "$url" -O "$output" && [ -s "$output" ]; then
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
	local list_info
	if [ -n "$github_token" ]; then
		list_info="$($WGET --header="Authorization: Bearer $github_token" -O- "$api_url")"
	else
		list_info="$($WGET -O- "$api_url")"
	fi
	local wget_exit=$?

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
