import AppKit

/// Cerca la versione nuova nelle release di GitHub, la scarica e sostituisce l'app.
enum Aggiornamento {
    static let repo = "lorenzoseitu/riquadri"
    static let pagina = URL(string: "https://github.com/\(repo)/releases/latest")!

    static var versioneAttuale: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    struct Rilascio {
        let versione: String
        let zip: URL
    }

    struct Errore: LocalizedError {
        let errorDescription: String?
        init(_ testo: String) { errorDescription = testo }
    }

    private static var inCorso = false

    // MARK: Ricerca

    private static func cerca(_ fine: @escaping (Result<Rilascio, Error>) -> Void) {
        var richiesta = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        richiesta.setValue("Riquadri", forHTTPHeaderField: "User-Agent")
        richiesta.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        richiesta.timeoutInterval = 20
        URLSession.shared.dataTask(with: richiesta) { dati, _, errore in
            let esito: Result<Rilascio, Error>
            if let errore {
                esito = .failure(errore)
            } else if let dati,
                      let json = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
                      let etichetta = json["tag_name"] as? String,
                      let allegati = json["assets"] as? [[String: Any]],
                      let indirizzo = allegati.first(where: { ($0["name"] as? String) == "Riquadri.zip" })?["browser_download_url"] as? String,
                      let zip = URL(string: indirizzo) {
                let versione = etichetta.hasPrefix("v") ? String(etichetta.dropFirst()) : etichetta
                esito = .success(Rilascio(versione: versione, zip: zip))
            } else {
                esito = .failure(Errore("La risposta di GitHub non contiene una versione scaricabile."))
            }
            DispatchQueue.main.async { fine(esito) }
        }.resume()
    }

    private static func piuNuova(_ versione: String) -> Bool {
        versione.compare(versioneAttuale, options: .numeric) == .orderedDescending
    }

    /// `manuale`: richiesto dal menu, quindi risponde sempre. Altrimenti parla solo se c'è una versione nuova
    /// non ancora proposta. `senzaChiedere`: installa subito (usato dall'avvio con --installa-aggiornamento).
    static func controlla(manuale: Bool, senzaChiedere: Bool = false) {
        guard !inCorso else { return }
        cerca { esito in
            switch esito {
            case .failure(let errore):
                if manuale { avvisa("Impossibile controllare gli aggiornamenti", errore.localizedDescription) }
            case .success(let rilascio):
                guard piuNuova(rilascio.versione) else {
                    if manuale { avvisa("Riquadri è aggiornato", "Hai la versione \(versioneAttuale), la più recente.") }
                    return
                }
                if senzaChiedere { installa(rilascio); return }
                let chiave = "versioneProposta"
                if !manuale, UserDefaults.standard.string(forKey: chiave) == rilascio.versione { return }
                UserDefaults.standard.set(rilascio.versione, forKey: chiave)
                NSApp.activate(ignoringOtherApps: true)
                let avviso = NSAlert()
                avviso.messageText = "È disponibile Riquadri \(rilascio.versione)"
                avviso.informativeText = "Hai la versione \(versioneAttuale). L'app scarica la versione nuova, si chiude e si riapre da sola. Riquadri e file restano come sono."
                avviso.addButton(withTitle: "Installa")
                avviso.addButton(withTitle: "Più tardi")
                if avviso.runModal() == .alertFirstButtonReturn { installa(rilascio) }
            }
        }
    }

    // MARK: Installazione

    private static func installa(_ rilascio: Rilascio) {
        let app = Bundle.main.bundleURL
        // App aperta da una posizione di sola lettura (es. dalla cartella Download appena scaricata).
        guard !app.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            avvisa("Impossibile aggiornare da qui",
                   "Sposta Riquadri nella cartella Applicazioni e riprova, oppure scarica la versione nuova a mano.")
            NSWorkspace.shared.open(pagina)
            return
        }
        inCorso = true
        URLSession.shared.downloadTask(with: rilascio.zip) { scaricato, _, errore in
            let esito = Result<URL, Error> {
                if let errore { throw errore }
                guard let scaricato else { throw Errore("Download non riuscito.") }
                return try prepara(zip: scaricato)
            }
            DispatchQueue.main.async {
                inCorso = false
                switch esito {
                case .failure(let errore):
                    avvisa("Aggiornamento non riuscito", errore.localizedDescription)
                case .success(let nuova):
                    sostituisci(app: app, con: nuova)
                }
            }
        }.resume()
    }

    /// Scompatta lo zip in una cartella temporanea e controlla che dentro ci sia Riquadri.
    private static func prepara(zip: URL) throws -> URL {
        let fm = FileManager.default
        let lavoro = fm.temporaryDirectory.appendingPathComponent("riquadri-aggiornamento-\(UUID().uuidString)")
        try fm.createDirectory(at: lavoro, withIntermediateDirectories: true)
        let scompatta = Process()
        scompatta.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        scompatta.arguments = ["-x", "-k", zip.path, lavoro.path]
        try scompatta.run()
        scompatta.waitUntilExit()
        let nuova = lavoro.appendingPathComponent("Riquadri.app")
        guard scompatta.terminationStatus == 0,
              let pacchetto = Bundle(url: nuova),
              pacchetto.bundleIdentifier == Bundle.main.bundleIdentifier,
              let eseguibile = pacchetto.executableURL,
              fm.isExecutableFile(atPath: eseguibile.path) else {
            throw Errore("Il file scaricato non contiene Riquadri.")
        }
        return nuova
    }

    /// Avvia uno script che aspetta la chiusura dell'app, mette la versione nuova al suo posto e la riapre.
    /// Se lo scambio fallisce rimette la versione vecchia.
    private static func sostituisci(app: URL, con nuova: URL) {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$2.vecchia"
        if mv "$2" "$2.vecchia" && mv "$3" "$2"; then rm -rf "$2.vecchia"; else mv "$2.vecchia" "$2" 2>/dev/null; fi
        open "$2"
        """
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: "/bin/sh")
        processo.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), app.path, nuova.path]
        do {
            try processo.run()
            NSApp.terminate(nil)
        } catch {
            avvisa("Aggiornamento non riuscito", error.localizedDescription)
        }
    }

    private static func avvisa(_ titolo: String, _ dettaglio: String) {
        NSApp.activate(ignoringOtherApps: true)
        let avviso = NSAlert()
        avviso.messageText = titolo
        avviso.informativeText = dettaglio
        avviso.runModal()
    }
}
