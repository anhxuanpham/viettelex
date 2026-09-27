#!/bin/zsh
# Dev loop: build → sign → kill IME → replace bundle in ~/Library/Input Methods.
# No logout needed after the input source has been registered once.
# (Logout/login IS required the first time, or when bundle id /
#  Info.plist input-mode metadata changes.)
#
# Install location is the USER dir (~/Library/Input Methods): user-owned,
# no sudo, correct ownership. NOTE: the bundle must NOT be sandboxed for a
# Developer ID / local build — sandbox without a provisioning profile blocks
# input-source registration. VietTelex.entitlements is sandbox=false; the
# sandboxed entitlements live in VietTelex-MAS.entitlements (App Store only).
set -e
cd "$(dirname "$0")/.."

SIGN_ID="Developer ID Application: Phil Trinh (84T567KMYD)"
DEST="$HOME/Library/Input Methods/VietTelex.app"

# FIXED derived path — the default DerivedData grows one dir per xcodegen
# regeneration, and `ls | head -1` then installs a STALE build (bit us
# 2026-07-22: engine changes "didn't take"). Same pattern as notarize-install.
DERIVED="${TMPDIR:-/tmp}/viettelex-derived-dev"
xcodebuild -project VietTelex.xcodeproj -scheme VietTelex \
           -configuration Release -destination 'platform=macOS' \
           -derivedDataPath "$DERIVED" \
           build | grep -E "BUILD" || true

APP="$DERIVED/Build/Products/Release/VietTelex.app"
source Scripts/icloud-profile.sh      # → $ENTITLEMENTS (+ embedded.provisionprofile nếu có)
codesign --force --options runtime \
         --entitlements "$ENTITLEMENTS" \
         --sign "$SIGN_ID" "$APP"

pkill -x VietTelex 2>/dev/null || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
# Bản build trong $DERIVED cũng đã được LaunchServices đăng ký dưới CÙNG bundle id
# (xcodebuild/test host tự đăng ký ở bất cứ đâu nó được build; xoá thư mục KHÔNG huỷ
# đăng ký — đo 13/09/2026 ở fork vtx: 4 bản ghi trong khi mdfind thấy 1). Huỷ đăng
# ký bản build ngay sau khi cài, rồi liệt kê nếu còn bản lạ để dọn tay bằng
# lsregister -u <path>. Không fail: bản cài đã xong. (Port vtx PR#16/#17.)
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Huỷ đăng ký MỌI bản ngoài $DEST, không chỉ bản build của script: một vòng
# xcodebuild build+test là DerivedData Debug/Release + build/Release + bản cũ trong
# ~/Downloads quay lại ngay (đo 16/09/2026 trên máy maintainer) — cảnh báo suông sẽ
# thành nhiễu. -u chỉ xoá bản ghi LaunchServices, không đụng file.
"$LSREG" -dump 2>/dev/null | grep -E '^path:.*/VietTelex\.app \(0x' \
  | sed -E 's/^path: *//; s/ \(0x[0-9a-f]+\)$//' \
  | while IFS= read -r reg; do
      [ "$reg" = "$DEST" ] && continue
      "$LSREG" -u "$reg" >/dev/null 2>&1 && echo "  lsregister -u (bản thừa): $reg"
    done

# The keyboard menu is drawn by TextInputMenuAgent, which keeps an IMK
# connection to the OLD (now dead) IME process. Without this restart the
# VietTelex menu section vanishes in EVERY app until the agent is bounced.
killall TextInputMenuAgent 2>/dev/null || true

echo "Installed to $DEST. Type anywhere (or switch input source away and back) to relaunch."
echo "NOTE: apps hold their own IMK connection — an app that stopped responding to"
echo "      the IME needs an input-source flip; Chrome/iTerm need a full app relaunch."
echo "Live logs: /usr/bin/log stream --predicate 'process == \"VietTelex\"'"
