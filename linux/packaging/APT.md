# Kho APT của VietTelex / VietTelex APT repository

Kho: `https://ptrinh.github.io/viettelex-apt/` — Ubuntu 22.04 (jammy) và 24.04 (noble),
amd64 + arm64. Được ký bằng GPG; `apt` tự kiểm chữ ký.

## Cài bằng một lệnh / One-line install

```sh
curl -fsSL https://viettelex.com/install.sh | bash
```

Script (`docs/install.sh`) làm đúng các bước bên dưới: kiểm `InRelease` được ký bởi khoá
`43ADE236BCC43900B8F146B4F57C885055149990` (vân tay ghim trong script), thêm khoá + file
`viettelex.sources`, rồi `apt-get install viettelex` (metapackage; Fcitx5 mặc định, hỏi nếu máy
chỉ có IBus/GNOME) và `im-config -n fcitx5`. Tuỳ chọn: `--ibus`, `--fcitx5`, `--yes`,
`--uninstall`, `--dry-run`. Chạy lại = cập nhật. Cùng script cài bản macOS (Homebrew hoặc .pkg
đã kiểm chữ ký). / The script performs the steps below, pins the repository key fingerprint,
installs the `viettelex` metapackage and supports `--ibus`, `--uninstall` and `--dry-run`.

## Tiếng Việt — cài đặt từng bước

```sh
# 1. Khoá ký của kho
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://ptrinh.github.io/viettelex-apt/viettelex-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/viettelex.gpg >/dev/null

# 2. Khai báo kho (định dạng deb822)
sudo tee /etc/apt/sources.list.d/viettelex.sources >/dev/null <<EOF
Types: deb
URIs: https://ptrinh.github.io/viettelex-apt/
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Signed-By: /etc/apt/keyrings/viettelex.gpg
EOF

# 3. Cài — chọn MỘT bộ khung gõ
sudo apt update
sudo apt install viettelex            # metapackage: engine + app cài đặt + Fcitx5 (khuyên dùng)
# hoặc: sudo apt install viettelex viettelex-ibus   (giữ IBus, mặc định Ubuntu/GNOME)
# (kho cũ chưa có metapackage: sudo apt install viettelex-fcitx5 viettelex-settings)
```

Sau khi cài: mở **VietTelex** trong menu ứng dụng (hoặc `viettelex-settings --onboarding`)
và làm theo hướng dẫn bật bộ gõ. Cập nhật về sau: `sudo apt update && sudo apt upgrade`.

Nút **Giới thiệu → Kiểm tra cập nhật** trong app cũng cập nhật được (một chạm, hỏi mật khẩu qua
polkit): máy có kho APT thì chạy `apt-get install --only-upgrade` các gói VietTelex; cài bằng
.deb thì tải đúng bộ .deb, kiểm SHA256 theo `stable.json` rồi cài.

Gỡ: `curl -fsSL https://viettelex.com/install.sh | bash -s -- --uninstall`, hoặc
`sudo apt remove viettelex viettelex-fcitx5 viettelex-ibus viettelex-settings libviettelex-core`,
rồi xoá `/etc/apt/sources.list.d/viettelex.sources` và `/etc/apt/keyrings/viettelex.gpg`.

## English — install

Run the three steps above (add the key to `/etc/apt/keyrings/viettelex.gpg`, add the
`viettelex.sources` file, then `sudo apt update && sudo apt install viettelex-fcitx5`, or
`viettelex-ibus` for IBus). Then open **VietTelex** from the app menu, or run
`viettelex-settings --onboarding`, and follow the setup guide. `apt upgrade` delivers updates.

## Không dùng kho: tải .deb / Without the repository: download the .deb

Mỗi bản phát hành trên GitHub Releases (`https://github.com/ptrinh/viettelex/releases`) có
các file `.deb` theo series và kiến trúc. Tải đúng bộ (vd Ubuntu 24.04, máy Intel/AMD:
các file `~noble1_amd64.deb` + `viettelex-settings_…~noble1_all.deb`) rồi cài một lệnh:

Each GitHub release ships `.deb` files per series and architecture. Download the matching
set, then install it with one command:

```sh
sudo apt install ./libviettelex-core_*_amd64.deb ./viettelex-fcitx5_*_amd64.deb \
                 ./viettelex-settings_*_all.deb
```

Cách này không tự cập nhật qua apt; nút *Kiểm tra cập nhật* trong app tải + kiểm SHA256 +
cài bản mới. This route does not update through apt; the app's *Kiểm tra cập nhật* button
downloads the new .debs, checks their SHA256 against `stable.json` and installs them.

---

## Dành cho người phát hành / For maintainers

