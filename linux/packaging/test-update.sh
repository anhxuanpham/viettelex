#!/bin/sh
# E2E cập nhật một chạm: bản đã phát hành OLD (GitHub Releases) → bản vừa build NEW
# (linux/dist từ build-all.sh), trong Ubuntu sạch cho mọi series × arch. Chạy trên HOST có docker.
# Không ký, không đẩy gì lên mạng: kho APT thử dựng cục bộ bằng apt-repo.sh --no-sign.
#
#   linux/packaging/test-update.sh --old 1.0.3 [--series "jammy noble"] [--arch "amd64 arm64"]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DIST="$REPO/linux/dist"
OLD=""
SERIES_LIST="jammy noble"
ARCH_LIST="amd64 arm64"
while [ $# -gt 0 ]; do
  case "$1" in
    --old) OLD=$2; shift ;;
    --series) SERIES_LIST=$2; shift ;;
    --arch) ARCH_LIST=$2; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$OLD" ] || { echo "usage: $0 --old <bản đã phát hành, vd 1.0.3>" >&2; exit 2; }
NEW=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$REPO/linux/settings/viettelex_settings/__init__.py")
[ "$OLD" != "$NEW" ] || { echo "OLD = NEW = $NEW — build bản mới trước (build-all.sh)" >&2; exit 2; }
ubuntu_of() { case "$1" in jammy) echo 22.04 ;; noble) echo 24.04 ;; *) echo "$1" ;; esac; }

WORK="$DIST/.e2e"          # dưới linux/dist (đã .gitignore), docker mount được
rm -rf "$WORK"; mkdir -p "$WORK/rel" "$WORK/fake/dist"
trap 'rm -rf "$WORK"' EXIT
GH="https://github.com/ptrinh/viettelex/releases/download/linux-v$OLD"
for s in $SERIES_LIST; do
  ls "$DIST/$s"/*"_$NEW~${s}1_"*.deb >/dev/null 2>&1 || { echo "thiếu linux/dist/$s/*_$NEW~${s}1_*.deb" >&2; exit 1; }
  cp -R "$DIST/$s" "$WORK/fake/dist/$s"
  for p in libviettelex-core viettelex-fcitx5 viettelex-ibus; do
    for a in $ARCH_LIST; do
      curl -fsSL -o "$WORK/rel/${p}_$OLD.${s}1_$a.deb" "$GH/${p}_$OLD.${s}1_$a.deb"
    done
  done
  curl -fsSL -o "$WORK/rel/viettelex-settings_$OLD.${s}1_all.deb" "$GH/viettelex-settings_$OLD.${s}1_all.deb"
done
cp "$REPO/docs/stable.json" "$WORK/fake/stable.json"
python3 "$HERE/stable-linux.py" --dist "$WORK/fake/dist" --stable "$WORK/fake/stable.json" \
  --sums "$WORK/fake/SHA256SUMS" >/dev/null
sh "$HERE/apt-repo.sh" --no-sign --dist "$WORK/fake/dist" --out "$WORK/fake/repo" >/dev/null

rc=0
for s in $SERIES_LIST; do
  for a in $ARCH_LIST; do
    echo "==> update e2e $s/$a ($OLD → $NEW)"
    docker run --rm --platform "linux/$a" -e OLD="$OLD" -e NEW="$NEW" \
      -v "$REPO:/src:ro" -v "$WORK/fake:/fake:ro" -v "$WORK/rel:/rel:ro" \
      -v "$HERE/docker/update-e2e.sh:/e2e.sh:ro" "ubuntu:$(ubuntu_of "$s")" bash /e2e.sh \
      > "$WORK/$s-$a.log" 2>&1 || true
    grep -E "^(###|FAIL)" "$WORK/$s-$a.log"
    grep -q "FAILS=0" "$WORK/$s-$a.log" || { rc=1; tail -30 "$WORK/$s-$a.log"; }
  done
done
[ $rc = 0 ] && echo "UPDATE E2E OK" || echo "UPDATE E2E FAILED" >&2
exit $rc
