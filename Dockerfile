# Multi-stage Dockerfile for Eclipse Cargo Tracker (Jakarta EE 10 Application)
# This Dockerfile builds a WAR file and deploys it to Payara Micro

# Stage 1: Build the application
FROM maven:3.9.4-eclipse-temurin-11 AS builder

WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (this layer will be cached)
RUN mvn dependency:go-offline -B

# Copy the entire source code
COPY src ./src

# Build the application (skip tests for faster builds)
RUN mvn clean package -DskipTests -B

# Stage 2: Runtime image with Payara Micro
FROM amazoncorretto:11

# Set environment variables
ENV PAYARA_VERSION=6.2025.3 \
    PAYARA_HOME=/opt/payara \
    DEPLOY_DIR=/opt/payara/deployments \
    JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0" \
    TZ=UTC

# Create non-root user for security
RUN yum install -y shadow-utils && \
    groupadd -r payara && \
    useradd -r -g payara -d ${PAYARA_HOME} -s /sbin/nologin payara && \
    yum clean all

# Create necessary directories
RUN mkdir -p ${PAYARA_HOME} ${DEPLOY_DIR} && \
    chown -R payara:payara ${PAYARA_HOME}

# Switch to non-root user
USER payara

WORKDIR ${PAYARA_HOME}

# Download Payara Micro
ADD --chown=payara:payara https://repo1.maven.org/maven2/fish/payara/extras/payara-micro/${PAYARA_VERSION}/payara-micro-${PAYARA_VERSION}.jar ${PAYARA_HOME}/payara-micro.jar

# Copy the built WAR file from builder stage
COPY --from=builder --chown=payara:payara /workspace/target/cargo-tracker.war ${DEPLOY_DIR}/cargo-tracker.war

# Expose application port
EXPOSE 8080

# Health check using application endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD java -cp ${PAYARA_HOME}/payara-micro.jar fish.payara.micro.PayaraMicro --version || exit 1

# Start Payara Micro with the deployed WAR
CMD ["java", "-jar", "payara-micro.jar", "--deploy", "/opt/payara/deployments/cargo-tracker.war", "--port", "8080"]
