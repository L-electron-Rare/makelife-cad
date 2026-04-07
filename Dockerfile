FROM python:3.12-slim

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl bzip2 ca-certificates gnupg wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install KiCad 9.x CLI from Debian sid (only kicad-cli, not full GUI)
RUN echo "deb http://deb.debian.org/debian sid main" \
    > /etc/apt/sources.list.d/sid.list && \
    echo 'APT::Default-Release "bookworm";' \
    > /etc/apt/apt.conf.d/99default-release && \
    apt-get update && \
    apt-get install -y --no-install-recommends -t sid kicad-cli 2>/dev/null; \
    rm -f /etc/apt/sources.list.d/sid.list /etc/apt/apt.conf.d/99default-release && \
    rm -rf /var/lib/apt/lists/*

# Install FreeCAD 1.x AppImage (headless STEP/STL export)
ARG FREECAD_VERSION=1.1.0
RUN mkdir -p /opt/freecad && \
    wget -q "https://github.com/FreeCAD/FreeCAD/releases/download/${FREECAD_VERSION}/FreeCAD_${FREECAD_VERSION}-Linux-x86_64-py311.AppImage" \
    -O /opt/freecad/FreeCAD.AppImage && \
    chmod +x /opt/freecad/FreeCAD.AppImage && \
    cd /opt/freecad && ./FreeCAD.AppImage --appimage-extract > /dev/null 2>&1 && \
    rm FreeCAD.AppImage && \
    ln -s /opt/freecad/squashfs-root/usr/bin/freecadcmd /usr/local/bin/FreeCADCmd

ENV FREECAD_CMD=/usr/local/bin/FreeCADCmd

RUN groupadd -r app && useradd -r -g app -d /app app
WORKDIR /app

COPY pyproject.toml .
COPY gateway/ gateway/
RUN pip install --no-cache-dir .

# FreeCAD needs writable config/cache dirs
RUN mkdir -p /app/.config/FreeCAD /app/.cache/FreeCAD /app/.local/share/FreeCAD \
    && chown -R app:app /app/.config /app/.cache /app/.local

ENV HOME=/app
ENV XDG_CONFIG_HOME=/app/.config
ENV XDG_CACHE_HOME=/app/.cache
ENV XDG_DATA_HOME=/app/.local/share

USER app
EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8001/health || exit 1

CMD ["uvicorn", "gateway.app:app", "--host", "0.0.0.0", "--port", "8001"]
