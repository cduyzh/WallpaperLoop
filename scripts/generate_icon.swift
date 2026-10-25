#!/usr/bin/env swift
import AppKit
import Foundation

// 原创矢量绘制，所有尺寸均由 1024 点设计坐标直接重绘。
// 用法：swift scripts/generate_icon.swift [资源目录]
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
}

func gradient(_ path: NSBezierPath, _ first: UInt32, _ last: UInt32, angle: CGFloat = -90) {
    NSGradient(starting: color(first), ending: color(last))!.draw(in: path, angle: angle)
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "IconRenderer", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)

    // 雾白圆角底板，与系统 Dock 图标一致的安全边距。
    let plate = rounded(72, 72, 880, 880, 196)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -16), blur: 24, color: color(0x25344A, 0.18).cgColor)
    gradient(plate, 0xFBFCFF, 0xE4EAF1)
    cg.restoreGState()
    plate.lineWidth = 2
    color(0xFFFFFF, 0.95).setStroke()
    plate.stroke()

    // 内嵌“屏幕”：动态壁纸的晨昏渐变是唯一的视觉主体。
    let screen = rounded(176, 236, 672, 470, 64)
    screen.addClip()
    NSGradient(colors: [color(0x2C3E7A), color(0x6C63C8), color(0xE98A6D), color(0xF6C89A)])!
        .draw(in: screen, angle: -90)

    // 地平线以下的深色地面，稳住构图。
    let ground = NSBezierPath(rect: NSRect(x: 176, y: 236, width: 672, height: 132))
    color(0x1D2440).setFill()
    ground.fill()

    // 太阳：晨昏线上的一轮低角度光源。
    cg.saveGState()
    let sun = NSBezierPath(ovalIn: NSRect(x: 428, y: 470, width: 168, height: 168))
    cg.setShadow(offset: .zero, blur: 42, color: color(0xFFD9A0, 0.85).cgColor)
    gradient(sun, 0xFFE7BE, 0xF2A65E)
    cg.restoreGState()

    // 远山剪影两层，制造纵深。
    let farHill = NSBezierPath()
    farHill.move(to: NSPoint(x: 176, y: 372))
    farHill.curve(to: NSPoint(x: 848, y: 372), controlPoint1: NSPoint(x: 360, y: 462), controlPoint2: NSPoint(x: 560, y: 300))
    farHill.line(to: NSPoint(x: 848, y: 236))
    farHill.line(to: NSPoint(x: 176, y: 236))
    farHill.close()
    color(0x273058, 0.85).setFill()
    farHill.fill()
    let nearHill = NSBezierPath()
    nearHill.move(to: NSPoint(x: 176, y: 340))
    nearHill.curve(to: NSPoint(x: 848, y: 340), controlPoint1: NSPoint(x: 430, y: 428), controlPoint2: NSPoint(x: 680, y: 288))
    nearHill.line(to: NSPoint(x: 848, y: 236))
    nearHill.line(to: NSPoint(x: 176, y: 236))
    nearHill.close()
    color(0x1B2242, 0.94).setFill()
    nearHill.fill()
    NSGraphicsContext.current?.cgContext.resetClip()

    // 播放三角水印：一帧视频正在播放的语义，克制地放在地面上方。
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 488, y: 460))
    play.line(to: NSPoint(x: 488, y: 556))
    play.line(to: NSPoint(x: 572, y: 508))
    play.close()
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 18, color: color(0xFFFFFF, 0.55).cgColor)
    color(0xFFFFFF, 0.96).setFill()
    play.fill()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconRenderer", code: 2)
    }
    return png
}

let mainIcon = output.appendingPathComponent("AppIcon_1024.png")
try drawIcon(size: 1024).write(to: mainIcon)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }
for base in [16, 32, 128, 256, 512] {
    try drawIcon(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try drawIcon(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", output.appendingPathComponent("AppIcon.icns").path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconRenderer", code: Int(process.terminationStatus))
}
print("已生成 \(mainIcon.path) 与 AppIcon.icns")
