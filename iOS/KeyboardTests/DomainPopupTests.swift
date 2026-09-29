// DomainPopupTests — giữ "." / ".com" ở ô địa chỉ/URL/email ra hàng đuôi tên miền như stock,
// và chip đuôi mail sau "@" ở ô email (EmailDomains).
import XCTest
import UIKit

final class DomainPopupTests: XCTestCase {
    // MARK: lựa chọn theo loại ô

    func testChoicesPerField() {
        let t = DomainPopup.tlds
        XCTAssertEqual(t, [".com", ".vn", ".net", ".org", ".edu"], ".com mặc định, .vn thứ hai")
        XCTAssertEqual(DomainPopup.choices(kind: .search, key: ".", lettersPlane: true), t)
        XCTAssertEqual(DomainPopup.choices(kind: .url, key: ".", lettersPlane: true), t)
        XCTAssertEqual(DomainPopup.choices(kind: .url, key: ".com", lettersPlane: true), t)
        XCTAssertEqual(DomainPopup.choices(kind: .email, key: ".", lettersPlane: true), t)
        XCTAssertEqual(DomainPopup.choices(kind: .url, key: "/", lettersPlane: true), [])
        XCTAssertEqual(DomainPopup.choices(kind: .email, key: "@", lettersPlane: true), [])
        XCTAssertEqual(DomainPopup.choices(kind: .search, key: ",", lettersPlane: true), [])
        XCTAssertEqual(DomainPopup.choices(kind: .normal, key: ".", lettersPlane: true), [], "ô thường: không")
        XCTAssertEqual(DomainPopup.choices(kind: .number, key: ".", lettersPlane: true), [])
        XCTAssertEqual(DomainPopup.choices(kind: .url, key: ".", lettersPlane: false), [], "chỉ bàn chữ")
    }

    // MARK: bố cục + chỉ số dưới ngón

    func testLayoutLeftToRightWhenRoomOnRight() {
        let l = DomainPopup.layout(keyMidX: 60, itemWidth: 56, count: 5, containerWidth: 390)
        XCTAssertFalse(l.mirrored)
        XCTAssertEqual(l.originX, 32)
        XCTAssertEqual(l.slotMinX(0), 32)
        func idx(_ x: CGFloat, _ yy: CGFloat = 20) -> Int? {
            DomainPopup.index(at: CGPoint(x: x, y: yy), startX: 60, layout: l, top: 0, bottom: 60)
        }
        XCTAssertEqual(idx(60), 0, "ô dưới ngón lúc mở = .com")
        XCTAssertEqual(idx(60 + 56), 1)
        XCTAssertEqual(idx(60 + 56 * 4), 4)
        XCTAssertEqual(idx(l.originX + l.width + 10), 4, "lố mép trong ngần: kẹp ô cuối")
        XCTAssertEqual(idx(l.originX - 10), 0)
        XCTAssertNil(idx(l.originX + l.width + DomainPopup.cancelSlackX + 1), "trượt xa ngang ⇒ huỷ")
        XCTAssertNil(idx(l.originX - DomainPopup.cancelSlackX - 1))
        XCTAssertNil(idx(60, -DomainPopup.cancelSlackY - 1), "trượt lên quá ⇒ huỷ")
        XCTAssertNil(idx(60, 60 + DomainPopup.cancelSlackY + 1), "trượt xuống quá ⇒ huỷ")
        XCTAssertEqual(idx(60, 60 + 10), 0, "ngón vẫn trên phím ⇒ chọn")
    }

    func testLayoutMirrorsNearRightEdge() {
        let l = DomainPopup.layout(keyMidX: 350, itemWidth: 56, count: 5, containerWidth: 390)
        XCTAssertTrue(l.mirrored)
        XCTAssertEqual(l.slotMinX(0), 350 - 28, ".com vẫn ngay trên phím")
        XCTAssertGreaterThanOrEqual(l.originX, 2)
        let i = { (x: CGFloat) in DomainPopup.index(at: CGPoint(x: x, y: 10), startX: 350, layout: l, top: 0, bottom: 60) }
        XCTAssertEqual(i(350), 0)
        XCTAssertEqual(i(350 - 56), 1, "loe sang trái: trượt trái ra .vn")
        XCTAssertEqual(i(350 - 56 * 4), 4)
    }

    func testLayoutClampedInsideNarrowContainer() {
        let l = DomainPopup.layout(keyMidX: 150, itemWidth: 56, count: 5, containerWidth: 300)
        XCTAssertGreaterThanOrEqual(l.originX, 2)
        XCTAssertLessThanOrEqual(l.originX + l.width, 298)
        let i = { (x: CGFloat) in DomainPopup.index(at: CGPoint(x: x, y: 10), startX: 150, layout: l, top: 0, bottom: 60) }
        XCTAssertEqual(i(150), 0, "hàng bị kẹp: lúc mở vẫn là .com")
        XCTAssertEqual(i(150 + (l.mirrored ? -56 : 56)), 1)
        XCTAssertEqual(i(150 + (l.mirrored ? -20 : 20)), 0, "dời chưa nửa ô: giữ nguyên")
    }

    // MARK: KeyboardView (iPhone) — đường action thật

