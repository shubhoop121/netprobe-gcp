// apps/dashboard/server.js (DEBUGGING VERSION)
import express from 'express';
import path from 'path';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { GoogleAuth } from 'google-auth-library';
import { fileURLToPath } from 'url';

// --- Configuration ---
const app = express();
const port = process.env.PORT || 8080;
const targetApiUrl = process.env.API_URL;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const staticDir = path.join(__dirname, 'dist');

// --- 0. SQUEAKY-WHEEL LOGGER ---
// This logs EVERY request that hits the server, BEFORE any routes.
app.use((req, res, next) => {
  console.log(`[Logger] Received request: ${req.method} ${req.path}`);
  next(); // Continue to the next middleware
});
// --- End Logger ---

if (!targetApiUrl) {
  console.error('CRITICAL: API_URL environment variable is not set. Shutting down.');
  process.exit(1);
}

// --- 1. Google Auth Setup ---
const auth = new GoogleAuth();
let idTokenClient;

// --- 2. Authenticated Proxy Setup ---
console.log(`[Proxy] Setting up proxy to target: ${targetApiUrl}`);
const apiProxy = createProxyMiddleware({
  target: targetApiUrl,
  changeOrigin: true,
  pathRewrite: {
    '^/api': '', // This is correct.
  },
  onProxyReq: async (proxyReq, req, res) => {
    try {
      if (!idTokenClient) {
        console.log('[Auth] Initializing IdTokenClient...');
        idTokenClient = await auth.getIdTokenClient(targetApiUrl);
      }
      const token = await idTokenClient.idTokenProvider.fetchIdToken();
      proxyReq.setHeader('Authorization', `Bearer ${token}`);
      console.log(`[Proxy] Authenticated request to: ${targetApiUrl}${req.path}`);
    } catch (err) {
      console.error('[Auth] Failed to get identity token:', err);
      res.status(500).send('Failed to authenticate proxy request');
    }
  },
  onError: (err, req, res) => {
    console.error('[Proxy] Proxy error:', err);
    res.status(502).send('Proxy encountered an error.');
  }
});

// --- 3. App Routing ---
console.log('[Router] Registering /api route');
// Use '/api' NOT '/api/*'. The proxy middleware handles sub-paths.
app.use('/api', apiProxy);

console.log('[Router] Registering static file route');
app.use(express.static(staticDir));

console.log('[Router] Registering fallback route');
app.get('*', (req, res) => {
  console.log(`[Fallback] Serving index.html for: ${req.path}`);
  const file = path.join(__dirname, 'dist', 'index.html');
  res.sendFile(file, (err) => {
    if (err) {
      console.error(`[Fallback] CRITICAL: Could not send file: ${file}`, err);
      res.status(500).send('Internal server error: index.html not found.');
    }
  });
});

// --- 4. Start Server ---
app.listen(port, () => {
  console.log(`[Dashboard] Server listening on port ${port}`);
  console.log(`[Dashboard] Serving static files from: ${staticDir}`);
  console.log(`[Dashboard] Proxying /api requests to: ${targetApiUrl}`);
});