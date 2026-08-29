import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(1) }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.18, green: 0.46, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.52, green: 0.25, blue: 0.91, alpha: 1)
])!
gradient.draw(in: background, angle: -45)

NSColor.white.withAlphaComponent(0.96).setFill()
let card = NSBezierPath(roundedRect: NSRect(x: 190, y: 240, width: 644, height: 544), xRadius: 86, yRadius: 86)
card.fill()

NSColor(calibratedRed: 0.26, green: 0.39, blue: 0.90, alpha: 1).setFill()
let barWidths: [CGFloat] = [42, 42, 42, 42, 42, 42, 42]
let heights: [CGFloat] = [150, 260, 360, 240, 400, 280, 170]
var x: CGFloat = 270
for (index, width) in barWidths.enumerated() {
    let height = heights[index]
    let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 512 - height / 2, width: width, height: height), xRadius: width / 2, yRadius: width / 2)
    bar.fill()
    x += 70
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
try png.write(to: destination)
