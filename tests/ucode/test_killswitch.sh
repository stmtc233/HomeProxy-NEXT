#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# killswitch.sh: renders the nft script for each routing mode and checks it.
# When nft and the privileges for a private network namespace are available the
# arm/disarm/install state handling is exercised on the real kernel as well.

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
KS="$ROOT/root/etc/homeproxy/scripts/killswitch.sh"
WORK="${2:-/tmp/hp-killswitch-test}"
FAILED=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }

rm -rf "$WORK"
mkdir -p "$WORK/resources" "$WORK/run"
printf '1.1.8.0/24\n1.2.4.0/24\nnot-a-cidr; flush ruleset\n\n' > "$WORK/resources/china_ip4.txt"
printf '2001:250::/30\r\n2001:254::/31\n' > "$WORK/resources/china_ip6.txt"

render() {
	KS_ROUTING_MODE="$1" HP_DIR="$WORK" RUN_DIR="$WORK/run" sh "$KS" render
}

render bypass_mainland_china > "$WORK/bypass.nft"
render global > "$WORK/global.nft"
render custom > "$WORK/custom.nft"

grep -q "ip daddr @mainland_v4 return" "$WORK/bypass.nft" \
	&& grep -q "ip6 daddr @mainland_v6 return" "$WORK/bypass.nft" \
	&& pass "bypass_mainland_china lets mainland destinations through" \
	|| fail "bypass_mainland_china lacks the mainland sets"

grep -q "1.1.8.0/24,1.2.4.0/24 }" "$WORK/bypass.nft" \
	&& grep -q "2001:250::/30,2001:254::/31 }" "$WORK/bypass.nft" \
	&& pass "the mainland sets carry the listed networks (CRLF tolerated)" \
	|| fail "the mainland sets are wrong"

if grep -q "flush ruleset\|not-a-cidr" "$WORK/bypass.nft"; then
	fail "an invalid line of a resource list reached the nft script"
else
	pass "invalid lines of a resource list are dropped"
fi

grep -q "mainland" "$WORK/global.nft" \
	&& fail "global mode must not exempt mainland addresses" \
	|| pass "global mode blocks every non-private destination"

grep -q "ip daddr @mainland_v4 return" "$WORK/custom.nft" \
	&& pass "custom mode uses the mainland sets" \
	|| fail "custom mode lacks the mainland sets"

for f in bypass global custom; do
	grep -q "192.168.0.0/16" "$WORK/$f.nft" && grep -q "fc00::/7" "$WORK/$f.nft" \
		&& grep -q "hook forward priority -5" "$WORK/$f.nft" \
		&& pass "$f: private ranges are exempt and the hook is the forward chain" \
		|| fail "$f: private ranges or forward hook missing"
done

# the switch must be a no-op for modes whose proxied set is unknowable
for mode in gfwlist proxy_mainland_china; do
	if KS_ROUTING_MODE="$mode" sh "$KS" supported; then
		fail "$mode must not get a kill switch"
	else
		pass "$mode is reported as unsupported"
	fi
done

if ! command -v nft >"/dev/null" 2>&1; then
	echo "SKIP: nft not installed, kernel state checks skipped"
	exit $FAILED
fi

if ! nft -c -f "$WORK/bypass.nft" 2>"$WORK/nft.err" || ! nft -c -f "$WORK/global.nft" 2>>"$WORK/nft.err"; then
	fail "nft rejects the rendered script"
	head -5 "$WORK/nft.err"
else
	pass "nft accepts the rendered scripts"
fi

if ! unshare -n true 2>"/dev/null"; then
	echo "SKIP: cannot create a network namespace, kernel state checks skipped"
	exit $FAILED
fi

STATE="$(unshare -n sh -c "
	export KS_ROUTING_MODE=bypass_mainland_china HP_DIR='$WORK' RUN_DIR='$WORK/run'
	echo \$(sh '$KS' status)
	sh '$KS' install; echo \$(sh '$KS' status)
	sh '$KS' disarm; sh '$KS' install; echo \$(sh '$KS' status)
	sh '$KS' arm; sh '$KS' install; echo \$(sh '$KS' status)
	sh '$KS' remove; echo \$(sh '$KS' status)
" 2>"$WORK/ns.err" | tr '\n' ' ')"

if [ "$STATE" = "absent armed disarmed armed absent " ]; then
	pass "install starts armed and keeps the state across a rebuild"
else
	fail "unexpected state sequence: $STATE"
	head -5 "$WORK/ns.err"
fi

exit $FAILED
