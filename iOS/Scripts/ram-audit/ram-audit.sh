#!/bin/zsh
# Đo RAM process VietTelexKeyboard THẬT trên simulator (iOS/docs/RAM-AUDIT.md).
#
#   ram-audit.sh <default|all|off> [outdir] [device-udid] [cycles]
#
# Yêu cầu: VietTelexApp (kèm extension) ĐÃ cài trên simulator, bàn phím VietTelex đã thêm
# trong Cài đặt + Cho phép Toàn quyền (một lần tay). Script:
#   1. ghi cấu hình vào App Group (qua `simctl spawn defaults`, không đụng file trực tiếp),
#   2. giết process extension cũ (đo từ lạnh),
#   3. build + chạy driver XCUITest (Driver/RamDriverUITests.swift),
#   4. ở mỗi mốc driver báo: footprint / vmmap --summary / heap -s của process extension,
#   5. in bảng tóm tắt (summarize.py).
set -u
CFG=${1:-default}
OUT=${2:-/tmp/ram-audit/$CFG}
DEV=${3:-904A6001-5753-403F-98B3-BBB46852534B}
CYCLES=${4:-30}
HERE=${0:A:h}
DRV=${RAM_DRV_DIR:-${OUT:h}/drvproj}

rm -rf $OUT; mkdir -p $OUT/sync $OUT/samples $DRV

GROUP=$(xcrun simctl get_app_container $DEV com.viettelex.ios group.com.viettelex) || {
    echo "chưa cài com.viettelex.ios trên $DEV"; exit 1; }
PL=$GROUP/Library/Preferences/group.com.viettelex
dw() { xcrun simctl spawn $DEV defaults write $PL "$@" }

FEATURES=(showSuggestions smartTouch swipeTyping swipeEnglish swipeFuto reEditWord autoFixAdjacent
  contextualEnglish shortcutsEnabled templatesEnabled clipboardHistory numberChips mathResults
  emojiSuggest pasteButton addTonesChip hapticFeedback keySound numberRow teencode wallpaperEnabled
  debugTouchLog)
for k in $FEATURES keyboardTheme keyboardTransparency keyLabelTransparency keySoundStyle wallpaperDim; do
  xcrun simctl spawn $DEV defaults delete $PL $k >/dev/null 2>&1
done
dw kbFullAccess -bool true
dw plusUnlocked -bool true
dw uiLanguage vi
case $CFG in
  all)
    for k in $FEATURES; do [[ $k == debugTouchLog ]] || dw $k -bool true; done
    dw keyboardTheme peach
    dw keyboardTransparency -int 30
    dw keySoundStyle mechanical
    dw wallpaperDim -int 30
    # ảnh nền 1080px cạnh dài như app lưu (Wallpaper.prepare) — ảnh chụp store trong repo
    sips -s format jpeg -s formatOptions 70 -Z 1080 $HERE/../../store-assets/6.9/01-onboarding.png \
      --out $GROUP/wallpaper.jpg >/dev/null || echo "không tạo được wallpaper.jpg"
    dw wallpaperVersion -float $(date +%s)
    ;;
  off)
    for k in $FEATURES; do dw $k -bool false; done
    ;;
  default) ;;
  *) echo "cấu hình lạ: $CFG"; exit 1 ;;
esac
# Clipboard có vài mục cho panel
print -n "RAM audit clipboard sample $(date)" | xcrun simctl pbcopy $DEV

pkill -f "$DEV/.*VietTelexKeyboard.appex/VietTelexKeyboard" 2>/dev/null
xcrun simctl terminate $DEV com.viettelex.ramdrv.host >/dev/null 2>&1
sleep 2

if [[ ! -d $DRV/RamDrv.xcodeproj ]]; then
  xcodegen generate --spec $HERE/project.yml --project $DRV --project-root $HERE >/dev/null || exit 1
fi
if [[ ! -d $DRV/dd/Build/Products ]]; then
  xcodebuild -project $DRV/RamDrv.xcodeproj -scheme RamHost -destination "id=$DEV" \
    -derivedDataPath $DRV/dd build-for-testing >$DRV/build.log 2>&1 || { tail -20 $DRV/build.log; exit 1; }
fi
XCTESTRUN=$(ls $DRV/dd/Build/Products/*.xctestrun | head -1)
TEST_RUNNER_RAM_SYNC=$OUT/sync TEST_RUNNER_RAM_CYCLES=$CYCLES \
  xcodebuild test-without-building -xctestrun $XCTESTRUN -destination "id=$DEV" \
  -only-testing:RamDriverUITests/RamDriverUITests/testRamAudit >$OUT/driver.log 2>&1 &
XPID=$!

kbpid() { pgrep -o -f "^/.*$DEV/.*VietTelexKeyboard.appex/VietTelexKeyboard$" }

sample() {   # $1 = tên mốc
  local p=$(kbpid)
  [[ -z $p ]] && { echo "$1 NO-PROCESS" >>$OUT/samples/missing.txt; return; }
  echo $p >$OUT/samples/$1.pid
  footprint -p $p >$OUT/samples/$1.footprint 2>&1
  vmmap --summary $p >$OUT/samples/$1.vmmap 2>&1
  heap -s $p >$OUT/samples/$1.heap 2>&1
}

memwarn() {
  # UIKit simulator nghe notify "com.apple.system.lowmemory"? không chắc → gửi cả hai đường:
  # (1) mức áp lực bộ nhớ của hệ (memorystatus, dispatch memorypressure source của UIKit),
  # (2) notify thử nghiệm. Kết quả thật đọc ở log (didReceiveMemoryWarning) — xem RAM-AUDIT.md.
  # Đường Simulator "Simulate Memory Warning" dùng: ghi file SIMULATOR_MEMORY_WARNINGS
  # (CoreSimulator, UIKit sim theo dõi file này).
  local f=$(xcrun simctl getenv $DEV SIMULATOR_MEMORY_WARNINGS 2>/dev/null)
  [[ -n $f ]] && { mkdir -p ${f:h}; rm -f $f; date +%s >$f }   # phải TẠO MỚI file mới bắn
  xcrun simctl spawn $DEV notifyutil -p com.apple.system.lowmemory >/dev/null 2>&1
  xcrun simctl spawn $DEV notifyutil -p com.apple.system.memorystatus >/dev/null 2>&1
}

while kill -0 $XPID 2>/dev/null; do
  for m in $OUT/sync/*.mark(N); do
    local n=${m:t:r}
    [[ -e $OUT/sync/$n.ack ]] && continue
    if [[ $n == [0-9][0-9]-memwarn ]]; then
      sample ${n}-before
      ${RAM_MEMWARN_CMD:-memwarn}
      sleep 3
    fi
    sample $n
    echo "mốc $n: $(grep -m1 phys_footprint: $OUT/samples/$n.footprint 2>/dev/null)"
    touch $OUT/sync/$n.ack
  done
  sleep 0.5
done
grep -E "TEST (SUCC|FAIL)|error:|XCTAssert" $OUT/driver.log | head -5
python3 $HERE/summarize.py $OUT