    @MainActor private func makeKeyboard(_ kind: KeyboardView.InputKind,
                                         log: @escaping (String) -> Void) -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { k in
            switch k {
            case .letter(let c): log("L\(c.lowercased())")
            case .text(let s): log("T\(s)")
            default: log("?")
            }
        }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.configureInputKind(kind)
        kb.layoutIfNeeded()
        return (kb, host)
    }

    @MainActor func testHoldPeriodInsertsSelectedTLD() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        for kind in [KeyboardView.InputKind.url, .search, .email] {
            var out: [String] = []
            let (kb, host) = makeKeyboard(kind) { out.append($0) }
            XCTAssertFalse(kb.debugDomainPopupMade)
            XCTAssertTrue(kb.debugDomainHold(".", fire: false), "\(kind)")
            XCTAssertEqual(out, ["T."], "chạm thường vẫn ra \".\" (\(kind))")
            XCTAssertFalse(kb.debugDomainPopupMade, "chưa đủ giờ ⇒ không dựng view")
            out = []
            kb.debugDomainHold(".")
            XCTAssertEqual(out, ["T.com"], "\(kind)")
            XCTAssertTrue(kb.debugDomainPopupMade)
            XCTAssertFalse(kb.debugDomainPopupVisible, "nhấc ⇒ popup tắt")
            out = []
            let l = try XCTUnwrap(kb.debugLastDomainLayout)
            kb.debugDomainHold(".", dx: l.mirrored ? -56 : 56)
            XCTAssertEqual(out, ["T.vn"], "\(kind)")
            out = []
            kb.debugDomainHold(".", dy: -300)                     // trượt xa ⇒ huỷ
            XCTAssertEqual(out, [], "\(kind)")
            out = []
            kb.debugDomainHold(".", secondTouch: "a")             // ngón khác chạm: đuôi chốt TRƯỚC
            XCTAssertEqual(out, ["T.com", "La"], "\(kind)")
            withExtendedLifetime(host) {}
        }
    }

    @MainActor func testPopupStaysOpenWhileHeld() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        var out: [String] = []
        let (kb, host) = makeKeyboard(.url) { out.append($0) }
        kb.debugDomainHold(".com", keepOpen: true)
        XCTAssertTrue(kb.debugDomainPopupVisible)
        XCTAssertEqual(kb.debugDomainSelection, ".com")
        XCTAssertEqual(out, [])
        withExtendedLifetime(host) {}
    }

    @MainActor func testOtherFieldsHaveNoPopup() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        var out: [String] = []
        let (kb, host) = makeKeyboard(.url) { out.append($0) }
        XCTAssertFalse(kb.debugDomainHold("/"), "\"/\" không có popup")
        XCTAssertEqual(out, ["T/"])
        let (kb2, host2) = makeKeyboard(.normal) { _ in }
        XCTAssertFalse(kb2.debugDomainHold("."), "ô thường không có phím \".\" hàng đáy")
        XCTAssertFalse(kb2.debugDomainPopupMade)
        withExtendedLifetime((host, host2)) {}
    }

    // MARK: chip đuôi mail (ô email)

    func testEmailChipsAfterAt() {
        let c = EmailDomains.chips(before: "phuc@")
        XCTAssertEqual(c.map(\.label), ["@gmail.com", "@icloud.com", "@yahoo.com"], "gmail trước, tối đa 3")
        XCTAssertEqual(c.first?.insert, "gmail.com", "không lặp \"@\"")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@", limit: 4).map(\.label).last, "@outlook.com")
        XCTAssertEqual(EmailDomains.chips(before: "To: a, phuc@").first?.insert, "gmail.com")
    }

    func testEmailChipsCompletePrefix() {
        XCTAssertEqual(EmailDomains.chips(before: "phuc@gm"), [.init(label: "@gmail.com", insert: "ail.com")])
        XCTAssertEqual(EmailDomains.chips(before: "phuc@GM").first?.insert, "ail.com")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@o").map(\.label), ["@outlook.com"])
        XCTAssertEqual(EmailDomains.chips(before: "phuc@gmail.").first?.insert, "com")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@gmail.co").first?.insert, "m")
    }

    func testEmailChipsGone() {
        XCTAssertEqual(EmailDomains.chips(before: ""), [])
        XCTAssertEqual(EmailDomains.chips(before: "phuc"), [])
        XCTAssertEqual(EmailDomains.chips(before: "@"), [], "phần trước @ rỗng")
        XCTAssertEqual(EmailDomains.chips(before: "hi @"), [])
        XCTAssertEqual(EmailDomains.chips(before: "phuc@gmail.com"), [], "đã đủ")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@abc."), [], "có \".\" mà không khớp")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@senprints"), [])
        XCTAssertEqual(EmailDomains.chips(before: "a@b@"), [], "hai @")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@ "), [], "đã sang token khác")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@", limit: 0), [])
    }

    func testEmailFieldAlwaysHasBar() {
        XCTAssertTrue(FieldTraits(keyboardType: .emailAddress, autocorrection: .no).allowsSuggestions)
        XCTAssertFalse(FieldTraits(keyboardType: .emailAddress, secure: true).allowsSuggestions)
        XCTAssertFalse(FieldTraits(keyboardType: .URL, autocorrection: .no).allowsSuggestions)
        XCTAssertFalse(FieldTraits(autocorrection: .no).allowsSuggestions)
    }
}
