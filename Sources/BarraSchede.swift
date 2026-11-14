import AppKit

/// Una linguetta della barra delle schede.
final class Linguetta: NSView {
    let indice: Int
    private let etichetta: NSTextField
    weak var barra: BarraSchede?

    init(indice: Int, nome: String, attiva: Bool) {
        self.indice = indice
        etichetta = NSTextField(labelWithString: nome)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = attiva
            ? NSColor.labelColor.withAlphaComponent(0.16).cgColor
            : NSColor.clear.cgColor
        etichetta.font = .systemFont(ofSize: 12, weight: attiva ? .semibold : .regular)
        etichetta.textColor = attiva ? .labelColor : .secondaryLabelColor
        etichetta.lineBreakMode = .byTruncatingTail
        etichetta.translatesAutoresizingMaskIntoConstraints = false
        etichetta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(etichetta)
        NSLayoutConstraint.activate([
            etichetta.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            etichetta.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            etichetta.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { barra?.alRinomina?(indice) }
        else { barra?.allaSelezione?(indice) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        barra?.menuScheda?(indice)
    }
}

/// Intestazione del riquadro: schede, "+", menu. Trascinandola si sposta il riquadro.
final class BarraSchede: NSView {
    var allaSelezione: ((Int) -> Void)?
    var alRinomina: ((Int) -> Void)?
    var allAggiunta: (() -> Void)?
    var menuScheda: ((Int) -> NSMenu?)?
    var menuRiquadro: (() -> NSMenu)?
    var bloccato = false

    private let pila = NSStackView()
    private let piu = NSButton()
    private let altro = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        pila.orientation = .horizontal
        pila.spacing = 2
        pila.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pila)

        configura(piu, simbolo: "plus", descrizione: "Nuova scheda", azione: #selector(premutoPiu))
        configura(altro, simbolo: "ellipsis", descrizione: "Menu del riquadro", azione: #selector(premutoAltro))

        NSLayoutConstraint.activate([
            pila.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pila.centerYAnchor.constraint(equalTo: centerYAnchor),
            piu.leadingAnchor.constraint(equalTo: pila.trailingAnchor, constant: 4),
            piu.centerYAnchor.constraint(equalTo: centerYAnchor),
            altro.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            altro.centerYAnchor.constraint(equalTo: centerYAnchor),
            piu.trailingAnchor.constraint(lessThanOrEqualTo: altro.leadingAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configura(_ b: NSButton, simbolo: String, descrizione: String, azione: Selector) {
        b.image = NSImage(systemSymbolName: simbolo, accessibilityDescription: descrizione)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = descrizione
        b.target = self
        b.action = azione
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        addSubview(b)
    }

    func aggiorna(nomi: [String], attiva: Int) {
        pila.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, nome) in nomi.enumerated() {
            let l = Linguetta(indice: i, nome: nome, attiva: i == attiva)
            l.barra = self
            pila.addArrangedSubview(l)
        }
    }

    @objc private func premutoPiu() { allAggiunta?() }

    @objc private func premutoAltro() {
        guard let menu = menuRiquadro?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: altro.bounds.height + 4), in: altro)
    }

    override func mouseDown(with event: NSEvent) {
        if !bloccato { window?.performDrag(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuRiquadro?() }
}
