# SPDX-License-Identifier: GPL-2.0-only
#
# The fallbacks the shell side needs, for options missing from
# /etc/config/homeproxy. DEFAULTS in homeproxy.uc is the full table; every
# value here mirrors its entry there (tests/ucode/test_defaults.sh checks).

HP_DEFAULT_PROXY_MODE="redirect_tproxy"
HP_DEFAULT_DEFAULT_MODE="nil"
HP_DEFAULT_DNS_PORT="5333"
HP_DEFAULT_TABLE_MARK="100"
HP_DEFAULT_TPROXY_MARK="101"
HP_DEFAULT_TUN_MARK="102"
HP_DEFAULT_TUN_NAME="singtun0"
HP_DEFAULT_AUTO_UPDATE_TIME="2"
