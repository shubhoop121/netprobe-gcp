// apps/dashboard/server.js (FINAL, MANUAL PROXY, v2)
import express from 'express';
import path from 'path';
import { GoogleAuth } from 'google-auth-library';
import { fileURLToPath } from 'url';

// --- Configuration ---
const app = express();
const port = process.env.PORT || 8080;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const staticDir = path.join(__dirname, 'dist');

const targetApiUrl = process.env.API_TARGET_URL;
const audienceApiUrl = process.env.API_AUDIENCE_URL;

// --- DEBUG BLOCK ---
console.log('==================================================');
console.log('[DEBUG] Environment Variables:');
console.log(`[DEBUG] PORT: ${port}`);
console.log(`[DEBUG] API_TARGET_URL: ${targetApiUrl}`);
console.log(`[DEBUG] API_AUDIENCE_URL: ${audienceApiUrl}`);
console.log('==================================================');

// --- 0. Request Logger ---
app.use(express.json()); // Add JSON body parser for POST requests
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

// --- 2. OUR NEW MANUAL PROXY HANDLER ---
console.log('[Init] Registering /api route handler');
app.use('/api/*', async (req, res) => {
  console.log(`[Proxy] Handler triggered for: ${req.originalUrl}`);

  try {
    // 1. Get Auth Token
    console.log('[Auth] Attempting to get IdTokenClient...');
    if (!idTokenClient) {
      idTokenClient = await auth.getIdTokenClient(audienceApiUrl);
    }
    console.log('[Auth] Attempting to fetch IdToken...');
    const token = await idTokenClient.idTokenProvider.fetchIdToken();
    if (!token) {
      throw new Error('Fetched an empty or null token.');
    }
    console.log('[Auth] Token fetched successfully.');

    // 2. Prepare the new request
    const newPath = req.originalUrl.replace('/api', '');
    const newUrl = `${targetApiUrl}${newPath}`;
    
    console.log(`[Proxy] Forwarding authenticated request to: ${newUrl}`);

    // --- THIS IS THE FIX ---
    // We only pass the Content-Type header if it was
    // provided by the original request.
    const headers = {
      'Authorization': `Bearer ${token}`,
    };
    if (req.header('Content-Type')) {
      headers['Content-Type'] = req.header('Content-Type');
    }
    // --- END OF FIX ---
    
    // 3. Make the proxied request using built-in fetch
    const apiResponse = await fetch(newUrl, {
      method: req.method,
      headers: headers,
      // Pass the body only if it's not a GET request
      body: (req.method !== 'GET' && req.body) ? JSON.stringify(req.body) : undefined,
    });

    // 4. Send the API's response back to the browser
    console.log(`[Proxy] Received status ${apiResponse.status} from API.`);
    res.status(apiResponse.status);
    const data = await apiResponse.text();
    res.send(data);

  } catch (err) {
    // If auth or fetch fails, we will see it.
    console.error('==================================================');
    console.error('[Proxy] CRITICAL PROXY FAILURE:');
    console.error(`[Proxy] Error: ${err.message}`);
    console.error(`[Proxy] Full Error:`, err);
    console.error('==================================================');
    res.status(500).send(`[Proxy Failure] ${err.message}`);
  }
});

// --- 3. Static File & Fallback Routes ---
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

// --- 4. Start Server ---
app.listen(port, () => {
  console.log(`[Init] Server listening on port ${port}`);
  console.log(`[Init] Serving static files from: ${staticDir}`);
});