// EmojiPlane — bàn phím emoji render theo đúng cấu trúc bàn phím US stock
// (đối chiếu video 2026-07-24): lưới emoji lớn
// cuộn NGANG column-major liên tục theo category, hàng dưới
// [ABC][icon 9 category][⌫] với category đang xem được highlight tròn.
// Recents (🕐) lưu App Group, tối đa 30. (Search bar đã bỏ — user 2026-07-24.)
// 27/09/2026: tab kaomoji / ký tự đặc biệt (^‿^) ở cuối dãy category.
// 27/09/2026 (góp ý user: emoji bé, sát nhau): bỏ tiêu đề nhóm nhỏ trên lưới; THANH TÌM
// luôn hiện trên cùng như iOS 26/27 gốc (chạm → KeyboardView dựng ô tìm + phím chữ);
// ô emoji ≥ 40pt, glyph ~32pt như stock — hình học ở EmojiGridMetrics (thuần, có test).
import UIKit

/// Hình học lưới emoji (thuần): chọn số hàng sao cho ô ≥ `minCell` (40pt — vùng chạm
/// thoải mái, stock iPhone dọc ~44pt), tối đa 5 hàng như stock; ô vuông, KHÔNG khe
/// giữa ô (khoảng trắng quanh glyph chính là khoảng cách — stock cũng vậy). Glyph
/// ~72% ô, trần 34pt (stock ~32pt trên iPhone 6.1").
struct EmojiGridMetrics: Equatable {
    let rows: Int
    let cell: CGFloat
    let fontSize: CGFloat

    static let minCell: CGFloat = 40, maxRows = 5, minRows = 2
    static let searchRow: CGFloat = 40, categoryRow: CGFloat = 34

    static func compute(gridHeight h: CGFloat) -> EmojiGridMetrics {
        let fit = Int((max(h, 0) / minCell).rounded(.down))
        let rows = min(max(fit, minRows), maxRows)
        let cell = max((h / CGFloat(rows) * 2).rounded(.down) / 2, 1)   // nửa pt: khỏi rớt hàng
        return EmojiGridMetrics(rows: rows, cell: cell,
                                fontSize: min((cell * 0.72).rounded(), 34))
    }
}

