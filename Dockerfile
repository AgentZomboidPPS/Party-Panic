# SPECTRE in one container: dashboard, live feeds and the KAIROS bot (`spectre run`).
#
#   docker build -t spectre .
#   docker run -p 8000:8000 -v spectre-data:/data \
#     -e SPECTRE_DASHBOARD_PASSWORD=choose-one \
#     -e SPECTRE_ALPACA_KEY_ID=... -e SPECTRE_ALPACA_SECRET_KEY=... spectre
#
# Keys and the password are given at run time. Never bake them into the image.
FROM python:3.13-slim

WORKDIR /app
COPY pyproject.toml README.md ./
COPY spectre ./spectre
RUN pip install --no-cache-dir .

# The database lives on a volume so trades and history survive restarts and redeploys.
ENV SPECTRE_DATABASE_URL=sqlite:////data/spectre.db \
    SPECTRE_HOST=0.0.0.0 \
    PYTHONUNBUFFERED=1
VOLUME /data
EXPOSE 8000

CMD ["spectre", "run"]
