import type { Config } from 'tailwindcss'

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#0b0b0b',
        card: '#121212',
        accent: '#8ab4f8',
        good: '#22c55e',
        warn: '#f59e0b',
        bad: '#ef4444',
      },
      boxShadow: {
        soft: '0 10px 30px rgba(0,0,0,0.35)'
      }
    },
  },
  plugins: [],
} satisfies Config