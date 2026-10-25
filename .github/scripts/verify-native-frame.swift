import AppKit
import Foundation
let image = NSImage(contentsOfFile: CommandLine.arguments[1])!
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
var values = [Double]()
for y in stride(from: bitmap.pixelsHigh / 8, to: bitmap.pixelsHigh * 7 / 8, by: max(1, bitmap.pixelsHigh / 30)) {
    for x in stride(from: bitmap.pixelsWide / 8, to: bitmap.pixelsWide * 7 / 8, by: max(1, bitmap.pixelsWide / 30)) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        values.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
    }
}
let mean = values.reduce(0, +) / Double(max(1, values.count))
let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, values.count))
guard values.count > 100, variance > 0.0001 else {
    fputs("Blank native framebuffer rejected: variance=\(variance)\n", stderr)
    exit(1)
}
print("Native framebuffer variance=\(variance)")
