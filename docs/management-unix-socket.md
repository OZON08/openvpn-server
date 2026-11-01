# Management-Interface über einen Unix-Socket

Stand: 2026-11-01. Die Änderung ist auf `main` und als `ozon08/openvpn-server:dev` veröffentlicht, noch nicht als `latest`. Der komplette Stack wurde mit beiden Images getestet, und eine bestehende Installation läuft damit im Betrieb.

## Ziel

OpenVPN wird über `/etc/openvpn/run/mi.sock` gesteuert statt über TCP-Port 2080. Das Interface hat kein Passwort, deshalb konnte jeder, der den Port erreichte, Client-Daten lesen, Clients trennen oder den Server stoppen.

Das Gegenstück liegt im Repo `openvpn-ui` unter `docs/management-unix-socket.md`.

## Änderungen in diesem Repo

| Datei | Änderung |
|---|---|
| `server.conf` | `management /etc/openvpn/run/mi.sock unix` |
| `docker-entrypoint.sh` | Legt `run` mit Besitzer root, GID `61194` und Modus `0750` an und stellt alte Configs mit Port 2080 um |
| `Dockerfile` | `LABEL version` auf `0.6.4` |
| `docker-entrypoint.sh` | Startet OpenVPN mit `exec` als PID 1. `openvpn.log` und `openvpn-status.log` erhalten vorab die Socket-Gruppe und Modus `0640`, damit die UI sie lesen kann |
| `docker-compose.yml`, `docker-compose-no-ui.yml` | Neues Volume `./run:/etc/openvpn/run`, Healthcheck prüft Socket und Prozess, Port-Eintrag entfernt, `start_period` auf `7200s` |
| `README.md`, `DOCKER_HUB.md` | Beispiele, Volumes und Sicherheitshinweise angepasst |
| `.github/workflows/` | `docker-build-dev.yml` baut bei einem Push auf `main` den Tag `dev`. `docker-build.yml` baut `latest` nur noch aus einem Git-Tag `v*`. Alle Actions sind auf Commit-SHAs fixiert, weil sie das Docker-Hub-Token erhalten |
| `.gitignore` | `run/` ergänzt |
| `CHANGELOG.md` | Eintrag `v0.6.4` |

## So ist der Zugriff beschränkt

Der Socket hat den Modus `0777`, seine eigenen Rechte schützen also nichts. Den Zugriff begrenzt das Verzeichnis `run`, das der Container bei jedem Start auf Besitzer root, GID `61194` und Modus `0750` setzt. `chown` ist nötig, weil das Host-Verzeichnis einem beliebigen Benutzer gehören kann und dieser sonst Zugriff behielte.

Der Webprozess von `openvpn-ui` läuft als UID und GID `61195` und erhält den Zugriff über die Gruppe `openvpn-mi` mit dieser GID. Eine eigene GID ist nötig, weil GID 1000 oft einem normalen Host-Benutzer gehört.

Eine andere GID lässt sich mit `OPENVPN_MI_GID` setzen, und zwar auf beiden Services mit demselben Wert. Ein Host-Benutzer in dieser Gruppe kann OpenVPN steuern, die GID darf also niemand sonst erhalten.

## Umstellung bestehender Configs

Der Container stellt eine Zeile `management <Adresse> 2080` beim Start auf den Socket um, wenn `./run:/etc/openvpn/run` gemountet ist. Ohne dieses Volume bleibt die Config auf TCP. Eine Config mit einem anderen Port bleibt ebenfalls auf TCP. Der Container schreibt dann eine Warnung ins Log, und sein Healthcheck schlägt fehl. `server.conf` wird dabei in derselben Datei geändert, weil sie als einzelne Datei gemountet ist und ein `sed -i` dort fehlschlagen würde.

## Rollout

1. Images von `openvpn` und `openvpn-ui` gemeinsam aktualisieren. Die neue UI spricht nur noch mit dem Socket. Eine ältere UI öffnet `run` bei ihrem Start für GID 1000 und damit für einen Host-Benutzer mit dieser GID.
2. `./run:/etc/openvpn/run` beim Service `openvpn` ergänzen.
3. Den neuen Healthcheck aus den Compose-Dateien übernehmen. Der alte prüft Port 2080 und würde fehlschlagen.
4. Bei `openvpn-ui` `./:/etc/openvpn` und `docker.sock` durch die Einzel-Mounts aus `docker-compose.yml` ersetzen. `restart: always` muss auf beiden Services bleiben, die Neustart-Buttons brauchen es. UID und GID `61195` müssen auf dem Host frei sein, `OPENVPN_MI_GID=61195` lehnt die UI beim Start ab.

