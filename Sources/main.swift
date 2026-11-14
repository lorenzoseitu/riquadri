import AppKit

let app = NSApplication.shared
let delegato = AppDelegate()
app.delegate = delegato
app.setActivationPolicy(.accessory)
app.run()
