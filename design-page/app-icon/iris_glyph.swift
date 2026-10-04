import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Iris glyph: a woman with a bob and big round glasses. Drawn on the 36px grid (2x of 18pt), y down,
// so every edge lands on a whole pixel at 2x. Pure paths (no knock-outs), so it is a real template image.
func rounded(_ pts: [(CGFloat, CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath(); let n = pts.count
    func pt(_ i: Int) -> CGPoint { CGPoint(x: pts[(i + n) % n].0, y: pts[(i + n) % n].1) }
    // start at the midpoint of the last edge so every corner can use addArc
    let start = CGPoint(x: (pt(n-1).x + pt(0).x) / 2, y: (pt(n-1).y + pt(0).y) / 2)
    p.move(to: start)
    for i in 0..<n { p.addArc(tangent1End: pt(i), tangent2End: pt(i + 1), radius: pts[i].2) }
    p.closeSubpath(); return p
}
let hair = rounded([(2, 34, 4), (2, 2, 12), (34, 2, 12), (34, 34, 4), (30, 34, 0), (30, 13, 7), (6, 13, 7), (6, 34, 0)])
func draw(_ c: CGContext) {
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.setStrokeColor(CGColor(gray: 0, alpha: 1))
    c.addPath(hair); c.fillPath()
    c.setLineWidth(2.5)
    for cx in [12.5, 23.5] as [CGFloat] { c.strokeEllipse(in: CGRect(x: cx - 3.75, y: 23 - 3.75, width: 7.5, height: 7.5)) }
    c.fill(CGRect(x: 17, y: 21.5, width: 2, height: 2))
}
func pdf(_ path: String) {
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    let c = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil)!
    c.beginPDFPage(nil); c.translateBy(x: 0, y: 18); c.scaleBy(x: 0.5, y: -0.5); draw(c); c.endPDFPage(); c.closePDF()
}
func png(_ path: String, f: Int) {
    let px = 36 * f
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(px)); c.scaleBy(x: CGFloat(f), y: -CGFloat(f)); draw(c)
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
}
pdf("IrisIcon.pdf"); png("IrisIcon_2x.png", f: 1); png("IrisIcon_big.png", f: 16)
