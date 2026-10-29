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

// Optional content gate for app-owned screen captures. The preparation view is
// nonblank too, but its Brand.ice canvas is not the screen's cool-white/night canvas.
// Map and system-calendar captures omit this argument and keep the variance gate.
if CommandLine.arguments.count > 2 {
    let scheme = CommandLine.arguments[2]
    guard scheme == "light" || scheme == "dark" else { exit(2) }
    let target: [CGFloat] = scheme == "dark" ? [0.025, 0.065, 0.085] : [0.98, 0.99, 1.0]
    var matches = 0
    var samples = 0
    for fraction in stride(from: 0.22, through: 0.87, by: 0.05) {
        for edge in [0.025, 0.975] {
            guard let color = bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * edge),
                                            y: Int(Double(bitmap.pixelsHigh) * fraction))?.usingColorSpace(.sRGB) else { continue }
            samples += 1
            let components = [color.redComponent, color.greenComponent, color.blueComponent]
            // Light content must match cool white closely enough to reject mint
            // preparation. The unchanged dark target needs profile tolerance.
            let tolerance: CGFloat = scheme == "dark" ? 0.035 : 0.02
            if zip(components, target).allSatisfy({ abs($0.0 - $0.1) < tolerance }) { matches += 1 }
        }
    }
    print("Native content canvas: \(matches)/\(samples), scheme=\(scheme)")
    guard matches >= 4 else {
        fputs("App content has not replaced the preparation surface.\n", stderr)
        exit(2)
    }
}
