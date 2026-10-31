# Management-Interface über einen Unix-Socket

Stand: 2026-10-31. Die Änderung ist auf dem Branch `management-unix-socket` committet. Der Test des kompletten Stacks steht noch aus, siehe „Offen“.

## Ziel

OpenVPN wird über `/etc/openvpn/run/mi.sock` gesteuert statt über TCP-Port 2080. Das Interface hat kein Passwort, deshalb konnte jeder, der den Port erreichte, Client-Daten lesen, Clients trennen oder den Server stoppen.

Das Gegenstück liegt im Repo `openvpn-ui` unter `docs/management-unix-socket.md`.

## Änderungen in diesem Repo

| Datei | Änderung |
|---|---|
| `server.conf` | `management /etc/openvpn/run/mi.sock unix` |
| `docker-entrypoint.sh` | Legt `run` mit `root:root` und Modus `0700` an und stellt alte Configs mit Port 2080 um |
| `docker-compose.yml`, `docker-compose-no-ui.yml` | Neues Volume `./run:/etc/openvpn/run`, Healthcheck prüft Socket und Prozess, Port-Eintrag entfernt |
| `README.md` | Compose-Beispiel angepasst |
| `.gitignore` | `run/` ergänzt |
| `CHANGELOG.md` | Eintrag `v0.6.4` |

## So ist der Zugriff beschränkt

Der Socket hat den Modus `0777`, seine eigenen Rechte schützen also nichts. Den Zugriff begrenzt das Verzeichnis `run`, das der Container beim Start auf `root:root` mit Modus `0700` setzt. `chown` ist nötig, weil das Host-Verzeichnis einem beliebigen Benutzer gehören kann und dieser sonst Zugriff behielte.

Der Prozess, der den Socket öffnet, muss deshalb als root laufen. Bei Rootless Docker ist root im Container der Benutzer, der Docker ausführt.

**Ungeprüfter Verdacht:** Der Container von `openvpn-ui` startet zwar als root, `build/assets/start.sh` wechselt für den Webprozess aber mit `su-exec` zu UID 1000. Diese UID erhält laut dem Test unten `permission denied`. Die UI erreicht den Socket mit dem echten Image daher vermutlich nicht.

## Umstellung bestehender Configs

Der Container stellt eine Zeile `management <Adresse> 2080` beim Start auf den Socket um, wenn `./run:/etc/openvpn/run` gemountet ist. Ohne dieses Volume bleibt die Config auf TCP. `server.conf` wird dabei in derselben Datei geändert, weil sie als einzelne Datei gemountet ist und ein `sed -i` dort fehlschlagen würde.

## Rollout

1. Images von `openvpn` und `openvpn-ui` gemeinsam aktualisieren. Die neue UI spricht nur noch mit dem Socket.
2. `./run:/etc/openvpn/run` beim Service `openvpn` ergänzen.
3. Den neuen Healthcheck aus den Compose-Dateien übernehmen. Der alte prüft Port 2080 und würde fehlschlagen.

## Bekannte Einschränkung

`SIGHUP` beendet OpenVPN, wenn `server.conf` den Modus `0600` hat, weil der Prozess als `nobody` läuft und die Datei nicht erneut lesen kann. Mit `restart: always` startet der Container neu. `openvpn-ui` setzt den Modus `0600` beim Speichern. Die Buttons der Oberfläche nutzen `SIGUSR1`, die Signal-API nimmt aber auch andere Signale an.

## Getestet

Der Test lief mit OpenVPN 2.6 in Alpine 3.21, dem Startblock aus `docker-entrypoint.sh` und einem Client aus der Bibliothek in einem zweiten Container:

- root aus einem anderen Container verbindet sich, UID 1000 und UID 65534 erhalten `permission denied`.
- Der normale Host-Benutzer hat keinen Zugriff auf `run`.
- `SIGUSR1` und ein Container-Neustart lassen den Socket funktionieren.
- Eine alte `server.conf` wird umgestellt und behält ihre Inode.
- Der Healthcheck besteht, wenn OpenVPN läuft, und schlägt ohne den Prozess fehl.

Das echte Image dieses Repos wurde dabei nicht gebaut.

## Offen

1. Den kompletten Stack mit beiden echten Images testen. Dabei den Socket-Zugriff der UI mit UID 1000 klären, auch weil `start.sh` mit `chgrp -R` und `chmod -R g+w` das Verzeichnis `run` verändert.
2. `LABEL version` im `Dockerfile` steht noch auf `0.6.3` und muss für v0.6.4 angehoben werden.
3. Code-Review.
