# Multi-stage Dockerfile for Eclipse Cargo Tracker (Jakarta EE 10 Application)
# This Dockerfile builds a WAR file and deploys it to Payara Server

# ============================================================================
# Stage 1: Build Stage
# ============================================================================
FROM maven:3.9.4-eclipse-temurin-11 AS builder

WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (this layer will be cached if pom.xml doesn't change)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application (WAR file)
RUN mvn clean package -DskipTests -B

# ============================================================================
# Stage 2: Runtime Stage
# ============================================================================
FROM eclipse-temurin:11-jdk

# Install Payara Server
ENV PAYARA_VERSION=6.2025.3
ENV PAYARA_HOME=/opt/payara
ENV DEPLOYMENT_DIR=${PAYARA_HOME}/glassfish/domains/domain1/autodeploy

# Create payara user for security
RUN groupadd -r payara && useradd -r -g payara -u 1001 payara

# Download and install Payara Server
RUN apt-get update && \
    apt-get install -y wget unzip && \
    wget -q https://repo1.maven.org/maven2/fish/payara/distributions/payara/${PAYARA_VERSION}/payara-${PAYARA_VERSION}.zip && \
    unzip -q payara-${PAYARA_VERSION}.zip -d /opt && \
    mv /opt/payara6 ${PAYARA_HOME} && \
    rm payara-${PAYARA_VERSION}.zip && \
    apt-get remove -y wget unzip && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    chown -R payara:payara ${PAYARA_HOME}

# Copy WAR file from builder stage
COPY --from=builder /workspace/target/cargo-tracker.war ${DEPLOYMENT_DIR}/

# Set ownership
RUN chown -R payara:payara ${DEPLOYMENT_DIR}

# Switch to non-root user
USER payara

# Expose HTTP port
EXPOSE 8080

# Expose HTTPS port (optional)
EXPOSE 8181

# Expose admin port (optional, for management)
EXPOSE 4848

# Set working directory
WORKDIR ${PAYARA_HOME}

# Configure JVM options for containerized environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.awt.headless=true"

# Start Payara Server in foreground
CMD ["bin/asadmin", "start-domain", "--verbose"]
