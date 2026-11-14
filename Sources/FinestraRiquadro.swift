import AppKit

final class Pannello: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Sfondo del riquadro: accetta i file anche dove la griglia è vuota.
final class SfondoRiquadro: NSVisualEffectView {
    weak var griglia: GrigliaFile?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { griglia?.apriCartella() }
        else { super.mouseDown(with: event) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        griglia?.operazione(per: sender) ?? []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        griglia?.operazione(per: sender) ?? []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        griglia?.accetta(sender) ?? false
    }
}

/// Un riquadro sulla scrivania: finestra, barra delle schede e griglia dei file.
final class ControlloreRiquadro: NSObject, NSWindowDelegate {
    let id: UUID
    let pannello: Pannello
    private let barra = BarraSchede()
    private let griglia = GrigliaFile()
    private let vuoto = NSTextField(labelWithString: "Trascina qui i file")
    private let tinta = NSView()
    var allaEliminazione: ((UUID) -> Void)?

    private var archivio: Archivio { .shared }
    private var riquadro: Riquadro {
        get { archivio.riquadri[archivio.indice(id)!] }
        set { archivio.riquadri[archivio.indice(id)!] = newValue; archivio.salva() }
    }

    static let livello = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    init(riquadro: Riquadro) {
        id = riquadro.id
        pannello = Pannello(contentRect: riquadro.frame,
                            styleMask: [.borderless, .nonactivatingPanel, .resizable],
                            backing: .buffered, defer: false)
        super.init()

        // Appena sopra le icone della scrivania, sotto tutte le finestre normali.
        pannello.isFloatingPanel = false
        pannello.level = Self.livello
        pannello.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        pannello.hidesOnDeactivate = false
        pannello.isReleasedWhenClosed = false
        pannello.isOpaque = false
        pannello.backgroundColor = .clear
        pannello.hasShadow = true
        pannello.minSize = NSSize(width: 220, height: 150)
        pannello.delegate = self

        let sfondo = SfondoRiquadro()
        sfondo.griglia = griglia
        sfondo.material = .hudWindow
        sfondo.blendingMode = .behindWindow
        sfondo.state = .active
        sfondo.wantsLayer = true
        sfondo.layer?.cornerRadius = 12
        sfondo.layer?.masksToBounds = true
        sfondo.layer?.borderWidth = 1
        sfondo.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        sfondo.registerForDraggedTypes([.fileURL])
        pannello.contentView = sfondo

        barra.translatesAutoresizingMaskIntoConstraints = false
        vuoto.translatesAutoresizingMaskIntoConstraints = false
        vuoto.textColor = .tertiaryLabelColor
        vuoto.font = .systemFont(ofSize: 12)
        tinta.wantsLayer = true
        tinta.autoresizingMask = [.width, .height]
        tinta.frame = sfondo.bounds
        sfondo.addSubview(tinta)
        sfondo.addSubview(griglia.scorrimento)
        sfondo.addSubview(vuoto)
        sfondo.addSubview(barra)
        NSLayoutConstraint.activate([
            barra.topAnchor.constraint(equalTo: sfondo.topAnchor),
            barra.leadingAnchor.constraint(equalTo: sfondo.leadingAnchor),
            barra.trailingAnchor.constraint(equalTo: sfondo.trailingAnchor),
            barra.heightAnchor.constraint(equalToConstant: 32),
            griglia.scorrimento.topAnchor.constraint(equalTo: barra.bottomAnchor),
            griglia.scorrimento.leadingAnchor.constraint(equalTo: sfondo.leadingAnchor),
            griglia.scorrimento.trailingAnchor.constraint(equalTo: sfondo.trailingAnchor),
            griglia.scorrimento.bottomAnchor.constraint(equalTo: sfondo.bottomAnchor, constant: -4),
            vuoto.centerXAnchor.constraint(equalTo: griglia.scorrimento.centerXAnchor),
            vuoto.centerYAnchor.constraint(equalTo: griglia.scorrimento.centerYAnchor),
        ])

        griglia.alCambioOrdine = { [weak self] o in
            guard let self else { return }
            var r = self.riquadro
            r.schede[min(r.schedaAttiva, r.schede.count - 1)].ordine = o.rawValue
            self.riquadro = r
        }
        barra.allaSelezione = { [weak self] i in self?.seleziona(i) }
        barra.alRinomina = { [weak self] i in self?.rinominaScheda(i) }
        barra.allAggiunta = { [weak self] in self?.nuovaScheda() }
        barra.menuScheda = { [weak self] i in self?.menuScheda(i) }
        barra.menuRiquadro = { [weak self] in self?.menuRiquadro() ?? NSMenu() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(aggiornaVuoto),
            name: NSView.frameDidChangeNotification, object: griglia.vista)

        allineaCartella()
        riportaSulloSchermo()
        aggiorna()
        pannello.orderFront(nil)
    }

