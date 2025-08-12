# docker/Dockerfile
FROM node:18-alpine

# Install curl for health checks
RUN apk add --no-cache curl

# Set working directory
WORKDIR /app

# Copy package.json only (not package-lock.json since it's invalid)
COPY package.json ./

# Use npm install instead of npm ci (since we don't have valid package-lock.json)
RUN npm install --only=production

# Copy application files
COPY server.js ./

# Set the port
ENV PORT=3000

# Expose the port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Start the application
CMD ["node", "server.js"]
