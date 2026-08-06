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
        // Antes apuntaba a http://127.0.0.1:32866 (puerto de un entorno previo).
        // En el compose local, el servicio "api" publica el puerto 3000 en el host.
        target: "http://localhost:3000",
        changeOrigin: true
      }
    }
  }
});
