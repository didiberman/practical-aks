# Stage 1: Build dependencies
FROM node:22-alpine AS builder
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm ci --only=production

# Stage 2: Final secure runtime image
FROM node:22-alpine
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY package.json index.js ./
COPY prompts ./prompts

# Run container process as standard non-root 'node' user for security compliance
USER node

EXPOSE 8080
ENV PORT=8080
ENV NODE_ENV=production

CMD [ "node", "index.js" ]
