// 앱 아이콘 생성 — 몬스터볼을 Core Graphics 로 그린다.
//
// 원작 에셋을 쓸 수 없으므로 도형으로 그린다: 위 절반(빨강), 아래 절반(흰색),
// 가운데 띠, 중앙 버튼. macOS 아이콘 관례대로 여백을 두고 살짝 입체감을 준다.
//
//   swift scripts/make-icon.swift <출력 디렉토리>
import AppKit
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func draw(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // macOS 아이콘은 사방에 여백을 둔다 (독에서 다른 앱과 크기가 맞아 보이게)
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let r = rect.width / 2
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let band = rect.width * 0.115      // 가운데 띠 두께
    let button = rect.width * 0.27
    let line = max(1, rect.width * 0.035)

    let ink = CGColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1)
    let red = CGColor(red: 0.90, green: 0.20, blue: 0.17, alpha: 1)
    let redDark = CGColor(red: 0.72, green: 0.13, blue: 0.12, alpha: 1)
    let white = CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
    let whiteDark = CGColor(red: 0.84, green: 0.85, blue: 0.87, alpha: 1)

    // 아래 절반 (흰색) — 위아래로 살짝 그라디언트
    ctx.saveGState()
    ctx.addEllipse(in: rect); ctx.clip()
    if let g = CGGradient(colorsSpace: cs, colors: [whiteDark, white] as CFArray,
                          locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: rect.minY),
                               end: CGPoint(x: c.x, y: c.y), options: [])
    }
    // 위 절반 (빨강)
    ctx.clip(to: CGRect(x: rect.minX, y: c.y, width: rect.width, height: r))
    if let g = CGGradient(colorsSpace: cs, colors: [redDark, red] as CFArray,
                          locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y),
                               end: CGPoint(x: c.x, y: rect.maxY), options: [])
    }
    ctx.restoreGState()

    // 가운데 띠
    ctx.setFillColor(ink)
    ctx.saveGState()
    ctx.addEllipse(in: rect); ctx.clip()
    ctx.fill(CGRect(x: rect.minX, y: c.y - band / 2, width: rect.width, height: band))
    ctx.restoreGState()

    // 중앙 버튼
    let btn = CGRect(x: c.x - button / 2, y: c.y - button / 2, width: button, height: button)
    ctx.setFillColor(ink); ctx.fillEllipse(in: btn)
    let inner = btn.insetBy(dx: line * 1.1, dy: line * 1.1)
    ctx.setFillColor(white); ctx.fillEllipse(in: inner)

    // 테두리
    ctx.setStrokeColor(ink); ctx.setLineWidth(line)
    ctx.strokeEllipse(in: rect.insetBy(dx: line / 2, dy: line / 2))

    // 위쪽 하이라이트 — 구슬처럼 보이게 (작은 크기에서는 생략)
    if size >= 64 {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
        ctx.fillEllipse(in: CGRect(x: rect.minX + rect.width * 0.2,
                                   y: rect.minY + rect.height * 0.66,
                                   width: rect.width * 0.34, height: rect.height * 0.18))
    }

    guard let img = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let setDir = out + "/AppIcon.iconset"
try? fm.createDirectory(atPath: setDir, withIntermediateDirectories: true)

// icns 가 요구하는 이름 규칙
let names: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
var made = 0
for (px, name) in names {
    guard let d = draw(size: px) else { continue }
    try? d.write(to: URL(fileURLWithPath: "\(setDir)/\(name).png"))
    made += 1
}
print("    아이콘 \(made)장 생성")
_ = sizes
