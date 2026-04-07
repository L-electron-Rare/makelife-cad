FROM python:3.12-slim

# System deps + KiCad backports repo
RUN echo "deb http://deb.debian.org/debian bookworm-backports main contrib non-free" \
    > /etc/apt/sources.list.d/bookworm-backports.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    curl bzip2 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install KiCad CLI from backports (DRC, ERC, SVG/Gerber export)
RUN apt-get update && apt-get install -y --no-install-recommends \
    -t bookworm-backports \
    kicad \
    && rm -rf /var/lib/apt/lists/*

# Install FreeCAD 1.1 via conda-forge (headless STEP/STL export)
RUN curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    -o /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && \
    rm /tmp/miniconda.sh && \
    /opt/conda/bin/conda config --add channels conda-forge && \
    /opt/conda/bin/conda install -y --no-update-deps freecad && \
    /opt/conda/bin/conda clean --all -y

ENV PATH="/opt/conda/bin:$PATH"
ENV FREECAD_CMD=/opt/conda/bin/FreeCADCmd

RUN groupadd -r app && useradd -r -g app -d /app app
WORKDIR /app

COPY pyproject.toml .
COPY gateway/ gateway/
RUN pip install --no-cache-dir .

USER app
EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8001/health || exit 1

CMD ["uvicorn", "gateway.app:app", "--host", "0.0.0.0", "--port", "8001"]
