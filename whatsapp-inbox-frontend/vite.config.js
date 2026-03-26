import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  base: "/whatsapp-inbox/",
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
    proxy: {
      "/internal": {
        target: "http://127.0.0.1:32866",
        changeOrigin: true
      }
    }
  }
});
