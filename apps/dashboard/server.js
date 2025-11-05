// apps/dashboard/server.js (FINAL, CORRECTED VERSION)
import express from 'express';
import path from 'path';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { GoogleAuth } from 'google-auth-library';
import { fileURLToPath } from 'url';

// --- Configuration ---
const app = express();
const port = process.env.PORT || 8080;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const staticDir = path.join(__dirname, 'dist');

// --- THIS IS THE CHANGE (Part 1) ---
const targetApiUrl = process.env.API_TARGET_URL; // e.g., http://netprobe-api:8080
const audienceApiUrl = process.env.API_AUDIENCE_URL; // e.g., https://netprobe-api-....run.app

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

// --- 2. Authenticated Proxy ---
console.log(`[Init] Setting up proxy for target: ${targetApiUrl}`);
const apiProxy = createProxyMiddleware({
  target: targetApiUrl, // Use the internal URL
  changeOrigin: true,
  pathRewrite: {
    '^/api': '', // Rewrites /api/ping-db to /ping-db
  },
  onProxyReq: async (proxyReq, req, res) => {
    try {
      if (!idTokenClient) {
        // --- THIS IS THE CHANGE (Part 2) ---
        // Use the *audience* URL to get the token
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

// --- 3. App Routing (ORDER IS CRITICAL) ---
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
      res.status(5.00).send('Internal server error: index.html not found.');
    }
  });
});

// --- 4. Start Server ---
app.listen(port, () => {
  console.log(`[Init] Server listening on port ${port}`);
  console.log(`[Init] Serving static files from: ${staticDir}`);
});