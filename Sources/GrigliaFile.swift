import AppKit
import Quartz
import QuickLookThumbnailing

/// Cella con icona e nome del file.
final class CellaFile: NSCollectionViewItem {
    static let identificatore = NSUserInterfaceItemIdentifier("CellaFile")

    private let icona = NSImageView()
    private let etichetta = NSTextField(wrappingLabelWithString: "")
    private var urlCorrente: URL?

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 88, height: 96))
        v.wantsLayer = true
        v.layer?.cornerRadius = 8

        icona.imageScaling = .scaleProportionallyUpOrDown
        icona.translatesAutoresizingMaskIntoConstraints = false
        icona.unregisterDraggedTypes()

        etichetta.font = .systemFont(ofSize: 11)
        etichetta.alignment = .center
        etichetta.maximumNumberOfLines = 2
        etichetta.lineBreakMode = .byTruncatingMiddle
        etichetta.cell?.truncatesLastVisibleLine = true
        etichetta.isSelectable = false
        etichetta.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(icona)
        v.addSubview(etichetta)
        NSLayoutConstraint.activate([
            icona.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
            icona.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            icona.widthAnchor.constraint(equalToConstant: 48),
            icona.heightAnchor.constraint(equalToConstant: 48),
            etichetta.topAnchor.constraint(equalTo: icona.bottomAnchor, constant: 4),
            etichetta.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 3),
            etichetta.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -3),
        ])
        view = v
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
                : NSColor.clear.cgColor
        }
    }

    func configura(url: URL) {
        urlCorrente = url
        etichetta.stringValue = FileManager.default.displayName(atPath: url.path)
        icona.image = NSWorkspace.shared.icon(forFile: url.path)

        let richiesta = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 48, height: 48),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: richiesta) { [weak self] rap, _ in
            guard let rap else { return }
            DispatchQueue.main.async {
                guard let self, self.urlCorrente == url else { return }
                self.icona.image = rap.nsImage
            }
        }
    }
}

/// Collection view con doppio clic, menu contestuale, tasti e Quick Look.
final class VistaGriglia: NSCollectionView {
    weak var griglia: GrigliaFile?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        // Doppio clic su un file lo apre; sullo sfondo apre la cartella della scheda.
        if indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil {
            griglia?.apriSelezionati()
        } else {
            griglia?.apriCartella()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let punto = convert(event.locationInWindow, from: nil)
        if let ip = indexPathForItem(at: punto) {
            if !selectionIndexPaths.contains(ip) {
                deselectAll(nil)
                selectItems(at: [ip], scrollPosition: [])
            }
            return griglia?.menuFile()
        }
        deselectAll(nil)
        return griglia?.menuVuoto()
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            griglia?.quickLook()
        } else if event.keyCode == 51, event.modifierFlags.contains(.command) {
            griglia?.cestinaSelezionati()
        } else if event.keyCode == 36 {
            griglia?.rinominaSelezionato()
        } else {
            super.keyDown(with: event)
        }
    }

    // Quick Look
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = griglia
        panel.delegate = griglia
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

