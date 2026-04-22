# Changelog

## [v0.6.2]

### Neu

- **`client-disconnect.sh`-Hook im Image gebündelt** (`bin/client-disconnect.sh`, `Dockerfile`)
  Der Hook aus `openvpn-ui` v0.9.7 liegt jetzt fest im Image unter `/opt/app/bin/client-disconnect.sh` — kein Host-Mount mehr nötig. Das Skript postet bei jedem Disconnect die finalen Byte-Counter und Dauer an `openvpn-ui` (`/api/v1/monitor/disconnect`, authentifiziert via `X-Monitor-Token`). Aktivierung:
  1. `client-disconnect /opt/app/bin/client-disconnect.sh` in `server.conf` einkommentieren (die Zeile ist bereits im Template vorbereitet).
  2. Im openvpn-Container `OPENVPN_UI_URL=http://openvpn-ui:8080` und `OPENVPN_UI_HOOK_TOKEN=<token>` setzen — gleicher Wert wie `OPENVPN_UI_MONITORING_HOOK_TOKEN` beim openvpn-ui-Container.
  `script-security 2` wird weiterhin vom Entrypoint automatisch gesetzt.

- **Compose-Vorlage aktualisiert** (`docker-compose.yml`)
  Auskommentierte `OPENVPN_UI_URL` / `OPENVPN_UI_HOOK_TOKEN` im `openvpn`-Service-Block mit Kurzanleitung.

---

## [v0.6.1]

- **CRLF-Zeilenenden in Shell-Scripts behoben** (`Dockerfile`, `.gitattributes`)
  Auf Windows gespeicherte Scripts enthielten `\r\n`-Zeilenenden. Linux konnte den Shebang `#!/bin/bash\r` nicht interpretieren, was zu `exec /opt/app/docker-entrypoint.sh: no such file or directory` führte.
  - `sed -i 's/\r$//'` im Dockerfile entfernt `\r` beim Build aus allen Scripts
  - `.gitattributes` hinzugefügt: erzwingt LF-Zeilenenden für `.sh`, `.conf`, `.vars`, `.cnf` und `Dockerfile`

---

## [v0.6]

### Sicherheit

- **`privileged: true` bei `openvpn-ui` entfernt** (`docker-compose.yml`)
  Der UI-Container lief zuvor mit vollen Host-Rechten, obwohl nur der Docker-Socket benötigt wird. Der Socket bleibt weiterhin über das Volume-Mount verfügbar.

- **Admin-Passwort aus Compose-Datei ausgelagert** (`docker-compose.yml`, `.env`)
  `OPENVPN_ADMIN_USERNAME` und `OPENVPN_ADMIN_PASSWORD` standen im Klartext in `docker-compose.yml` und waren damit Teil des Git-Verlaufs. Die Credentials wurden in eine `.env`-Datei verschoben, die über `.gitignore` vom Repository ausgeschlossen wird. Im Compose werden sie via `${VAR}` referenziert.

- **Management-Interface bindet jetzt nur auf localhost** (`server.conf`)
  `management 0.0.0.0 2080` wurde auf `management 127.0.0.1 2080` geändert. Das Interface ist damit nicht mehr im Docker-Netzwerk für andere Container erreichbar.

