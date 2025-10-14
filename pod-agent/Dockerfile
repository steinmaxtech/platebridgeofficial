FROM python:3.11-slim

WORKDIR /app

# Configure apt to use alternative mirrors if needed and increase timeouts
RUN echo 'Acquire::http::Timeout "30";' > /etc/apt/apt.conf.d/99timeout \
    && echo 'Acquire::https::Timeout "30";' >> /etc/apt/apt.conf.d/99timeout \
    && echo 'Acquire::Retries "3";' >> /etc/apt/apt.conf.d/99timeout

# Install system dependencies
# Note: If build fails with DNS errors, ensure the POD has internet connectivity
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY complete_pod_agent.py .

# Create directories
RUN mkdir -p /config /logs /recordings /tmp/hls_output

# Expose ports
EXPOSE 8000 1883

# Run the agent
# config.yaml will be mounted at runtime via volume mount
CMD ["python3", "complete_pod_agent.py", "/app/config.yaml"]
