# Multi-stage Dockerfile for production deployment
# Optimized for security, performance, and minimal image size

# Build stage
FROM node:18-alpine AS builder

# Install security updates and build dependencies
RUN apk update && apk upgrade && \
    apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    && rm -rf /var/cache/apk/*

# Create non-root user for build process
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy package files first for better caching
COPY package*.json ./
COPY yarn.lock* ./

# Install dependencies with security audit
RUN npm ci --only=production --no-audit --no-fund && \
    npm cache clean --force

# Copy application source code
COPY --chown=nodejs:nodejs . .

# Build application (if needed)
RUN if [ -f "package.json" ] && grep -q "build" package.json; then \
        npm run build; \
    fi

# Production stage
FROM node:18-alpine AS production

# Install runtime security updates and required packages
RUN apk update && apk upgrade && \
    apk add --no-cache \
    dumb-init \
    curl \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy built application from builder stage
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./

# Copy application files
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist 2>/dev/null || \
COPY --from=builder --chown=nodejs:nodejs /app/build ./build 2>/dev/null || \
COPY --from=builder --chown=nodejs:nodejs /app/src ./src

# Copy additional necessary files
COPY --from=builder --chown=nodejs:nodejs /app/public ./public 2>/dev/null || true
COPY --from=builder --chown=nodejs:nodejs /app/views ./views 2>/dev/null || true
COPY --from=builder --chown=nodejs:nodejs /app/config ./config 2>/dev/null || true

# Create health check script
RUN echo '#!/bin/sh\ncurl -f http://localhost:${PORT:-3000}/health || exit 1' > /app/healthcheck.sh && \
    chmod +x /app/healthcheck.sh && \
    chown nodejs:nodejs /app/healthcheck.sh

# Set build arguments as labels
ARG VERSION=unknown
ARG BUILD_DATE=unknown
ARG COMMIT_SHA=unknown

LABEL org.opencontainers.image.title="Nomad Application" \
      org.opencontainers.image.description="Application deployed via Nomad and Consul" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${COMMIT_SHA}" \
      org.opencontainers.image.vendor="friendy21" \
      org.opencontainers.image.source="https://github.com/friendy21/CI-CD-with-nomad"

# Switch to non-root user
USER nodejs

# Expose port (configurable via environment)
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /app/healthcheck.sh

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000 \
    NPM_CONFIG_LOGLEVEL=warn

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start application
CMD ["node", "dist/index.js"]

# Alternative Dockerfile for Python applications
# Uncomment and modify as needed

# FROM python:3.11-alpine AS python-builder
# 
# RUN apk update && apk upgrade && \
#     apk add --no-cache \
#     gcc \
#     musl-dev \
#     libffi-dev \
#     && rm -rf /var/cache/apk/*
# 
# WORKDIR /app
# 
# COPY requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt
# 
# COPY . .
# 
# FROM python:3.11-alpine AS python-production
# 
# RUN apk update && apk upgrade && \
#     apk add --no-cache \
#     curl \
#     && rm -rf /var/cache/apk/*
# 
# RUN addgroup -g 1001 -S appuser && \
#     adduser -S appuser -u 1001
# 
# WORKDIR /app
# 
# COPY --from=python-builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
# COPY --from=python-builder --chown=appuser:appuser /app .
# 
# USER appuser
# 
# EXPOSE 8000
# 
# HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
#     CMD curl -f http://localhost:8000/health || exit 1
# 
# CMD ["python", "app.py"]

