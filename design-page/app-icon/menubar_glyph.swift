import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Hatch menu bar glyph: the arch and dot from the app icon, drawn on an 18pt grid.
// Every edge (3, 5, 13, 15 pt across; 1.5 and 16.5 down; dot 7..11) lands on a whole pixel at 2x, so it renders crisp.
let canvas: CGFloat = 18
let cx: CGFloat = 9, W: CGFloat = 12, SW: CGFloat = 2
let top: CGFloat = 1.5, bottom: CGFloat = 16.5
let dotR: CGFloat = 2, dotTop: CGFloat = 11.5

func draw(_ ctx: CGContext, color: CGColor = CGColor(gray: 0, alpha: 1)) {
    func y(_ t: CGFloat) -> CGFloat { canvas - t }
    let rc = (W - SW) / 2
    let arcCenterY = top + W / 2
    let legEnd = bottom - SW / 2
    ctx.setStrokeColor(color); ctx.setFillColor(color)
    ctx.setLineWidth(SW); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: cx - rc, y: y(legEnd)))
    ctx.addLine(to: CGPoint(x: cx - rc, y: y(arcCenterY)))
    ctx.addArc(center: CGPoint(x: cx, y: y(arcCenterY)), radius: rc, startAngle: .pi, endAngle: 0, clockwise: true)
    ctx.addLine(to: CGPoint(x: cx + rc, y: y(legEnd)))
    ctx.strokePath()
    ctx.fillEllipse(in: CGRect(x: cx - dotR, y: y(dotTop) - dotR, width: dotR * 2, height: dotR * 2))
}

func writePDF(_ path: String) {
    var box = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let ctx = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF()
}
func writePNG(_ path: String, scale: Int, color: CGColor = CGColor(gray: 0, alpha: 1), bg: CGColor? = nil) {
    let px = Int(canvas) * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let bg { ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: px, height: px)) }
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale)); draw(ctx, color: color)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
}
writePDF("MenuBarIcon.pdf")
writePNG("MenuBarIcon.png", scale: 1)
writePNG("MenuBarIcon@2x.png", scale: 2)
writePNG("preview_big.png", scale: 24)
