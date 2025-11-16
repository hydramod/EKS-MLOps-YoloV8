# Multi-stage Dockerfile for Frontend
# Stage 1: Builder (if we had a build step for React/Vue, we'd use it here)
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies (none needed for our simple static server)
RUN npm install --production || true

# Copy application files
COPY . .

# Stage 2: Runtime
FROM node:18-alpine

WORKDIR /app

# Change ownership to existing node user
RUN chown -R node:node /app

# Copy from builder
COPY --from=builder --chown=node:node /app ./

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000

# Switch to non-root user (use existing 'node' user)
USER node

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/', (r) => {if(r.statusCode !== 200) throw new Error(r.statusCode)})"

# Start server
CMD ["node", "server.js"]