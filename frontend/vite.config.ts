import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  base: process.env.DOCAYA_BASE_PATH || '/',
  plugins: [react()],
  server: {
    proxy: {
      '/api': process.env.DOCAYA_API_PROXY || 'http://localhost:8787',
      '/health': process.env.DOCAYA_API_PROXY || 'http://localhost:8787',
    },
  },
})
