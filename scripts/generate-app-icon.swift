import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let canvas = CGRect(origin: .zero, size: size)
let insetCanvas = canvas.insetBy(dx: 70, dy: 70)
let cornerRadius: CGFloat = 228

let backgroundPath = NSBezierPath(
    roundedRect: insetCanvas,
    xRadius: cornerRadius,
    yRadius: cornerRadius
)

backgroundPath.addClip()

let backgroundGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.95, green: 0.63, blue: 0.18, alpha: 1.0),
    NSColor(calibratedRed: 0.79, green: 0.34, blue: 0.12, alpha: 1.0)
])!
backgroundGradient.draw(in: backgroundPath, angle: -45)

let glowPath = NSBezierPath(ovalIn: CGRect(x: 180, y: 500, width: 640, height: 420))
NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.88, alpha: 0.26).setFill()
glowPath.fill()

let bottomGlow = NSBezierPath(ovalIn: CGRect(x: 210, y: 170, width: 620, height: 320))
NSColor(calibratedRed: 0.29, green: 0.09, blue: 0.05, alpha: 0.18).setFill()
bottomGlow.fill()

let discRect = CGRect(x: 252, y: 212, width: 520, height: 520)
let discPath = NSBezierPath(ovalIn: discRect)
NSColor(calibratedRed: 0.18, green: 0.13, blue: 0.13, alpha: 0.95).setFill()
discPath.fill()

NSColor(calibratedRed: 0.43, green: 0.32, blue: 0.18, alpha: 0.7).setStroke()
discPath.lineWidth = 12
discPath.stroke()

for ringInset in [54, 108, 162] {
    let ringRect = discRect.insetBy(dx: CGFloat(ringInset), dy: CGFloat(ringInset))
    let ringPath = NSBezierPath(ovalIn: ringRect)
    NSColor(calibratedRed: 0.89, green: 0.74, blue: 0.42, alpha: 0.12).setStroke()
    ringPath.lineWidth = 8
    ringPath.stroke()
}

let coreRect = discRect.insetBy(dx: 192, dy: 192)
let corePath = NSBezierPath(ovalIn: coreRect)
NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.46, alpha: 0.95).setFill()
corePath.fill()

let noteColor = NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.92, alpha: 0.98)
noteColor.setFill()

let leftStem = NSBezierPath(roundedRect: CGRect(x: 500, y: 448, width: 42, height: 218), xRadius: 21, yRadius: 21)
leftStem.fill()

let beam = NSBezierPath(roundedRect: CGRect(x: 500, y: 620, width: 158, height: 44), xRadius: 22, yRadius: 22)
beam.fill()

let rightStem = NSBezierPath(roundedRect: CGRect(x: 616, y: 486, width: 42, height: 178), xRadius: 21, yRadius: 21)
rightStem.fill()

let leftHead = NSBezierPath(ovalIn: CGRect(x: 394, y: 362, width: 150, height: 118))
leftHead.fill()

let rightHead = NSBezierPath(ovalIn: CGRect(x: 544, y: 322, width: 150, height: 118))
rightHead.fill()

let accent = NSBezierPath(roundedRect: CGRect(x: 250, y: 250, width: 112, height: 28), xRadius: 14, yRadius: 14)
NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.82, alpha: 0.34).setFill()
accent.fill()

context.setShadow(
    offset: CGSize(width: 0, height: -18),
    blur: 40,
    color: NSColor(calibratedWhite: 0.0, alpha: 0.22).cgColor
)
let shadowPath = NSBezierPath(
    roundedRect: insetCanvas,
    xRadius: cornerRadius,
    yRadius: cornerRadius
)
NSColor.clear.setFill()
shadowPath.fill()
context.setShadow(offset: .zero, blur: 0, color: nil)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
