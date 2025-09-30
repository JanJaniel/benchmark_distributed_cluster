# Flink Docker image for ARM64 (Raspberry Pi)
FROM flink:1.18.1-java11

# Install additional dependencies for ARM64
RUN apt-get update && \
    apt-get install -y \
        python3 \
        python3-pip \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Copy custom configuration
COPY flink-conf.yaml $FLINK_HOME/conf/

# Set memory constraints for Raspberry Pi
ENV FLINK_PROPERTIES="jobmanager.memory.process.size=1600m\ntaskmanager.memory.process.size=1600m"

# Expose ports
# 6123: RPC
# 8081: Web UI
# 6121-6130: Data exchange
EXPOSE 6123 8081 6121-6130

# Note: For distributed setup, you'll need to create separate 
# docker-compose files for JobManager and TaskManager roles