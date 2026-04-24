FROM jrottenberg/ffmpeg:7-ubuntu

# Benötigte Tools installieren
RUN apt-get update && apt-get install -y \
    bash \
    findutils \
    coreutils \
    ca-certificates \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis
WORKDIR /app

# Stream-Script kopieren
COPY stream.sh /app/stream.sh
RUN chmod +x /app/stream.sh

# Wichtig: ENTRYPOINT vom Base-Image überschreiben
# sonst wird unser Script an "ffmpeg" als Argument übergeben
ENTRYPOINT []

CMD ["/app/stream.sh"]
