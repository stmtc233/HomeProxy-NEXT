#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# The fw4 helpers in scripts/fw4_names.sh that init.d/homeproxy uses to tell
# whether a fw4 reload is needed and to take the homeproxy objects out in one
# nft batch. Runs against a stand-in fw4 table inside a network namespace:
# fw4 reloads by `flush table`, which empties the chains but keeps the sets
# and their elements, so the helpers are checked against that behaviour.

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
WORK="${2:-/tmp/hp-fw4-cleanup}"

if ! command -v nft > "/dev/null" 2>&1 || ! unshare -n true 2>"/dev/null"; then
	echo "SKIP: needs nft and a network namespace"
	exit 0
fi

rm -rf "$WORK"
mkdir -p "$WORK"

# What firewall_post.ut renders: homeproxy sets and chains, plus rules in
# fw4's own chains that jump into them.
cat > "$WORK/post.nft" <<-'EOF'
	set homeproxy_local_addr_v4 {
		type ipv4_addr
		flags interval
		auto-merge
		elements = { 10.0.0.0/8 }
	}
	set homeproxy_mainland_addr_v4 {
		type ipv4_addr
		flags interval
		auto-merge
		elements = { 1.0.1.0/24 }
	}
	chain homeproxy_mangle_lanac {
		ip daddr @homeproxy_local_addr_v4 return
		ip daddr @homeproxy_mainland_addr_v4 return
		goto homeproxy_mangle_tproxy
	}
	chain homeproxy_mangle_tproxy {
		counter
	}
	chain mangle_prerouting {
		meta l4proto { tcp, udp } jump homeproxy_mangle_lanac
	}
EOF
: > "$WORK/empty.nft"

OUT="$(unshare -n sh -c "
	. '$ROOT/root/etc/homeproxy/scripts/fw4_names.sh'
	fw4_reload() {
		nft -f - <<-NFT
			table inet fw4
			flush table inet fw4
			table inet fw4 {
				chain mangle_prerouting { type filter hook prerouting priority mangle; }
				chain unrelated { counter; }
				set unrelated_set { type ipv4_addr; }
				include \"\$1\"
			}
		NFT
	}

	fw4_reload '$WORK/post.nft'
	echo present=\$(hp_fw4_present | tr '\n' ',')
	hp_fw4_loaded '$WORK/post.nft' && echo loaded=yes || echo loaded=no

	# still referenced from fw4's chain: the batch is rejected, the fallback
	# removes what it can
	hp_fw4_remove_all
	echo referenced_left=\$(hp_fw4_present | tr '\n' ',')
	hp_fw4_loaded '$WORK/post.nft' && echo loaded=yes || echo loaded=no

	# the way init.d unloads: reload on blank snippets, then one batch
	fw4_reload '$WORK/post.nft'
	fw4_reload '$WORK/empty.nft'
	hp_fw4_remove_all
	echo unloaded_left=\$(hp_fw4_present | tr '\n' ',')
	echo unrelated=\$(nft -t list table inet fw4 | grep -cE '(chain unrelated|set unrelated_set) ')
	hp_fw4_loaded '$WORK/empty.nft' && echo empty_loaded=yes || echo empty_loaded=no
" 2>"$WORK/ns.err")"

FAILED=0
expect() {
	if printf '%s\n' "$OUT" | grep -qx -- "$2"; then
		echo "PASS: $1"
	else
		echo "FAIL: $1 (expected '$2')"
		FAILED=1
	fi
}

expect "only inventory objects are listed" \
	"present=set homeproxy_local_addr_v4,set homeproxy_mainland_addr_v4,chain homeproxy_mangle_lanac,chain homeproxy_mangle_tproxy,"
expect "a loaded snippet is recognised" "loaded=yes"
expect "a referenced chain survives, the rest is removed" \
	"referenced_left=chain homeproxy_mangle_lanac,"
expect "a partly removed snippet is not taken for loaded" "loaded=no"
expect "reload on blank snippets + one batch removes everything" "unloaded_left="
expect "objects outside the inventory are left alone" "unrelated=2"
expect "a blank snippet counts as loaded" "empty_loaded=yes"

if [ "$FAILED" -ne 0 ]; then
	printf '%s\n' "$OUT"
	head -5 "$WORK/ns.err"
fi

exit $FAILED
