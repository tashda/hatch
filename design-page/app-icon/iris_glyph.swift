import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Iris glyph: a bitter old woman with her hair parted and gathered in a bun, glaring over round glasses (round 3 of
// the Iris mark review, owner's pick 2026-10-05). Drawn on the 36-unit grid (18 pt at 2x), y down. The rims' outer
// edges, the bun's sides and top and the hair's sides land on whole pixels at 2x. Every part is merged into one
// outline, and the hair tie and the gap around the lenses are subtracted, so it is a real template image with no
// overlaps or knock-outs. Run with `swift iris_glyph.swift` and copy IrisIcon.pdf into the asset catalog.

// MARK: Geometry

let eyeY: CGFloat = 25.5            // lens centres, so the rims span y 20 to 31
let lensX: [CGFloat] = [11.5, 24.5] // so the rims span x 6 to 17 and 19 to 30
let rimR: CGFloat = 4.25            // to the middle of the rim
let rimW: CGFloat = 2.5             // outer radius 5.5, inner radius 3
let lineW: CGFloat = 2.1            // bridge and arms, a touch lighter than the rims
let lidTilt: CGFloat = 20           // degrees; the outer corner of each lid is high, the inner low
let haloGap: CGFloat = 1.1          // hair kept clear of the rims, so the glasses sit in front
let drop: CGFloat = 2               // the hair and bun are drawn high and moved down to sit on the face

/// Parses the absolute M, L, C and Z commands the hair is written in.
func svgPath(_ d: String, _ t: CGAffineTransform = .identity) -> CGPath {
    let p = CGMutablePath()
    var tokens: [String] = []
    var cur = ""
    for ch in d {
        if "MLCZ".contains(ch) { if !cur.isEmpty { tokens.append(cur); cur = "" }; tokens.append(String(ch)) }
        else if ch == " " || ch == "," || ch == "\n" { if !cur.isEmpty { tokens.append(cur); cur = "" } }
        else { cur.append(ch) }
    }
    if !cur.isEmpty { tokens.append(cur) }
    var i = 0
    func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    func pt() -> CGPoint { CGPoint(x: num(), y: num()) }
    var cmd = ""
    while i < tokens.count {
        if "MLCZ".contains(tokens[i]) { cmd = tokens[i]; i += 1 }
        switch cmd {
        case "M": p.move(to: pt(), transform: t); cmd = "L"
        case "L": p.addLine(to: pt(), transform: t)
        case "C": let a = pt(), b = pt(), c = pt(); p.addCurve(to: c, control1: a, control2: b, transform: t)
        case "Z": p.closeSubpath()
        default: fatalError("unsupported command \(cmd)")
        }
    }
    return p
}

func stroked(_ build: (CGMutablePath) -> Void, width: CGFloat) -> CGPath {
    let p = CGMutablePath(); build(p)
    return p.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func rad(_ deg: CGFloat) -> CGFloat { deg * .pi / 180 }

// Hair: parted in the middle, the two sides falling to the temples and ending clear of the rims. Narrowed a little about the centre so its sides
// land on x 5 and 31. Every joint is smooth except the parting.
let narrow = CGAffineTransform(translationX: 18, y: drop).scaledBy(x: 13 / 13.2, y: 1).translatedBy(x: -18, y: 0)
let hair = svgPath("""
    M18 6.4 C25.8 6.4 31.2 11.2 31.2 17.2 C31.2 17.9 31 18.5 30.7 18.9 C30.3 19.43 29.5 19.3 29.3 18.7
    C28.7 16.9 26.82 15.81 24.4 14.6 C22.2 13.5 19.7 13.2 18 11.8 C16.3 13.2 13.8 13.5 11.6 14.6
    C9.18 15.81 7.3 16.9 6.7 18.7 C6.5 19.3 5.7 19.43 5.3 18.9 C5 18.5 4.8 17.9 4.8 17.2 C4.8 11.2 10.2 6.4 18 6.4 Z
    """, narrow)

// Bun: wider than the band that gathers it, so it reads as a knot of hair rather than a pompom. Top at y 3, sides at
// x 13 and 23.
let bun = CGPath(ellipseIn: CGRect(x: 13, y: 1 + drop, width: 10, height: 7.6), transform: nil)
let band = CGPath(roundedRect: CGRect(x: 14.5, y: 5.6 + drop, width: 7, height: 3), cornerWidth: 1, cornerHeight: 1, transform: nil)
// The hair tie: a gap cut between the bun and the head.
let tie = stroked({ p in
    p.move(to: CGPoint(x: 14.7, y: 8.6 + drop))
    p.addQuadCurve(to: CGPoint(x: 21.3, y: 8.6 + drop), control: CGPoint(x: 18, y: 9.9 + drop))
}, width: 1.5)

var head = hair.union(bun).union(band).subtracting(tie)
for x in lensX {
    let r = rimR + rimW / 2 + haloGap
    head = head.subtracting(CGPath(ellipseIn: CGRect(x: x - r, y: eyeY - r, width: 2 * r, height: 2 * r), transform: nil))
}

// Glasses.
var glasses = CGMutablePath() as CGPath
for x in lensX {
    let rim = stroked({ $0.addEllipse(in: CGRect(x: x - rimR, y: eyeY - rimR, width: 2 * rimR, height: 2 * rimR)) }, width: rimW)
    glasses = glasses.union(rim)
}
// Lids: a segment of a circle just past the inside of the rim, so the lid meets the rim with no sliver.
let lidR = rimR - rimW / 2 + 0.45
func lid(_ x: CGFloat, from a0: CGFloat, to a1: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addArc(center: CGPoint(x: x, y: eyeY), radius: lidR, startAngle: rad(a0), endAngle: rad(a1), clockwise: false)
    p.closeSubpath()
    return p
}
glasses = glasses.union(lid(lensX[0], from: 180 + lidTilt, to: 366))
glasses = glasses.union(lid(lensX[1], from: 174, to: 360 - lidTilt))
// Bridge: a low arch whose ends sit inside both rims.
glasses = glasses.union(stroked({ p in
    p.move(to: CGPoint(x: lensX[0] + rimR - 0.3, y: eyeY - 1.2))
    p.addQuadCurve(to: CGPoint(x: lensX[1] - rimR + 0.3, y: eyeY - 1.2), control: CGPoint(x: 18, y: eyeY - 3.4))
}, width: lineW))
// Arms: from the top outer edge of each rim across the gap and into the tip of the hair at the temple.
let armA = rad(220)
let armTip: [CGPoint] = [CGPoint(x: 6.7, y: 18.1 + drop), CGPoint(x: 29.3, y: 18.1 + drop)]
glasses = glasses.union(stroked({ p in
    p.move(to: CGPoint(x: lensX[0] + rimR * cos(armA), y: eyeY + rimR * sin(armA))); p.addLine(to: armTip[0])
    p.move(to: CGPoint(x: lensX[1] - rimR * cos(armA), y: eyeY + rimR * sin(armA))); p.addLine(to: armTip[1])
}, width: lineW))

let glyph = head.union(glasses)

// MARK: Output

func draw(_ c: CGContext) {
    c.setFillColor(CGColor(gray: 0, alpha: 1))
    c.addPath(glyph); c.fillPath()
}
func pdf(_ path: String) {
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    let c = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil)!
    c.beginPDFPage(nil); c.translateBy(x: 0, y: 18); c.scaleBy(x: 0.5, y: -0.5); draw(c); c.endPDFPage(); c.closePDF()
}
/// `px` is the image size; 18 is 1x, 36 is 2x.
func png(_ path: String, px: Int, background: CGFloat? = nil, ink: CGFloat = 0) {
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let b = background { c.setFillColor(CGColor(gray: b, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: px, height: px)) }
    let f = CGFloat(px) / 36
    c.translateBy(x: 0, y: CGFloat(px)); c.scaleBy(x: f, y: -f)
    c.setFillColor(CGColor(gray: ink, alpha: 1)); c.addPath(glyph); c.fillPath()
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
}
pdf("IrisIcon.pdf")
png("IrisIcon_1x.png", px: 18, background: 1)
png("IrisIcon_2x.png", px: 36, background: 1)
png("IrisIcon_big.png", px: 576, background: 1)
png("IrisIcon_dark_2x.png", px: 36, background: 0.12, ink: 0.95)
