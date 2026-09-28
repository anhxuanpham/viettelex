#!/usr/bin/env bash
#
# ram-audit.sh — đo RAM process IME VietTelex trên emulator/máy (xem android/docs/RAM-AUDIT.md).
#
# Cần: adb, emulator userdebug (adb root — để ghi prefs của bản release + SIGQUIT lấy thống kê
# cấp phát ART). Không cài app lạ. Tự đặt VietTelex làm IME rồi TRẢ LẠI IME mặc định lúc thoát.
#
#   ram-audit.sh matrix OUT_DIR [APK]   chạy đủ ma trận cấu hình × trạng thái, ghi OUT_DIR/*.txt + summary.tsv
#   ram-audit.sh snap LABEL OUT_DIR     một ảnh meminfo (+ smaps asset + thống kê cấp phát ART)
#   ram-audit.sh prefs default|all|off  ghi prefs (force-stop app trước)
#   ram-audit.sh type N                 chạm N phím chữ/cách thật trên bàn phím (qua `input tap`)
#   ram-audit.sh settings OUT_DIR       mở app cài đặt (cùng process IME) rồi Back: PSS trước/sau
#   ram-audit.sh switch OUT_DIR         đổi IME Gboard ↔ VietTelex 3 lần, heap dump (-g), đếm VietTelexIME sống
#
# Ma trận: shown / 200keys / emoji / (clipboard) / hidden / hidden-idle (ẩn IDLE_WAIT=50 s — hẹn
# giờ nhả của IME) / trim-bg / trim-complete / after20show (hiện/ẩn thêm 20 lần).
#
# Toạ độ phím mặc định cho màn 1080x2400 @420dpi (sdk_gphone64_arm64, bàn phím mặc định, hàng
# số tắt). Máy khác: đặt ROW1_Y/ROW2_Y/ROW3_Y/KEY_W/... qua env.
set -euo pipefail
[[ -n ${TRACE:-} ]] && set -x
export PATH="$PATH:${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools"

S="${ANDROID_SERIAL:-emulator-5560}"
PKG=com.viettelex.android
IME=$PKG/.ime.VietTelexIME
ADB="adb -s $S"
PREFS_DIR=/data/data/$PKG/shared_prefs

ROW1_Y=${ROW1_Y:-1759}; ROW2_Y=${ROW2_Y:-1906}; ROW3_Y=${ROW3_Y:-2052}; ROW4_Y=${ROW4_Y:-2200}
KEY_W=${KEY_W:-107.6}; ROW1_X0=${ROW1_X0:-55}; ROW2_X0=${ROW2_X0:-108}; ROW3_X0=${ROW3_X0:-212}
SPACE_X=${SPACE_X:-600}; EMOJI_X=${EMOJI_X:-358}; ABC_X=${ABC_X:-79}; ABC_Y=${ABC_Y:-2226}
FIELD_X=${FIELD_X:-540}; FIELD_Y=${FIELD_Y:-943}; CLIP_X=${CLIP_X:-890}; CLIP_Y=${CLIP_Y:-1633}

pid() { { $ADB shell pidof $PKG || true; } | tr -d '\r'; }

key_xy() {  # chữ thường → "x y"
  local c=$1 r1=qwertyuiop r2=asdfghjkl r3=zxcvbnm i
  if [[ $c == " " ]]; then echo "$SPACE_X $ROW4_Y"; return; fi
  i=$(awk -v s=$r1 -v c="$c" 'BEGIN{print index(s,c)-1}'); if (( i >= 0 )); then awk -v i=$i -v x0=$ROW1_X0 -v w=$KEY_W -v y=$ROW1_Y 'BEGIN{printf "%d %d\n", x0+i*w, y}'; return; fi
  i=$(awk -v s=$r2 -v c="$c" 'BEGIN{print index(s,c)-1}'); if (( i >= 0 )); then awk -v i=$i -v x0=$ROW2_X0 -v w=$KEY_W -v y=$ROW2_Y 'BEGIN{printf "%d %d\n", x0+i*w, y}'; return; fi
  i=$(awk -v s=$r3 -v c="$c" 'BEGIN{print index(s,c)-1}'); if (( i >= 0 )); then awk -v i=$i -v x0=$ROW3_X0 -v w=$KEY_W -v y=$ROW3_Y 'BEGIN{printf "%d %d\n", x0+i*w, y}'; return; fi
}

