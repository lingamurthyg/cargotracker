# Build stage
FROM maven:3.9.4-eclipse-temurin-11 AS builder

WORKDIR /workspace

# Copy POM file for dependency caching
COPY pom.xml .

# Download dependencies
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build WAR file (using default payara profile)
RUN mvn clean package -DskipTests -B

# Runtime stage with Open Liberty
FROM eclipse-temurin:8-jdk

LABEL maintainer="cargo-tracker"
LABEL version="3.1-SNAPSHOT"

WORKDIR /opt/ol

# Install Open Liberty
ENV LIBERTY_VERSION=24.0.0.12
RUN apt-get update && \
    apt-get install -y wget unzip && \
    wget https://repo1.maven.org/maven2/io/openliberty/openliberty-runtime/${LIBERTY_VERSION}/openliberty-runtime-${LIBERTY_VERSION}.zip && \
    unzip openliberty-runtime-${LIBERTY_VERSION}.zip && \
    rm openliberty-runtime-${LIBERTY_VERSION}.zip && \
    apt-get remove -y wget unzip && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV WLP_HOME=/opt/ol/wlp
ENV PATH=${WLP_HOME}/bin:$PATH

# Copy server configuration
COPY src/main/liberty/config/server.xml ${WLP_HOME}/usr/servers/defaultServer/
COPY src/main/liberty/config/bootstrap.properties ${WLP_HOME}/usr/servers/defaultServer/

# Copy WAR file from builder
COPY --from=builder /workspace/target/cargo-tracker.war ${WLP_HOME}/usr/servers/defaultServer/apps/

# Create shared resources directory for JDBC drivers
RUN mkdir -p ${WLP_HOME}/usr/shared/resources

# Copy H2 database driver (embedded in WAR during build)
# For production with PostgreSQL, mount the driver as a volume or use init container

# Create non-root user
RUN groupadd -r liberty && useradd -r -g liberty liberty && \
    chown -R liberty:liberty ${WLP_HOME}

USER liberty

# Environment variables
ENV HTTP_PORT=8080
ENV HTTPS_PORT=8081
ENV JMS_PORT=7276
ENV JMS_SSL_PORT=9100
ENV DB_URL="jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1"
ENV DB_USER="sa"
ENV DB_PASSWORD=""
ENV TIMER_DB_URL="jdbc:h2:mem:timerdb;DB_CLOSE_DELAY=-1"
ENV TIMER_DB_USER="sa"
ENV TIMER_DB_PASSWORD=""
ENV GRAPH_TRAVERSAL_URL="http://localhost:8080/graph-traversal/"
ENV ADMIN_USER="admin"
ENV ADMIN_PASSWORD="admin"
ENV TZ=UTC
ENV LANG=en_US.UTF-8

# Expose ports
EXPOSE 8080 8081 7276 9100

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
  CMD ${WLP_HOME}/bin/server status defaultServer || exit 1

# Start Open Liberty server
CMD ["server", "run", "defaultServer"]