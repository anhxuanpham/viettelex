import XCTest

/// Tab Mẫu Câu: thêm/sửa mẫu câu (App/TemplateEdit.swift). Lỗi người dùng báo 27/09/2026:
/// nhập label "Ig😊" + câu dài có "→"/"&" bấm ⊕ "không thêm được" — thật ra lần bấm đầu
/// ĐÃ thêm nhưng ô nhập không xoá (SwiftUI reset binding lúc bàn phím còn chữ đang soạn),
/// nút xám; sửa lại thì trùng → `return` IM LẶNG. Giờ mọi lần từ chối đều có lý do.
final class TemplateEditTests: XCTestCase {
    private let base = [
        TemplateItem(label: "👋", text: "Chào buổi sáng"),
        TemplateItem(label: "", text: "Cảm ơn nhiều nhé!"),
    ]

    func testAddUserReportedTemplate() {
        let label = "Ig😊"
        let text = "Vào Cài đặt → Avatar iCloud → Phương tiện & Mục mua"
        guard case .ok(let out) = TemplateEdit.add(base, label: label, text: text) else {
            return XCTFail("phải thêm được")
        }
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out.last, TemplateItem(label: label, text: text))
        // Khứ hồi YAML (bàn phím + export đọc cùng định dạng) giữ nguyên label emoji + "→"/"&".
        XCTAssertEqual(TemplateEdit.parseYAML(TemplateEdit.exportYAML(out)), out)
    }

    func testTrimsWhitespaceAndNewlinesIncludingLabel() {
        guard case .ok(let out) = TemplateEdit.add([], label: " Ig😊\n", text: "\n  Đi nhé  \n") else {
            return XCTFail()
        }
        XCTAssertEqual(out, [TemplateItem(label: "Ig😊", text: "Đi nhé")])
    }

    func testEmptyIsRejectedWithMessage() {
        XCTAssertEqual(TemplateEdit.add(base, label: "Ig😊", text: "  \n "), .rejected(.emptyText))
        XCTAssertFalse(TemplateEdit.message(.emptyText, items: base).isEmpty)
    }

    func testDuplicateIsRejectedWithLineNumber() {
        let r = TemplateEdit.add(base, label: "khác", text: " Cảm ơn nhiều nhé! ")
        XCTAssertEqual(r, .rejected(.duplicate(index: 1)))
        XCTAssertTrue(TemplateEdit.message(.duplicate(index: 1), items: base).contains("dòng 2"))
        XCTAssertTrue(TemplateEdit.message(.duplicate(index: 0), items: base).contains("👋"))
    }

    /// Câu gõ bằng bàn phím khác nhau có thể ra NFC hoặc NFD — vẫn phải coi là trùng.
    func testDuplicateAcrossUnicodeNormalization() {
        let nfd = "Cảm ơn nhiều nhé!".decomposedStringWithCanonicalMapping
        XCTAssertEqual(TemplateEdit.add(base, label: "", text: nfd), .rejected(.duplicate(index: 1)))
    }

    func testNoItemLimit() {
        let many = (0..<500).map { TemplateItem(label: "", text: "câu \($0)") }
        guard case .ok(let out) = TemplateEdit.add(many, label: "Ig😊", text: "mới") else { return XCTFail() }
        XCTAssertEqual(out.count, 501)
    }

    func testUpdate() {
        guard case .ok(let out) = TemplateEdit.update(base, at: 0, label: "Ig😊", text: "Chào") else {
            return XCTFail()
        }
        XCTAssertEqual(out[0], TemplateItem(label: "Ig😊", text: "Chào"))
        // Giữ nguyên câu của chính dòng đó không tính là trùng.
        if case .rejected = TemplateEdit.update(base, at: 1, label: "x", text: "Cảm ơn nhiều nhé!") { XCTFail() }
        XCTAssertEqual(TemplateEdit.update(base, at: 0, label: "", text: "Cảm ơn nhiều nhé!"),
                       .rejected(.duplicate(index: 1)))
        XCTAssertEqual(TemplateEdit.update(base, at: 0, label: "", text: " "), .rejected(.emptyText))
    }
}
