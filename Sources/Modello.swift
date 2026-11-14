import AppKit

struct Scheda: Codable {
    var id = UUID()
    var nome: String
    var cartella: String
    /// Criterio di ordinamento dei file (vedi `Ordine`); nil = per nome.
    var ordine: String?

    var url: URL { URL(fileURLWithPath: cartella, isDirectory: true) }
}

enum Ordine: String, CaseIterable {
    case nome, tipo, modifica, creazione, dimensione

    var titolo: String {
        switch self {
        case .nome: return "Nome"
        case .tipo: return "Tipo"
        case .modifica: return "Data di modifica"
        case .creazione: return "Data di creazione"
        case .dimensione: return "Dimensione"
        }
    }
}

struct Riquadro: Codable {
    var id = UUID()
    var x: Double
    var y: Double
    var larghezza: Double
    var altezza: Double
    var bloccato = false
    var cartella: String
    var schede: [Scheda]
    var schedaAttiva = 0
    /// Nome del colore di sfondo (vedi `Tinta`); nil = predefinito.
    var colore: String?

    var frame: NSRect { NSRect(x: x, y: y, width: larghezza, height: altezza) }
    var url: URL { URL(fileURLWithPath: cartella, isDirectory: true) }
}

final class Archivio {
    static let shared = Archivio()

    /// Cartella che contiene i file di tutti i riquadri. Si cambia dal menu nella barra.
    static var radice: URL {
        if let scelta = UserDefaults.standard.string(forKey: "radice") {
            return URL(fileURLWithPath: scelta, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Riquadri", isDirectory: true)
    }

    struct ErroreSpostamento: LocalizedError {
        let errorDescription: String?
    }

    /// Sposta la cartella "Riquadri" con tutto il contenuto dentro `genitore` e aggiorna i percorsi.
    func spostaRadice(in genitore: URL) throws {
        let fm = FileManager.default
        let vecchia = Self.radice.standardizedFileURL
        let nuova = genitore.appendingPathComponent("Riquadri", isDirectory: true).standardizedFileURL
        if nuova.path == vecchia.path { return }
        if (nuova.path + "/").hasPrefix(vecchia.path + "/") {
            throw ErroreSpostamento(errorDescription: "La nuova posizione non può stare dentro la cartella attuale.")
        }
        if fm.fileExists(atPath: nuova.path) {
            throw ErroreSpostamento(errorDescription: "In quella posizione esiste già una cartella “Riquadri”.")
        }
        if fm.fileExists(atPath: vecchia.path) {
            try fm.moveItem(at: vecchia, to: nuova)
        } else {
            try fm.createDirectory(at: nuova, withIntermediateDirectories: true)
        }
        func aggiornato(_ percorso: String) -> String {
            let p = URL(fileURLWithPath: percorso).standardizedFileURL.path
            guard p == vecchia.path || p.hasPrefix(vecchia.path + "/") else { return percorso }
            return nuova.path + p.dropFirst(vecchia.path.count)
        }
        for i in riquadri.indices {
            riquadri[i].cartella = aggiornato(riquadri[i].cartella)
            for j in riquadri[i].schede.indices {
                riquadri[i].schede[j].cartella = aggiornato(riquadri[i].schede[j].cartella)
            }
        }
        UserDefaults.standard.set(nuova.path, forKey: "radice")
        salva()
    }

    private static let fileStato: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Riquadri", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("riquadri.json")
    }()

    var riquadri: [Riquadro] = []

    private init() {
        if let dati = try? Data(contentsOf: Self.fileStato),
           let letti = try? JSONDecoder().decode([Riquadro].self, from: dati) {
            riquadri = letti
        }
    }

    func salva() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let dati = try? enc.encode(riquadri) else { return }
        try? dati.write(to: Self.fileStato, options: .atomic)
    }

    func indice(_ id: UUID) -> Int? { riquadri.firstIndex { $0.id == id } }

    // MARK: Cartelle

    static func nomePulito(_ nome: String) -> String {
        let pulito = nome.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pulito.isEmpty ? "Senza nome" : pulito
    }

    /// Restituisce un URL libero dentro `cartella` partendo da `nome` ("nome", "nome 2", "nome 3"...).
    static func urlLibero(in cartella: URL, nome: String) -> URL {
        let fm = FileManager.default
        let est = (nome as NSString).pathExtension
        let base = (nome as NSString).deletingPathExtension
        var candidato = cartella.appendingPathComponent(nome)
        var n = 2
        while fm.fileExists(atPath: candidato.path) {
            let nuovo = est.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(est)"
            candidato = cartella.appendingPathComponent(nuovo)
            n += 1
        }
        return candidato
    }

    /// Crea una cartella nuova con nome libero e la restituisce.
    static func creaCartella(in cartella: URL, nome: String) -> URL {
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        let url = urlLibero(in: cartella, nome: nomePulito(nome))
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Chiede un testo con una finestrella. Restituisce nil se annullato o vuoto.
func chiediTesto(titolo: String, valore: String) -> String? {
    NSApp.activate(ignoringOtherApps: true)
    let avviso = NSAlert()
    avviso.messageText = titolo
    avviso.addButton(withTitle: "OK")
    avviso.addButton(withTitle: "Annulla")
    let campo = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    campo.stringValue = valore
    avviso.accessoryView = campo
    avviso.window.initialFirstResponder = campo
    guard avviso.runModal() == .alertFirstButtonReturn else { return nil }
    let testo = campo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return testo.isEmpty ? nil : testo
}

func chiediConferma(titolo: String, dettaglio: String, bottone: String) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let avviso = NSAlert()
    avviso.messageText = titolo
    avviso.informativeText = dettaglio
    avviso.addButton(withTitle: bottone)
    avviso.addButton(withTitle: "Annulla")
    return avviso.runModal() == .alertFirstButtonReturn
}

/// Colori di sfondo disponibili per i riquadri.
enum Tinta {
    static let tutte: [(nome: String, colore: NSColor)] = [
        ("Blu", .systemBlue), ("Azzurro", .systemTeal), ("Verde", .systemGreen),
        ("Giallo", .systemYellow), ("Arancione", .systemOrange), ("Rosso", .systemRed),
        ("Rosa", .systemPink), ("Viola", .systemPurple), ("Grigio", .systemGray),
        ("Nero", .black), ("Bianco", .white),
    ]

    static func colore(_ nome: String?) -> NSColor? {
        tutte.first { $0.nome == nome }?.colore
    }

    static func campione(_ colore: NSColor?) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            let cerchio = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            if let colore { colore.setFill(); cerchio.fill() }
            NSColor.secondaryLabelColor.setStroke()
            cerchio.stroke()
            return true
        }
    }
}
