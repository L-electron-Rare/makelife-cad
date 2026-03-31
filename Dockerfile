FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
RUN groupadd -r app && useradd -r -g app -d /app app
WORKDIR /app

COPY pyproject.toml .
RUN pip install --no-cache-dir -e .
COPY . .

USER app
EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8001/health || exit 1

CMD ["uvicorn", "gateway.app:app", "--host", "0.0.0.0", "--port", "8001"]
