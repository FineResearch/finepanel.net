#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f ~/finepanel/tmp/pids/server.pid

# Exec CDM inside Dockerfile.
exec "$@"
