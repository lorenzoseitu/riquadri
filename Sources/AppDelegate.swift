import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var voceBarra: NSStatusItem!
    private var controllori: [UUID: ControlloreRiquadro] = [:]
    private let voceLogin = NSMenuItem(title: "Avvia all'accensione", action: #selector(cambiaLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        creaMenuPrincipale()

        voceBarra = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        voceBarra.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Riquadri")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Nuovo riquadro", action: #selector(nuovoRiquadro), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Apri la cartella dei file", action: #selector(apriRadice), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Sposta la cartella dei file…", action: #selector(spostaRadice), keyEquivalent: "").target = self
        menu.addItem(.separator())
        voceLogin.target = self
        menu.addItem(voceLogin)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Esci da Riquadri", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        voceBarra.menu = menu

        for riquadro in Archivio.shared.riquadri { apri(riquadro) }
        if Archivio.shared.riquadri.isEmpty { nuovoRiquadro() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        voceLogin.state = AvvioLogin.attivo ? .on : .off
    }

    /// Menu Modifica invisibile: serve per copia/incolla nei campi di testo.
    private func creaMenuPrincipale() {
        let principale = NSMenu()
        let modifica = NSMenuItem()
        let sotto = NSMenu(title: "Modifica")
        sotto.addItem(withTitle: "Annulla", action: Selector(("undo:")), keyEquivalent: "z")
        sotto.addItem(withTitle: "Taglia", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        sotto.addItem(withTitle: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        sotto.addItem(withTitle: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        sotto.addItem(withTitle: "Seleziona tutto", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        modifica.submenu = sotto
        principale.addItem(modifica)
        NSApp.mainMenu = principale
    }

    private func apri(_ riquadro: Riquadro) {
        let c = ControlloreRiquadro(riquadro: riquadro)
        c.allaEliminazione = { [weak self] id in
            self?.controllori[id] = nil
            Archivio.shared.riquadri.removeAll { $0.id == id }
            Archivio.shared.salva()
        }
        controllori[riquadro.id] = c
    }

    @objc private func nuovoRiquadro() {
        let cartella = Archivio.creaCartella(in: Archivio.radice, nome: "Generale")
        let prima = Archivio.creaCartella(in: cartella, nome: "Generale")
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let scarto = Double(Archivio.shared.riquadri.count % 10) * 28
        let dimensione = NSSize(width: 320, height: 240)
        let riquadro = Riquadro(
            x: area.midX - dimensione.width / 2 + scarto,
            y: area.midY - dimensione.height / 2 - scarto,
            larghezza: dimensione.width, altezza: dimensione.height,
            cartella: cartella.path,
            schede: [Scheda(nome: "Generale", cartella: prima.path)])
        Archivio.shared.riquadri.append(riquadro)
        Archivio.shared.salva()
        apri(riquadro)
    }

    @objc private func apriRadice() {
        try? FileManager.default.createDirectory(at: Archivio.radice, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Archivio.radice)
    }

    @objc private func spostaRadice() {
        NSApp.activate(ignoringOtherApps: true)
        let scelta = NSOpenPanel()
        scelta.canChooseDirectories = true
        scelta.canChooseFiles = false
        scelta.canCreateDirectories = true
        scelta.message = "Scegli dove mettere la cartella “Riquadri”. Ora è in \(Archivio.radice.deletingLastPathComponent().path)."
        scelta.prompt = "Sposta qui"
        guard scelta.runModal() == .OK, let genitore = scelta.url else { return }
        do {
            try Archivio.shared.spostaRadice(in: genitore)
        } catch {
            let avviso = NSAlert()
            avviso.messageText = "Impossibile spostare la cartella"
            avviso.informativeText = error.localizedDescription
            avviso.runModal()
            return
        }
        // Riapre i riquadri sui percorsi nuovi.
        controllori.values.forEach { $0.pannello.close() }
        controllori.removeAll()
        for riquadro in Archivio.shared.riquadri { apri(riquadro) }
    }

    @objc private func cambiaLogin() {
        if let errore = AvvioLogin.imposta(!AvvioLogin.attivo) {
            NSApp.activate(ignoringOtherApps: true)
            let avviso = NSAlert()
            avviso.messageText = "Impossibile cambiare l'avvio all'accensione"
            avviso.informativeText = errore
            avviso.runModal()
        }
    }
}