```sh
linux/packaging/build-all.sh                         # linux/dist/{jammy,noble}/*.deb, lintian + smoke test
VT_APT_KEY=<fingerprint> linux/packaging/apt-repo.sh --out ../viettelex-apt
```

- `apt-repo.sh` sinh `pool/main/v/viettelex/`, `dists/<series>/main/binary-{amd64,arm64}/Packages(.gz)`
  và `Release` bằng `apt-ftparchive` (trong container `ubuntu:24.04` nếu host không có). Script ký
  `InRelease` (clearsign) và `Release.gpg` (detached) bằng `gpg` **trên host**, rồi xuất khoá công khai
  ra `viettelex-archive-keyring.gpg` (binary). Khoá bí mật không bao giờ vào container hay repo.
- Mỗi series có phiên bản riêng (`1.0.0~jammy1`, `1.0.0~noble1`), nên pool dùng chung được.
  Gói `_all` lấy từ bản build đầu tiên của series để mọi arch cùng trỏ vào một file.
- Đẩy thư mục output lên repo GitHub Pages `viettelex-apt` (có sẵn `.nojekyll`).
- Đổi/xoay khoá: xuất bản khoá mới cùng lúc với khoá cũ trong một thời gian, và báo người dùng
  tải lại `viettelex-archive-keyring.gpg`. **Nhớ sửa `APT_KEY_FPR` trong `docs/install.sh`** —
  script từ chối kho ký bằng khoá khác. Khoá hiện tại hết hạn 2031-09.
- Gói `viettelex` (metapackage, `_all`) build cùng các gói khác; phụ thuộc
  `libviettelex-core`, `viettelex-settings (=)` và `viettelex-fcitx5 | viettelex-ibus`.
- `viettelex-settings` mang helper `/usr/libexec/viettelex/viettelex-update` + polkit action
  `org.viettelex.update` (`/usr/share/polkit-1/actions/org.viettelex.update.policy`) cho nút
  cập nhật một chạm; helper chỉ nhận các gói VietTelex (danh sách trắng).

### Checklist phát hành Linux

1. Tăng `VERSION` trong `linux/settings/viettelex_settings/__init__.py` + mục mới đầu
   `linux/packaging/debian/changelog` (cùng số).
2. `linux/packaging/build-all.sh` → `linux/dist/{jammy,noble}/*.deb` (lintian + smoke test).
3. `linux/packaging/stable-linux.py --notes "…"` → ghi mục `"linux"` vào `docs/stable.json`
   (phiên bản, link, series, SHA256 từng .deb theo tên asset GitHub — `~` thành `.`) và
   `linux/dist/SHA256SUMS`. Khoá gốc (macOS) và `"windows"` giữ nguyên.
4. `gh release create linux-vX.Y.Z linux/dist/*/*.deb linux/dist/SHA256SUMS --notes-file …`
   (ghi chú theo mẫu dưới). **Tên asset phải đúng như stable.json** — kiểm bằng
   `sha256sum -c` sau khi tải lại vài file.
5. `VT_APT_KEY=… linux/packaging/apt-repo.sh --out ../viettelex-apt` rồi push repo
   `viettelex-apt` (Pages).
6. Commit + push `docs/stable.json` **sau cùng** (khi asset và kho đã có): app cài đặt Linux
   đọc `https://viettelex.com/stable.json` → mục `linux` để báo/cài bản mới.

`stable.json` — mục Linux (app bản ≥ 1.0.4 đọc; macOS/Windows bỏ qua):

```json
"linux": {
  "version": "1.0.4",
  "url": "https://github.com/ptrinh/viettelex/releases/tag/linux-v1.0.4",
  "download": "https://github.com/ptrinh/viettelex/releases/download/linux-v1.0.4/",
  "series": ["jammy", "noble"],
  "sha256": { "libviettelex-core_1.0.4.noble1_amd64.deb": "<sha256>", "…": "…" },
  "notes": "…"
}
```

### Mẫu ghi chú phát hành / Release notes template

```markdown
**Cài / cập nhật bằng một lệnh (Ubuntu 22.04/24.04):**

    curl -fsSL https://viettelex.com/install.sh | bash

Đã cài từ kho APT: `sudo apt update && sudo apt upgrade`, hoặc app VietTelex → Giới thiệu →
Kiểm tra cập nhật. Tải tay: chọn `.jammy1` (22.04) / `.noble1` (24.04) + kiến trúc, rồi
`sudo apt install ./*.deb` — kiểm bằng `sha256sum -c SHA256SUMS --ignore-missing`.

### Thay đổi
- …

---
**One-line install / update:** `curl -fsSL https://viettelex.com/install.sh | bash`
(APT users: `sudo apt update && sudo apt upgrade`.)
```
