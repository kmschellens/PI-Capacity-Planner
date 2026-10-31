#!/bin/bash
set -e

# Both Compose projects use this external network. Create it once when needed.
docker network inspect shared_net >/dev/null 2>&1 || docker network create shared_net >/dev/null

# Start Supabase
./supabase-local/run.sh start

# Keep Presence and Broadcast access scoped to users who can open the board.
docker compose --project-directory ./supabase-local --env-file ./supabase-local/.env -f ./supabase-local/docker-compose.yml exec -T db \
  psql -v ON_ERROR_STOP=1 -U postgres -d postgres < ./supabase-local/dev/realtime-collaboration.sql

# Start PI capacity planner
docker compose up -d --force-recreate