/// Mostra i file di una cartella e gestisce trascinamento e azioni.
final class GrigliaFile: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate,
                         QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    let scorrimento = NSScrollView()
    let vista = VistaGriglia()
    private(set) var cartella: URL?
    private var file: [URL] = []
    private var sorvegliante: Sorvegliante?
    var ordine: Ordine = .nome
    var alCambioOrdine: ((Ordine) -> Void)?

    override init() {
        super.init()
        let disposizione = NSCollectionViewFlowLayout()
        disposizione.itemSize = NSSize(width: 88, height: 96)
        disposizione.minimumInteritemSpacing = 4
        disposizione.minimumLineSpacing = 4
        disposizione.sectionInset = NSEdgeInsets(top: 6, left: 8, bottom: 8, right: 8)

        vista.griglia = self
        vista.collectionViewLayout = disposizione
        vista.backgroundColors = [.clear]
        vista.isSelectable = true
        vista.allowsMultipleSelection = true
        vista.allowsEmptySelection = true
        vista.register(CellaFile.self, forItemWithIdentifier: CellaFile.identificatore)
        vista.dataSource = self
        vista.delegate = self
        vista.registerForDraggedTypes([.fileURL])
        vista.setDraggingSourceOperationMask([.move, .copy, .link], forLocal: false)
        vista.setDraggingSourceOperationMask(.move, forLocal: true)

        scorrimento.documentView = vista
        scorrimento.drawsBackground = false
        scorrimento.hasVerticalScroller = true
        scorrimento.autohidesScrollers = true
        scorrimento.translatesAutoresizingMaskIntoConstraints = false
    }

    func mostra(cartella nuova: URL) {
        cartella = nuova
        try? FileManager.default.createDirectory(at: nuova, withIntermediateDirectories: true)
        sorvegliante = Sorvegliante(cartella: nuova) { [weak self] in self?.ricarica() }
        ricarica()
    }

    func ricarica() {
        guard let cartella else { return }
        let selezionati = Set(selezione())
        let chiavi: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey,
                                           .fileSizeKey, .localizedTypeDescriptionKey]
        let elenco = (try? FileManager.default.contentsOfDirectory(
            at: cartella, includingPropertiesForKeys: Array(chiavi), options: [.skipsHiddenFiles])) ?? []
        let dati = elenco.map { ($0, try? $0.resourceValues(forKeys: chiavi)) }
        func perNome(_ a: URL, _ b: URL) -> Bool {
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        // Come nel Finder: date dalla più recente, dimensioni dalla più grande; a parità, per nome.
        file = dati.sorted { a, b in
            switch ordine {
            case .nome:
                break
            case .tipo:
                let (x, y) = (a.1?.localizedTypeDescription ?? "", b.1?.localizedTypeDescription ?? "")
                if x != y { return x.localizedStandardCompare(y) == .orderedAscending }
            case .modifica:
                let (x, y) = (a.1?.contentModificationDate ?? .distantPast, b.1?.contentModificationDate ?? .distantPast)
                if x != y { return x > y }
            case .creazione:
                let (x, y) = (a.1?.creationDate ?? .distantPast, b.1?.creationDate ?? .distantPast)
                if x != y { return x > y }
            case .dimensione:
                let (x, y) = (a.1?.fileSize ?? 0, b.1?.fileSize ?? 0)
                if x != y { return x > y }
            }
            return perNome(a.0, b.0)
        }.map(\.0)
        vista.reloadData()
        let daRiselezionare = Set(file.enumerated()
            .filter { selezionati.contains($0.element) }
            .map { IndexPath(item: $0.offset, section: 0) })
        if !daRiselezionare.isEmpty { vista.selectItems(at: daRiselezionare, scrollPosition: []) }
    }

    private func selezione() -> [URL] {
        vista.selectionIndexPaths.map(\.item).sorted().filter { $0 < file.count }.map { file[$0] }
    }

    // MARK: Dati

    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int { file.count }

    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cella = cv.makeItem(withIdentifier: CellaFile.identificatore, for: indexPath)
        (cella as? CellaFile)?.configura(url: file[indexPath.item])
        return cella
    }

    // MARK: Trascinamento

    func collectionView(_ cv: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        file[indexPath.item] as NSURL
    }

    func collectionView(_ cv: NSCollectionView, validateDrop info: NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        operazione(per: info)
    }

    func collectionView(_ cv: NSCollectionView, acceptDrop info: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        accetta(info)
    }

    func operazione(per info: NSDraggingInfo) -> NSDragOperation {
        if (info.draggingSource as? VistaGriglia) === vista { return [] }
        return .move
    }

    func accetta(_ info: NSDraggingInfo) -> Bool {
        let letti = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return importa(letti)
    }

    /// Sposta i file nella cartella della scheda.
    @discardableResult
    func importa(_ sorgenti: [URL]) -> Bool {
        guard let cartella, !sorgenti.isEmpty else { return false }
        let fm = FileManager.default
        var falliti: [String] = []
        for sorgente in sorgenti {
            let origine = sorgente.standardizedFileURL
            if origine.deletingLastPathComponent().path == cartella.standardizedFileURL.path { continue }
            // Mai spostare una cartella dentro se stessa.
            if cartella.standardizedFileURL.path.hasPrefix(origine.path + "/") { continue }
            let destinazione = Archivio.urlLibero(in: cartella, nome: origine.lastPathComponent)
            do { try fm.moveItem(at: origine, to: destinazione) }
            catch { falliti.append("\(origine.lastPathComponent): \(error.localizedDescription)") }
        }
        ricarica()
        if !falliti.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            let avviso = NSAlert()
            avviso.messageText = "Alcuni file non sono stati spostati"
            avviso.informativeText = falliti.joined(separator: "\n")
            avviso.runModal()
        }
        return true
    }

    // MARK: Azioni

    func menuFile() -> NSMenu {
        let menu = NSMenu()
        func voce(_ titolo: String, _ azione: Selector) {
            let v = NSMenuItem(title: titolo, action: azione, keyEquivalent: "")
            v.target = self
            menu.addItem(v)
        }
        voce("Apri", #selector(apriSelezionati))
        voce("Quick Look", #selector(quickLook))
        menu.addItem(.separator())
        if vista.selectionIndexPaths.count == 1 { voce("Rinomina…", #selector(rinominaSelezionato)) }
        voce("Mostra nel Finder", #selector(mostraNelFinder))
        menu.addItem(.separator())
        voce("Sposta nel Cestino", #selector(cestinaSelezionati))
        return menu
    }

    /// Voce "Ordina per" con i criteri, come nel Finder.
    func voceOrdine() -> NSMenuItem {
        let voce = NSMenuItem(title: "Ordina per", action: nil, keyEquivalent: "")
        let sotto = NSMenu()
        for o in Ordine.allCases {
            let v = NSMenuItem(title: o.titolo, action: #selector(scegliOrdine(_:)), keyEquivalent: "")
            v.target = self
            v.representedObject = o.rawValue
            v.state = o == ordine ? .on : .off
            sotto.addItem(v)
        }
        voce.submenu = sotto
        return voce
    }

    @objc private func scegliOrdine(_ s: NSMenuItem) {
        guard let o = Ordine(rawValue: s.representedObject as? String ?? "") else { return }
        ordine = o
        ricarica()
        alCambioOrdine?(o)
    }

    func menuVuoto() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(voceOrdine())
        let v = NSMenuItem(title: "Apri la cartella nel Finder", action: #selector(apriCartella), keyEquivalent: "")
        v.target = self
        menu.addItem(v)
        return menu
    }

    @objc func apriSelezionati() {
        selezione().forEach { NSWorkspace.shared.open($0) }
    }

    @objc func mostraNelFinder() {
        let s = selezione()
        if !s.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(s) }
    }

    @objc func apriCartella() {
        if let cartella { NSWorkspace.shared.open(cartella) }
    }

    @objc func cestinaSelezionati() {
        for url in selezione() { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        ricarica()
    }

    @objc func rinominaSelezionato() {
        guard let url = selezione().first, selezione().count == 1 else { return }
        guard let nuovo = chiediTesto(titolo: "Rinomina", valore: url.lastPathComponent) else { return }
        let nome = Archivio.nomePulito(nuovo)
        guard nome != url.lastPathComponent else { return }
        let destinazione = url.deletingLastPathComponent().appendingPathComponent(nome)
        if FileManager.default.fileExists(atPath: destinazione.path) {
            let avviso = NSAlert()
            avviso.messageText = "Esiste già un elemento con questo nome"
            avviso.runModal()
            return
        }
        try? FileManager.default.moveItem(at: url, to: destinazione)
        ricarica()
    }

    @objc func quickLook() {
        guard !selezione().isEmpty, let pannello = QLPreviewPanel.shared() else { return }
        if pannello.isVisible {
            pannello.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            vista.window?.makeFirstResponder(vista)
            pannello.makeKeyAndOrderFront(nil)
            pannello.reloadData()
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { selezione().count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let s = selezione()
        return index < s.count ? s[index] as NSURL : nil
    }
}