- **`tls-auth` in Server-Config ergänzt** (`server.conf`)
  Der HMAC-Key `ta.key` wurde zwar beim Start generiert und in Client-Configs eingebettet, vom Server selbst aber nie überprüft. Mit dem neuen Eintrag `tls-auth pki/ta.key 0` wird jedes Paket ohne gültigen HMAC vom Server sofort verworfen — schützt gegen DoS-Angriffe und Port-Scanning.
  > **Hinweis:** Siehe Abschnitt [PKI-Migration](#pki-migration) weiter unten.

- **RSA Key-Größe auf 4096 Bit erhöht** (`config/easy-rsa.vars`)
  `EASYRSA_KEY_SIZE` wurde von `2048` auf `4096` gesetzt. 2048-Bit gilt heute als Mindeststandard; 4096-Bit bietet deutlich mehr Sicherheitsmarge.
  > **Hinweis:** Wirkt nur bei einer neu generierten PKI. Siehe Abschnitt [PKI-Migration](#pki-migration).

- **TLS-Mindestversion auf 1.3 angehoben** (`config/client.conf`)
  `tls-version-min 1.2` wurde auf `tls-version-min 1.3` geändert. TLS 1.2 gilt als veraltet; TLS 1.3 bietet bessere Sicherheit und Performance.

---

### Verbesserungen

- **Healthchecks für beide Container hinzugefügt** (`docker-compose.yml`, `docker-compose-no-ui.yml`)
  - `openvpn`: Prüft via Bash `/dev/tcp` ob der Management-Port 2080 erreichbar ist. `start_period: 60s` gibt dem Container Zeit für die PKI-Generierung beim ersten Start.
  - `openvpn-ui`: HTTP-Check auf `localhost:8080` via `wget`. `start_period: 15s`.

- **`depends_on` Richtung korrigiert und auf `service_healthy` umgestellt** (`docker-compose.yml`)
  Zuvor hing `openvpn` von `openvpn-ui` ab — logisch umgekehrt. Jetzt wartet `openvpn-ui` auf `openvpn` mit `condition: service_healthy`, d.h. die UI startet erst wenn der VPN-Server den Healthcheck besteht.

- **`version`-Key aus Compose-Files entfernt** (`docker-compose.yml`, `docker-compose-no-ui.yml`)
  Das `version`-Feld ist ab Docker Compose v2 deprecated und wird ignoriert.

- **`.env` zu `.gitignore` hinzugefügt** (`.gitignore`)

---

### Bugfixes

- **Veralteten `--genkey`-Befehl korrigiert** (`docker-entrypoint.sh`)
  `openvpn --genkey --secret` ist seit OpenVPN 2.5 deprecated. Ersetzt durch `openvpn --genkey tls-auth`.

- **iptables ICMP-Regeln korrigiert** (`docker-entrypoint.sh`)
  `--icmp-type` erfordert das Match-Modul `-m icmp`. Ohne es wurde der ICMP-Type-Filter ignoriert und die Regel traf entweder den gesamten ICMP-Traffic oder gar nichts. Beide Regeln wurden um `-m icmp` ergänzt und `-j DROP` ans Ende verschoben (iptables-Konvention).

- **Alle Pfad-Variablen in `backup.sh` gequoted** (`backup.sh`)
  Variablen wie `$SERVER_ENV` und `$BACKUP_DIR` waren in `rm -rf`- und `cp`-Befehlen unquoted. Pfade mit Leerzeichen hätten falsche Verzeichnisse gelöscht oder kopiert.

---

### Dockerfile

- **Alpine-Version gepinnt**: `FROM alpine` → `FROM alpine:3.21`
  Unpinnte Base-Images sind nicht reproduzierbar; ein `docker build` zu unterschiedlichen Zeitpunkten kann unterschiedliche Images liefern.

- **`ADD` durch `COPY` ersetzt** für `openssl-easyrsa.cnf`
  `ADD` sollte nur für URL-Downloads oder tar-Extraktion verwendet werden. Für lokale Dateien ist `COPY` korrekt.

- **`ENTRYPOINT` auf Exec-Form umgestellt**
  `ENTRYPOINT ./docker-entrypoint.sh` (Shell-Form) wurde durch `ENTRYPOINT ["/opt/app/docker-entrypoint.sh"]` (Exec-Form) ersetzt. Die Shell-Form fängt Signale wie `SIGTERM` nicht weiter, was zu hängendem Shutdown-Verhalten führt.

---

### Sonstiges

- **Typo behoben**: `"Generating ertificate authority"` → `"Generating certificate authority"` (`docker-entrypoint.sh`)
- **Log-Level reduziert**: `verb 4` → `verb 3` in `server.conf` (Level 4 ist Debug-Output, für Produktion reicht Level 3)

---

## PKI-Migration

Zwei Änderungen wirken sich **nicht automatisch** auf eine bereits laufende Instanz aus und erfordern eine manuelle Aktion:

### 1. `tls-auth` aktivieren (ohne PKI-Neugenerierung)

Wenn du keine neue PKI generieren möchtest, kannst du `tls-auth` auch nachträglich aktivieren:

```bash
# Im laufenden openvpn-Container:
docker exec -it openvpn bash

# ta.key neu generieren (falls noch nicht vorhanden oder neu gewünscht)
openvpn --genkey tls-auth /etc/openvpn/pki/ta.key

# Container neu starten damit server.conf neu eingelesen wird
docker compose restart openvpn
```

Anschließend müssen **alle bestehenden Client-Configs (`.ovpn`)** neu generiert werden, da der neue `ta.key` eingebettet werden muss. Clients mit alten `.ovpn`-Dateien können sich danach nicht mehr verbinden.

### 2. RSA Key-Größe auf 4096 Bit (erfordert PKI-Neugenerierung)

Die neue Key-Größe greift erst bei einer frisch generierten PKI. Eine bestehende PKI kann nicht nachträglich auf 4096 Bit geändert werden.

> **Warnung:** Eine PKI-Neugenerierung macht alle bestehenden Client-Zertifikate ungültig. Alle Clients müssen danach neu ausgestellt werden.

```bash
# Backup der aktuellen PKI
./backup.sh -b . backup/pre-migration-$(date +%Y%m%d)

# Bestehende PKI löschen (löscht alle Zertifikate!)
rm -rf ./pki/*

# Container neu starten — Entrypoint generiert die PKI automatisch neu
docker compose down
docker compose up -d
```

Nach dem Neustart alle Client-Zertifikate über die OpenVPN-UI oder `bin/genclient.sh` neu ausstellen.