final class EmojiPlane: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var onEmoji: ((String) -> Void)?
    var onABC: (() -> Void)?
    var onBackspace: (() -> Void)?
    /// Bấm 🔍 — KeyboardView chuyển sang chế độ tìm emoji.
    var onSearch: (() -> Void)?
    /// Chạm một kaomoji / ký tự đặc biệt — chèn nguyên văn (không vào Recents).
    var onKaomoji: ((String) -> Void)?

    private var dark = false
    private var sections: [(name: String, emoji: [String])] = []
    private var collection: UICollectionView!
    private var categoryButtons: [UIButton] = []
    private var kaomojiButton: UIButton?
    private var kaomojiView: KaomojiView?
    private var repeatTimer: Timer?

    private static let recentsKey = "emojiRecents"
    private static let categoryIcons: [String] = [
        "clock", "face.smiling", "hare", "fork.knife", "soccerball",
        "car.fill", "lightbulb", "heart", "flag",
    ]
    /// Thanh tìm luôn hiện trên cùng (chạm → onSearch).
    private(set) var searchField: UIControl!

    /// Chỗ phím emoji vừa bấm (toạ độ KeyboardView; plane cùng mép trái + đáy):
    /// minX, maxX, top = khoảng từ đáy lên đỉnh phím. ABC đặt ĐÚNG cột đó —
    /// bấm nhầm emoji thì chạm lại chỗ cũ là về chữ (user 26/09/2026).
    struct ABCSlot { var minX: CGFloat; var maxX: CGFloat; var top: CGFloat }
    private let abcSlot: ABCSlot?
    private var abcButton: UIButton?

    /// Vùng chạm nở lên tới đỉnh phím emoji cũ và sang trái tới mép bàn phím.
    private final class ABCButton: UIButton {
        var hitRect: CGRect?   // toạ độ superview
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard let r = hitRect, let sv = superview else { return super.point(inside: point, with: event) }
            return r.contains(convert(point, to: sv))
        }
    }

    init(dark: Bool, abcSlot: ABCSlot? = nil) {
        self.abcSlot = abcSlot
        super.init(frame: .zero)
        self.dark = dark
        isMultipleTouchEnabled = true
        reloadSections()
        buildSearchField()
        buildCollection()
        buildCategoryRow()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { repeatTimer?.invalidate() }

    // UserDefaults.standard: không Full Access → iOS cấm GHI App Group từ
    // extension (ghi group fail âm thầm — recents từng mất qua phiên vì vậy).
    private var recents: [String] { Self.recents }
    static var recents: [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    private func reloadSections() {
        var s: [(String, [String])] = []
        let r = recents
        if !r.isEmpty { s.append(("recents", r)) }
        s.append(contentsOf: EmojiData.categories.map { ($0.name, $0.emoji) })
        sections = s
    }

    private func noteUsed(_ e: String) { Self.noteUsed(e) }
    /// Dùng chung với kết quả tìm emoji (KeyboardView).
    static func noteUsed(_ e: String) {
        var r = recents.filter { $0 != e }
        r.insert(e, at: 0)
        if r.count > 30 { r.removeLast(r.count - 30) }
        UserDefaults.standard.set(r, forKey: recentsKey)
    }

    // MARK: UI

    /// Ô tìm dạng viên thuốc như stock iOS 26/27 ("Tìm emoji" + kính lúp). Không
    /// phải ô nhập thật (extension không có bàn phím cho chính nó): chạm là sang chế
    /// độ tìm (EmojiSearchBar + phím chữ VietTelex).
    private func buildSearchField() {
        let ink: UIColor = dark ? .white : .black
        let f = UIControl()
        // ≈ tertiarySystemFill (118,118,128) — nền ô tìm stock trên bàn phím.
        f.backgroundColor = UIColor(red: 118 / 255, green: 118 / 255, blue: 128 / 255,
                                    alpha: dark ? 0.24 : 0.12)
        f.layer.cornerRadius = 16
        f.accessibilityLabel = "Tìm emoji"
        f.accessibilityTraits = .searchField
        f.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)))
        icon.tintColor = ink.withAlphaComponent(0.5)
        let label = UILabel()
        label.text = "Tìm emoji"
        label.font = .systemFont(ofSize: 17)
        label.textColor = ink.withAlphaComponent(0.5)
        for v in [icon, label] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.isUserInteractionEnabled = false
            f.addSubview(v)
        }
        f.addAction(UIAction { [weak self] _ in
            KeyboardView.clickModifier()
            self?.onSearch?()
        }, for: .touchUpInside)
        addSubview(f)
        searchField = f
        NSLayoutConstraint.activate([
            f.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            f.leftAnchor.constraint(equalTo: leftAnchor, constant: 8),
            f.rightAnchor.constraint(equalTo: rightAnchor, constant: -8),
            f.heightAnchor.constraint(equalToConstant: EmojiGridMetrics.searchRow - 8),
            icon.leftAnchor.constraint(equalTo: f.leftAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: f.centerYAnchor),
            label.leftAnchor.constraint(equalTo: icon.rightAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: f.centerYAnchor),
        ])
    }

    private var metrics = EmojiGridMetrics.compute(gridHeight: 0)

    private func buildCollection() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal        // column-major như stock
        layout.minimumLineSpacing = 0               // khe = khoảng trắng quanh glyph
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.disableKeyboardEdgeEffects()
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.isMultipleTouchEnabled = true
        // Long-press emoji có skin tone → popup 6 biến thể (cancelsTouchesInView
        // mặc định true nên tap thường không bị chèn kèm emoji gốc).
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(cellHold(_:)))
        hold.minimumPressDuration = 0.35
        collection.addGestureRecognizer(hold)
        addSubview(collection)
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 2),
            collection.leftAnchor.constraint(equalTo: leftAnchor),
            collection.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    private func buildCategoryRow() {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.alignment = .center
        row.spacing = 2
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false

        let ink: UIColor = dark ? .white : .black
        let abc = ABCButton(type: .custom)
        abc.setTitle("ABC", for: .normal)
        abc.setTitleColor(ink, for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        abc.addAction(UIAction { [weak self] _ in
            KeyboardView.clickModifier()
            self?.onABC?()
        }, for: .touchDown)
        if let slot = abcSlot {
            // ABC nằm ngoài stack (layoutSubviews đặt frame theo slot); stack chừa
            // chỗ bằng spacer để icon category không chui dưới ABC.
            let spacer = UIView()
            spacer.widthAnchor.constraint(equalToConstant: max(slot.maxX - 8 + 2, 44)).isActive = true
            row.addArrangedSubview(spacer)
            addSubview(abc)
            abcButton = abc
        } else {
            row.addArrangedSubview(abc)
            abc.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }

        let iconsStack = UIStackView()
        iconsStack.axis = .horizontal
        iconsStack.distribution = .fillEqually
        for (i, name) in Self.categoryIcons.enumerated() {
            let b = UIButton(type: .custom)
            b.setImage(UIImage(systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
            b.tintColor = ink.withAlphaComponent(0.55)
            b.layer.cornerRadius = 13
            b.addAction(UIAction { [weak self] _ in self?.jumpToCategory(i) }, for: .touchUpInside)
            categoryButtons.append(b)
            iconsStack.addArrangedSubview(b)
        }
        let kao = UIButton(type: .custom)
        kao.setTitle("^‿^", for: .normal)
        kao.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        kao.titleLabel?.adjustsFontSizeToFitWidth = true
        kao.setTitleColor(ink.withAlphaComponent(0.55), for: .normal)
        kao.layer.cornerRadius = 13
        kao.accessibilityLabel = "Kaomoji và ký tự đặc biệt"
        kao.addAction(UIAction { [weak self] _ in self?.showKaomoji() }, for: .touchUpInside)
        kaomojiButton = kao
        iconsStack.addArrangedSubview(kao)
        row.addArrangedSubview(iconsStack)

        let del = UIButton(type: .custom)
        del.setImage(UIImage(systemName: "delete.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        del.tintColor = ink
        del.addAction(UIAction { [weak self] _ in
            KeyboardView.clickDelete()
            self?.onBackspace?()
        }, for: .touchDown)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(backspaceHold(_:)))
        long.minimumPressDuration = 0.5
        del.addGestureRecognizer(long)
        row.addArrangedSubview(del)
        del.widthAnchor.constraint(equalToConstant: 44).isActive = true

        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: collection.bottomAnchor, constant: 2),
            row.leftAnchor.constraint(equalTo: leftAnchor),
            row.rightAnchor.constraint(equalTo: rightAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            row.heightAnchor.constraint(equalToConstant: EmojiGridMetrics.categoryRow - 2),
        ])
        highlightCategory(sectionOnScreen())
    }

    @objc private func backspaceHold(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                self?.onBackspace?()
            }
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate(); repeatTimer = nil
        default: break
        }
    }

    // MARK: category nav

    /// Map icon index (0 = recents) → section index thực (recents có thể vắng).
    private func sectionIndex(forIcon i: Int) -> Int? {
        let hasRecents = sections.first?.name == "recents"
        if i == 0 { return hasRecents ? 0 : nil }
        let idx = i - 1 + (hasRecents ? 1 : 0)
        return idx < sections.count ? idx : nil
    }

    private func iconIndex(forSection s: Int) -> Int {
        let hasRecents = sections.first?.name == "recents"
        if hasRecents { return s == 0 ? 0 : s }
        return s + 1
    }

    private var pendingIcon: Int?

    private func jumpToCategory(_ i: Int) {
        hideKaomoji()
        guard let s = sectionIndex(forIcon: i), collection.numberOfItems(inSection: s) > 0 else { return }
        // Giữ highlight ở icon vừa bấm: các section cuối (tim, cờ) không thể
        // cuộn tới mép trái (clamp contentSize) nên leftmost-visible sẽ báo
        // section trước đó — scroll callback không được đè trong lúc animate.
        pendingIcon = i
        collection.scrollToItem(at: IndexPath(item: 0, section: s), at: .left, animated: true)
        highlightCategory(i)
    }

    private func sectionOnScreen() -> Int {
        let visible = collection.indexPathsForVisibleItems.sorted()
        return visible.first?.section ?? 0
    }

    /// icon = -1 → không category nào (đang ở tab kaomoji).
    private func highlightCategory(_ icon: Int) {
        let ink: UIColor = dark ? .white : .black
        for (i, b) in categoryButtons.enumerated() {
            let on = i == icon
            b.backgroundColor = on ? ink.withAlphaComponent(0.18) : .clear
            b.tintColor = on ? ink : ink.withAlphaComponent(0.55)
        }
        let kao = kaomojiView != nil
        kaomojiButton?.backgroundColor = kao ? ink.withAlphaComponent(0.18) : .clear
        kaomojiButton?.setTitleColor(kao ? ink : ink.withAlphaComponent(0.55), for: .normal)
    }

    // MARK: kaomoji

    private func showKaomoji() {
        KeyboardView.clickModifier()
        dismissTonePopup()
        if kaomojiView == nil {
            let v = KaomojiView(groups: EmojiData.kaomoji, dark: dark)
            v.onPick = { [weak self] s in
                KeyboardView.clickLetter()
                self?.onKaomoji?(s)
            }
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: collection.topAnchor),
                v.bottomAnchor.constraint(equalTo: collection.bottomAnchor),
                v.leftAnchor.constraint(equalTo: collection.leftAnchor),
                v.rightAnchor.constraint(equalTo: collection.rightAnchor),
            ])
            kaomojiView = v
        }
        collection.isHidden = true
        highlightCategory(-1)
    }

    private func hideKaomoji() {
        guard let v = kaomojiView else { return }
        v.removeFromSuperview()
        kaomojiView = nil
        collection.isHidden = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collection, kaomojiView == nil else { return }
        guard pendingIcon == nil else { return }
        highlightCategory(iconIndex(forSection: sectionOnScreen()))
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        pendingIcon = nil          // user cuộn tay tiếp thì highlight lại bám theo
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pendingIcon = nil
        dismissTonePopup()
    }

    // MARK: skin tones

    /// [gốc + 5 tông da] nếu emoji có scalar là modifier base; nil nếu không.
    /// Tông áp cho MỌI base trong chuỗi ZWJ (chọn 1 tông cho cả nhóm — như
    /// lựa chọn nhanh của stock; chưa nhớ tông riêng từng emoji).
    static func toneVariants(of e: String) -> [String]? {
        guard e.unicodeScalars.contains(where: { $0.properties.isEmojiModifierBase })
        else { return nil }
        let tones: [Unicode.Scalar] = (0x1F3FB...0x1F3FF).compactMap { Unicode.Scalar($0) }
        var out = [e]
        for t in tones {
            var v = String.UnicodeScalarView()
            for sc in e.unicodeScalars {
                if (0x1F3FB...0x1F3FF).contains(sc.value) { continue }  // bỏ tông cũ
                v.append(sc)
                if sc.properties.isEmojiModifierBase { v.append(t) }
            }
            out.append(String(v))
        }
        return out
    }

    private var tonePopup: UIView?

    @objc private func cellHold(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let pt = g.location(in: collection)
        guard let ip = collection.indexPathForItem(at: pt),
              let cell = collection.cellForItem(at: ip),
              let variants = Self.toneVariants(of: sections[ip.section].emoji[ip.item])
        else { return }
        showTonePopup(variants, over: cell)
    }

    private func showTonePopup(_ variants: [String], over cell: UIView) {
        dismissTonePopup()
        KeyboardView.clickModifier()
        let itemW: CGFloat = 36, h: CGFloat = 44
        let pop = UIView()
        pop.backgroundColor = dark ? UIColor(white: 0.25, alpha: 1) : .white
        pop.layer.cornerRadius = 10
        pop.layer.shadowColor = UIColor.black.cgColor
        pop.layer.shadowOffset = CGSize(width: 0, height: 1)
        pop.layer.shadowRadius = 3
        pop.layer.shadowOpacity = 0.3
        pop.layer.zPosition = 20
        for (i, v) in variants.enumerated() {
            let b = UIButton(type: .custom)
            b.setTitle(v, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 26)
            b.frame = CGRect(x: CGFloat(i) * itemW, y: 0, width: itemW, height: h)
            b.addAction(UIAction { [weak self] _ in
                KeyboardView.clickLetter()
                self?.noteUsed(v)
                self?.onEmoji?(v)
                self?.dismissTonePopup()
            }, for: .touchUpInside)
            pop.addSubview(b)
        }
        let w = CGFloat(variants.count) * itemW
        let cf = convert(cell.bounds, from: cell)
        // trên cell, kẹp trong bounds của plane
        let x = min(max(cf.midX - w / 2, 4), bounds.width - w - 4)
        let y = max(cf.minY - h - 6, 2)
        pop.frame = CGRect(x: x, y: y, width: w, height: h)
        addSubview(pop)
        tonePopup = pop
    }

    private func dismissTonePopup() {
        tonePopup?.removeFromSuperview()
        tonePopup = nil
    }

    // Xoay màn hình / đổi cỡ Split View → cell size tính lại theo chiều cao mới.
    private var lastLayoutWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        let m = EmojiGridMetrics.compute(gridHeight: collection.bounds.height)
        if bounds.width != lastLayoutWidth || m != metrics {
            lastLayoutWidth = bounds.width
            metrics = m
            dismissTonePopup()
            collection.collectionViewLayout.invalidateLayout()
            for case let c as EmojiCell in collection.visibleCells { c.setFont(m.fontSize) }
        }
        if let abc = abcButton as? ABCButton, let slot = abcSlot {
            // Nhìn: cột phím emoji cũ, cao bằng hàng category (32, cách đáy 2).
            abc.frame = CGRect(x: slot.minX, y: bounds.height - 34,
                               width: slot.maxX - slot.minX, height: 32)
            // Chạm: từ mép trái tới hết phím cũ, từ đỉnh phím cũ xuống đáy.
            abc.hitRect = CGRect(x: 0, y: bounds.height - slot.top,
                                 width: slot.maxX, height: slot.top)
            bringSubviewToFront(abc)
        }
    }

    // MARK: collection

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        cell.label.text = sections[indexPath.section].emoji[indexPath.item]
        cell.setFont(metrics.fontSize)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let c = metrics.cell
        return CGSize(width: c, height: c)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dismissTonePopup()
        let e = sections[indexPath.section].emoji[indexPath.item]
        KeyboardView.clickLetter()
        let hadRecents = sections.first?.name == "recents"
        noteUsed(e)
        onEmoji?(e)
        if !hadRecents {
            // lần dùng đầu tiên trong phiên: section 🕐 xuất hiện ngay,
            // không phải đợi mở lại plane
            reloadSections()
            collection.reloadData()
        }
    }

    /// Tab kaomoji: cuộn dọc, mỗi nhóm một tiêu đề xám + các "viên" chữ dàn dòng.
    final class KaomojiView: UIScrollView {
        var onPick: ((String) -> Void)?
        private(set) var chips: [(button: UIButton, text: String)] = []
        private var headers: [UILabel] = []
        private var groupStarts: [Int] = []
        private var lastW: CGFloat = 0

        init(groups: [(name: String, items: [String])], dark: Bool) {
            super.init(frame: .zero)
            showsVerticalScrollIndicator = false
            alwaysBounceVertical = true
            let ink: UIColor = dark ? .white : .black
            let fill = dark ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 1, alpha: 0.9)
            for g in groups {
                let h = UILabel()
                h.text = g.name.uppercased()
                h.font = .systemFont(ofSize: 11, weight: .semibold)
                h.textColor = ink.withAlphaComponent(0.5)
                addSubview(h)
                headers.append(h)
                groupStarts.append(chips.count)
                for item in g.items {
                    let b = UIButton(type: .custom)
                    b.setTitle(item, for: .normal)
                    b.setTitleColor(ink, for: .normal)
                    b.titleLabel?.font = .systemFont(ofSize: 17)
                    b.backgroundColor = fill
                    b.layer.cornerRadius = 8
                    b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
                    b.accessibilityLabel = item
                    b.addAction(UIAction { [weak self] _ in self?.onPick?(item) }, for: .touchUpInside)
                    addSubview(b)
                    chips.append((b, item))
                }
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width != lastW else { return }
            lastW = bounds.width
            let side: CGFloat = 8, gap: CGFloat = 6, h: CGFloat = 34
            var y: CGFloat = 2
            for (gi, header) in headers.enumerated() {
                header.frame = CGRect(x: side + 2, y: y, width: bounds.width - 2 * side, height: 14)
                y += 18
                var x = side
                let end = gi + 1 < groupStarts.count ? groupStarts[gi + 1] : chips.count
                for ci in groupStarts[gi]..<end {
                    let b = chips[ci].button
                    let w = min(max(b.intrinsicContentSize.width, h), bounds.width - 2 * side)
                    if x + w > bounds.width - side, x > side { x = side; y += h + gap }
                    b.frame = CGRect(x: x, y: y, width: w, height: h)
                    x += w + gap
                }
                y += h + 12
            }
            contentSize = CGSize(width: bounds.width, height: y)
        }
    }

    private final class EmojiCell: UICollectionViewCell {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 32)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leftAnchor.constraint(equalTo: contentView.leftAnchor),
                label.rightAnchor.constraint(equalTo: contentView.rightAnchor),
                label.topAnchor.constraint(equalTo: contentView.topAnchor),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }
        func setFont(_ size: CGFloat) {
            if label.font.pointSize != size { label.font = .systemFont(ofSize: size) }
        }
    }
}
