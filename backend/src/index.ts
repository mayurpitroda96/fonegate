import express from 'express';
import http from 'http';
import cors from 'cors';
import { WebSocketServer } from 'ws';
import url from 'url';
import { config } from './config';
import { initDatabase } from './db';
import { handleGatewayConnection } from './ws/gateway-socket';
import { DashboardSocket } from './ws/dashboard-socket';
import { smsRouter } from './routes/sms-routes';
import { deviceRouter } from './routes/device-routes';
import { webhookRouter } from './routes/webhook-routes';
import { statsRouter } from './routes/stats-routes';
import { authRouter } from './routes/auth-routes';
import { backupRouter } from './routes/backup-routes';
import { apiKeyRouter } from './routes/apikey-routes';
import { apiKeyOrAuthMiddleware } from './middleware/auth';

// Initialize SQLite
initDatabase();

const app = express();
app.use(cors({ origin: config.corsOrigin }));
app.use(express.json({ limit: '50mb' }));

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'FoneGate Backend',
    time: new Date().toISOString(),
  });
});

// REST API routes
app.use('/api/v1/auth', authRouter);
app.use('/api/v1/backup', backupRouter);
app.use('/api/v1/sms', apiKeyOrAuthMiddleware, smsRouter);
app.use('/api/v1/devices', deviceRouter);
app.use('/api/v1/webhooks', webhookRouter);
app.use('/api/v1/stats', statsRouter);
app.use('/api/v1/api-keys', apiKeyRouter);

// HTTP Server
const server = http.createServer(app);
server.timeout = 0; // Disable socket inactivity timeout for 24/7 WebSockets
server.keepAliveTimeout = 0;

// WebSocket Servers
const wssGateway = new WebSocketServer({ noServer: true });
const wssDashboard = new WebSocketServer({ noServer: true });

wssGateway.on('connection', handleGatewayConnection);
wssDashboard.on('connection', (ws) => DashboardSocket.addClient(ws));

// Upgrade HTTP connection to appropriate WebSocket endpoint
server.on('upgrade', (request, socket, head) => {
  // Prevent Node.js from terminating long-running WebSocket connections
  if ('setTimeout' in socket && typeof (socket as any).setTimeout === 'function') {
    (socket as any).setTimeout(0);
    (socket as any).setKeepAlive?.(true, 10000);
    (socket as any).setNoDelay?.(true);
  }

  const pathname = url.parse(request.url || '').pathname;

  if (pathname === '/ws/gateway') {
    wssGateway.handleUpgrade(request, socket, head, (ws) => {
      wssGateway.emit('connection', ws, request);
    });
  } else if (pathname === '/ws/dashboard') {
    wssDashboard.handleUpgrade(request, socket, head, (ws) => {
      wssDashboard.emit('connection', ws, request);
    });
  } else {
    socket.destroy();
  }
});

server.listen(config.port, config.host, () => {
  console.log(`=======================================================`);
  console.log(`🚀 FoneGate Server running at http://${config.host}:${config.port}`);
  console.log(`📡 WebSocket Android Gateway at: ws://${config.host}:${config.port}/ws/gateway`);
  console.log(`📊 WebSocket Dashboard Stream at: ws://${config.host}:${config.port}/ws/dashboard`);
  console.log(`🔗 REST API available at: http://${config.host}:${config.port}/api/v1`);
  console.log(`=======================================================`);
});

