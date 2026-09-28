//
//  RGBABitmap.swift
//  Hangly
//
//  A small CPU pixel buffer for the image-import pipeline.
//

import CoreGraphics
import Foundation

/// Integer pixel bounds inside a bitmap.
struct PixelBounds: Equatable, Sendable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

/// 8-bit premultiplied RGBA pixels in CoreGraphics' native orientation.
///
/// **Row zero is the bottom of the image**, because that is how a `CGContext` lays
/// memory out and converting on every access would double the work. Every method
/// here documents which way is up where it matters.
///
/// This exists so background removal and analysis can be plain loops over an array,
/// which are easy to read, easy to test and fast enough: a 2048-pixel-square image
/// flood-fills in tens of milliseconds.
struct RGBABitmap {
    static let bytesPerPixel = 4
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    let width: Int
    let height: Int
    private(set) var pixels: [UInt8]

    init?(image: CGImage) {
        // Locals rather than `self.width`: the closure below must not capture `self`
        // before every stored property is initialised.
        let imageWidth = image.width
        let imageHeight = image.height
        guard imageWidth > 0, imageHeight > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: imageWidth * imageHeight * Self.bytesPerPixel)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = Self.makeContext(data: base, width: imageWidth, height: imageHeight) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }
        guard drawn else { return nil }

        width = imageWidth
        height = imageHeight
        pixels = buffer
    }

    /// Renders the buffer back into an image. The buffer is copied, so the result
    /// is independent of later mutation.
    func makeImage() -> CGImage? {
        var copy = pixels
        return copy.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = Self.makeContext(data: base, width: width, height: height) else { return nil }
            return context.makeImage()
        }
    }

    // MARK: - Shadows

    /// A soft drop shadow for an image: its alpha, blurred, in black.
    ///
    /// SwiftUI can do this with a shadow filter, but a filter resolves an offscreen
    /// pass on every frame it is drawn, and the overlay draws at 120 Hz. A charm's
    /// shadow never changes shape between frames, so it is made once here, cached,
    /// and afterwards drawn as an ordinary image.
    ///
    /// - Parameters:
    ///   - image: The artwork to cast the shadow of. Only its alpha is read.
    ///   - blurRadius: Box-blur radius in pixels. Three passes approximate a Gaussian.
    ///   - opacity: Darkness of the shadow at its most solid.
    /// - Returns: A bitmap `padding` pixels larger than `image` on every side, with
    ///   the shadow centred in it, or `nil` if the image cannot be read.
    static func shadow(from image: CGImage, blurRadius: Int, opacity: Double) -> CGImage? {
        guard blurRadius > 0, let source = RGBABitmap(image: image) else { return nil }
        let padding = padding(forBlurRadius: blurRadius)
        let width = source.width + (padding * 2)
        let height = source.height + (padding * 2)
        guard width > 0, height > 0 else { return nil }

        // Alpha only, laid into the padded canvas.
        var alpha = [Double](repeating: 0, count: width * height)
        for y in 0..<source.height {
            let row = (y + padding) * width
            for x in 0..<source.width {
                alpha[row + x + padding] = Double(source.alpha(x: x, y: y))
            }
        }

        var scratch = [Double](repeating: 0, count: width * height)
        for _ in 0..<3 {
            boxBlur(&alpha, into: &scratch, width: width, height: height, radius: blurRadius)
        }

        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for index in 0..<(width * height) {
            let value = UInt8((alpha[index] * opacity).rounded().clamped(to: 0...255))
            // Premultiplied black: only the alpha channel carries the shadow.
            pixels[(index * bytesPerPixel) + 3] = value
        }

        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = makeContext(data: base, width: width, height: height) else { return nil }
            return context.makeImage()
        }
    }

    /// How far a shadow of this radius spreads beyond its artwork, in pixels.
    static func padding(forBlurRadius radius: Int) -> Int {
        radius * 3
    }

    /// One separable box-blur pass, horizontal then vertical, by running sums.
    private static func boxBlur(
        _ values: inout [Double],
        into scratch: inout [Double],
        width: Int,
        height: Int,
        radius: Int
    ) {
        let span = Double((radius * 2) + 1)

        for y in 0..<height {
            let row = y * width
            var total = 0.0
            for x in -radius...radius { total += values[row + min(max(x, 0), width - 1)] }
            for x in 0..<width {
                scratch[row + x] = total / span
                let leaving = values[row + min(max(x - radius, 0), width - 1)]
                let entering = values[row + min(max(x + radius + 1, 0), width - 1)]
                total += entering - leaving
            }
        }

        for x in 0..<width {
            var total = 0.0
            for y in -radius...radius { total += scratch[(min(max(y, 0), height - 1) * width) + x] }
            for y in 0..<height {
                values[(y * width) + x] = total / span
                let leaving = scratch[(min(max(y - radius, 0), height - 1) * width) + x]
                let entering = scratch[(min(max(y + radius + 1, 0), height - 1) * width) + x]
                total += entering - leaving
            }
        }
    }

    static func makeContext(data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    // MARK: - Reading

    @inline(__always)
    private func offset(x: Int, y: Int) -> Int {
        ((y * width) + x) * Self.bytesPerPixel
    }

    func alpha(x: Int, y: Int) -> UInt8 {
        pixels[offset(x: x, y: y) + 3]
    }

    /// Bounds of every pixel more opaque than `threshold`, in buffer coordinates
    /// (bottom-up). `nil` when the image is entirely transparent.
    func opaqueBounds(threshold: UInt8) -> PixelBounds? {
        var bounds: PixelBounds?
        for y in 0..<height {
            for x in 0..<width where alpha(x: x, y: y) > threshold {
                if var current = bounds {
                    current.minX = min(current.minX, x)
                    current.maxX = max(current.maxX, x)
                    current.minY = min(current.minY, y)
                    current.maxY = max(current.maxY, y)
                    bounds = current
                } else {
                    bounds = PixelBounds(minX: x, minY: y, maxX: x, maxY: y)
                }
            }
        }
        return bounds
    }

    /// Fraction of pixels more opaque than `threshold`.
    func coverage(threshold: UInt8) -> Double {
        var count = 0
        for index in stride(from: 3, to: pixels.count, by: Self.bytesPerPixel) where pixels[index] > threshold {
            count += 1
        }
        return Double(count) / Double(width * height)
    }

    /// Fraction of pixels that are at most `threshold` opaque.
    func transparentFraction(threshold: UInt8) -> Double {
        1 - coverage(threshold: threshold)
    }

    /// Alpha-weighted mean colour of the visible pixels, un-premultiplied.
    /// `nil` when nothing is visible.
    func averageColor(threshold: UInt8) -> CharmColor? {
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for index in stride(from: 0, to: pixels.count, by: Self.bytesPerPixel) {
            let alpha = Double(pixels[index + 3])
            guard alpha > Double(threshold) else { continue }
            // Un-premultiply: stored channels were scaled by alpha/255.
            red += Double(pixels[index]) * 255 / alpha * alpha
            green += Double(pixels[index + 1]) * 255 / alpha * alpha
            blue += Double(pixels[index + 2]) * 255 / alpha * alpha
            weight += alpha
        }
        guard weight > 0 else { return nil }
        return CharmColor(red / weight / 255, green / weight / 255, blue / weight / 255)
    }

    // MARK: - Background removal

    /// Clears every pixel reachable from a corner whose colour is within `tolerance`
    /// (per channel, 0...255) of that corner's colour.
    ///
    /// The comparison is against the *seed corner*, not the neighbouring pixel, so
    /// a soft edge on the subject cannot let the fill creep inwards one shade at a
    /// time. The cost is that a strongly graded background is only partly removed,
    /// which is why this is the fallback and subject lifting is tried first.
    mutating func floodFillBackground(tolerance: Int) {
        guard width > 0, height > 0 else { return }
        var visited = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        queue.reserveCapacity(width * 2 + height * 2)

        let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
        for (cornerX, cornerY) in corners {
            let seed = offset(x: cornerX, y: cornerY)
            let reference = (Int(pixels[seed]), Int(pixels[seed + 1]), Int(pixels[seed + 2]))
            guard pixels[seed + 3] > 250 else { continue }   // an already-transparent corner is not a background

            queue.removeAll(keepingCapacity: true)
            let start = (cornerY * width) + cornerX
            guard !visited[start] else { continue }
            visited[start] = true
            queue.append(start)

            var head = 0
            while head < queue.count {
                let index = queue[head]
                head += 1
                let pixel = index * Self.bytesPerPixel
                let matches = pixels[pixel + 3] > 250
                    && abs(Int(pixels[pixel]) - reference.0) <= tolerance
                    && abs(Int(pixels[pixel + 1]) - reference.1) <= tolerance
                    && abs(Int(pixels[pixel + 2]) - reference.2) <= tolerance
                guard matches else { continue }

                pixels[pixel] = 0
                pixels[pixel + 1] = 0
                pixels[pixel + 2] = 0
                pixels[pixel + 3] = 0

                let x = index % width
                let y = index / width
                if x > 0 { enqueue(index - 1, &visited, &queue) }
                if x < width - 1 { enqueue(index + 1, &visited, &queue) }
                if y > 0 { enqueue(index - width, &visited, &queue) }
                if y < height - 1 { enqueue(index + width, &visited, &queue) }
            }
        }
    }

    @inline(__always)
    private func enqueue(_ index: Int, _ visited: inout [Bool], _ queue: inout [Int]) {
        guard !visited[index] else { return }
        visited[index] = true
        queue.append(index)
    }

    /// Softens hard alpha edges by one pixel without growing the shape: each pixel's
    /// alpha becomes the lesser of itself and its neighbourhood mean.
    mutating func featherAlphaEdges() {
        guard width > 2, height > 2 else { return }
        let original = pixels
        for y in 0..<height {
            for x in 0..<width {
                let index = offset(x: x, y: y)
                let alpha = Int(original[index + 3])
                guard alpha > 0 else { continue }

                var sum = 0
                var count = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        sum += Int(original[((ny * width) + nx) * Self.bytesPerPixel + 3])
                        count += 1
                    }
                }
                let mean = sum / max(count, 1)
                guard mean < alpha else { continue }

                // Keep the buffer premultiplied: scale colour with the new alpha.
                let ratio = Double(mean) / Double(alpha)
                pixels[index] = UInt8((Double(original[index]) * ratio).rounded())
                pixels[index + 1] = UInt8((Double(original[index + 1]) * ratio).rounded())
                pixels[index + 2] = UInt8((Double(original[index + 2]) * ratio).rounded())
                pixels[index + 3] = UInt8(mean)
            }
        }
    }
}
