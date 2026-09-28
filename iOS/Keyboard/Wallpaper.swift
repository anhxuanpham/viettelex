import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage

/// Ảnh nền bàn phím. App chọn ảnh (PhotosPicker) → thu nhỏ ≤1080px cạnh dài,
/// áp mờ (nếu có), nén JPEG ~200–400KB → ghi `wallpaper.jpg` vào App Group.
/// Extension CHỈ đọc: giải mã bằng ImageIO thumbnail ở đúng cỡ hiển thị (không
/// bao giờ giải bản gốc — RAM extension ~48–60MB).
enum Wallpaper {
    static let fileName = "wallpaper.jpg"
    static let maxEdge = 1080
    static let maxBytes = 400_000

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.viettelex")?
            .appendingPathComponent(fileName)
    }

    /// Thu nhỏ bằng ImageIO (không giải ảnh gốc vào RAM). Cạnh dài ≤ maxPixel.
    static func downsample(source: CGImageSource, maxPixel: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // xoay theo EXIF
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }

    static func downsample(data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsample(source: src, maxPixel: maxPixel)
    }

    static func downsample(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsample(source: src, maxPixel: maxPixel)
    }

    /// Mờ Gauss (app, lúc lưu) — bàn phím chỉ hiện ảnh đã mờ sẵn, không tốn gì.
    static func blurred(_ img: CGImage, radius: Int) -> CGImage {
        guard radius > 0 else { return img }
        let ci = CIImage(cgImage: img).clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(ci, from: ci.extent) ?? img
    }

    /// JPEG ≤ maxBytes: hạ chất lượng dần 0.8 → 0.4.
    static func encodeJPEG(_ img: CGImage, maxBytes: Int = maxBytes) -> Data? {
        var out: Data?
        for q in stride(from: 0.8, through: 0.4, by: -0.1) {
            let data = NSMutableData()
            guard let dst = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
            guard CGImageDestinationFinalize(dst) else { return nil }
            out = data as Data
            if data.length <= maxBytes { break }
        }
        return out
    }

    /// Toàn bộ pipeline của app: ảnh gốc → JPEG nhỏ sẵn cho bàn phím.
    static func prepare(original: Data, blur: Int) -> Data? {
        guard let small = downsample(data: original, maxPixel: maxEdge) else { return nil }
        return encodeJPEG(blurred(small, radius: blur))
    }

    /// Cạnh dài cần giải cho view w×h pt (aspect-fill): ảnh phải phủ kín view,
    /// không lớn hơn bản đã lưu (maxEdge).
    static func displayMaxPixel(viewSize: CGSize, scale: CGFloat, imageAspect: CGFloat) -> Int {
        guard viewSize.width > 0, viewSize.height > 0, imageAspect > 0 else { return maxEdge }
        let w = viewSize.width * scale, h = viewSize.height * scale
        // aspect-fill: cạnh ngắn của ảnh ≥ cạnh tương ứng của view.
        let needW = max(w, h * imageAspect)          // bề ngang ảnh cần
        let needH = needW / imageAspect
        return min(maxEdge, Int(ceil(max(needW, needH))))
    }

    // MARK: extension — cache một ảnh đã giải (controller dựng lại mỗi lần hiện)

    /// Mọi lần giải/cache chạy tuần tự trên queue này (cache không cần khoá).
    static let queue = DispatchQueue(label: "viettelex.wallpaper", qos: .userInitiated)
    nonisolated(unsafe) private static var cache: (key: String, image: UIImage)?

    /// Ảnh cho bàn phím; nil nếu không có file. Cache theo version + cỡ.
    static func loadForKeyboard(version: Double, viewSize: CGSize, scale: CGFloat) -> UIImage? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { cache = nil; return nil }
        guard let src = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        var aspect: CGFloat = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let pw = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let ph = props[kCGImagePropertyPixelHeight] as? CGFloat, ph > 0 {
            aspect = pw / ph
        }
        let px = displayMaxPixel(viewSize: viewSize, scale: scale, imageAspect: aspect)
        let target = CGSize(width: (viewSize.width * scale).rounded(), height: (viewSize.height * scale).rounded())
        let key = "\(version)|\(px)|\(Int(target.width))x\(Int(target.height))"
        if let c = cache, c.key == key { return c.image }
        cache = nil                     // nhả ảnh cũ TRƯỚC khi giải ảnh mới
        guard let full = downsample(source: src, maxPixel: px) else { return nil }
        // Chỉ giữ phần HIỆN (aspect-fill cắt giữa): ảnh dọc 3:4 trên bàn phím ngang chỉ lộ
        // ~55 % — bitmap giữ lại cỡ đúng view thay vì cả ảnh.
        let cg = aspectFillCrop(full, to: target) ?? full
        let img = UIImage(cgImage: cg, scale: scale, orientation: .up)
        cache = (key, img)
        return img
    }

    /// Vẽ `img` kiểu aspect-fill (căn giữa, cắt phần thừa) vào bitmap MỚI đúng `size` px —
    /// bitmap gốc nhả được ngay (CGImage.cropping chia chung bộ nhớ gốc nên không dùng).
    /// Ảnh gốc hẹp hơn view (phải phóng to mới phủ kín) ⇒ cắt ở ĐỘ PHÂN GIẢI GỐC (bitmap nhỏ
    /// hơn `size`, cùng tỉ lệ; UIImageView aspect-fill tự phóng — không phóng hai lần).
    /// Đúng cỡ sẵn ⇒ trả nil (dùng thẳng ảnh gốc).
    static func aspectFillCrop(_ img: CGImage, to size: CGSize) -> CGImage? {
        guard size.width >= 1, size.height >= 1, img.width > 0, img.height > 0 else { return nil }
        var k = max(size.width / CGFloat(img.width), size.height / CGFloat(img.height))
        var target = size
        if k > 1 { target = CGSize(width: size.width / k, height: size.height / k); k = 1 }
        let w = max(Int(target.width.rounded()), 1), h = max(Int(target.height.rounded()), 1)
        if img.width == w, img.height == h { return nil }
        let dw = CGFloat(img.width) * k, dh = CGFloat(img.height) * k
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
        return ctx.makeImage()
    }

    static func dropCache() { cache = nil }
    static var hasCache: Bool { cache != nil }

    /// Scale giải ảnh nền cho bàn phím: tối đa @2x (máy @3x giải ở @2x rồi phóng). Nền đã
    /// mờ + phủ tối + thường trong suốt một phần ⇒ mắt không phân biệt, mà bitmap 810×1080
    /// @3x (3,4 MB) còn ~1,5 MB (RAM-AUDIT.md §6).
    static func decodeScale(screenScale: CGFloat) -> CGFloat { min(screenScale, 2) }
}
