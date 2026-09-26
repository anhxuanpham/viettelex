# Nguồn dữ liệu & giấy phép

Mã nguồn VietTelex theo [MIT](../LICENSE). Một số **file dữ liệu** đóng gói trong app có
nguồn và giấy phép riêng, ghi dưới đây.

## vnbigram.bin — bigram âm tiết cho gõ vuốt

`iOS/Keyboard/Resources/vnbigram.bin` = `android/app/src/main/assets/vnbigram.bin`
(~1,2 MB, 400.807 cặp). Sinh bởi `Scripts/gen-syllable-bigram.py`. Chỉ chứa **số liệu
thống kê**: với mỗi cặp âm tiết liền nhau (a, b) là một byte PMI đã lượng tử hoá. Không
chứa câu hay đoạn văn nào của nguồn.

### Nguồn

| Nguồn | Bản dùng | Giấy phép | Trọng số | Âm tiết đếm |
|---|---|---|---|---|
| [Wikipedia tiếng Việt](https://vi.wikipedia.org) | CirrusSearch dump `viwiki-20251229-cirrussearch-content.json.gz`, 600 MB nén đầu | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | ×1 | 57,5 tr |
| [Wikisource tiếng Việt](https://vi.wikisource.org) | `viwikisource-20251229-cirrussearch-content` | CC BY-SA 4.0 (nhiều tác phẩm là phạm vi công cộng) | ×1 | 33,0 tr |
| [Wikibooks](https://vi.wikibooks.org), [Wikivoyage](https://vi.wikivoyage.org), [Wikiquote](https://vi.wikiquote.org) tiếng Việt | `…-20251229-cirrussearch-content` | CC BY-SA 4.0 | ×1 / ×1 / ×2 | 2,6 / 1,3 / 0,6 tr |
| [Tatoeba](https://tatoeba.org) (câu tiếng Việt) | `downloads.tatoeba.org/exports/per_language/vie/vie_sentences.tsv.bz2` (09/2026) | [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/) | ×30 | 0,25 tr |

Dump Wikimedia lấy tại https://dumps.wikimedia.org/other/cirrussearch/20251229/ (trường
`text` đã là văn bản thuần). Tatoeba nhỏ nhưng là câu hội thoại, gần văn phong bàn phím
nhất ⇒ trọng số cao (chọn trên tập dev, xem dưới).

### Giấy phép của vnbigram.bin

Số đếm n-gram là dữ liệu thống kê, nhưng để an toàn ta **coi vnbigram.bin là tác phẩm
phái sinh** của các nguồn trên và phát hành nó theo **CC BY-SA 4.0** (Tatoeba CC BY 2.0 FR
cho phép gộp vào tác phẩm CC BY-SA khi ghi công). Hệ quả:

- Dùng thương mại được (cả CC BY-SA lẫn CC BY đều cho phép).
- ShareAlike chỉ áp lên **file dữ liệu** (và bản sửa của nó), không lên mã nguồn app đọc
  nó — mã vẫn MIT.
- Phải ghi công khi phân phối (app + repo). Ghi công đặt ở: file này, mục "Giới thiệu"
  trong app iOS/Android (dòng "Dữ liệu gõ vuốt…", mở trang này), header fixture kiểm thử.

**Thông báo ghi công** (dùng nguyên văn khi phân phối lại vnbigram.bin):

> vnbigram.bin chứa số liệu thống kê bigram âm tiết suy ra từ nội dung Wikipedia,
> Wikisource, Wikibooks, Wikivoyage và Wikiquote tiếng Việt (© các tác giả Wikimedia,
> CC BY-SA 4.0) và từ câu tiếng Việt của Tatoeba (© các thành viên Tatoeba, CC BY 2.0 FR).
> Đã biến đổi: tách âm tiết, đếm cặp liền nhau, chuyển thành PMI lượng tử hoá 1 byte.
> vnbigram.bin phát hành theo CC BY-SA 4.0.

### Nguồn KHÔNG dùng (và lý do)

- **OpenSubtitles thô / OPUS OpenSubtitles**: phụ đề thuộc bản quyền phim + người dịch;
  điều khoản của opensubtitles.org/OPUS không cấp rõ quyền phân phối số liệu phái sinh
  cho app thương mại.
- **Báo điện tử (VnExpress, Tuổi Trẻ…), corpus VLSP / corpus tin tức cào web**: bản
  quyền thuộc toà soạn; phần lớn chỉ cho phép dùng nghiên cứu.
- **Common Crawl / OSCAR / CC-100**: bản quyền từng trang không xác định (bộ dữ liệu chỉ
  cấp phép phần đóng gói), không đủ rõ cho repo công khai + app thương mại.

### Tái tạo

Lệnh đầy đủ ở docstring `Scripts/gen-syllable-bigram.py` (tải dump về thư mục tạm →
`count` → `build` → copy sang assets Android). Dữ liệu thô **không** commit. Định dạng
file ở cùng docstring và `iOS/Keyboard/SyllableBigram.swift`.

- Tách âm tiết: NFC, chữ thường, kiểu dấu cũ như vnlexicon (hòa, thủy); chỉ giữ âm
  tiết có trong vnlexicon; chuỗi đứt ở dấu câu/số/từ lạ.
- Điểm: PMI chiết khấu `ln((c(a,b) − 0.5)·N / (c(a)·c(b)))`, giữ khi đếm thô ≥ 3 và
  PMI ≥ 0.25, lượng tử `round(pmi·16)`.
- Câu có `blake2b(câu) % 20 == 0` là **tập kiểm thử**, `== 1` là **tập dev** — cả hai bị
  loại khỏi phép đếm. Trọng số nguồn/hệ số chấm điểm chỉnh trên tập dev.

### Đo (27/09/2026)

Tập kiểm thử: `iOS/KeyboardTests/Fixtures/bigram-heldout.txt` (1.674 câu Tatoeba giữ lại,
12.027 vị trí có âm tiết trước). Đường vuốt giả σ = 0.25 phím; "top-3" = từ chèn + 2
phương án đầu trên thanh gợi ý. Người dùng mới (không dữ liệu cá nhân):

| | top-1 | top-3 |
|---|---|---|
| Trước (tần suất unigram) | 70,4 % | 86,5 % |
| Sau (+ bigram tĩnh, trọng số 0.3/nat, trần 1.2) | **85,6 %** | **94,8 %** |

Test hồi quy: `SyllableBigramTests` (iOS + Android) — ngưỡng top-1 ≥ 84 %, top-3 ≥ 93,5 %,
và các cặp điển hình (không có, cho tôi, hôm nay, ngay lập, môi trường, một nửa…) phải
lên top-1.

## vnlexicon.bin — danh sách âm tiết + tần suất

Có từ trước (không đổi trong đợt bigram); nguồn ghi ở `Scripts/gen-vnlexicon.py`:
danh sách 7.184 âm tiết của hieuthi (gist GitHub) và tần suất từ
[hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) (nội dung
CC BY-SA 4.0 theo README dự án; số liệu suy ra từ OpenSubtitles). Cần rà soát giấy phép
gist hieuthi nếu phát hành lại vnlexicon.bin độc lập.
