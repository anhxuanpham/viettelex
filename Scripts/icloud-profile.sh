#!/bin/zsh
# Sourced by notarize-install.sh / dev-install.sh BEFORE codesign, with $APP set.
# Chọn entitlements cho chữ ký Developer ID:
#   • có Developer ID provisioning profile (bật iCloud) ⇒ nhúng vào
#     $APP/Contents/embedded.provisionprofile + ký VietTelex-iCloud.entitlements
#     (đồng bộ iCloud Mac ↔ iPhone, ICloudSync.swift);
#   • không có ⇒ VietTelex.entitlements như cũ (công tắc iCloud bị khoá trong Cài đặt).
# Profile KHÔNG nằm trong repo (repo public): đặt ở $VIETTELEX_PROFILE hoặc
# ~/.config/viettelex/VietTelex_Developer_ID.provisionprofile.
#
# An toàn: profile lệch (App ID khác, thiếu iCloud, hết hạn) ⇒ DỪNG, không ký — một
# bundle mang entitlement hạn chế mà profile không cho phép sẽ bị macOS chặn chạy,
# tức bộ gõ chết. Không đụng keychain.

ENTITLEMENTS="App/Resources/VietTelex.entitlements"
VT_PROFILE="${VIETTELEX_PROFILE:-$HOME/.config/viettelex/VietTelex_Developer_ID.provisionprofile}"
rm -f "$APP/Contents/embedded.provisionprofile"

if [ -f "$VT_PROFILE" ]; then
  VT_PLIST="$(mktemp -t vtprofile).plist"
  security cms -D -i "$VT_PROFILE" > "$VT_PLIST" 2>/dev/null \
    || { echo "  iCloud profile: không đọc được $VT_PROFILE"; exit 1; }
  pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$VT_PLIST" 2>/dev/null; }
  VT_APPID="$(pb Entitlements:com.apple.application-identifier)"
  VT_KVS="$(pb Entitlements:com.apple.developer.ubiquity-kvstore-identifier)"
  VT_EXP="$(pb ExpirationDate)"
  rm -f "$VT_PLIST"
  if [ "$VT_APPID" != "84T567KMYD.com.viettelex.inputmethod.telex" ]; then
    echo "  iCloud profile: App ID '$VT_APPID' ≠ 84T567KMYD.com.viettelex.inputmethod.telex"; exit 1
  fi
  case "$VT_KVS" in
    "84T567KMYD.*"|"84T567KMYD.com.viettelex.ios") ;;
    *) echo "  iCloud profile: thiếu iCloud Key-value storage (kvstore='$VT_KVS')"; exit 1 ;;
  esac
  # Không parse được ngày (định dạng PlistBuddy đổi) ⇒ bỏ qua kiểm tra hạn, không chặn.
  VT_EXP_S="$(date -j -f '%a %b %d %T %Z %Y' "$VT_EXP" +%s 2>/dev/null)"
  if [ -n "$VT_EXP_S" ] && [ "$VT_EXP_S" -lt "$(date +%s)" ]; then
    echo "  iCloud profile: đã hết hạn ($VT_EXP)"; exit 1
  fi
  cp "$VT_PROFILE" "$APP/Contents/embedded.provisionprofile"
  ENTITLEMENTS="App/Resources/VietTelex-iCloud.entitlements"
  echo "  iCloud: nhúng profile, ký với $ENTITLEMENTS (hết hạn: ${VT_EXP:-?})"
fi
