import AppKit

// Disegna l'icona dell'app (1024 px) e la salva come PNG nel percorso passato.
let lato = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: lato, pixelsHigh: lato,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let fondo = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.16, green: 0.20, blue: 0.30, alpha: 1),
           ending: NSColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1))!.draw(in: fondo, angle: -90)

let colori: [NSColor] = [
    NSColor(red: 0.36, green: 0.78, blue: 0.98, alpha: 1),
    NSColor(red: 0.98, green: 0.78, blue: 0.30, alpha: 1),
    NSColor(red: 0.55, green: 0.88, blue: 0.62, alpha: 1),
    NSColor(red: 0.95, green: 0.52, blue: 0.55, alpha: 1),
]
// Quattro riquadri di misure diverse.
let rettangoli = [
    NSRect(x: 220, y: 540, width: 330, height: 264),
    NSRect(x: 590, y: 620, width: 214, height: 184),
    NSRect(x: 220, y: 220, width: 214, height: 280),
    NSRect(x: 474, y: 220, width: 330, height: 360),
]
for (r, c) in zip(rettangoli, colori) {
    c.setFill()
    NSBezierPath(roundedRect: r, xRadius: 44, yRadius: 44).fill()
}

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
