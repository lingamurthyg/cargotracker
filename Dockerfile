# Multi-stage Dockerfile for Eclipse Cargo Tracker (Jakarta EE 10 Application)
# Stage 1: Build the application
FROM maven:3.9.4-eclipse-temurin-11 AS builder

WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (this layer will be cached)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application (WAR file)
RUN mvn clean package -DskipTests -B

# Stage 2: Runtime with Payara Server
FROM eclipse-temurin:11-jdk

# Install Payara Server
ENV PAYARA_VERSION=6.2025.3
ENV PAYARA_HOME=/opt/payara
ENV DEPLOYMENT_DIR=${PAYARA_HOME}/deployments

# Create non-root user for security
RUN groupadd -r payara && useradd -r -g payara -u 1001 payara

# Download and install Payara Micro
RUN mkdir -p ${PAYARA_HOME} && \
    curl -L -o ${PAYARA_HOME}/payara-micro.jar \
    https://repo1.maven.org/maven2/fish/payara/extras/payara-micro/${PAYARA_VERSION}/payara-micro-${PAYARA_VERSION}.jar

# Create deployment directory
RUN mkdir -p ${DEPLOYMENT_DIR} && \
    chown -R payara:payara ${PAYARA_HOME}

# Copy WAR file from builder stage
COPY --from=builder --chown=payara:payara /workspace/target/cargo-tracker.war ${DEPLOYMENT_DIR}/

# Switch to non-root user
USER payara

# Expose application port
EXPOSE 8080

# Set JVM options for containerized environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.awt.headless=true"

# Set timezone
ENV TZ=UTC

# Start Payara Micro with the deployed WAR
CMD ["sh", "-c", "java ${JAVA_OPTS} -jar ${PAYARA_HOME}/payara-micro.jar --deploy ${DEPLOYMENT_DIR}/cargo-tracker.war --port 8080"]
