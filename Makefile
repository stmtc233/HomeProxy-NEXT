# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2023 ImmortalWrt.org
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=HomeProxy NEXT - a lean sing-box 1.14 proxy for ImmortalWrt
# Pure ucode/JS payload with no compiled code, so the package itself is arch
# independent. sing-box (or sing-box-tiny) >= 1.14 is required at runtime, but
# not listed in LUCI_DEPENDS so that removing or switching the core package
# does not cascade into removing luci-app-homeproxy, and custom binaries work.
LUCI_PKGARCH:=all
LUCI_DEPENDS:= \
	+firewall4 \
	+kmod-nft-tproxy \
	+ip-full \
	+kmod-tun \
	+ucode-mod-digest \
	+unzip

PKG_NAME:=luci-app-homeproxy
PKG_VERSION:=27.919.1.14
PKG_RELEASE:=40

define Package/luci-app-homeproxy/conffiles
/etc/config/homeproxy
/etc/homeproxy/certs/
/etc/homeproxy/custom/
/etc/homeproxy/ruleset/
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
