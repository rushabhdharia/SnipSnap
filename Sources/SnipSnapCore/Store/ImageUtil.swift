import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Small ImageIO helpers so the store never has to pull in AppKit just to
/// re-encode a screenshot or make a thumbnail.
enum ImageUtil {

    struct Decoded {
        var png: Data
        var pixelWidth: Int
        var pixelHeight: Int
    }

    /// Normalise arbitrary image data (typically TIFF straight off the
    /// pasteboard) to PNG, and report its pixel dimensions.
    static func normalizeToPNG(_ data: Data) -> Decoded? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }

        let png: Data
        if let cfType = CGImageSourceGetType(src),
           UTType(cfType as String) == .png {
            png = data
        } else {
            // Carry the source's DPI through the re-encode — dropping it
            // (nil properties) would double the physical size of a pasted
            // screenshot in DPI-aware apps.
            var dpi: (width: Double, height: Double)?
            if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyDPIWidth] as? Double,
               let h = props[kCGImagePropertyDPIHeight] as? Double {
                dpi = (w, h)
            }
            guard let encoded = encodePNG(image, dpi: dpi) else { return nil }
            png = encoded
        }
        return Decoded(png: png, pixelWidth: image.width, pixelHeight: image.height)
    }

    /// A downscaled PNG whose longest edge is `maxPixel`, for list rows.
    static func thumbnailPNG(from data: Data, maxPixel: Int) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return nil }
        return encodePNG(thumb)
    }

    private static func encodePNG(_ image: CGImage, dpi: (width: Double, height: Double)? = nil) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        var properties: [CFString: Any] = [:]
        if let dpi {
            properties[kCGImagePropertyDPIWidth] = dpi.width
            properties[kCGImagePropertyDPIHeight] = dpi.height
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Pixel dimensions read from an image's header only — no full decode.
    /// Used to decide whether a stored thumbnail needs regenerating.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }
}
