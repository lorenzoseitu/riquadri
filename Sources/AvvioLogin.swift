import ServiceManagement

enum AvvioLogin {
    static var attivo: Bool { SMAppService.mainApp.status == .enabled }

    /// Restituisce l'eventuale errore come testo.
    @discardableResult
    static func imposta(_ acceso: Bool) -> String? {
        do {
            if acceso { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
