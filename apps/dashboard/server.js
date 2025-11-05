// apps/dashboard/server.js (FINAL, with DNS DEBUGGING)
import express from 'express';
import path from 'path';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { GoogleAuth } from 'google-auth-library';
import { fileURLToPath } from 'url';
import https from 'https';
import dns from 'node-dns';

// --- Configuration ---
const app = express();
const port = process.env.PORT || 8080;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const staticDir = path.join(__dirname, 'dist');

const targetApiUrl = process.env.API_TARGET_URL;
const audienceApiUrl = process.env.API_AUDIENCE_URL;

// --- 0. Request Logger ---
app.use((req, res, next) => {
  console.log(`[Logger] Received: ${req.method} ${req.path}`);
  next();
});

if (!targetApiUrl || !audienceApiUrl) {
  console.error('CRITICAL: API_TARGET_URL or API_AUDIENCE_URL env vars not set. Shutting down.');
  process.exit(1);
}

// --- 1. Google Auth Setup ---
const auth = new GoogleAuth();
let idTokenClient;

// --- 2. CUSTOM DNS AGENT (with DEBUG LOGS) ---
const googleDnsAgent = new https.Agent({
  lookup: (hostname, options, callback) => {
    // NEW LOG
    console.log(`[DNS] Attempting to resolve: ${hostname}`);
    
    const resolver = new dns.Request({
      question: dns.Question({ name: hostname, type: 'A' }),
      server: { address: '169.254.169.254', port: 53, type: 'udp' },
      timeout: 5000,
    });

    resolver.on('timeout', () => {
      // NEW LOG
      console.error('[DNS] Error: Query timed out for ' + hostname);
      callback(new Error('DNS query timed out'), null, null);
    });

    resolver.on('message', (err, msg) => {
      if (err) {
        // NEW LOG
        console.error(`[DNS] Error: ${err.message}`);
        return callback(err, null, null);
      }
      
      if (msg.answer.length === 0) {
        // NEW LOG
        console.error(`[DNS] Error: No IP found for ${hostname}`);
        return callback(new Error(`No IP found for ${hostname}`), null, null);
      }
      
      const ip = msg.answer.map(a => a.address)[0];
      // NEW LOG
      console.log(`[DNS] Resolved ${hostname} to ${ip}`);
      callback(null, ip, 4); // family 4 = IPv4
    });

    resolver.send();
  },
});
// --- END CUSTOM AGENT ---


// --- 3. Authenticated Proxy ---
console.log(`[Init] Setting up proxy for target: ${targetApiUrl}`);
const apiProxy = createProxyMiddleware({
  target: targetApiUrl,
  agent: googleDnsAgent, // Use our custom agent
  changeOrigin: true,
  pathRewrite: {
    '^/api': '',
  },
  onProxyReq: async (proxyReq, req, res) => {
    try {
      if (!idTokenClient) {
        idTokenClient = await auth.getIdTokenClient(audienceApiUrl);
      }
      const token = await idTokenClient.idTokenProvider.fetchIdToken();
      proxyReq.setHeader('Authorization', `Bearer ${token}`);
      console.log(`[Proxy] Forwarding authenticated request to: ${targetApiUrl}${req.path}`);
    } catch (err) {
      console.error('[Proxy] Auth Error:', err.message);
      res.status(500).send('Failed to authenticate proxy request');
    }
  },
  onError: (err, req, res) => {
    console.error('[Proxy] Connection Error:', err.message);
    res.status(502).send('Proxy connection error');
  }
});

// --- 4. App Routing ---
console.log('[Init] Registering /api route');
app.use('/api', apiProxy);

console.log('[Init] Registering static file route');
app.use(express.static(staticDir));

console.log('[Init] Registering fallback route');
app.get('*', (req, res) => {
  console.log(`[Fallback] Serving index.html for ${req.path}`);
  const file = path.join(__dirname, 'dist', 'index.html');
  res.sendFile(file, (err) => {
    if (err) {
      console.error(`[Fallback] Error: Could not send file: ${file}`, err);
      res.status(500).send('Internal server error: index.html not found.');
    }
  });
});

// --- 5. Start Server ---
app.listen(port, () => {
  console.log(`[Init] Server listening on port ${port}`);
  console.log(`[Init] Serving static files from: ${staticDir}`);
});