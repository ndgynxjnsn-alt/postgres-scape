# syntax=docker/dockerfile:1
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /src
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -q -B dependency:go-offline
COPY src src
RUN --mount=type=cache,target=/root/.m2 mvn -q -B package -DskipTests

FROM eclipse-temurin:25-jre
ARG OTEL_AGENT_VERSION=2.33.1
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VERSION}/opentelemetry-javaagent.jar /agents/
RUN chmod -R a+rX /agents
COPY --from=build /src/target/pg-client.jar /app/pg-client.jar
USER 1000
ENTRYPOINT ["java", "-javaagent:/agents/opentelemetry-javaagent.jar", "-jar", "/app/pg-client.jar"]