    // MARK: Stato

    private func aggiorna() {
        let r = riquadro
        barra.bloccato = r.bloccato
        tinta.layer?.backgroundColor = Tinta.colore(r.colore)?.withAlphaComponent(0.45).cgColor
        barra.aggiorna(nomi: r.schede.map(\.nome), attiva: r.schedaAttiva)
        if r.bloccato { pannello.styleMask.remove(.resizable) }
        else { pannello.styleMask.insert(.resizable) }
        pannello.level = Self.livello
        let scheda = r.schede[min(r.schedaAttiva, r.schede.count - 1)]
        let ordine = Ordine(rawValue: scheda.ordine ?? "") ?? .nome
        if griglia.cartella != scheda.url {
            griglia.ordine = ordine
            griglia.mostra(cartella: scheda.url)
        } else if griglia.ordine != ordine {
            griglia.ordine = ordine
            griglia.ricarica()
        }
        aggiornaVuoto()
    }

    @objc private func aggiornaVuoto() {
        vuoto.isHidden = griglia.vista.numberOfItems(inSection: 0) > 0
    }

    private func riportaSulloSchermo() {
        let visibile = NSScreen.screens.contains { $0.visibleFrame.intersects(pannello.frame) }
        guard !visibile, let schermo = NSScreen.main else { return }
        let f = pannello.frame
        pannello.setFrameOrigin(NSPoint(x: schermo.visibleFrame.midX - f.width / 2,
                                        y: schermo.visibleFrame.midY - f.height / 2))
        salvaFrame()
    }

    private func salvaFrame() {
        let f = pannello.frame
        var r = riquadro
        r.x = f.origin.x; r.y = f.origin.y
        r.larghezza = f.width; r.altezza = f.height
        riquadro = r
    }

