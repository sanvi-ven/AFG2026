FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Cloud Run injects $PORT; default to 8000 for local `docker run`
ENV PORT=8000
# --proxy-headers + --forwarded-allow-ips='*' trusts X-Forwarded-For from
# whatever sent the request — safe here because on Cloud Run the container
# is only ever reachable through Google's own front-end proxy, never
# directly from the internet, so this is Google's own recommended pattern
# for uvicorn on Cloud Run. Without it, slowapi's per-IP rate limiting reads
# the proxy's IP for every caller instead of the real one.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*'"]
