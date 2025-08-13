# docker/Dockerfile
# Multi-stage build with npm install fallback
FROM node:18-alpine AS deps
WORKDIR /app

# Copy package.json only (not package-lock.json to avoid conflicts)
COPY package.json ./

# Install dependencies with fallback options
RUN npm cache clean --force && \
    npm install --verbose --no-package-lock || \
    npm install --force --no-package-lock

# Production stage
FROM node:18-alpine AS production

# Install curl for health checks and create non-root user
RUN apk add --no-cache curl tini && \
    addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy application files
COPY --chown=nodejs:nodejs package.json ./
COPY --chown=nodejs:nodejs server.js ./

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Use tini to handle signals properly
ENTRYPOINT ["/sbin/tini", "--"]

# Run application
CMD ["node", "server.js"]
