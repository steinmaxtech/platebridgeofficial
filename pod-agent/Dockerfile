FROM python:3.11-slim

WORKDIR /app

# Configure apt to use alternative mirrors if needed and increase timeouts
RUN echo 'Acquire::http::Timeout "30";' > /etc/apt/apt.conf.d/99timeout \
    && echo 'Acquire::https::Timeout "30";' >> /etc/apt/apt.conf.d/99timeout \
    && echo 'Acquire::Retries "3";' >> /etc/apt/apt.conf.d/99timeout

# Install system dependencies including Tailscale
# Note: If build fails with DNS errors, ensure the POD has internet connectivity
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    curl \
    ca-certificates \
    gnupg \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends tailscale \
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
