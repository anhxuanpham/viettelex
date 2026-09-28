#!/bin/zsh
# Rò rỉ qua ẩn/hiện bàn phím, KHÔNG dùng XCUITest (không bật runtime Accessibility):
# app chủ tự đổi first responder mỗi 1,5 s (`-autocycle N`). In footprint + số KeyboardView
# còn sống sau mỗi ~10 vòng. Cần RamHost đã cài (ram-audit.sh build một lần).
#   leak-cycle.sh [cycles=30] [device-udid]
set -u
N=${1:-30}
DEV=${2:-904A6001-5753-403F-98B3-BBB46852534B}
kbpid() { pgrep -o -f "^/.*$DEV/.*VietTelexKeyboard.appex/VietTelexKeyboard$" }
count() {   # footprint + số instance KeyboardView / KeyButton
  local p=$(kbpid)
  [[ -z $p ]] && { echo "$1: không có process"; return; }
  local foot=$(footprint -p $p 2>/dev/null | grep -m1 "phys_footprint:" | awk '{print $2, $3}')
  local kv=$(heap -s $p 2>/dev/null | awk '$4 == "KeyboardView" {print $1}')
  local kb=$(heap -s $p 2>/dev/null | awk '$4 == "KeyboardView.KeyButton" {print $1}')
  echo "$1: pid=$p footprint=$foot KeyboardView=${kv:-0} KeyButton=${kb:-0}"
}
xcrun simctl terminate $DEV com.viettelex.ramdrv.host >/dev/null 2>&1
pkill -f "$DEV/.*RamDriverUITests-Runner" 2>/dev/null
pkill -f "$DEV/.*VietTelexKeyboard.appex/VietTelexKeyboard" 2>/dev/null
sleep 2
xcrun simctl launch $DEV com.viettelex.ramdrv.host -autocycle $N >/dev/null
sleep 4
count "vòng 0"
for ((i = 10; i <= N; i += 10)); do
  sleep 30        # 10 vòng × (1,5 s ẩn + 1,5 s hiện)
  count "vòng $i"
done
