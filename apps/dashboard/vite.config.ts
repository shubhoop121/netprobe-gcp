import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // For your new v1 endpoints
      '/api/v1': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true,
        secure: false,
      },
      // For your /ping-db
      '/ping-db': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true,
        secure: false,
      },
      // For your /api/login and /api/register
      '/api/login': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true,
        secure: false,
      },
      '/api/register': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true,
        secure: false,
      }
    }
  }
})