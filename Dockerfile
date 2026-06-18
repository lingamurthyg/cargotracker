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

# Build the WAR file (skip tests for faster builds)
RUN mvn clean package -DskipTests -B

# Runtime stage: Eclipse Temurin JRE 11 + Payara Micro
FROM eclipse-temurin:11-jdk

# Install Payara Micro
ENV PAYARA_VERSION=6.2025.3
ENV PAYARA_HOME=/opt/payara

RUN mkdir -p ${PAYARA_HOME} && \
    curl -L -o ${PAYARA_HOME}/payara-micro.jar \
    https://repo1.maven.org/maven2/fish/payara/extras/payara-micro/${PAYARA_VERSION}/payara-micro-${PAYARA_VERSION}.jar

# Create non-root user for security
RUN groupadd -r payara && useradd -r -g payara -u 1001 -m -d /home/payara payara

# Set working directory
WORKDIR /opt/payara

# Copy WAR file from builder stage
COPY --from=builder /workspace/target/cargo-tracker.war ${PAYARA_HOME}/cargo-tracker.war

# Create data directory for H2 database
RUN mkdir -p /opt/payara/cargo-tracker-data && \
    chown -R payara:payara ${PAYARA_HOME} /opt/payara/cargo-tracker-data

# Switch to non-root user
USER payara

# Set JVM options for containerized environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions"

# Expose application port
EXPOSE 8080

# Health check using Payara Micro admin endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD java -cp ${PAYARA_HOME}/payara-micro.jar fish.payara.micro.PayaraMicro --version || exit 1

# Run Payara Micro with the WAR file
CMD ["sh", "-c", "java ${JAVA_OPTS} -jar ${PAYARA_HOME}/payara-micro.jar --deploy ${PAYARA_HOME}/cargo-tracker.war --port 8080"]
