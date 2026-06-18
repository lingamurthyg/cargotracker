# Multi-stage Dockerfile for Eclipse Cargo Tracker (Jakarta EE 10 Application)
# Build stage: Maven + JDK 11
FROM maven:3.9.4-eclipse-temurin-11 AS builder

WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (cache this layer)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application (WAR file)
RUN mvn clean package -DskipTests -B

# Runtime stage: Payara Micro with JRE 11
FROM eclipse-temurin:11-jdk

# Install Payara Micro
ENV PAYARA_VERSION=6.2025.3
ENV PAYARA_HOME=/opt/payara

RUN apt-get update && \
    apt-get install -y wget && \
    mkdir -p ${PAYARA_HOME} && \
    wget -q https://repo1.maven.org/maven2/fish/payara/extras/payara-micro/${PAYARA_VERSION}/payara-micro-${PAYARA_VERSION}.jar \
         -O ${PAYARA_HOME}/payara-micro.jar && \
    apt-get remove -y wget && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r payara && useradd -r -g payara -u 1001 -m -s /bin/bash payara

# Set working directory
WORKDIR /opt/payara

# Copy WAR file from builder
COPY --from=builder /workspace/target/cargo-tracker.war ${PAYARA_HOME}/cargo-tracker.war

# Change ownership
RUN chown -R payara:payara ${PAYARA_HOME}

# Switch to non-root user
USER payara

# Set JVM options for containerized environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.net.preferIPv4Stack=true"

# Expose application port
EXPOSE 8080

# Health check endpoint (using Payara Micro health check)
# Note: No HEALTHCHECK instruction - ECS service will handle health checks

# Start Payara Micro with the WAR file
CMD ["sh", "-c", "java ${JAVA_OPTS} -jar ${PAYARA_HOME}/payara-micro.jar --deploy ${PAYARA_HOME}/cargo-tracker.war --port 8080"]
