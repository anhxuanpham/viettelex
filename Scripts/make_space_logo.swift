// make_space_logo.swift — logo mờ ở mép phải phím cách: Vᴛ (Tiếng Việt) và E (Tiếng Anh,
// chế độ vuốt phím cách). Cùng hình học với make_icon.swift (MenuIcon.pdf): hộp vuông bo
// góc viền 1/16, chữ đặc cao 0,53 hộp, căn giữa. Xuất PNG đen (tint lúc vẽ) 44/66 px =
// 22 pt/dp @2x/@3x cho iOS (iOS/Keyboard) và Android (drawable-xhdpi/xxhdpi).
//
// Usage: swift Scripts/make_space_logo.swift            (chạy từ gốc repo)
import AppKit
import CoreText

func glyphPath(_ ch: Character, weight: NSFont.Weight, size: CGFloat,
               baselineY: CGFloat, leftX: CGFloat) -> (path: CGPath, width: CGFloat)? {
    let font = NSFont.systemFont(ofSize: size, weight: weight) as CTFont
    var chars = [UniChar](String(ch).utf16)
    var glyph = CGGlyph()
    guard CTFontGetGlyphsForCharacters(font, &chars, &glyph, 1) else { return nil }
    var bbox = CGRect.zero
    withUnsafeMutablePointer(to: &glyph) { g in
        bbox = CTFontGetBoundingRectsForGlyphs(font, .default, g, nil, 1)
    }
    var transform = CGAffineTransform(translationX: leftX - bbox.minX, y: baselineY)
    guard let path = CTFontCreatePathForGlyph(font, glyph, &transform) else { return nil }
    return (path, bbox.width)
}

/// Vẽ logo lên canvas vuông S = 16 (đơn vị MenuIcon), `sub` = chữ nhỏ kèm (T của Vᴛ).
func draw(_ ctx: CGContext, main: Character, sub: Character?) {
    let S: CGFloat = 16
    let borderWidth: CGFloat = 1.0
    let box = CGRect(x: borderWidth / 2, y: borderWidth / 2, width: S - borderWidth, height: S - borderWidth)
    let radius = box.height * 0.28
    guard let probe = glyphPath(main, weight: .bold, size: 20, baselineY: 0, leftX: 0) else { return }
    // cap height đo trên V (như MenuIcon) để E cao đúng bằng V
    let vProbe = glyphPath("V", weight: .bold, size: 20, baselineY: 0, leftX: 0) ?? probe
    let capPerPt = vProbe.path.boundingBox.height / 20
    let mSize = S * 0.53 / capPerPt
    let tSize = mSize * 0.4
    let gap = -mSize * 0.05
    guard let mW = glyphPath(main, weight: .bold, size: mSize, baselineY: 0, leftX: 0) else { return }
    let tW = sub.flatMap { glyphPath($0, weight: .black, size: tSize, baselineY: 0, leftX: 0) }
    let totalW = mW.width + (tW.map { gap + $0.width } ?? 0)
    let baselineY = box.minY + (box.height - mW.path.boundingBox.height) / 2
    let leftX = box.minX + (box.width - totalW) / 2
    guard let m = glyphPath(main, weight: .bold, size: mSize, baselineY: baselineY, leftX: leftX) else { return }
    let t = sub.flatMap { glyphPath($0, weight: .black, size: tSize, baselineY: baselineY,
                                    leftX: leftX + m.width + gap) }

    ctx.setStrokeColor(CGColor.black)
    ctx.setLineWidth(borderWidth)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()
    let glyphs = CGMutablePath()
    glyphs.addPath(m.path)
    if let t { glyphs.addPath(t.path) }
    ctx.setFillColor(CGColor.black)
    ctx.addPath(glyphs)
    ctx.fillPath()
    if let t {
        ctx.setLineWidth(tSize * 0.06)
        ctx.setLineJoin(.round)
        ctx.addPath(t.path)
        ctx.strokePath()
    }
}

func png(px: Int, main: Character, sub: Character?, to path: String) {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.scaleBy(x: CGFloat(px) / 16, y: CGFloat(px) / 16)
    draw(ctx, main: main, sub: sub)
    guard let img = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for (name, main, sub) in [("SpaceLogo", Character("V"), Character("T") as Character?),
                          ("SpaceLogoEN", Character("E"), nil)] {
    png(px: 44, main: main, sub: sub, to: "\(out)/iOS/Keyboard/\(name)@2x.png")
    png(px: 66, main: main, sub: sub, to: "\(out)/iOS/Keyboard/\(name)@3x.png")
    let a = name == "SpaceLogo" ? "ime_space_logo" : "ime_space_logo_en"
    png(px: 44, main: main, sub: sub, to: "\(out)/android/app/src/main/res/drawable-xhdpi/\(a).png")
    png(px: 66, main: main, sub: sub, to: "\(out)/android/app/src/main/res/drawable-xxhdpi/\(a).png")
}
