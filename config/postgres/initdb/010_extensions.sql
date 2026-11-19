-- Runs once, on an empty data directory, after the base image's 000_install_timescaledb.sh (creates timescaledb).
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_tracing;
