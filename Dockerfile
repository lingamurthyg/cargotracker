# Multi-stage Dockerfile for Eclipse Cargo Tracker (Jakarta EE Application)
# Build stage: Use Maven with Eclipse Temurin JDK 11
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

# Runtime stage: Use explicit base image (Amazon Corretto 11)
FROM amazoncorretto:11

# Install Payara Micro for Jakarta EE runtime
ENV PAYARA_VERSION=6.2025.3
ENV PAYARA_HOME=/opt/payara

# Create non-root user for security
RUN yum install -y wget unzip && \
    yum clean all && \
    groupadd -r payara && \
    useradd -r -g payara -d ${PAYARA_HOME} -s /bin/bash payara && \
    mkdir -p ${PAYARA_HOME}

# Download and install Payara Micro
RUN wget -q https://repo1.maven.org/maven2/fish/payara/extras/payara-micro/${PAYARA_VERSION}/payara-micro-${PAYARA_VERSION}.jar \
    -O ${PAYARA_HOME}/payara-micro.jar && \
    chown -R payara:payara ${PAYARA_HOME}

# Copy WAR file from builder stage
COPY --from=builder /workspace/target/cargo-tracker.war ${PAYARA_HOME}/cargo-tracker.war

# Set working directory
WORKDIR ${PAYARA_HOME}

# Switch to non-root user
USER payara

# Expose application port
EXPOSE 8080

# Set JVM options for containerized environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Health check endpoint (Jakarta EE application)
# Note: Health checks are handled by Kubernetes probes, not Dockerfile HEALTHCHECK

# Run Payara Micro with the WAR file
CMD ["java", "-jar", "payara-micro.jar", "--deploy", "cargo-tracker.war", "--port", "8080"]
