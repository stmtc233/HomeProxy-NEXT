# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org

HP_FW4_CHAINS="
	homeproxy_output_redir
	homeproxy_redirect
	homeproxy_redirect_proxy
	homeproxy_redirect_proxy_port
	homeproxy_redirect_lanac
	homeproxy_mangle_prerouting
	homeproxy_mangle_output
	homeproxy_mangle_tproxy
	homeproxy_mangle_tproxy_port
	homeproxy_mangle_lanac
	homeproxy_mangle_mark
	homeproxy_mangle_tun
	homeproxy_mangle_tun_mark
"

HP_FW4_SETS="
	homeproxy_local_addr_v4
	homeproxy_local_addr_v6
	homeproxy_mainland_addr_v4
	homeproxy_mainland_addr_v6
	homeproxy_wan_proxy_addr_v4
	homeproxy_wan_proxy_addr_v6
	homeproxy_wan_direct_addr_v4
	homeproxy_wan_direct_addr_v6
	homeproxy_routing_port
"

# The inventory objects present in the fw4 table, one "chain <name>" or
# "set <name>" per line. One terse listing (no set elements) for all of them:
# on a router every nft call re-reads the ruleset, china sets included.
hp_fw4_present() {
	nft -t list table inet fw4 2>"/dev/null" | awk \
		-v chains="$(echo $HP_FW4_CHAINS)" -v sets="$(echo $HP_FW4_SETS)" '
		BEGIN {
			n = split(chains, c, " "); for (i = 1; i <= n; i++) known["chain " c[i]] = 1
			n = split(sets, s, " "); for (i = 1; i <= n; i++) known["set " s[i]] = 1
		}
		(($1 " " $2) in known) { print $1, $2 }'
}

# 0 when every chain and set declared in the given snippet is in the fw4 table.
hp_fw4_loaded() {
	{ hp_fw4_present; echo "--"; cat "$1" 2>"/dev/null"; } | awk '
		$0 == "--" { declared = 1; next }
		!declared { present[$0] = 1; next }
		($1 == "chain" || $1 == "set") && $2 ~ /^homeproxy_/ && !(($1 " " $2) in present) { missing = 1 }
		END { exit missing }'
}

# Delete every homeproxy chain and set from the fw4 table in one nft batch.
# These sets are only referenced from homeproxy chains, which only jump to
# each other, so once the chains are flushed nothing is referenced and the
# deletes go through in the same transaction. Should the batch be rejected
# anyway (it is atomic), fall back to one statement at a time.
hp_fw4_remove_all() {
	local batch
	batch="$(hp_fw4_present | awk '
		{ obj[$1] = obj[$1] " " $2 }
		END {
			n = split(obj["chain"], c, " ")
			for (i = 1; i <= n; i++) print "flush chain inet fw4 " c[i]
			for (i = 1; i <= n; i++) print "delete chain inet fw4 " c[i]
			n = split(obj["set"], s, " ")
			for (i = 1; i <= n; i++) print "flush set inet fw4 " s[i]
			for (i = 1; i <= n; i++) print "delete set inet fw4 " s[i]
		}')"
	[ -n "$batch" ] || return 0

	echo "$batch" | nft -f - 2>"/dev/null" && return 0
	echo "$batch" | while read -r stmt; do
		nft $stmt 2>"/dev/null"
	done
	return 0
}