Der Neustart-Button beendet OpenVPN über den Socket. Container mit `network_mode: service:openvpn` laufen danach weiter, haben aber nur noch `lo` und brauchen einen eigenen Neustart.

### Stolperstellen beim Umstieg

Diese Punkte traten beim ersten Umstieg einer bestehenden Installation auf, die zuvor mit `privileged` lief:

| Symptom | Ursache | Lösung |
|---|---|---|
| `openvpn` startet ständig neu, im `openvpn.log` steht `Failed running command (--up/--down)` | Ein eigenes `up`-Skript ruft `sysctl -w` auf, `/proc/sys` ist ohne `privileged` schreibgeschützt | Den Aufruf entfernen, `sysctls` in der Compose-Datei setzt den Wert |
| `sysctl: error setting key` beim Containerstart | `sysctl -p` im Entrypoint, das Skript läuft danach weiter | Harmlos, keine Änderung nötig |
| Angehängte Container melden `cannot join network namespace` | Container mit `network_mode: service:openvpn` starten nicht, solange `openvpn` neu startet | Erst `openvpn` reparieren, dann alle zusammen mit `--force-recreate` neu erstellen |
| `docker logs` endet bei `Start openvpn process...` | Mit der Option `log` in `server.conf` schreibt OpenVPN nur noch in seine Logdatei | `log/openvpn.log` lesen |
| Das alte Admin-Passwort gilt weiter | `openvpn-ui` liest `OPENVPN_ADMIN_PASSWORD` nur beim Anlegen des Kontos | Das Passwort zusätzlich in der UI ändern |

Vor dem Umstieg sollte man prüfen, dass `getent group 61194` nichts ausgibt und eigene Skripte ausführbar sind. Beim Sichern sollten `pki`, `db` und `server.conf` dabei sein.

## Bekannte Einschränkung

`SIGHUP` beendet OpenVPN, wenn `server.conf` den Modus `0600` hat, weil der Prozess als `nobody` läuft und die Datei nicht erneut lesen kann. Mit `restart: always` startet der Container neu. `openvpn-ui` setzt den Modus `0600` beim Speichern. Die Buttons der Oberfläche nutzen `SIGUSR1`, die Signal-API nimmt aber auch andere Signale an.

## Getestet

Der komplette Stack lief mit beiden echten Images, mit 2048-Bit-DH-Parametern und ohne `docker.sock`:

- Die UI läuft als `openvpn-ui` und zeigt die OpenVPN-Version, die sie über den Socket liest. Das gilt für beide Startreihenfolgen und nach dem Neustart jedes Containers.
- `run` bleibt auf `0:61194` mit Modus `0750`. UID 1000 ohne die Gruppe, UID 65534 und der Host-Benutzer haben keinen Zugriff.
- Eine alte `server.conf` wird umgestellt und behält ihre Inode. Eine Zeile mit Port `20800` bleibt unverändert.
- Der Healthcheck besteht, wenn OpenVPN läuft.
- Eine eigene GID über `.env` wirkt auf beiden Services.
- Eine Config mit anderem TCP-Port erzeugt die Warnung im Log, ein alter Socket wird beim Start entfernt.
- Zwei einzelne Fehlschläge kamen sehr wahrscheinlich aus dem Test selbst: Er sah direkt nach dem Start noch den alten Socket. Seit er wartet, bis OpenVPN PID 1 ist, bestanden drei komplette Läufe mit je 20 Prüfungen.
- Ein echter VPN-Client verbindet sich mit der `server.conf` aus dem Repo (`tls-auth`) und mit der von der UI gerenderten (`tls-crypt`), jeweils mit passendem Client. Der Ping durch den Tunnel geht durch, und die UI zeigt den Client über den Socket an.
- `docker stop` dauert 2,3 Sekunden mit Exit-Code 0, der Client erhält die Reset-Meldung vom Server.
- Die UI liest `openvpn-status.log` als `openvpn-ui`, `status.log parse failed` tritt nicht mehr auf.

