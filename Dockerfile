# ==========================================================
# Stage 1 - Build the Spring Boot application
# ==========================================================
FROM maven:3.9.11-eclipse-temurin-11 AS builder

LABEL stage="builder"

WORKDIR /app

# Copy Maven files first for better layer caching
COPY pom.xml .

# Download dependencies
RUN mvn dependency:go-offline -B

# Copy application source
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests

# ==========================================================
# Stage 2 - Runtime Image
# ==========================================================
FROM eclipse-temurin:11-jre-jammy

LABEL maintainer="Mina Bisa"
LABEL application="springboot-devsecops"

WORKDIR /app

# Create non-root user with numeric UID/GID
RUN groupadd --gid 10001 appgroup && \
    useradd \
    --uid 10001 \
    --gid appgroup \
    --system \
    --create-home \
    --home-dir /app \
    --shell /usr/sbin/nologin \
    appuser

# Copy the application JAR
COPY --from=builder \
    --chown=10001:10001 \
    /app/target/*.jar \
    /app/app.jar

# Switch to non-root user
USER 10001:10001

EXPOSE 8080

ENTRYPOINT ["java","-jar","/app/app.jar"]