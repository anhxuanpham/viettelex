// Bảng sửa văn bản — view thay chỗ phím chữ (mở bằng icon con trỏ trên thanh gợi ý).
// Lưới do TextEditing.grid quyết định (nút iOS không làm được không có mặt — xem đầu
// TextEditing.swift). Mũi tên / xoá chạy lúc chạm và lặp khi giữ; nút khác chạy lúc nhấc.
import UIKit

final class EditPanelView: UIView {
    private let onAction: (TextEditAction) -> Void
    private let onTool: (TextTool) -> Void
    private var toolButtons: [(TextTool, UIButton)] = []
    private var buttons: [(TextEditAction, UIButton)] = []
    private let fill: UIColor
    private let pressed: UIColor
    private let ink: UIColor
    private var repeatTimer: Timer?
    private var repeatAction: TextEditAction?

    /// `tools` rỗng = không có hàng công cụ văn bản (chưa mở khoá Plus / ô bảo mật);
    /// có ⇒ thêm một hàng cuối, chạm gọi `onTool` (controller áp lên phần chọn / câu).
    init(dark: Bool, fill: UIColor, pressed: UIColor, ink: UIColor, oneHandAvailable: Bool,
         tools: [TextTool] = [], caps: TextEditing.Caps,
         onTool: @escaping (TextTool) -> Void = { _ in },
         onAction: @escaping (TextEditAction) -> Void) {
        self.onAction = onAction
        self.onTool = onTool
        self.fill = fill
        self.pressed = pressed
        self.ink = ink
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
        if !tools.isEmpty {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 6
            for t in tools {
                let b = makeToolButton(t)
                toolButtons.append((t, b))
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

    private func makeToolButton(_ t: TextTool) -> UIButton {
        let b = UIButton(type: .custom)
        b.backgroundColor = pressed          // tông phím chức năng: tách khỏi lưới sửa
        b.layer.cornerRadius = KeyboardView.keyRadius
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.6
        b.setTitle(TextEditing.toolTitle(t), for: .normal)
        b.setTitleColor(ink, for: .normal)
        b.accessibilityLabel = "Công cụ văn bản: \(t.label)"
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            b.backgroundColor = self.fill
            KeyboardView.clickModifier()
        }, for: .touchDown)
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            b.backgroundColor = self.pressed
        }, for: [.touchUpOutside, .touchCancel])
        b.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            b.backgroundColor = self.pressed
            self.onTool(t)
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
    /// Test hook: hàng công cụ văn bản (thứ tự hiện).
    var debugTools: [TextTool] { toolButtons.map { $0.0 } }
    func debugTapTool(_ t: TextTool) {
        guard let b = toolButtons.first(where: { $0.0 == t })?.1 else { return }
        b.sendActions(for: .touchDown)
        b.sendActions(for: .touchUpInside)
    }
    /// Test hook: các nút đang có (theo thứ tự lưới) + bật/tắt.
    var debugButtons: [(TextEditAction, Bool)] { buttons.map { ($0.0, $0.1.isEnabled) } }
    func debugTap(_ a: TextEditAction) {
        guard let b = buttons.first(where: { $0.0 == a })?.1 else { return }
        b.sendActions(for: .touchDown)
        b.sendActions(for: .touchUpInside)
    }
    #endif
}
