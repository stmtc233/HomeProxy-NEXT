#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Fetches the default sing-box dashboard archive and unpacks it into
# root/etc/homeproxy/dashboard/web, so that build-pkg.sh can build a
# package variant that comes bundled with dashboard files.

set -o errexit
set -o pipefail
set -o nounset

BASE_DIR="$(cd "$(dirname "$0")"; pwd)"
PKG_DIR="$(cd "$BASE_DIR/.."; pwd)"
TARGET_DIR="$PKG_DIR/root/etc/homeproxy/dashboard"
DEFAULT_SH="$PKG_DIR/root/etc/homeproxy/scripts/defaults.sh"

URL="${1:-}"
if [ -z "$URL" ]; then
	if [ -f "$DEFAULT_SH" ]; then
		URL="$(grep -oP '^HP_DEFAULT_DASHBOARD_URL="\K[^"]+' "$DEFAULT_SH" 2>/dev/null || true)"
	fi
	[ -n "$URL" ] || URL="https://github.com/SagerNet/sing-box-dashboard/archive/refs/heads/gh-pages.zip"
fi

echo "Fetching sing-box dashboard from $URL..."

TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'hp-dash')"
trap 'rm -rf "$TEMP_DIR"' EXIT

ZIP_FILE="$TEMP_DIR/dashboard.zip"
EXTRACT_DIR="$TEMP_DIR/extracted"

if command -v curl >/dev/null 2>&1; then
	curl -fsSL --retry 3 -o "$ZIP_FILE" "$URL"
elif command -v wget >/dev/null 2>&1; then
	wget -q -O "$ZIP_FILE" "$URL"
else
	echo "error: neither curl nor wget found" >&2
	exit 1
fi

if [ ! -s "$ZIP_FILE" ]; then
	echo "error: downloaded dashboard archive is empty" >&2
	exit 1
fi

if command -v md5sum >/dev/null 2>&1; then
	MD5="$(md5sum "$ZIP_FILE" | awk '{print $1}')"
elif command -v md5 >/dev/null 2>&1; then
	MD5="$(md5 -q "$ZIP_FILE")"
else
	MD5="$(python3 -c "import hashlib; print(hashlib.md5(open('$ZIP_FILE','rb').read()).hexdigest())")"
fi
echo "Dashboard archive MD5: $MD5"

mkdir -p "$EXTRACT_DIR"
if command -v unzip >/dev/null 2>&1; then
	unzip -qo "$ZIP_FILE" -d "$EXTRACT_DIR"
elif command -v python3 >/dev/null 2>&1; then
	python3 -c "import zipfile; zipfile.ZipFile('$ZIP_FILE').extractall('$EXTRACT_DIR')"
else
	echo "error: neither unzip nor python3 found" >&2
	exit 1
fi

# GitHub archives wrap files in a single top-level folder (e.g. sing-box-dashboard-gh-pages)
ROOT_DIR="$EXTRACT_DIR"
if [ ! -f "$ROOT_DIR/index.html" ]; then
	shopt -s nullglob
	entries=("$EXTRACT_DIR"/*)
	if [ "${#entries[@]}" -eq 1 ] && [ -d "${entries[0]}" ]; then
		ROOT_DIR="${entries[0]}"
	fi
fi

if [ ! -f "$ROOT_DIR/index.html" ]; then
	echo "error: no index.html found at top level of extracted dashboard archive" >&2
	exit 1
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
mv "$ROOT_DIR" "$TARGET_DIR/web"
echo "$MD5 $URL" > "$TARGET_DIR/archive.ver"
date "+%s" > "$TARGET_DIR/archive.time"

find "$TARGET_DIR" -type d -exec chmod 0755 {} + 2>/dev/null || true
find "$TARGET_DIR" -type f -exec chmod 0644 {} + 2>/dev/null || true

FILE_COUNT="$(find "$TARGET_DIR/web" -type f | wc -l)"
TOTAL_SIZE="$(du -sh "$TARGET_DIR/web" 2>/dev/null | awk '{print $1}' || echo "done")"

echo "Successfully prepared bundled dashboard: $FILE_COUNT files, $TOTAL_SIZE"