    func windowDidMove(_ notification: Notification) { salvaFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { salvaFrame() }

    /// Porta una cartella al nome voluto. Restituisce il percorso finale (invariato se non serve o non riesce).
    private func rinominata(_ url: URL, in voluto: String) -> URL {
        let fm = FileManager.default
        let attuale = url.lastPathComponent
        if attuale == voluto { return url }
        let genitore = url.deletingLastPathComponent()
        let diretto = genitore.appendingPathComponent(voluto, isDirectory: true)
        var destinazione = diretto
        // Cambio di sole maiuscole/minuscole: è la stessa cartella, si rinomina direttamente.
        let soloMaiuscole = attuale.caseInsensitiveCompare(voluto) == .orderedSame
        if !soloMaiuscole, fm.fileExists(atPath: diretto.path) {
            // Nome già preso da un'altra cartella: "nome 2", "nome 3" vanno bene così.
            if attuale.hasPrefix(voluto + " "), Int(attuale.dropFirst(voluto.count + 1)) != nil { return url }
            destinazione = Archivio.urlLibero(in: genitore, nome: voluto)
        }
        return (try? fm.moveItem(at: url, to: destinazione)) != nil ? destinazione : url
    }

    /// Le cartelle seguono i nomi: quella del riquadro prende il nome della prima scheda,
    /// quelle dentro il nome di ogni scheda. Così si riconoscono nel Finder.
    private func allineaCartella() {
        var r = riquadro
        guard let prima = r.schede.first else { return }
        let vecchia = r.url.standardizedFileURL
        let nuova = rinominata(vecchia, in: Archivio.nomePulito(prima.nome)).standardizedFileURL
        if nuova.path != vecchia.path {
            r.cartella = nuova.path
            for i in r.schede.indices {
                let p = URL(fileURLWithPath: r.schede[i].cartella).standardizedFileURL.path
                if p.hasPrefix(vecchia.path + "/") {
                    r.schede[i].cartella = nuova.path + p.dropFirst(vecchia.path.count)
                }
            }
        }
        for i in r.schede.indices {
            r.schede[i].cartella = rinominata(r.schede[i].url, in: Archivio.nomePulito(r.schede[i].nome)).path
        }
        riquadro = r
    }

    // MARK: Schede

    private func seleziona(_ i: Int) {
        guard i != riquadro.schedaAttiva else { return }
        riquadro.schedaAttiva = i
        aggiorna()
    }

    private func nuovaScheda() {
        guard let nome = chiediTesto(titolo: "Nome della nuova scheda", valore: "Scheda \(riquadro.schede.count + 1)")
        else { return }
        let cartella = Archivio.creaCartella(in: riquadro.url, nome: nome)
        var r = riquadro
        r.schede.append(Scheda(nome: nome, cartella: cartella.path))
        r.schedaAttiva = r.schede.count - 1
        riquadro = r
        aggiorna()
    }

    private func rinominaScheda(_ i: Int) {
        let scheda = riquadro.schede[i]
        guard let nome = chiediTesto(titolo: "Rinomina scheda", valore: scheda.nome), nome != scheda.nome
        else { return }
        var r = riquadro
        r.schede[i].nome = nome
        riquadro = r
        allineaCartella()
        aggiorna()
    }

    private func eliminaScheda(_ i: Int) {
        guard riquadro.schede.count > 1 else { return }
        let scheda = riquadro.schede[i]
        guard chiediConferma(
            titolo: "Eliminare la scheda “\(scheda.nome)”?",
            dettaglio: "I file restano nella cartella \(scheda.cartella).",
            bottone: "Elimina scheda") else { return }
        var r = riquadro
        r.schede.remove(at: i)
        r.schedaAttiva = min(r.schedaAttiva, r.schede.count - 1)
        if i < riquadro.schedaAttiva { r.schedaAttiva = riquadro.schedaAttiva - 1 }
        riquadro = r
        allineaCartella()
        aggiorna()
    }

    // MARK: Menu

    private func voce(_ titolo: String, _ azione: Selector, tag: Int = 0, attiva: Bool = true) -> NSMenuItem {
        let v = NSMenuItem(title: titolo, action: attiva ? azione : nil, keyEquivalent: "")
        v.target = self
        v.tag = tag
        return v
    }

    private func menuScheda(_ i: Int) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(voce("Rinomina scheda…", #selector(azioneRinomina(_:)), tag: i))
        let elimina = voce("Elimina scheda", #selector(azioneEliminaScheda(_:)), tag: i)
        elimina.isEnabled = riquadro.schede.count > 1
        menu.addItem(elimina)
        return menu
    }

    private func menuRiquadro() -> NSMenu {
        let r = riquadro
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(voce("Nuova scheda…", #selector(azioneNuovaScheda)))
        menu.addItem(voce("Rinomina scheda…", #selector(azioneRinomina(_:)), tag: r.schedaAttiva))
        let elimina = voce("Elimina scheda", #selector(azioneEliminaScheda(_:)), tag: r.schedaAttiva)
        elimina.isEnabled = r.schede.count > 1
        menu.addItem(elimina)
        menu.addItem(.separator())
        menu.addItem(voce(r.bloccato ? "Sblocca riquadro" : "Blocca riquadro", #selector(azioneBlocca)))
        menu.addItem(griglia.voceOrdine())
        let colori = NSMenuItem(title: "Colore di sfondo", action: nil, keyEquivalent: "")
        let sotto = NSMenu()
        sotto.autoenablesItems = false
        let base = voce("Predefinito", #selector(azioneColore(_:)))
        base.image = Tinta.campione(nil)
        base.state = r.colore == nil ? .on : .off
        sotto.addItem(base)
        sotto.addItem(.separator())
        for t in Tinta.tutte {
            let v = voce(t.nome, #selector(azioneColore(_:)))
            v.representedObject = t.nome
            v.image = Tinta.campione(t.colore)
            v.state = r.colore == t.nome ? .on : .off
            sotto.addItem(v)
        }
        colori.submenu = sotto
        menu.addItem(colori)
        menu.addItem(voce("Apri la cartella nel Finder", #selector(azioneFinder)))
        menu.addItem(.separator())
        menu.addItem(voce("Elimina riquadro…", #selector(azioneEliminaRiquadro)))
        return menu
    }

    @objc private func azioneNuovaScheda() { nuovaScheda() }
    @objc private func azioneRinomina(_ s: NSMenuItem) { rinominaScheda(s.tag) }
    @objc private func azioneEliminaScheda(_ s: NSMenuItem) { eliminaScheda(s.tag) }
    @objc private func azioneBlocca() { riquadro.bloccato.toggle(); aggiorna() }
    @objc private func azioneColore(_ s: NSMenuItem) {
        riquadro.colore = s.representedObject as? String
        aggiorna()
    }
    @objc private func azioneFinder() { griglia.apriCartella() }

    @objc private func azioneEliminaRiquadro() {
        guard chiediConferma(
            titolo: "Eliminare questo riquadro?",
            dettaglio: "I file restano nella cartella \(riquadro.cartella).",
            bottone: "Elimina riquadro") else { return }
        pannello.close()
        allaEliminazione?(id)
    }
}
