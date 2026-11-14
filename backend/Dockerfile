FROM node:22-alpine AS builder

WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm install
COPY src ./src
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY --from=builder /app/dist ./dist

ENV PORT=8080
ENV HOST=0.0.0.0
ENV DB_PATH=/app/data/sms_gateway.db
EXPOSE 8080

VOLUME ["/app/data"]
CMD ["node", "dist/index.js"]

