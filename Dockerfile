# -----------------------------
# Stage 1: Build
# -----------------------------
FROM maven:3.9-eclipse-temurin-11 AS builder

WORKDIR /app

COPY pom.xml .

RUN mvn dependency:go-offline -B

COPY src ./src

RUN mvn clean package -B

# -----------------------------
# Stage 2: Runtime
# -----------------------------
FROM eclipse-temurin:11-jre-jammy AS runtime

WORKDIR /app

RUN addgroup -g 10001 appgroup && \
    adduser -D -u 10001 -G appgroup appuser

USER 10001

COPY --from=builder --chown=appuser:appgroup \
    /app/target/wezvatech-demo-1.0.0.jar \
    /app/app.jar


EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]