# Metrics collector Docker image
FROM python:3.10-slim-bookworm

# Set working directory
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the metrics collector script
COPY collect-metrics.py .

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Default command
CMD ["python", "collect-metrics.py"]