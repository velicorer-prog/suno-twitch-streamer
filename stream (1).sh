#!/bin/bash
# ================================================================
# Suno Twitch Streamer
# Läuft als Docker-Container auf Hetzner / Easypanel
# ================================================================

# ---- Konfiguration (alles über Umgebungsvariablen) -------------
SONGS_DIR="${SONGS_DIR:-/songs}"
TWITCH_KEY="${TWITCH_STREAM_KEY}"
BACKGROUND="${BACKGROUND_FILE:-/songs/background.jpg}"
DELETE_AFTER_DAYS="${DELETE_AFTER_DAYS:-60}"
CLEANUP_INTERVAL_HOURS="${CLEANUP_INTERVAL_HOURS:-24}"
EMPTY_WAIT_SECONDS="${EMPTY_WAIT_SECONDS:-30}"
# ----------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ---- Startup-Checks --------------------------------------------
log "================================================"
log " Suno Twitch Streamer wird gestartet..."
log "================================================"

if [ -z "$TWITCH_KEY" ]; then
  log "FEHLER: Umgebungsvariable TWITCH_STREAM_KEY ist nicht gesetzt!"
  log "Bitte in Easypanel unter Umgebungsvariablen eintragen."
  exit 1
fi

# Songs-Ordner anlegen falls nicht vorhanden
mkdir -p "$SONGS_DIR"

# Hintergrundbild prüfen, sonst schwarzes Fallback erstellen
if [ ! -f "$BACKGROUND" ]; then
  log "Kein Hintergrundbild gefunden — erstelle Standard-Hintergrund..."
  ffmpeg -f lavfi -i color=c=0x1a0b2e:size=1920x1080:rate=1 \
    -frames:v 1 "$BACKGROUND" -y -loglevel quiet
fi

RTMP_URL="rtmp://live.twitch.tv/app/${TWITCH_KEY}"
LAST_CLEANUP=$(date +%s)

log "Songs-Ordner:       $SONGS_DIR"
log "Hintergrund:        $BACKGROUND"
log "Lösch-Regel:        Songs älter als ${DELETE_AFTER_DAYS} Tage"
log "Cleanup-Intervall:  alle ${CLEANUP_INTERVAL_HOURS} Stunden"
log "RTMP-Ziel:          rtmp://live.twitch.tv/app/***"
log "================================================"

# ---- Cleanup-Funktion ------------------------------------------
cleanup_old_songs() {
  log "Cleanup läuft: Songs älter als ${DELETE_AFTER_DAYS} Tage werden gelöscht..."
  local deleted
  deleted=$(find "$SONGS_DIR" -name "*.mp3" -type f -mtime +${DELETE_AFTER_DAYS} -delete -print 2>/dev/null | wc -l)
  if [ "$deleted" -gt 0 ]; then
    log "  → ${deleted} alte Datei(en) gelöscht."
  else
    log "  → Keine alten Dateien zum Löschen."
  fi
}

# ---- Hauptschleife ---------------------------------------------
while true; do

  # Cleanup prüfen (alle X Stunden)
  NOW=$(date +%s)
  ELAPSED_HOURS=$(( (NOW - LAST_CLEANUP) / 3600 ))
  if [ "$ELAPSED_HOURS" -ge "$CLEANUP_INTERVAL_HOURS" ]; then
    cleanup_old_songs
    LAST_CLEANUP=$NOW
  fi

  # Verfügbare Songs zählen
  count=$(find "$SONGS_DIR" -name "*.mp3" -type f 2>/dev/null | wc -l)

  if [ "$count" -eq 0 ]; then
    log "Queue leer — warte ${EMPTY_WAIT_SECONDS} Sekunden auf neue Songs..."
    sleep "$EMPTY_WAIT_SECONDS"
    continue
  fi

  log "Starte Durchlauf mit $count Songs (zufällige Reihenfolge)..."

  # Alle MP3s zufällig sortieren
  mapfile -t songs < <(find "$SONGS_DIR" -name "*.mp3" -type f | shuf)

  for song in "${songs[@]}"; do

    # Datei noch vorhanden? (könnte durch Cleanup weg sein)
    [ -f "$song" ] || continue

    filename=$(basename "$song" .mp3)

    # Dateinamen-Format: Songname___Username___SongID
    # Mit `___` (drei Unterstriche) als Trennzeichen
    songname=$(echo "$filename" | awk -F'___' '{print $1}' | tr '_' ' ')
    username=$(echo "$filename" | awk -F'___' '{print $2}' | tr '_' ' ')

    # Fallback wenn Dateiname nicht dem Format entspricht
    [ -z "$songname" ] && songname="Unbekannt"
    [ -z "$username" ] && username="Anonym"

    log "► $songname  —  $username"

    # Text in Dateien schreiben (umgeht FFmpeg-Escape-Probleme)
    printf '%s' "$songname"            > /tmp/title.txt
    printf 'eingereicht von %s' "$username" > /tmp/artist.txt

    # ----------------------------------------------------------------
    # FFmpeg: Hintergrundbild + MP3 → Twitch
    # ----------------------------------------------------------------
    ffmpeg \
      -loglevel warning \
      -re \
      -loop 1 -i "$BACKGROUND" \
      -i "$song" \
      -vf "drawtext=\
fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
textfile=/tmp/title.txt:\
fontcolor=white:\
fontsize=58:\
x=(w-text_w)/2:\
y=h-180:\
shadowcolor=black:\
shadowx=3:\
shadowy=3,\
drawtext=\
fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
textfile=/tmp/artist.txt:\
fontcolor=#cccccc:\
fontsize=36:\
x=(w-text_w)/2:\
y=h-110:\
shadowcolor=black:\
shadowx=2:\
shadowy=2" \
      -c:v libx264 \
      -preset veryfast \
      -tune stillimage \
      -b:v 1500k \
      -maxrate 1500k \
      -bufsize 3000k \
      -pix_fmt yuv420p \
      -g 60 \
      -c:a aac \
      -b:a 160k \
      -ar 44100 \
      -ac 2 \
      -shortest \
      -f flv \
      "$RTMP_URL"

    EXIT_CODE=$?

    if [ $EXIT_CODE -ne 0 ]; then
      log "WARNUNG: FFmpeg Exit-Code $EXIT_CODE bei: $(basename "$song")"
      log "Kurze Pause, dann nächster Song..."
      sleep 5
    fi

  done

  log "Durchlauf beendet — starte neue zufällige Reihenfolge."

done
