# Multi-stage Dockerfile for Eclipse Cargo Tracker (Jakarta EE 10)
# Stage 1: Build the WAR file using Maven
FROM maven:3.9.4-eclipse-temurin-11 AS builder

WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application (skip tests for faster builds)
RUN mvn clean package -DskipTests -B

# Verify the WAR file was created
RUN ls -la /workspace/target/cargo-tracker.war

# Stage 2: Runtime image with Payara Server
FROM eclipse-temurin:8-jdk

# Install Payara Server
ENV PAYARA_VERSION=6.2025.3
ENV PAYARA_HOME=/opt/payara
ENV DEPLOYMENT_DIR=${PAYARA_HOME}/deployments

WORKDIR /opt

# Download and extract Payara Server
RUN apt-get update && apt-get install -y wget unzip && \
    wget -q https://repo1.maven.org/maven2/fish/payara/distributions/payara/${PAYARA_VERSION}/payara-${PAYARA_VERSION}.zip && \
    unzip -q payara-${PAYARA_VERSION}.zip && \
    rm payara-${PAYARA_VERSION}.zip && \
    mv payara6 ${PAYARA_HOME} && \
    apt-get remove -y wget unzip && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Create deployment directory
RUN mkdir -p ${DEPLOYMENT_DIR}

# Copy the built WAR from builder stage
COPY --from=builder /workspace/target/cargo-tracker.war ${DEPLOYMENT_DIR}/

# Create non-root user for security
RUN groupadd -r payara && useradd -r -g payara -d ${PAYARA_HOME} -s /bin/bash payara && \
    chown -R payara:payara ${PAYARA_HOME}

USER payara

# Set environment variables
ENV JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENV DB_JDBC_URL="jdbc:h2:file:/opt/payara/cargo-tracker-data/cargo-tracker-database"
ENV GRAPH_TRAVERSAL_URL="http://localhost:8080/cargo-tracker/rest/graph-traversal/shortest-path"

# Expose application port
EXPOSE 8080

# Expose admin port (optional)
EXPOSE 4848

# Start Payara Server with deployment
CMD ["sh", "-c", "${PAYARA_HOME}/bin/asadmin start-domain --verbose domain1"]