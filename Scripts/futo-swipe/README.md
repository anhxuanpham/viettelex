# Scripts/futo-swipe — encoder FUTO Swipe cho gõ vuốt (thử nghiệm)

Công cụ python3 **stdlib** (không torch/onnx/executorch) để lấy kiến trúc + weights encoder
**FUTO Swipe** "honorable_sturgeon" (https://huggingface.co/futo-org/futo-swipe) và đóng gói cho
VietTelex. Weights theo **FUTO Model Weights License 1.0** — xem `docs/DATA-SOURCES.md` mục
*FUTO Swipe* và bản giấy phép kèm file `futoswipe-LICENSE.md` (iOS Resources / Android assets).
Powered by FUTO Swipe.

`futoswipe.bin` là **Derivative Model đã chỉnh sửa**: weights tách khỏi chương trình ExecuTorch,
chuyển fp32 → fp16, xếp lại bố cục phẳng. Không huấn luyện lại.

| File | Việc |
|---|---|
| `fb.py`, `pte.py` | đọc flatbuffer `.pte` (ExecuTorch) + blob XNNPACK theo schema công khai (BSD) |
| `interp.py` | trình thông dịch python thuần cho đồ thị `.pte` — **chuẩn tham chiếu** |
| `convert.py` | `.pte` → `futoswipe.bin` (header `VTFS` v1 + 633 988 số fp16, thứ tự cố định) |
| `mine.py` | forward tự viết (y hệt Swift/Kotlin) đọc `futoswipe.bin` |
| `verify.py` | `mine.py` (weights fp32) vs `interp.py` trên đồ thị gốc: max |Δ| ≈ 4e-6 |
| `gen_fixture.py` | fixture parity `iOS/KeyboardTests/Fixtures/futo-swipe-fixture.txt` |
| `build.sh` | tải `.pte` (pin revision + sha256) → convert → verify → copy asset → fixture |

Không dùng code GPL của FUTO (swipe-library): suy luận viết lại từ đồ thị; decoder CTC + trie
là của VietTelex (`iOS/Keyboard/FutoSwipe*.swift`, `android/.../FutoSwipe*.kt`).
