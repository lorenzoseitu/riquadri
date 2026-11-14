import Foundation

/// Avvisa quando il contenuto di una cartella cambia.
final class Sorvegliante {
    private var sorgente: DispatchSourceFileSystemObject?

    init?(cartella: URL, alCambio: @escaping () -> Void) {
        let fd = open(cartella.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main)
        s.setEventHandler(handler: alCambio)
        s.setCancelHandler { close(fd) }
        s.resume()
        sorgente = s
    }

    deinit { sorgente?.cancel() }
}
