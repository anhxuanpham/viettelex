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
        let key = "\(version)|\(px)"
        if let c = cache, c.key == key { return c.image }
        cache = nil                     // nhả ảnh cũ TRƯỚC khi giải ảnh mới
        guard let cg = downsample(source: src, maxPixel: px) else { return nil }
        let img = UIImage(cgImage: cg, scale: scale, orientation: .up)
        cache = (key, img)
        return img
    }

    static func dropCache() { cache = nil }
}
