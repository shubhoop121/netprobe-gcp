import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // Proxy all requests starting with /api to the Flask backend
      '/api': {
        target: 'http://127.0.0.1:8080', // Flask server
        changeOrigin: true,
        // Rewrite the path: remove '/api' before sending to Flask
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    }
  }
})