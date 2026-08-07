# FinePanel - Levantar el entorno local (paso a paso)

Requisito: Docker Desktop instalado y corriendo. Todo lo de aqui usa `docker-compose.local.yml`, nunca `docker-compose.release.yml`.

## 0. Preparar el .env

```bash
cp .env.example .env
```

No hace falta completar nada mas para bootear: con `DISABLE_WHATSAPP_SEND=true` y `DISABLE_EMAIL_DELIVERY=true` la app arranca sin credenciales reales de Meta/SendGrid.

## 1. Build

```bash
docker compose -f docker-compose.local.yml build
```

Nota: la imagen base es `ruby:2.5.1-alpine` (fuera de soporte). Si falla compilando gems nativas (nokogiri, etc.), agregar temporalmente al `Dockerfile.local` los paquetes `gcc libtool linux-headers` en la linea de `apk add` (el propio `README.md` ya documenta este workaround para Apple M2; puede ser necesario tambien en Windows/WSL2). No commitear ese cambio si es solo para tu maquina.

## 2. Base de datos

```bash
docker compose -f docker-compose.local.yml run --rm api bundle exec rails db:create
docker compose -f docker-compose.local.yml run --rm api bundle exec rails db:migrate
```

**Importante:** usar `db:migrate`, no `db:schema:load` — `db/schema.rb` esta desactualizado y no incluye las tablas de WhatsApp (ver `docs/ARCHITECTURE.md`, hallazgo 1).

```bash
docker compose -f docker-compose.local.yml run --rm api bundle exec rails db:seed
```

`db/seeds.rb` esta vacio (plantilla default de Rails) — esto deja la base con schema completo pero sin datos. Para probar el inbox de WhatsApp vas a necesitar crear al menos un usuario y una conversacion de prueba a mano (Rails console, paso 6) o pedir que te arme un seed especifico despues.

## 3. Levantar todo

```bash
docker compose -f docker-compose.local.yml up
```

Esto levanta `db`, `redis`, `api` (puerto 3000) y `sidekiq`. `frontend-build` no se levanta con `up` (no es un servicio persistente).

- Rails: http://localhost:3000
- Inbox de WhatsApp (una vez compilado el frontend, paso 5): http://localhost:3000/internal/whatsapp/inbox

## 4. Sidekiq

Ya se levanta junto con `up` (servicio `sidekiq`, corre `bundle exec sidekiq -C config/sidekiq.yml`). Para ver solo sus logs:

```bash
docker compose -f docker-compose.local.yml logs -f sidekiq
```

## 5. Build del frontend (inbox React/Vite)

```bash
docker compose -f docker-compose.local.yml run --rm frontend-build
cp -r whatsapp-inbox-frontend/dist/* public/whatsapp-inbox/
```

Repetir cada vez que cambies codigo en `whatsapp-inbox-frontend/src`. Para desarrollo con hot-reload (fuera de Docker, corriendo Vite directo en tu maquina):

```bash
cd whatsapp-inbox-frontend
npm install
npm run dev
```

Con la API corriendo en `docker compose up` (puerto 3000 publicado en el host), el proxy de `/internal` en `vite.config.js` ya apunta a `http://localhost:3000`.

## 6. Rails console

```bash
docker compose -f docker-compose.local.yml run --rm api bundle exec rails console
```

## 7. Entrar a Postgres

```bash
docker compose -f docker-compose.local.yml exec db psql -U postgres -d finepanel_dev
```

(el puerto tambien esta publicado en el host como `5435`, por si preferis conectarte con un cliente Postgres local: `psql -h localhost -p 5435 -U postgres -d finepanel_dev`)

## 8. Tests

```bash
docker compose -f docker-compose.local.yml run --rm api bundle exec rspec
```

## 9. Detener y limpiar

```bash
docker compose -f docker-compose.local.yml down
```

Para borrar tambien los datos de Postgres (volumen anonimo) y forzar una base limpia:

```bash
docker compose -f docker-compose.local.yml down -v
```

## Verificacion de aislamiento (antes de dar por bueno el entorno)

- Confirmar en los logs de `api`/`sidekiq` que aparecen las lineas `DISABLE_WHATSAPP_SEND=true - envio simulado` y `DISABLE_EMAIL_DELIVERY=true - email simulado` al disparar un envio de prueba (por ejemplo desde la Rails console llamando a `ManualMessageSender` o `ApplicationMailer.send_plain_email`), y que **no** hay trafico saliente hacia `graph.facebook.com` ni `api.sendgrid.com`.
- Confirmar que `REDIS_URL` apunta al servicio `redis` local, nunca a un Redis de produccion.
- Confirmar que `DATABASE_HOST`/`DATABASE_NAME` apuntan a `db`/`finepanel_dev` local, nunca a la RDS de produccion.
