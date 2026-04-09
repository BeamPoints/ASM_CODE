; =============================================================================
; HELLO_WORLD.ASM — Bare-Metal "Hallo WORLD" Bootsektor
; =============================================================================
;
; Was passiert beim Einschalten?
;   1. CPU startet im "Real Mode" (16-bit, so wie 1981)
;   2. BIOS läuft, testet Hardware (POST)
;   3. BIOS sucht bootfähiges Medium (Disk, USB, ...)
;   4. BIOS liest die ersten 512 Bytes (Sektor 0) in RAM
;   5. BIOS lädt diese 512 Bytes an Adresse 0x7C00
;   6. BIOS springt zu 0x7C00 — ab hier sind WIR dran
;
; Assemblieren:  nasm -f bin hello_boot.asm -o hello_boot.bin
; Testen:        qemu-system-x86_64 -drive format=raw,file=hello_boot.bin
; Größe prüfen:  ls -la hello_boot.bin   →  muss exakt 512 Bytes sein
; =============================================================================


BITS 16
; ^^^^
; Sagt NASM: erzeuge 16-bit Maschinencode.
; Im Real Mode versteht die CPU nur 16-bit Befehle.
; Ohne diese Direktive würde NASM 32-bit Code erzeugen → sofortiger Absturz.

ORG 0x7C00
; ^^^^^^^^^
; "Origin" — sagt dem Assembler wo im RAM unser Code landet.
; BIOS lädt uns IMMER an 0x7C00. Niemals woanders. Das ist seit 1981 Standard.
; Wichtig für alle absoluten Adressen: wenn wir "mov si, msg" schreiben,
; muss der Assembler wissen dass "msg" bei 0x7C00+Offset liegt, nicht bei 0x0000.


; =============================================================================
; EINSTIEGSPUNKT — hier springt das BIOS hin
; =============================================================================

start:
    ; -------------------------------------------------------------------------
    ; Segmentregister initialisieren
    ; -------------------------------------------------------------------------
    ; Im Real Mode berechnet die CPU Adressen als:  Segment * 16 + Offset
    ; Das BIOS setzt CS (Code Segment) auf 0 bevor es zu uns springt,
    ; aber DS, ES, SS können beliebige Werte haben — wir setzen sie manuell.
    ; -------------------------------------------------------------------------

    xor ax, ax
    ; ^^^^^^^^^
    ; AX = AX XOR AX = 0
    ; Cleverer Trick: XOR mit sich selbst ergibt immer 0.
    ; Kürzer und schneller als "mov ax, 0".
    ; Wir brauchen den Wert 0 zum Initialisieren der Segmentregister.

    mov ds, ax
    ; ^^^^^^^^^
    ; DS (Data Segment) = 0
    ; Segmentregister können nicht direkt mit Konstanten geladen werden,
    ; nur über ein allgemeines Register wie AX.
    ; DS=0 bedeutet: Datenzugriffe starten bei Adresse 0x0000.

    mov es, ax
    ; ^^^^^^^^^
    ; ES (Extra Segment) = 0
    ; Extra Segment — wird von String-Befehlen wie LODSB als Quelle genutzt.
    ; Wir setzen es auf 0 damit Adressen konsistent berechnet werden.

    mov ss, ax
    ; ^^^^^^^^^
    ; SS (Stack Segment) = 0
    ; Der Stack liegt in Segment 0 — zusammen mit SP ergibt das die
    ; absolute Stack-Adresse: SS*16 + SP = 0 + 0x7C00 = 0x7C00

    mov sp, 0x7C00
    ; ^^^^^^^^^^^^
    ; SP (Stack Pointer) = 0x7C00
    ; Der Stack wächst NACH UNTEN (zu kleineren Adressen hin).
    ; Wir zeigen auf unseren eigenen Ladepunkt: PUSH verringert SP,
    ; also wächst der Stack in Richtung 0x0000 — weg von unserem Code.
    ; Ohne initialierten Stack würden CALL/RET/INT sofort Daten überschreiben.


    ; -------------------------------------------------------------------------
    ; Zeiger auf unseren Text setzen
    ; -------------------------------------------------------------------------

    mov si, msg
    ; ^^^^^^^^^^
    ; SI (Source Index) = Adresse des Labels "msg"
    ; SI ist das klassische Register für String-Quell-Adressen.
    ; Der Assembler ersetzt "msg" durch die korrekte 16-bit Adresse
    ; (dank ORG 0x7C00 stimmt diese Adresse auch zur Laufzeit).


; =============================================================================
; HAUPTSCHLEIFE — Zeichen für Zeichen ausgeben
; =============================================================================

