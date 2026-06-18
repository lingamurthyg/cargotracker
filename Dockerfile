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

# Runtime stage: Payara Micro with JDK 11
FROM eclipse-temurin:11-jdk

# Install Payara Micro
ENV PAYARA_VERSION=6.2025.3
ENV PAYARA_HOME=/opt/payara

RUN mkdir -p ${PAYARA_HOME} && \
    curl -L -o ${PAYARA_HOME}/payara-micro.jar \
    https://repo1.maven.org/maven2/fish/payara/extras/payara-micro/${PAYARA_VERSION}/payara-micro-${PAYARA_VERSION}.jar

# Create non-root user for security
RUN groupadd -r payara && useradd -r -g payara -u 1001 -m -d /home/payara payara

# Create application directories
RUN mkdir -p /opt/app /opt/app/data /opt/app/logs && \
    chown -R payara:payara /opt/app ${PAYARA_HOME}

WORKDIR /opt/app

# Copy WAR file from builder
COPY --from=builder --chown=payara:payara /workspace/target/cargo-tracker.war ./cargo-tracker.war

# Switch to non-root user
USER payara

# Set JVM options for containerized environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions"

# Expose application port
EXPOSE 8080

# Health check endpoint (Jakarta EE application)
# Note: Payara Micro provides health endpoints at /health

# Start Payara Micro with the WAR
CMD ["sh", "-c", "java ${JAVA_OPTS} -jar ${PAYARA_HOME}/payara-micro.jar --deploy /opt/app/cargo-tracker.war --port 8080"]
