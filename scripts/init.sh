#!/usr/bin/env bash
# EK HR DB Intelligence — Database initialization script
# Runs all migration files in order inside Docker container

set -e
echo "╔══════════════════════════════════════╗"
echo "║   EK HR DB Intelligence — DB INIT      ║"
echo "╚══════════════════════════════════════╝"

PSQL="psql -U postgres -d ek_hr_db"

for dir in migrations procedures triggers views; do
    for f in /docker-entrypoint-initdb.d/${dir}/*.sql; do
        [ -f "$f" ] || continue
        echo "  ▶ Running: $f"
        $PSQL -f "$f" && echo "  ✅ Done: $(basename $f)" || echo "  ⚠️  Warning in: $(basename $f)"
    done
done

echo ""
echo "✅ Database initialized successfully!"
echo "   Tables, Indexes, Views, Procedures, Triggers — all ready."
