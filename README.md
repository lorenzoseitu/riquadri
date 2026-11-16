# Riquadri

App per Mac che ordina la scrivania in riquadri. Ogni riquadro è una cartella vera: i file che trascini dentro spariscono dalla scrivania e restano raggiungibili con un clic.

Nessun limite sul numero di riquadri, nessun abbonamento, nessuna raccolta dati, nessuna connessione a internet.

## Cosa fa

- Riquadri sulla scrivania, sotto le finestre, visibili in tutti gli Spazi
- Schede dentro ogni riquadro
- Trascinamento dei file dentro e fuori
- Colore di sfondo diverso per ogni riquadro
- Ordinamento per nome, tipo, data di modifica, data di creazione, dimensione
- Quick Look con la barra spaziatrice, rinomina con Invio, cestino con Cmd+Backspace
- Doppio clic sullo sfondo per aprire la cartella nel Finder
- Riduzione del riquadro a una striscia con il solo nome
- Blocco della posizione e avvio all'accensione del Mac

## Installazione

Serve macOS 13 o successivo. Funziona su Mac con chip Apple e su Mac Intel.

1. Scarica `Riquadri.zip` dalla pagina [Releases](../../releases/latest)
2. Apri lo zip e trascina `Riquadri.app` nella cartella Applicazioni
3. Apri l'app. La prima volta macOS la blocca, perché non è firmata con un account sviluppatore Apple a pagamento
4. Vai in **Impostazioni di Sistema → Privacy e sicurezza**, scorri in fondo e premi **Apri comunque**
5. Riapri l'app e conferma

In alternativa al punto 4, dal Terminale:

```bash
xattr -dr com.apple.quarantine /Applications/Riquadri.app
```

Al primo trascinamento macOS chiede il permesso di accedere a Scrivania e Documenti: va concesso, altrimenti i file non si spostano.

## Come si usa

- L'icona a griglia nella barra dei menu crea un **Nuovo riquadro**
- **+** aggiunge una scheda, il doppio clic sul nome la rinomina
- **⋯** apre il menu del riquadro: colore, ordinamento, blocco, eliminazione
- La freccia accanto a **⋯**, o il doppio clic sulla barra, riduce il riquadro a una striscia e lo riapre
- I file stanno in `Documenti/Riquadri`, una cartella per riquadro con il nome della prima scheda. La posizione si cambia da **Sposta la cartella dei file…**
- Eliminare un riquadro o una scheda non cancella i file

## Compilazione dai sorgenti

Bastano i Command Line Tools di Xcode (`xcode-select --install`).

```bash
./build.sh
```

Lo script compila, firma in locale e installa in `~/Applications`.
