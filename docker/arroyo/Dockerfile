# Arroyo Docker image for ARM64 (Raspberry Pi)
FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download Arroyo binary for ARM64
RUN curl -L https://github.com/ArroyoSystems/arroyo/releases/download/v0.11.0/arroyo-linux-arm64 \
    -o /usr/local/bin/arroyo && \
    chmod +x /usr/local/bin/arroyo

# Create arroyo user
RUN useradd -m -s /bin/bash arroyo

# Create necessary directories
RUN mkdir -p /arroyo/data /arroyo/config && \
    chown -R arroyo:arroyo /arroyo

USER arroyo
WORKDIR /arroyo

# Copy entrypoint script
COPY --chown=arroyo:arroyo entrypoint.sh /arroyo/entrypoint.sh
RUN chmod +x /arroyo/entrypoint.sh

# Expose ports
# 8000: Web UI
# 8001: HTTP API  
# 9190: gRPC (for worker communication)
EXPOSE 8000 8001 9190

ENTRYPOINT ["/arroyo/entrypoint.sh"]
CMD ["controller"]