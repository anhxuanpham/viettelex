#!/bin/zsh
# Đánh giá decoder gõ vuốt (bản Kotlin, cùng thuật toán/hằng số với iOS) trên nét vuốt THẬT
# xuất từ "Luyện vuốt" trong app iOS/Android (Cài đặt → Gõ vuốt → Luyện vuốt → Xuất JSON).
# In top-1/top-3 theo decoder hiện tại, top-1 lúc ghi, tách Việt/Anh, và các nét sai.
#
#   Scripts/eval-swipe-traces.sh ~/Downloads/viettelex-swipe-traces.json
#
# Chạy hoàn toàn trên máy (JUnit: SwipePracticeTests.evaluateExportedTraces).
set -e
f=${1:?"cách dùng: $0 viettelex-swipe-traces.json"}
f=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
cd "$(dirname "$0")/../android"
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
SWIPE_TRACES="$f" ./gradlew --offline -q :keyboard:test --rerun \
  --tests 'com.viettelex.keyboard.SwipePracticeTests.evaluateExportedTraces' -i | grep 'SWIPE_TRACES'
