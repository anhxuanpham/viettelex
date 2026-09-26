# Nguồn dữ liệu & giấy phép

Dữ liệu tĩnh đóng gói trong bàn phím iOS/Android, nguồn gốc và điều kiện dùng lại. Dữ liệu
thô KHÔNG commit vào repo — script trong `Scripts/` tải về và sinh lại file nhị phân.

## Từ điển tiếng Anh cho gõ vuốt — `enlexicon.bin`

- File: `iOS/Keyboard/Resources/enlexicon.bin`, `android/app/src/main/assets/enlexicon.bin`
  (y hệt nhau, ~180 KB, 20.000 từ chữ thường a–z + tần suất 1 byte).
- Sinh bởi: `Scripts/gen-enlexicon.py` (python3 stdlib).
  ```
  python3 Scripts/gen-enlexicon.py --download <thư_mục_tạm>
  python3 Scripts/gen-enlexicon.py <thư_mục_tạm>
  ```
- Dùng cho: gõ vuốt giai đoạn 3 (vuốt ra từ tiếng Anh xen trong câu Việt), công tắc
  "Vuốt từ tiếng Anh".

### Nguồn

1. **Google Books Ngram Corpus** (phiên bản 20200217, sách xuất bản 2010–2019), qua danh
   sách đã làm sạch của dự án **google-books-ngram-frequency** (orgtre):
   `ngrams/1grams_english.csv` và `ngrams/1grams_english-fiction.csv`, mỗi file 10.000 từ
   phổ biến nhất kèm số lần xuất hiện. Ghim commit
   `6a72a4d96a2c36717479e9e9bf4e24260b3dbdae`.
   - Giấy phép: **Creative Commons Attribution 3.0 Unported (CC BY 3.0)** — cả bộ dữ liệu
     Google Books Ngram lẫn nội dung repo orgtre. Cho phép dùng thương mại, sửa đổi, phân
     phối lại; điều kiện: ghi công.
   - Ghi công: *"Google Books Ngram Viewer data, © Google, CC BY 3.0
     (https://books.google.com/ngrams); cleaned lists by orgtre/google-books-ngram-frequency
     (https://github.com/orgtre/google-books-ngram-frequency), CC BY 3.0."*
   - Chúng tôi đã sửa đổi: lọc, gộp hai danh sách, quy tần suất về thang 1 byte.
2. **wikipedia-word-frequency** (Ilya Semenov): `results/enwiki-2023-04-13.txt` — tần suất từ
   trong Wikipedia tiếng Anh. Chỉ dùng để BỔ SUNG từ phổ biến không có trong danh sách sách
   (google, facebook, website…) và lấy tần suất cho nguồn 3. Ghim commit
   `798ea9062d6e5aed1fa87deeeda1cd99d5b37903`.
   - Giấy phép: **MIT** (Copyright (c) 2015 Ilya Semenov) —
     https://github.com/IlyaSemenov/wikipedia-word-frequency. Chỉ dùng số đếm (dữ kiện
     thống kê), không chứa văn bản Wikipedia.
3. **Dữ liệu của chính repo**: các bảng `neutralLoanwords` / `words` / `restoreOnly` trong
   `TelexCore/Sources/TelexCore/EnglishContextWords.swift` (từ mượn/tên app hay chen trong
   câu Việt: wifi, login, zalo, shopee…) — luôn có mặt trong từ điển.

### Lọc & chuẩn hoá

- Chỉ giữ `^[a-z]{2,}$`; bỏ từ tục/xúc phạm/tình dục thô (danh sách trong script + các từ
  ASCII của `iOS/Keyboard/SensitiveWords.swift`).
- Phần bổ sung từ Wikipedia: ≥ 3 chữ, không trùng dạng không dấu của âm tiết Việt (loại
  tên riêng tiếng Việt như tran, nguyen), không phải số La Mã; lấy theo hạng tới khi đủ
  20.000 từ tổng.
- Tần suất: tỉ lệ token quy về cùng thang với `vnlexicon.bin` (255·ln(count)/ln(max) trên
  corpus OpenSubtitles tiếng Việt ~26,4 triệu token) để decoder so hai từ điển trên một thang.

## Từ điển tiếng Việt — `vnlexicon.bin` (đã có từ trước)

Sinh bởi `Scripts/gen-vnlexicon.py`; nguồn ghi trong docstring của script:

- 7.184 âm tiết tiếng Việt xếp theo tần suất (hieuthi):
  https://gist.github.com/hieuthi/1f5d80fca871f3642f61f7e3de883f3a
- Tần suất hội thoại OpenSubtitles tiếng Việt, `vi_50k.txt` của
  **hermitdave/FrequencyWords** (https://github.com/hermitdave/FrequencyWords) — README ghi
  "MIT License for code, CC-by-sa-4.0 for content".
