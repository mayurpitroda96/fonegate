import { WebSocket } from 'ws';

export class DashboardSocket {
  private static clients = new Set<WebSocket>();

  public static addClient(ws: WebSocket) {
    this.clients.add(ws);
    console.log(`Dashboard client connected. Active clients: ${this.clients.size}`);

    ws.on('close', () => {
      this.clients.delete(ws);
      console.log(`Dashboard client disconnected. Active clients: ${this.clients.size}`);
    });
  }

  public static broadcast(event: string, data: any) {
    const payload = JSON.stringify({ event, data, timestamp: new Date().toISOString() });
    for (const client of this.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(payload);
      }
    }
  }
}

