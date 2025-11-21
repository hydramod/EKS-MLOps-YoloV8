# Ultra-Optimized Multi-stage Dockerfile for YOLOv8 Backend
# Target size: 1.2-1.5GB (down from 1.5-2GB)
# Optimized for Trivy scanning speed

# Stage 1: Builder
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies in one layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies with optimizations
RUN pip install --no-cache-dir \
    --user \
    --no-warn-script-location \
    --compile \
    --upgrade pip setuptools wheel && \
    pip install --no-cache-dir \
    --user \
    --no-warn-script-location \
    -r requirements.txt

# Aggressive cleanup - remove unnecessary files
RUN find /root/.local -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true && \
    find /root/.local -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true && \
    find /root/.local -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true && \
    find /root/.local -type d -name "test" -exec rm -rf {} + 2>/dev/null || true && \
    find /root/.local -type f -name "*.pyc" -delete && \
    find /root/.local -type f -name "*.pyo" -delete && \
    find /root/.local -type f -name "*.c" -delete && \
    find /root/.local -type f -name "*.pyx" -delete && \
    find /root/.local -type f -name "*.md" -delete && \
    find /root/.local -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true

# Stage 2: Runtime - Minimal
FROM python:3.11-slim

WORKDIR /app

# Install ONLY essential runtime dependencies (no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libgomp1 \
    libgl1 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user with specific UID/GID
RUN groupadd -g 1000 appuser && \
    useradd -m -u 1000 -g appuser appuser && \
    mkdir -p /app/models /app/uploads && \
    chown -R appuser:appuser /app

# Copy Python packages from builder
COPY --from=builder --chown=appuser:appuser /root/.local /home/appuser/.local

# Copy application code
COPY --chown=appuser:appuser app.py .

# Copy models directory
COPY --chown=appuser:appuser models/ ./models/

# Set environment variables
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONOPTIMIZE=2 \
    MODEL_PATH=yolov8n.pt \
    PORT=5000 \
    CONFIDENCE_THRESHOLD=0.25 \
    WORKERS=2

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 5000

# Optimized health check (uses built-in urllib, no requests dependency)
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health', timeout=3).read()" || exit 1

# Run with gunicorn for production
CMD ["gunicorn", \
    "--bind", "0.0.0.0:5000", \
    "--workers", "2", \
    "--threads", "2", \
    "--timeout", "120", \
    "--worker-class", "sync", \
    "--worker-tmp-dir", "/dev/shm", \
    "--access-logfile", "-", \
    "--error-logfile", "-", \
    "--log-level", "info", \
    "app:app"]