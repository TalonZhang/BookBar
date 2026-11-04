import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

func icon(_ size: Int) throws -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = CGPath(roundedRect: CGRect(x: 97, y: 97, width: 830, height: 830),
                      cornerWidth: 190, cornerHeight: 190, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -15), blur: 40, color: color(0.13, 0.23, 0.18).copy(alpha: 0.32))
    context.addPath(tile)
    context.setFillColor(color(0.16, 0.36, 0.27))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(0.35, 0.57, 0.43), color(0.12, 0.31, 0.22)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 170, y: 920), end: CGPoint(x: 820, y: 130), options: [])
    context.restoreGState()

    context.saveGState()
    context.translateBy(x: 514, y: 507)
    context.rotate(by: .pi / 20)
    let cover = CGPath(roundedRect: CGRect(x: -179, y: -216, width: 365, height: 431),
                       cornerWidth: 45, cornerHeight: 45, transform: nil)
    context.setShadow(offset: CGSize(width: 15, height: -20), blur: 30, color: color(0.04, 0.17, 0.11).copy(alpha: 0.45))
    context.addPath(cover)
    context.setFillColor(color(0.12, 0.28, 0.21))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0)
    context.setFillColor(color(0.83, 0.79, 0.65))
    context.addPath(CGPath(roundedRect: CGRect(x: -148, y: -197, width: 311, height: 398),
                           cornerWidth: 28, cornerHeight: 28, transform: nil))
    context.fillPath()

    context.setFillColor(color(0.95, 0.90, 0.79))
    context.addPath(CGPath(roundedRect: CGRect(x: -164, y: -166, width: 336, height: 383),
                           cornerWidth: 32, cornerHeight: 32, transform: nil))
    context.fillPath()
    context.setFillColor(color(0.76, 0.73, 0.61))
    context.fill(CGRect(x: -110, y: -164, width: 9, height: 378))

    context.setStrokeColor(color(0.25, 0.42, 0.32))
    context.setLineCap(.round)
    context.setLineWidth(13)
    for (y, end) in [(91.0, 82.0), (54.0, 43.0), (17.0, 66.0)] {
        context.move(to: CGPoint(x: -60, y: y))
        context.addLine(to: CGPoint(x: end, y: y))
        context.strokePath()
    }

    let ribbon = CGMutablePath()
    ribbon.move(to: CGPoint(x: 65, y: -142))
    ribbon.addLine(to: CGPoint(x: 120, y: -142))
    ribbon.addLine(to: CGPoint(x: 120, y: -232))
    ribbon.addLine(to: CGPoint(x: 93, y: -214))
    ribbon.addLine(to: CGPoint(x: 65, y: -232))
    ribbon.closeSubpath()
    context.addPath(ribbon)
    context.setFillColor(color(0.81, 0.54, 0.36))
    context.fillPath()
    context.restoreGState()

    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

try icon(512).write(to: output)
