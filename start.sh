#!/bin/bash
set -e

# Both Compose projects use this external network. Create it once when needed.
docker network inspect shared_net >/dev/null 2>&1 || docker network create shared_net >/dev/null

# Start Supabase
./supabase-local/run.sh start

# Start PI capacity planner
docker compose up -d
