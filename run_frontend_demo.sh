#!/usr/bin/env zsh
set -e

cd "$(dirname "$0")/frontend"

if ! lsof -ti tcp:8000 >/dev/null 2>&1; then
	echo "Starting backend on http://127.0.0.1:8000..."
	cd ../backend
	../.venv/bin/python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000 >/tmp/afg2026-backend.log 2>&1 &
	cd ../frontend

	for _ in {1..30}; do
		if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
			break
		fi
		sleep 1
	done
fi

flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
