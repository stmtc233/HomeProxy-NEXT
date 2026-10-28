#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Kill switch: while the sing-box client is not running, drop forwarded traffic
# towards overseas destinations so that nothing leaks out directly.
#
# It lives in its own nftables table (inet homeproxy_killswitch) instead of the
# fw4 one, because the fw4 objects are torn down on every stop/reload/restart -
# exactly the window this has to cover. The table holds the destination sets
# and a "guard" chain with the drop rules; the base "forward" chain only jumps
# to the guard while the switch is armed, so arming and disarming are a single
# cheap chain operation.
#
#   install   (re)build the table, keeping the current armed/disarmed state
#             (a brand new table starts armed)
#   arm       block overseas traffic (installs the table when missing)
#   disarm    let traffic through again
#   remove    delete the table
#   guard     long-running watchdog: arm when sing-box is down, disarm once it
#             has been up for a few seconds (and no hold file asks otherwise)
#   render    print the nft script and exit (no nft needed; used by the tests)
#   status    print "armed", "disarmed" or "absent"
#
# "Overseas" is every destination that is neither local/private nor a
# mainland China address.

HP_DIR="${HP_DIR:-/etc/homeproxy}"
RUN_DIR="${RUN_DIR:-/var/run/homeproxy}"
LOG_PATH="$RUN_DIR/homeproxy.log"

TABLE="homeproxy_killswitch"
GUARD_INTERVAL="${KS_GUARD_INTERVAL:-2}"
# present while the service is restarting: sing-box may still be alive in that
# window although the firewall rules it relies on are already gone
HOLD_FILE="$RUN_DIR/ks_hold"

log() {
	mkdir -p "$RUN_DIR" 2>"/dev/null"
	echo -e "$(date "+%Y-%m-%d %H:%M:%S") [KILLSWITCH] $*" >> "$LOG_PATH"
}

has_table() {
	nft list table inet "$TABLE" >"/dev/null" 2>&1
}

is_armed() {
	nft list chain inet "$TABLE" forward 2>"/dev/null" | grep -q "jump guard"
}

# Comma separated, validated CIDR list of a resource file ("" when unusable).
# Only the characters of an address survive, so a damaged file cannot inject
# anything into the nft script.
cidr_list() {
	[ -s "$1" ] || return 0
	tr -d '\r' < "$1" | grep -E "$2" | tr '\n' ',' | sed 's/,$//'
}

render() {
	local v4 v6
	v4="$(cidr_list "$HP_DIR/resources/china_ip4.txt" '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$')"
	v6="$(cidr_list "$HP_DIR/resources/china_ip6.txt" '^[0-9a-fA-F:]+(/[0-9]{1,3})?$')"

	# `table` creates the table when absent, so the delete that follows never
	# fails and the whole replacement stays one atomic transaction.
	echo "table inet $TABLE"
	echo "delete table inet $TABLE"
	echo "table inet $TABLE {"
	if [ -n "$v4" ]; then
		echo "	set mainland_v4 {"
		echo "		type ipv4_addr"
		echo "		flags interval"
		echo "		auto-merge"
		echo "		elements = { $v4 }"
		echo "	}"
	fi
	if [ -n "$v6" ]; then
		echo "	set mainland_v6 {"
		echo "		type ipv6_addr"
		echo "		flags interval"
		echo "		auto-merge"
		echo "		elements = { $v6 }"
		echo "	}"
	fi
	echo "	chain guard {"
	echo "		ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 } return"
	echo "		ip6 daddr { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8 } return"
	[ -z "$v4" ] || echo "		ip daddr @mainland_v4 return"
	[ -z "$v6" ] || echo "		ip6 daddr @mainland_v6 return"
	echo "		counter drop comment \"!homeproxy: kill switch\""
	echo "	}"
	echo "	chain forward {"
	echo "		type filter hook forward priority -5; policy accept;"
	echo "	}"
	echo "}"
}

arm() {
	has_table || install
	has_table || return 1
	is_armed && return 0

	nft -f - <<-EOF
		flush chain inet $TABLE forward
		add rule inet $TABLE forward jump guard
	EOF
}

disarm() {
	has_table || return 0
	nft flush chain inet "$TABLE" forward
}

remove() {
	has_table && nft delete table inet "$TABLE"
	return 0
}

install() {
	local armed=1

	# keep the state across a rebuild; a table that did not exist starts armed
	# because nothing proves sing-box is up yet (the guard disarms it)
	if has_table && ! is_armed; then
		armed=0
	fi

	mkdir -p "$RUN_DIR"
	render > "$RUN_DIR/killswitch.nft" || return 1
	if ! nft -f "$RUN_DIR/killswitch.nft" 2>>"$LOG_PATH"; then
		log "Error: failed to load the kill switch rules."
		return 1
	fi

	[ "$armed" = "0" ] || arm
}

client_running() {
	[ "$(ubus call service list '{"name":"homeproxy"}' 2>"/dev/null" \
		| jsonfilter -e '@.homeproxy.instances["sing-box-c"].running' 2>"/dev/null")" = "true" ]
}

guard() {
	local up=0

	while :; do
		if [ ! -e "$HOLD_FILE" ] && client_running; then
			up=$((up + 1))
			# a client that keeps crashing right after it came up must not
			# lift the block, so wait until it has stayed up for two checks
			if [ "$up" -ge 2 ] && has_table && is_armed; then
				disarm && log "sing-box is running, overseas traffic is allowed again."
			fi
		else
			up=0
			if ! is_armed; then
				arm && log "sing-box is not running, blocking overseas traffic."
			fi
		fi

		sleep "$GUARD_INTERVAL"
	done
}

status() {
	if ! has_table; then
		echo "absent"
	elif is_armed; then
		echo "armed"
	else
		echo "disarmed"
	fi
}

case "$1" in
install) install ;;
arm) arm ;;
disarm) disarm ;;
remove) remove ;;
guard) guard ;;
render) render ;;
status) status ;;
*)
	echo "usage: $0 {install|arm|disarm|remove|guard|render|status}" >&2
	exit 1
	;;
esac