.print_loop:
    ; Label mit Punkt = lokales Label, gehört zu "start".
    ; Verhindert Namenskollisionen in größeren Programmen.

    lodsb
    ; ^^^^^
    ; "Load String Byte"
    ; Macht zwei Dinge gleichzeitig:
    ;   1. AL = Byte an Adresse [DS:SI]  →  AL = *SI
    ;   2. SI = SI + 1                   →  SI++
    ; Perfekt für das Durchlaufen von Strings — kein manuelles Inkrementieren.

    test al, al
    ; ^^^^^^^^^^
    ; Führt AL AND AL durch, verwirft das Ergebnis, setzt aber FLAGS.
    ; Konkret: setzt das Zero Flag (ZF) wenn AL == 0.
    ; Wir suchen den Nullterminator am Ende des Strings.
    ; "test" ist kürzer als "cmp al, 0" und macht dasselbe.

    jz .halt
    ; ^^^^^^^
    ; "Jump if Zero" — springt zu .halt wenn ZF gesetzt ist.
    ; D.h.: wenn AL == 0 (Nullterminator erreicht), sind wir fertig.
    ; Sonst: weitermachen mit der Ausgabe.

    mov ah, 0x0E
    ; ^^^^^^^^^^
    ; AH = 0x0E = BIOS-Funktion "Teletype Output"
    ; Das BIOS bietet Dienste via Software-Interrupts an.
    ; Die Funktion wird durch AH ausgewählt — wie eine Syscall-Nummer.
    ; 0x0E = Zeichen ausgeben und Cursor weiterbewegen.

    mov bh, 0
    ; ^^^^^^^^
    ; BH = 0 = Bildschirmseite 0
    ; Das BIOS unterstützt mehrere Textseiten (0-7).
    ; Wir nutzen Seite 0, die standardmäßig sichtbare Seite.

    int 0x10
    ; ^^^^^^^
    ; Software-Interrupt Nr. 16 (0x10 hex) = BIOS Video Services
    ; Übergabe:  AH = 0x0E (Funktion), AL = Zeichen, BH = Seite
    ; Rückgabe:  Zeichen erscheint auf dem Bildschirm, Cursor rückt vor
    ; Das ist die einzige "API" die wir ohne OS zur Verfügung haben!
    ; INT speichert Flags + CS + IP auf dem Stack -> deshalb brauchten wir SS/SP.

    jmp .print_loop
    ; ^^^^^^^^^^^^^
    ; Unbedingt zurück zum Schleifenanfang.
    ; Nächstes Zeichen holen und ausgeben.


; =============================================================================
; ENDE — CPU anhalten
; =============================================================================

.halt:

    hlt
    ; ^^^
    ; "Halt" — CPU hält die Ausführung an und wartet auf einen Interrupt.
    ; Ohne HLT würde die CPU einfach weiterlaufen und zufälligen Speicher
    ; als Befehle interpretieren → undefiniertes Verhalten, Absturz.

    jmp .halt
    ; ^^^^^^^^
    ; Sicherheitsnetz: falls ein NMI (Non-Maskable Interrupt) die CPU
    ; aus dem Halt-Zustand weckt, springen wir sofort wieder zurück zu HLT.
    ; Endlosschleife als "ewig schlafen" — übliches Muster in Bootloadern.


; =============================================================================
; DATEN
; =============================================================================

msg:
    ; Label "msg" markiert die Adresse dieses Bytes im Code-Segment.
    ; Landet direkt hinter dem ausführbaren Code im 512-Byte-Sektor.

    db "Hello World", 0x0D, 0x0A, 0
    ;  ^^^^^^^^^^^^^^ ^^^^   ^^^^  ^
    ;  |              |      |     Nullterminator: signalisiert End-of-String
    ;  |              |      0x0A = Line Feed (LF): Cursor in nächste Zeile
    ;  |              0x0D = Carriage Return (CR): Cursor an Zeilenanfang
    ;  Unser Text als Byte-Sequenz (ASCII)
    ;
    ; CR+LF zusammen = Windows/BIOS-Zeilenende, bewegt Cursor korrekt.
    ; Nur LF würde den Cursor nach unten bewegen, aber NICHT an den Anfang.


; =============================================================================
; BOOT-SIGNATUR — die letzten 2 Bytes des Sektors
; =============================================================================

TIMES 510 - ($ - $$) db 0
; ^^^^^^^^^^^^^^^^^^^^^^^^
; TIMES n  = wiederhole den folgenden Ausdruck n-mal
; $        = aktuelle Adresse (Position im Code)
; $$       = Adresse des Anfangs der aktuellen Sektion (= 0x7C00)
; $ - $$   = wie viele Bytes haben wir bisher erzeugt?
; 510 - ($ - $$) = wie viele Null-Bytes müssen noch aufgefüllt werden?
;
; Ergebnis: der gesamte Code + Daten + Padding = exakt 510 Bytes.
; Die letzten 2 Bytes reservieren wir für die Magic Number unten.

DW 0xAA55
; ^^^^^^^^
; DW = "Define Word" = 2 Bytes
; 0xAA55 = die BIOS Boot-Signatur (Magic Number)
;
; Das BIOS liest Sektor 0 und prüft: sind die letzten 2 Bytes == 0xAA55?
; Wenn JA  -> "Das ist ein bootfähiger Sektor!" → springt zu 0x7C00
; Wenn NEIN -> "Kein Betriebssystem gefunden" → Fehlermeldung
;
; Achtung: x86 ist Little-Endian, d.h. 0xAA55 wird als Bytes 0x55, 0xAA
; im Speicher abgelegt. Das BIOS liest es in dieser Reihenfolge und
; interpretiert es korrekt als Boot-Signatur.
;
; Gesamtgröße: 510 Bytes Code/Daten/Padding + 2 Bytes Signatur = 512 Bytes 