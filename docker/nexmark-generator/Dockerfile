# Nexmark generator Docker image
FROM python:3.10-slim-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the generator script (will be mounted as volume in production)
# This allows for easy updates without rebuilding the image
VOLUME ["/app/generator"]

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV KAFKA_BROKER=192.168.2.42:9094

CMD ["python", "/app/generator/nexmark-generator-deterministic.py"]