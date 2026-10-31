# Management-Interface über einen Unix-Socket

Stand: 2026-10-31. Die Änderung ist auf dem Branch `management-unix-socket` committet. Der komplette Stack wurde mit beiden echten Images getestet.

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
| `.gitignore` | `run/` ergänzt |
| `CHANGELOG.md` | Eintrag `v0.6.4` |

## So ist der Zugriff beschränkt

Der Socket hat den Modus `0777`, seine eigenen Rechte schützen also nichts. Den Zugriff begrenzt das Verzeichnis `run`, das der Container bei jedem Start auf Besitzer root, GID `61194` und Modus `0750` setzt. `chown` ist nötig, weil das Host-Verzeichnis einem beliebigen Benutzer gehören kann und dieser sonst Zugriff behielte.

Der Webprozess von `openvpn-ui` läuft als UID 1000 und erhält den Zugriff über die Gruppe `openvpn-mi` mit dieser GID. Eine eigene GID ist nötig, weil GID 1000 oft einem normalen Host-Benutzer gehört.

Eine andere GID lässt sich mit `OPENVPN_MI_GID` setzen, und zwar auf beiden Services mit demselben Wert. Ein Host-Benutzer in dieser Gruppe kann OpenVPN steuern, die GID darf also niemand sonst erhalten.

## Umstellung bestehender Configs

Der Container stellt eine Zeile `management <Adresse> 2080` beim Start auf den Socket um, wenn `./run:/etc/openvpn/run` gemountet ist. Ohne dieses Volume bleibt die Config auf TCP. Eine Config mit einem anderen Port bleibt ebenfalls auf TCP. Der Container schreibt dann eine Warnung ins Log, und sein Healthcheck schlägt fehl. `server.conf` wird dabei in derselben Datei geändert, weil sie als einzelne Datei gemountet ist und ein `sed -i` dort fehlschlagen würde.

## Rollout

1. Images von `openvpn` und `openvpn-ui` gemeinsam aktualisieren. Die neue UI spricht nur noch mit dem Socket. Eine ältere UI öffnet `run` bei ihrem Start für GID 1000 und damit für einen Host-Benutzer mit dieser GID.
2. `./run:/etc/openvpn/run` beim Service `openvpn` ergänzen.
3. Den neuen Healthcheck aus den Compose-Dateien übernehmen. Der alte prüft Port 2080 und würde fehlschlagen.

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

## Nicht getestet

- Die Neustart-Buttons, die `docker.sock` nutzen.
- Rootless Docker.
- Ein erster Start mit 4096-Bit-DH-Parametern bis zum Ende. Auf dem Testrechner war er nach 44 Minuten bei hoher Last nicht fertig, deshalb ist `start_period` jetzt `7200s`. Ob das auf jeder Hardware reicht, ist offen.

## Offen

1. `tls-auth` und `tls-crypt` passen nicht zusammen: Speichert die UI die OpenVPN-Config, steht in `server.conf` `tls-crypt`. `genclient.sh` schreibt in `.ovpn`-Dateien aber `<tls-auth>`. Ein solcher Client scheitert dann mit `tls-crypt unwrap error`. Das kommt nicht von dieser Änderung und betrifft `openvpn-ui`.
2. `start.sh` von `openvpn-ui` setzt die Gruppe der Logs auf GID 1000 und gibt ihr Schreibrecht. Bis das eingegrenzt ist, kann ein Host-Benutzer mit dieser GID sie lesen und ändern.
