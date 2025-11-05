import express from 'express';
import path from 'path';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { GoogleAuth } from 'google-auth-library';
import { fileURLToPath } from 'url';

// --- Configuration ---
const app = express();
const port = process.env.PORT || 8080;
const targetApiUrl = process.env.API_URL; // Injected by main.yml

// ES Module-safe way to get __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const staticDir = path.join(__dirname, 'dist');

if (!targetApiUrl) {
  console.error('CRITICAL: API_URL environment variable is not set. Shutting down.');
  process.exit(1);
}

// --- 1. Google Auth Setup ---
// We create one auth client to be reused
const auth = new GoogleAuth();
let idTokenClient;

// --- 2. Authenticated Proxy Setup ---
console.log(`[Proxy] Setting up proxy to target: ${targetApiUrl}`);

const apiProxy = createProxyMiddleware({
  target: targetApiUrl,
  changeOrigin: true, // Required for Cloud Run
  pathRewrite: {
    '^/api': '', // Rewrites '/api/ping-db' to '/ping-db'
  },
  
  // This is the "magic" that fixes the 401/403 errors
  onProxyReq: async (proxyReq, req, res) => {
    try {
      // Lazily initialize the token client
      if (!idTokenClient) {
        console.log('[Auth] Initializing IdTokenClient...');
        idTokenClient = await auth.getIdTokenClient(targetApiUrl);
      }
      
      // Fetch a new, valid identity token
      const token = await idTokenClient.idTokenProvider.fetchIdToken();
      
      // Set the Authorization header for the proxied request
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

// All requests to '/api' go to our authenticated proxy
app.use('/api', apiProxy);

// All other requests serve the static React app
app.use(express.static(staticDir));

// Fallback for React Router (handles page reloads on sub-routes)
app.get('*', (req, res) => {
  res.sendFile(path.join(staticDir, 'index.html'));
});

// --- 4. Start Server ---
app.listen(port, () => {
  console.log(`[Dashboard] Server listening on port ${port}`);
  console.log(`[Dashboard] Serving static files from: ${staticDir}`);
  console.log(`[Dashboard] Proxying /api requests to: ${targetApiUrl}`);
});