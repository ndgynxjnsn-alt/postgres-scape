# PostgreSQL 18 + pg_tracing (https://github.com/DataDog/pg_tracing)
# PG18 support is only on main (no release yet), so pin a commit.
ARG PG_IMAGE=postgres:18.6

FROM ${PG_IMAGE} AS build
ARG PG_TRACING_COMMIT=c343277660011200212c4e0833eea0c6b1ee8fa2
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential ca-certificates curl \
      libcurl4-openssl-dev postgresql-server-dev-${PG_MAJOR} \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl -fsSL https://github.com/DataDog/pg_tracing/archive/${PG_TRACING_COMMIT}.tar.gz \
      | tar xz --strip-components=1 \
 # libcurl 8.x type-checks curl_easy_setopt: the timeout GUC is an int but must be passed as long
 && sed -i 's/CURLOPT_CONNECTTIMEOUT_MS, pg_tracing_otel_connect_timeout_ms/CURLOPT_CONNECTTIMEOUT_MS, (long) pg_tracing_otel_connect_timeout_ms/' src/pg_tracing_otel.c \
 && make -j"$(nproc)" \
 && make install DESTDIR=/out

FROM ${PG_IMAGE}
# Runtime dependency for the OTLP exporter (background worker)
RUN apt-get update \
 && apt-get install -y --no-install-recommends libcurl4t64 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/ /
