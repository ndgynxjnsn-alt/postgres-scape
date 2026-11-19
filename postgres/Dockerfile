# TimescaleDB (PostgreSQL 18, Alpine) + pg_tracing (https://github.com/DataDog/pg_tracing)
# BASE_IMAGE: any timescale/timescaledb-based PG18 image, e.g. the one your existing database runs on
#   (lnf9s35w2/my-offline-timescale:pg18), so all extensions of the existing data are there.
# The base runs PostgreSQL as user postgres, uid 70.
ARG BASE_IMAGE=timescale/timescaledb:2.24.0-pg18

FROM ${BASE_IMAGE} AS build
# PG18 support is only on pg_tracing's main branch (no release yet), so pin a commit.
ARG PG_TRACING_COMMIT=c343277660011200212c4e0833eea0c6b1ee8fa2
# PGXS also compiles LLVM bitcode for JIT (the base PostgreSQL is built --with-llvm): clang19/llvm19
RUN apk add --no-cache build-base clang19 llvm19-dev curl curl-dev
WORKDIR /src
RUN curl -fsSL https://github.com/DataDog/pg_tracing/archive/${PG_TRACING_COMMIT}.tar.gz \
      | tar xz --strip-components=1 \
 # libcurl 8.x type-checks curl_easy_setopt: the timeout GUC is an int but must be passed as long
 && sed -i 's/CURLOPT_CONNECTTIMEOUT_MS, pg_tracing_otel_connect_timeout_ms/CURLOPT_CONNECTTIMEOUT_MS, (long) pg_tracing_otel_connect_timeout_ms/' src/pg_tracing_otel.c \
 && make -j"$(nproc)" \
 && make install DESTDIR=/out

FROM ${BASE_IMAGE}
# Runtime dependency of pg_tracing's OTLP exporter (background worker)
RUN apk add --no-cache libcurl
COPY --from=build /out/ /
# Log directory for logging_collector, readable for the Alloy sidecar through the shared volume.
# A new named volume mounted here takes over this owner (postgres, uid 70).
RUN install -d -o postgres -g postgres -m 0755 /var/log/postgresql
