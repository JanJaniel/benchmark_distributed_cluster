# Multi-stage build for Flink Nexmark benchmark
# Stage 1: Build the JAR with Maven
# Note: Maven official images support ARM64 (multi-arch)
FROM maven:3.8-openjdk-11 AS builder

WORKDIR /build

# Copy pom.xml first for dependency caching
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the project
RUN mvn clean package -DskipTests -B

# Stage 2: Create Flink runtime image
FROM flink:1.18.1-scala_2.12

# Copy the built JAR to Flink's usrlib directory
# This makes it available to the Flink cluster
COPY --from=builder /build/target/flink-nexmark-distributed-1.0-SNAPSHOT.jar /opt/flink/usrlib/nexmark.jar

# Set environment variable for Kafka broker (can be overridden at runtime)
ENV KAFKA_BOOTSTRAP_SERVERS=192.168.2.70:9094

# The entrypoint is inherited from the base flink image
# It will run either 'jobmanager' or 'taskmanager' based on the command
