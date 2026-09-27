// Bảng sửa văn bản — view thay chỗ phím chữ (mở bằng icon con trỏ trên thanh gợi ý).
// Lưới do TextEditing.grid quyết định (nút iOS không làm được không có mặt — xem đầu
// TextEditing.swift). Mũi tên / xoá chạy lúc chạm và lặp khi giữ; nút khác chạy lúc nhấc.
import UIKit

final class EditPanelView: UIView {
    private let onAction: (TextEditAction) -> Void
    private var buttons: [(TextEditAction, UIButton)] = []
    private let fill: UIColor
    private let pressed: UIColor
    private let ink: UIColor
    private var repeatTimer: Timer?
    private var repeatAction: TextEditAction?

    init(dark: Bool, fill: UIColor, pressed: UIColor, oneHandAvailable: Bool, caps: TextEditing.Caps,
         onAction: @escaping (TextEditAction) -> Void) {
        self.onAction = onAction
        self.fill = fill
        self.pressed = pressed
        self.ink = dark ? .white : .black
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = KeyboardView.touchableClear
        let rows = UIStackView()
        rows.axis = .vertical
        rows.distribution = .fillEqually
        rows.spacing = 10
        rows.isLayoutMarginsRelativeArrangement = true
        rows.layoutMargins = UIEdgeInsets(top: 10, left: 3, bottom: 0, right: 3)
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leftAnchor.constraint(equalTo: leftAnchor),
            rows.rightAnchor.constraint(equalTo: rightAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for line in TextEditing.grid(oneHandAvailable: oneHandAvailable) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 6
            for cell in line {
                guard let a = cell else { row.addArrangedSubview(UIView()); continue }
                let b = makeButton(a)
                buttons.append((a, b))
                row.addArrangedSubview(b)
            }
            rows.addArrangedSubview(row)
        }
        update(caps: caps)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { repeatTimer?.invalidate() }

    override func removeFromSuperview() {
        stopRepeat()
        super.removeFromSuperview()
    }

    /// Bật/tắt Sao chép / Cắt / Dán theo quyền + vùng chọn hiện tại.
    func update(caps: TextEditing.Caps) {
        for (a, b) in buttons {
            let on = TextEditing.isEnabled(a, caps: caps)
            b.isEnabled = on
            b.alpha = on ? 1 : 0.35
        }
    }

    private func makeButton(_ a: TextEditAction) -> UIButton {
        let b = UIButton(type: .custom)
        b.backgroundColor = fill
        b.layer.cornerRadius = KeyboardView.keyRadius
        b.isMultipleTouchEnabled = true
        let glyph = a == .left || a == .right || a == .up || a == .down || a == .lineStart || a == .lineEnd
        b.titleLabel?.font = .systemFont(ofSize: glyph ? 22 : 15, weight: .regular)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.7
        b.setTitle(TextEditing.title(a), for: .normal)
        b.setTitleColor(ink, for: .normal)
        b.tintColor = ink
        switch a {
        case .delete: b.setImage(UIImage(systemName: "delete.left"), for: .normal)
        case .oneHand: b.setImage(UIImage(systemName: "hand.raised",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)), for: .normal)
        default: break
        }
        b.accessibilityLabel = Self.accessibility(a)
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            b.backgroundColor = self.pressed
            KeyboardView.clickModifier()
            if a.repeats { self.onAction(a); self.startRepeat(a) }
        }, for: .touchDown)
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            b.backgroundColor = self.fill
            self.stopRepeat()
        }, for: [.touchUpOutside, .touchCancel])
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            b.backgroundColor = self.fill
            self.stopRepeat()
            if !a.repeats { self.onAction(a) }
        }, for: .touchUpInside)
        return b
    }

    private func startRepeat(_ a: TextEditAction) {
        stopRepeat()
        repeatAction = a
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self, self.repeatAction == a else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                guard let self, let r = self.repeatAction else { return }
                self.onAction(r)
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatAction = nil
    }

    private static func accessibility(_ a: TextEditAction) -> String {
        switch a {
        case .left: return "Con trỏ sang trái"
        case .right: return "Con trỏ sang phải"
        case .up: return "Lên một dòng"
        case .down: return "Xuống một dòng"
        case .lineStart: return "Đầu dòng"
        case .lineEnd: return "Cuối dòng"
        case .delete: return "Xoá"
        case .close: return "Về bàn phím chữ"
        case .oneHand: return "Bật tắt chế độ một tay"
        default: return TextEditing.title(a)
        }
    }

    #if DEBUG
    /// Test hook: các nút đang có (theo thứ tự lưới) + bật/tắt.
    var debugButtons: [(TextEditAction, Bool)] { buttons.map { ($0.0, $0.1.isEnabled) } }
    func debugTap(_ a: TextEditAction) {
        guard let b = buttons.first(where: { $0.0 == a })?.1 else { return }
        b.sendActions(for: .touchDown)
        b.sendActions(for: .touchUpInside)
    }
    #endif
}
