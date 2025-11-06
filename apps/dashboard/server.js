// apps/dashboard/server.js (FINAL, with PROXY-LEVEL DEBUGGING)
import express from 'express';
import path from 'path';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { GoogleAuth } from 'google-auth-library';
import { fileURLToPath } from 'url';
import https from 'https';
import { Resolver } from 'node:dns/promises';

// --- Configuration ---
const app = express();
const port = process.env.PORT || 8080;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const staticDir = path.join(__dirname, 'dist');

const targetApiUrl = process.env.API_TARGET_URL;
const audienceApiUrl = process.env.API_AUDIENCE_URL;

// --- DEBUG BLOCK (This is good, keep it) ---
console.log('==================================================');
console.log('[DEBUG] Environment Variables:');
console.log(`[DEBUG] PORT: ${port}`);
console.log(`[DEBUG] API_TARGET_URL: ${targetApiUrl}`);
console.log(`[DEBUG] API_AUDIENCE_URL: ${audienceApiUrl}`);
console.log('==================================================');

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

// --- 2. CUSTOM DNS AGENT ---
console.log('[DNS] Initializing Google DNS Resolver (169.254.169.254)...');
const resolver = new Resolver();
resolver.setServers(['169.254.169.254']);

const googleDnsAgent = new https.Agent({
  lookup: async (hostname, options, callback) => {
    console.log(`[DNS] Attempting to resolve: ${hostname}`);
    try {
      const addresses = await resolver.resolve4(hostname);
      if (!addresses || addresses.length === 0) {
        console.error(`[DNS] Error: No IP found for ${hostname}`);
        return callback(new Error(`No IP found for ${hostname}`), null, null);
      }
      const ip = addresses[0];
      console.log(`[DNS] Resolved ${hostname} to ${ip}`);
      callback(null, ip, 4);
    } catch (err) {
      console.error(`[DNS] Error: ${err.message}`);
      callback(err, null, null);
    }
  },
});

// --- 3. Authenticated Proxy ---
console.log(`[Init] Setting up proxy for target: ${targetApiUrl}`);
const apiProxy = createProxyMiddleware({
  target: targetApiUrl,
  agent: googleDnsAgent,
  changeOrigin: true,
  pathRewrite: {
    '^/api': '',
  },
  
  // --- THIS IS THE NEW FIX ---
  // Force the proxy to log its internal state.
  logLevel: 'debug',
  logProvider: (provider) => {
    return {
      log: (msg) => console.log(`[PROXY_DEBUG] ${msg}`),
      info: (msg) => console.info(`[PROXY_INFO] ${msg}`),
      warn: (msg) => console.warn(`[PROXY_WARN] ${msg}`),
      error: (msg) => console.error(`[PROXY_ERROR] ${msg}`),
    };
  },
  // --- END OF NEW FIX ---

  onProxyReq: async (proxyReq, req, res) => {
    try {
      console.log('[Auth] Attempting to get IdTokenClient...');
      if (!idTokenClient) {
        idTokenClient = await auth.getIdTokenClient(audienceApiUrl);
      }
      console.log('[Auth] Attempting to fetch IdToken...');
      const token = await idTokenClient.idTokenProvider.fetchIdToken();
      if (!token) {
        throw new Error('Fetched an empty or null token.');
      }
      console.log('[Auth] Token fetched successfully. Adding Authorization header.');
      proxyReq.setHeader('Authorization', `Bearer ${token}`);
      console.log(`[Proxy] Forwarding authenticated request to: ${targetApiUrl}${req.path}`);
    } catch (err) {
      console.error('==================================================');
      console.error('[Proxy] CRITICAL AUTH FAILURE:');
      console.error(`[Proxy] Failed to get auth token: ${err.message}`);
      console.error(`[Proxy] Full Error:`, err);
      console.error('==================================================');
      res.status(500).send(`[Proxy Auth Failure] ${err.message}`);
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

// ... (rest of the file: static route, fallback route, app.listen)
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

app.listen(port, () => {
  console.log(`[Init] Server listening on port ${port}`);
  console.log(`[Init] Serving static files from: ${staticDir}`);
});