# Chạm N phím: soạn file lệnh `input tap` rồi chạy MỘT lần trên máy (không round-trip adb mỗi phím).
type_keys() {
  local n=$1 text="xin chaof cacs banj hoom nay trowif ddepj quas tooi ddi hocj tieengs vieetj " f
  f=$(mktemp); local i=0
  while (( i < n )); do
    local c=${text:$(( i % ${#text} )):1}
    echo "input tap $(key_xy "$c")" >> "$f"; i=$((i+1))
  done
  $ADB push "$f" /data/local/tmp/vt-type.sh >/dev/null; rm -f "$f"
  $ADB shell sh /data/local/tmp/vt-type.sh
}

focus_field() {
  $ADB shell am force-stop com.google.android.contacts   # editor mới, trống (không mở lại form cũ)
  $ADB shell am start -W -a android.intent.action.INSERT -t vnd.android.cursor.dir/contact >/dev/null
  sleep 3; $ADB shell input tap $FIELD_X $FIELD_Y
  # đợi bàn phím THẬT SỰ hiện + vẽ xong (process mới: onCreate + input view + nạp nền)
  local i; for i in $(seq 20); do
    $ADB shell dumpsys input_method | grep -q "mInputShown=true" && break; sleep 1
  done
  sleep 5
}

hide_kb() { $ADB shell input keyevent KEYCODE_BACK; sleep 2; }
home()    { $ADB shell input keyevent KEYCODE_HOME; sleep 2; }

write_prefs() {  # default|all|off
  local cfg=$1 f; f=$(mktemp)
  {
    echo "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>"; echo "<map>"
    case $cfg in
      all)
        for k in swipeTyping swipeEnglish swipeFuto showSuggestions clipboardHistory keySound hapticFeedback \
                 wallpaperEnabled templatesEnabled smartTouch autoCorrect addTonesChip spaceSwipeLanguage \
                 keyPreviewEnabled numberChips mathResults showSpaceLogo plusUnlocked; do
          echo "  <boolean name=\"$k\" value=\"true\" />"; done
        echo '  <int name="keyboardTransparency" value="30" />'
        echo '  <int name="keySoundVolume" value="60" />'
        echo '  <long name="wallpaperVersion" value="1" />' ;;
      off)
        for k in swipeTyping swipeEnglish swipeFuto showSuggestions clipboardHistory keySound hapticFeedback \
                 wallpaperEnabled templatesEnabled smartTouch autoCorrect addTonesChip spaceSwipeLanguage \
                 keyPreviewEnabled numberChips mathResults showSpaceLogo liveSpellCheck autoFixAdjacent \
                 contextualEnglish reEditWords shortcutsEnabled; do
          echo "  <boolean name=\"$k\" value=\"false\" />"; done ;;
      default) ;;
    esac
    echo "</map>"
  } > "$f"
  $ADB shell am force-stop $PKG
  $ADB shell mkdir -p $PREFS_DIR
  $ADB push "$f" /data/local/tmp/vt-prefs.xml >/dev/null; rm -f "$f"
  $ADB shell "cp /data/local/tmp/vt-prefs.xml $PREFS_DIR/viettelex.xml && chown \$(stat -c %u:%g /data/data/$PKG) $PREFS_DIR $PREFS_DIR/viettelex.xml && chmod 660 $PREFS_DIR/viettelex.xml && restorecon -R /data/data/$PKG"
  if [[ $cfg == all && -n "${WALLPAPER_JPG:-}" ]]; then
    $ADB shell mkdir -p /data/data/$PKG/files
    $ADB push "$WALLPAPER_JPG" /data/local/tmp/vt-wall.jpg >/dev/null
    $ADB shell "cp /data/local/tmp/vt-wall.jpg /data/data/$PKG/files/wallpaper.jpg && chown -R \$(stat -c %u:%g /data/data/$PKG) /data/data/$PKG/files && restorecon -R /data/data/$PKG"
  else
    $ADB shell rm -f /data/data/$PKG/files/wallpaper.jpg
  fi
  # force-stop package của IME hiện hành ⇒ hệ thống rơi về IME khác: đặt lại.
  $ADB shell ime enable $IME >/dev/null; $ADB shell ime set $IME >/dev/null
}

# ART: tổng byte đã cấp phát + số GC (SIGQUIT → /data/anr/traces). In "bytes gcs".
art_alloc() {
  local p; p=$(pid); [[ -z $p ]] && { echo "0 0"; return; }
  local before; before=$($ADB shell ls -t /data/anr 2>/dev/null | head -1 | tr -d '\r')
  $ADB shell kill -3 "$p"; sleep 2
  local f; f=$($ADB shell ls -t /data/anr 2>/dev/null | head -1 | tr -d '\r')
  [[ -z $f || $f == "$before" ]] && { echo "0 0"; return; }
  $ADB shell cat "/data/anr/$f" | awk '
    /^----- pid/ { inside = ($3 == P) }
    function kb(v,  n) { n=v+0; if (v ~ /GB$/) return n*1048576; if (v ~ /MB$/) return n*1024; if (v ~ /KB$/) return n; return int(n/1024) }
    inside && /^Total bytes allocated/ { b=kb($4) }
    inside && /^Total GC count/ { g=$4 }
    END { print (b==""?0:b), (g==""?0:g) }' P="$p"
}

snap() {  # LABEL OUT_DIR
  local label=$1 out=$2 p; p=$(pid)
  mkdir -p "$out"
  if [[ -z $p ]]; then echo -e "$label\tNO_PROCESS" >> "$out/summary.tsv"; return; fi
  $ADB shell dumpsys meminfo $PKG > "$out/$label.meminfo.txt"
  # asset .bin mmap: vùng base.apk theo offset — Rss/Pss thực sự chạm (trang sạch, kernel thu hồi được)
  $ADB shell "cat /proc/$p/smaps" > "$out/$label.smaps.txt" 2>/dev/null || true
  local m="$out/$label.meminfo.txt"
  local total java native code gfx other sys
  total=$(awk '/TOTAL PSS:/{print $3}' "$m"); java=$(awk '/Java Heap:/{print $3}' "$m")
  native=$(awk '/^ +Native Heap:/{print $3}' "$m")
  code=$(awk '/^ +Code:/{print $2}' "$m"); gfx=$(awk '/^ +Graphics:/{print $2}' "$m")
  other=$(awk '/Private Other:/{print $3}' "$m"); sys=$(awk '/^ +System:/{print $2}' "$m")
  local dalvikAlloc nativeAlloc views
  dalvikAlloc=$(awk '/^ +Dalvik Heap +[0-9]/{print $(NF-1)}' "$m"); nativeAlloc=$(awk '/^ +Native Heap +[0-9]/{print $(NF-1)}' "$m")
  views=$(awk '$1=="Views:"{print $2}' "$m")
  $ADB shell dumpsys gfxinfo $PKG > "$out/$label.gfxinfo.txt" 2>/dev/null || true
  local apk; apk=$(awk '/base.apk/{on=1;next} /^[0-9a-f]+-[0-9a-f]+ /{on=0} on && /^Pss:/{s+=$2} END{print s+0}' "$out/$label.smaps.txt")
  local alloc; alloc=$(art_alloc)
  [[ -f "$out/summary.tsv" ]] || echo -e "label\tpss\tjava\tnative\tcode\tgraphics\tprivOther\tsystem\tdalvikAllocKB\tnativeAllocKB\tbaseApkPss\tviews\tartAllocKB\tgcCount" > "$out/summary.tsv"
  printf '%s\t' "$label" "$total" "$java" "$native" "$code" "$gfx" "$other" "$sys" "$dalvikAlloc" "$nativeAlloc" "$apk" "$views" >> "$out/summary.tsv"
  echo "$alloc" | tr ' ' '\t' >> "$out/summary.tsv"
  echo "$label pss=$total java=$java native=$native code=$code apk=$apk alloc=$alloc" >&2
}

trim() {  # mô phỏng áp lực RAM lúc bàn phím ẩn
  $ADB shell am send-trim-memory $PKG ${1:-RUNNING_LOW} || true; sleep 2
}

run_config() {  # CFG OUT
  local cfg=$1 out=$2
  write_prefs "$cfg"
  focus_field; snap "$cfg-shown" "$out"
  type_keys 200; sleep 2; snap "$cfg-200keys" "$out"
  # emoji pane
  $ADB shell input tap $EMOJI_X $ROW4_Y; sleep 3
  for _ in 1 2 3 4 5 6; do $ADB shell input swipe 540 2100 540 1750 150; sleep 1; done   # cuộn lưới emoji
  sleep 2; snap "$cfg-emoji" "$out"
  $ADB shell input tap $ABC_X $ABC_Y; sleep 2
  if [[ $cfg == all ]]; then   # nút 📋 trên thanh gợi ý (chỉ có khi bật lịch sử clipboard)
    $ADB shell input tap $CLIP_X $CLIP_Y; sleep 3; snap "$cfg-clipboard" "$out"
    $ADB shell input tap $CLIP_X $CLIP_Y; sleep 1
  fi
  hide_kb; snap "$cfg-hidden" "$out"
  sleep "${IDLE_WAIT:-50}"; snap "$cfg-hidden-idle" "$out"   # hẹn giờ ẩn của IME (45 s) đã chạy
  home; trim BACKGROUND; snap "$cfg-trim-bg" "$out"
  trim COMPLETE; snap "$cfg-trim-complete" "$out"
  # leak check: hiện/ẩn 20 lần
  focus_field
  for _ in $(seq 20); do hide_kb; $ADB shell input tap $FIELD_X $FIELD_Y; sleep 1; done
  snap "$cfg-after20show" "$out"
  hide_kb; home
}

# App cài đặt (Compose) chạy cùng process IME: mở rồi Back — PSS có trở về không (RAM-AUDIT #5).
settings_check() {  # OUT
  local out=$1
  focus_field; hide_kb; home; sleep 3; snap "settings-before" "$out"
  # như chạm icon launcher (task gốc ⇒ API 31+ Back KHÔNG finish, chỉ đưa task ra sau)
  $ADB shell am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n $PKG/.ui.MainActivity >/dev/null; sleep 5
  snap "settings-open" "$out"
  $ADB shell input keyevent KEYCODE_BACK; sleep 5
  snap "settings-after" "$out"
  echo "MainActivity sống: $($ADB shell dumpsys activity activities | grep -c "ActivityRecord{.*$PKG/.ui.MainActivity")" >&2
  sleep 30; snap "settings-after30s" "$out"
}

# Đổi IME 3 lần, heap dump sau GC, đếm instance VietTelexIME còn sống (RAM-AUDIT #2).
switch_check() {  # OUT
  local out=$1 other=${OTHER_IME:-com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME} i
  focus_field
  for i in 1 2 3; do
    $ADB shell ime set "$other" >/dev/null; sleep 3
    $ADB shell ime set $IME >/dev/null; sleep 2
    $ADB shell input tap $FIELD_X $FIELD_Y; sleep 3
  done
  hide_kb; snap "switch3" "$out"
  local p; p=$(pid)
  $ADB shell am dumpheap -g $PKG /data/local/tmp/vt.hprof; sleep 3
  $ADB pull /data/local/tmp/vt.hprof "$out/switch3.hprof" >/dev/null
  "${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/hprof-conv" "$out/switch3.hprof" "$out/switch3-std.hprof"
  python3 "$(dirname "$0")/hprof-summary.py" "$out/switch3-std.hprof" --filter com.viettelex.android.ime.VietTelexIME --top 5 >&2 || true
  python3 "$(dirname "$0")/hprof-summary.py" "$out/switch3-std.hprof" --referrers com.viettelex.android.ime.VietTelexIME --path > "$out/switch3-referrers.txt" 2>&1 || true
  head -40 "$out/switch3-referrers.txt" >&2
}

with_ime() {  # đặt VietTelex làm IME, trả lại IME cũ lúc thoát
  prev=${RESTORE_IME:-$($ADB shell settings get secure default_input_method | tr -d '\r')}
  [[ $prev == $IME ]] && prev=com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME
  trap '$ADB shell ime set "$prev" >/dev/null; echo "IME trả lại: $prev" >&2' EXIT
  $ADB root >/dev/null; $ADB wait-for-device
  $ADB shell ime enable $IME >/dev/null; $ADB shell ime set $IME >/dev/null
}

cmd=${1:-}; shift || true
case $cmd in
  snap) snap "$1" "$2" ;;
  prefs) write_prefs "$1" ;;
  type) type_keys "$1" ;;
  trim) trim "${1:-}" ;;
  settings) mkdir -p "$1"; with_ime; settings_check "$1" ;;
  switch) mkdir -p "$1"; with_ime; switch_check "$1" ;;
  matrix)
    out=$1; apk=${2:-}; mkdir -p "$out"
    prev=${RESTORE_IME:-$($ADB shell settings get secure default_input_method | tr -d '\r')}
    [[ $prev == $IME ]] && prev=com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME
    trap '$ADB shell ime set "$prev" >/dev/null; echo "IME trả lại: $prev" >&2' EXIT
    $ADB root >/dev/null; $ADB wait-for-device
    [[ -n $apk ]] && $ADB install -r "$apk" >/dev/null
    $ADB shell ime enable $IME >/dev/null; $ADB shell ime set $IME >/dev/null
    for cfg in ${CONFIGS:-default off all}; do run_config "$cfg" "$out"; done
    column -t -s $'\t' "$out/summary.tsv" >&2 ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
