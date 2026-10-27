FROM postgres:18.3

HEALTHCHECK --interval=5s --timeout=5s --retries=15 \
  CMD pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"