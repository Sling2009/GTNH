# GregTech: New Horizons – Docker Container

Ein leichtgewichtiges Docker-Image für den **Minecraft GregTech: New Horizons** Server.  
Basierend auf **Eclipse Temurin JRE 25 / Alpine Linux**, läuft als non-root User.  
Image wird automatisch via GitHub Actions gebaut und auf der **GitHub Container Registry** veröffentlicht.

---

## Features

- Vollständig containerisierter GTNH-Server
- **GREGTECH_VERSION** steuert Version und löst automatisches Update aus
- **Automatischer Config-Merge** – eigene Werte bleiben, neue Keys kommen hinzu
- **Auto-Restart** – Server wird bei unerwartetem Absturz automatisch neu gestartet
- **Graceful Shutdown** – sauberes Herunterfahren bei `docker stop`
- **HEALTHCHECK** – Docker meldet `healthy` sobald Port 25565 erreichbar ist
- Kompatibel mit **Unraid Docker Templates**

---

## Voraussetzungen

Folgende Umgebungsvariablen **müssen** gesetzt werden, sonst startet der Container nicht:

| Variable               | Beispielwert | Beschreibung                                                    |
|------------------------|--------------|-----------------------------------------------------------------|
| `EULA`                 | `true`       | Minecraft EULA akzeptieren – **muss `true` sein**              |
| `GREGTECH_VERSION`     | `2.8.4`      | GTNH-Serverversion – Änderung löst automatisches Update aus     |
| `GREGTECH_JAVA_VERSION`| `17-25`      | Java-Kompatibilitätsbereich des Server-Packs (immer `17-25`)   |

Optionale Variablen:

| Variable  | Standardwert | Beschreibung              |
|-----------|--------------|---------------------------|
| `MEM_MIN` | `6G`         | Minimaler RAM (`-Xms`)    |
| `MEM_MAX` | `6G`         | Maximaler RAM (`-Xmx`)    |

---

## Installation

### Docker Compose (empfohlen)

```yaml
services:
  gtnh:
    image: ghcr.io/sling2009/gt-new-horizons:latest
    container_name: greg_tech_new_horizons
    environment:
      EULA: "true"
      GREGTECH_VERSION: "2.8.4"
      GREGTECH_JAVA_VERSION: "17-25"
      MEM_MIN: "6G"
      MEM_MAX: "6G"
    ports:
      - "25565:25565"
    volumes:
      - ./data:/home/minecraft
    restart: unless-stopped
    stop_grace_period: 30s
```

```bash
docker compose up -d
```

### Docker (manuell)

```bash
docker run --detach --name greg_tech_new_horizons \
  -e EULA=true \
  -e GREGTECH_VERSION=2.8.4 \
  -e GREGTECH_JAVA_VERSION=17-25 \
  -e MEM_MIN=12G \
  -e MEM_MAX=12G \
  -v "$(pwd)/data:/home/minecraft" \
  --publish 25565:25565 \
  ghcr.io/sling2009/gt-new-horizons:latest
```

> **Hinweis:** Das Datenverzeichnis muss dem Container-User gehören (uid 99, gid 100):
> ```bash
> sudo chown -R 99:100 ./data
> ```
> Auf **Unraid** ist das nicht nötig – dort entspricht uid 99/gid 100 dem `nobody`-User.

---

## Server-Update

Um auf eine neue GTNH-Version zu aktualisieren, `GREGTECH_VERSION` ändern und den Container neu starten. Der Rest passiert automatisch.

**Was beim Update passiert:**
1. Container erkennt die Versionsabweichung und lädt das neue Server-Pack herunter
2. `mods/` und `libraries/` werden vollständig ersetzt
3. Config-Dateien werden **gemergt** (siehe Config-Merge)
4. Weltdaten (`world/`, `world_nether/`, `world_the_end/`) werden **nie angefasst**

**Neue Config-Keys im Log sehen:**
```bash
docker logs greg_tech_new_horizons | grep "added new key"
```

---

## Config-Merge

Beim Update werden bestehende Config-Dateien nicht überschrieben, sondern intelligent zusammengeführt:

**Regel: Alte Werte gewinnen. Neue Keys kommen hinzu. Nichts wird gelöscht.**

| Format        | Strategie                                          |
|---------------|----------------------------------------------------|
| `.json`       | Deep-Merge via `jq` – alte Werte haben Vorrang     |
| `.cfg`        | Forge `TYPE:key=value`-Format – neue Keys werden angehängt |
| `.properties` | Neue Keys werden angehängt, bestehende bleiben     |
| Sonstige      | Nur kopieren wenn Datei noch nicht existiert       |

Von jeder gemergten Datei wird vorher ein `.bak`-Backup angelegt.

---

## Auto-Restart

Wenn der Server-Prozess unerwartet abstürzt, startet der Container den Server automatisch neu – mit einem 12-Sekunden-Countdown im Log. Bei `docker stop` wird **nicht** neu gestartet.

```bash
docker logs -f greg_tech_new_horizons
```

---

## Graceful Shutdown

Bei `docker stop` läuft folgender Prozess ab:

1. Docker sendet `SIGTERM` an den Container
2. Das Entrypoint-Script schickt `stop` an den Minecraft-Server
3. Der Server speichert die Welt und beendet sich sauber
4. Erst danach beendet sich der Container

Die `stop_grace_period` von 30 Sekunden kann für sehr große Welten im Compose-File erhöht werden.

---

## Health Check

Docker prüft alle 60 Sekunden ob Port 25565 erreichbar ist. Die erste Prüfung findet nach 180 Sekunden statt (GTNH braucht beim ersten Start länger).

```bash
docker inspect greg_tech_new_horizons | grep -i health
```

---

## Server-Konfiguration

OPS, Whitelist und andere Server-Konfigurationen werden über Dateien im Volume verwaltet – nicht über Umgebungsvariablen:

| Datei            | Pfad im Volume          |
|------------------|-------------------------|
| OPS              | `./data/ops.json`       |
| Whitelist        | `./data/whitelist.json` |
| Server-Einstellungen | `./data/server.properties` |

Diese Dateien können vor dem ersten Start angelegt oder jederzeit bearbeitet werden. Beim Update bleiben eigene Werte in `server.properties` durch den Config-Merge erhalten.

---

## Releases & CI/CD

Neue Image-Versionen werden automatisch via **GitHub Actions** gebaut und auf die **GitHub Container Registry** gepusht.

**Ablauf:**
1. Tag mit `v*` setzen und pushen – das löst die Pipeline aus
2. Tests laufen automatisch: Merge-Unit-Tests + simulierter Update-Flow
3. Nur wenn alle Tests grün sind: Image wird gebaut und auf ghcr.io gepusht

```bash
git tag v1.x
git push origin v1.x
```

Benötigte GitHub-Secrets: **keine** – der Build verwendet `GITHUB_TOKEN`.

---

## Image

[ghcr.io/sling2009/gt-new-horizons](https://github.com/Sling2009/gregTech/pkgs/container/gt-new-horizons)
# GTNH
