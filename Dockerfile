# ===================================
# A股自选股智能分析系统 - Railway Dockerfile
# ===================================
# Multi-stage build:
#   builder  — Python 3.13 + Rust/Cargo to compile native extensions
#              (longbridge, pytdx, etc.)
#   runtime  — lean Python 3.13 image without the Rust toolchain

# ---------------------------------------------------------------------------
# Stage 1: builder
# ---------------------------------------------------------------------------
FROM python:3.13-slim-bookworm AS builder

WORKDIR /app

# Install system build dependencies:
#   - gcc / g++ / make: generic C/C++ compilation
#   - curl:             rustup installer
#   - pkg-config / libssl-dev: OpenSSL headers required by several Rust crates
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    make \
    curl \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Rust via rustup (non-interactive, default stable toolchain)
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable

# Install Python dependencies into an isolated prefix so we can copy only
# the site-packages into the runtime stage.
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM python:3.13-slim-bookworm

WORKDIR /app

# Runtime system dependencies:
#   - wkhtmltopdf: Markdown → image conversion (imgkit, Issue #289)
#   - fontconfig / libjpeg62-turbo / libxrender1 / libxext6: wkhtmltopdf deps
#   - curl: health-check probe
#   - libssl3: OpenSSL runtime (needed by Rust-compiled wheels at import time)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wkhtmltopdf \
    fontconfig \
    libjpeg62-turbo \
    libxrender1 \
    libxext6 \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled Python packages from the builder stage
COPY --from=builder /install /usr/local

# Copy application source
COPY *.py ./
COPY api/ ./api/
COPY data_provider/ ./data_provider/
COPY bot/ ./bot/
COPY patch/ ./patch/
COPY src/ ./src/
COPY strategies/ ./strategies/

# Create persistent-data directories
RUN mkdir -p /app/data /app/logs /app/reports

# Environment defaults
ENV PYTHONUNBUFFERED=1 \
    TZ=Asia/Shanghai \
    LOG_DIR=/app/logs \
    DATABASE_PATH=/app/data/stock_analysis.db \
    WEBUI_HOST=0.0.0.0 \
    API_PORT=8000

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/api/health || curl -f http://localhost:8000/health \
    || python -c "import sys; sys.exit(0)"

CMD ["python", "main.py"]
