FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY complete_pod_agent.py .
COPY config.example.yaml .

# Create directories
RUN mkdir -p /config /logs /recordings /tmp/hls_output

# Expose ports
EXPOSE 8000 1883

# Run the agent
CMD ["python3", "complete_pod_agent.py"]