Mit `alpine:3.24` und OpenVPN 2.7.7 wurden wiederholt: Erststart mit neuer PKI, alle 20 Stack-Prüfungen, VPN-Clients mit 2.7 und 2.6, Speichern über die UI mit anschließendem `tls-crypt`-Client und ein Upgrade mit einer PKI aus dem 3.21-Image. Dabei lief `openvpn-ui` auf dem Stand `6cdc640`, die Client-Zertifikate entstanden direkt mit `easyrsa`, nicht über `genclient.sh`.

Mit `pki` und `staticclients` auf Modus `0700` wird ein gesperrter Client im laufenden Betrieb abgewiesen, und die statische Adresse greift. `nobody` kann `ca.key` weiter nicht lesen und `pki` nicht auflisten.

Am 2026-11-01 lief die Umstellung einer bestehenden Installation mit den veröffentlichten `dev`-Images, einer PKI von 2025 und ohne `privileged`:

- `server.conf` und die Einstellung in der Datenbank der UI wurden automatisch auf den Socket umgestellt.
- `openvpn` und `openvpn-ui` wurden `healthy`.
- Ein bestehender Client verband sich mit `tls-crypt` über OpenVPN 2.7.7 und erhielt seine statische Adresse.
- Die Logs lagen auf `root:61194` mit Modus `0640`.

Danach lief die `docker-compose.yml` aus dem Repo mit den Einzel-Mounts und den veröffentlichten `dev`-Images, `openvpn-ui` auf dem Stand `43543c7`:

- Beide Container wurden `healthy`, die UI läuft als UID `61195` in der Gruppe `61194` und liest die OpenVPN-Version über den Socket.
- Die UI sieht weder `.env` noch `fw-rules.sh`, und `docker.sock` fehlt.
- `ca.key` liegt auf `0:61195` mit Modus `0640`. `nobody` kann die Datei nicht lesen, `crl.pem` aber schon.
- Das UI-Log enthält keinen Passwort-Hash und keine Debug-Zeilen.
- Ein Client verbindet sich, erhält seine statische Adresse und wird nach dem Sperren im laufenden Betrieb abgewiesen.

Der Host-Benutzer kann danach nicht mehr direkt in `staticclients` schreiben, das geht nur noch über die UI, im Container oder mit `sudo`.

## Nicht getestet

- Rootless Docker.
- Die Images für arm64 und arm/v7, die erst ein Release baut.
- Ein erster Start mit 4096-Bit-DH-Parametern bis zum Ende. Auf dem Testrechner war er nach 44 Minuten bei hoher Last nicht fertig, deshalb ist `start_period` jetzt `7200s`. Ob das auf jeder Hardware reicht, ist offen.

## Offen

1. `bin/genclient.sh`, `bin/revoke.sh` und `bin/rmcert.sh` laufen im Server-Image nicht, obwohl das `README.md` sie beschreibt. Sie lesen ihre Pfade aus `../openvpn-ui/conf/app.conf`, die es dort nicht gibt. Das kommt nicht von dieser Änderung.
2. Das Sperren erneuerter Zertifikate wirkt nicht: `revoke.sh` löscht dann nur die Zeile aus `index.txt`, nichts landet in der CRL, und altes wie neues Zertifikat verbinden sich weiter. Das hat die Session von `openvpn-ui` dort getestet, `bin/revoke.sh` enthält dieselbe Logik. Das kommt nicht von dieser Änderung.
3. `sysctl -p` im Entrypoint meldet ohne `privileged` bei jedem Start einen Fehler, obwohl `sysctls` den Wert bereits setzt. Das ist harmlos, wirkt aber wie ein Problem.

## Erledigt

- Schlüsselrechte: In einem aktuellen `openvpn-ui` liegt `ca.key` auf `0:61195` mit Modus `0640`. Der Webprozess kann die Datei lesen, aber nicht ändern, und die GID 1000 hat keinen Zugriff mehr.
- Neustart-Buttons: Sie brauchen `docker.sock` nicht mehr. Die Session von `openvpn-ui` hat sie mit einem angehängten Container getestet.

- `tls-auth` und `tls-crypt`: Die Erkennung des Modus ist in `openvpn-ui` auf `main` (`5f39925`). Im Betrieb geprüft ist bisher nur ein bestehender `tls-crypt`-Client, kein neu erstellter.
- Logs: Nach dem Start der UI liegen sie auf `root:61194` mit Modus `0640`, nicht mehr auf GID 1000.
