# FinePanel - Arquitectura actual y notas para entorno local

_Generado a partir de inspeccion directa del repo copiado desde EC2 (`/home/ec2-user/finepanel-migration/finepanel`) el 2026-07-30. No se asumio nada que no estuviera confirmado en archivos reales._

## Stack confirmado

- Ruby 2.5.1 (Gemfile.lock, RUBY VERSION), Rails 5.2.3 (`~> 5.2.2, >= 5.2.2.1`).
- Postgres via gem `pg 0.18.4`, adapter `postgresql`. Sin version fija de servidor en `database.yml` (se define en Docker/RDS).
- Redis via gem `redis 4.1.1`, usado unicamente por Sidekiq. No existe `config/redis.yml`; la URL se lee de `ENV['REDIS_URL']` en `config/initializers/sidekiq.rb` (default `redis://localhost:6379` si no esta seteada).
- Sidekiq 5.2.7 + `sidekiq-scheduler`. `config/sidekiq.yml` define jobs cron (`ArticlesCreatorWorker`, no relacionados a WhatsApp) y concurrencia por ambiente (`staging`/`production`; sin esas keys, RAILS_ENV=development usa el default top-level `:concurrency: 5`).
- Emails: `ApplicationMailer` **no usa ActionMailer/SMTP**, llama directo a la API HTTP de SendGrid (`app/mailers/application_mailer.rb`). Letter Opener/Mailcatcher no interceptan esto.
- WhatsApp: `app/services/whats_app/client.rb` llama directo a `https://graph.facebook.com/<version>/<phone_number_id>/messages` via `Net::HTTP`. Se instancia en 4 lugares: `webhooks_controller.rb`, `manual_message_sender.rb`, `reminder_sender.rb`, `send_whatsapp_messages_worker.rb`.
- Frontend inbox: React 18 + Vite 5 en `whatsapp-inbox-frontend/`, build a `dist/`, copiado a `public/whatsapp-inbox` y servido por Rails en `/internal/whatsapp/inbox`.

## Docker / despliegue

- Ya existian `Dockerfile.local` / `Dockerfile.release` y `docker-compose.local.yml` / `docker-compose.release.yml` (no se creo Docker desde cero).
- Ambos Dockerfiles usan `ruby:2.5.1-alpine` (imagen EOL, base musl). El `README.md` ya documenta fallas de compilacion de gems nativas en Apple M2 con un parche manual (agregar `gcc libtool linux-headers`). En Windows/Docker Desktop (WSL2) deberia compilar mejor, pero **no se confirmo** — validar al hacer `docker compose build`.
- `entrypoint.release.sh` explota el secreto unico `SECRETS` (JSON de Secrets Manager) a variables de entorno individuales con `jq`. `entrypoint.local.sh` no necesita esto: corre `bundle install` si hace falta y `rake db:migrate` si `AUTOMATICALLY_MIGRATE` esta seteado.
- `deploy_all.sh` (lineas 12-13) confirma que los task definitions fuente reales son `taskdef-api-new.json` y `taskdef-sidekiq-new.json`. **Estos archivos no existian en el checkout** (solo backups `.bak`/`.bak-<timestamp>`, ya eliminados de esta copia local por ser ruido). Se uso el backup mas reciente solo como referencia de estructura (EFS `EmailParsing` en `/app/tmp/feed_files`, secreto unico via Secrets Manager, variables `WHATSAPP_*_NUMBER(_ID)` en texto plano en el task def). No se replicaron ARNs, IDs de cuenta ni el EFS id reales en ningun archivo de este entorno local.

## Variables de entorno relevantes

Ver `.env.example` (nuevo) para la lista completa con valores vacios/de ejemplo. Resumen por categoria:

- Base de datos: `DATABASE_HOST/PORT/NAME/USER/PASSWORD`, `DB_POOL`.
- Redis/Sidekiq: `REDIS_URL`.
- WhatsApp (deben existir tanto en API como en Sidekiq): `WHATSAPP_API_VERSION`, `WHATSAPP_AUTH_TOKEN`, `WHATSAPP_ID_NUMBER`, y las variantes por pais `WHATSAPP_{AR,BR,CO,MX}_NUMBER[_ID]`.
- Email: `SENDGRID_API_KEY` (y `SENDGRID_USERNAME/PASSWORD`, `NOTIFICATIONS_API_*`, sin uso confirmado en el mailer pero presentes en `.env.sample` original).
- Switches nuevos de aislamiento: `DISABLE_WHATSAPP_SEND`, `DISABLE_EMAIL_DELIVERY` (no existian antes, se agregaron en esta iteracion).
- Otras integraciones sin confirmar uso critico para el inbox: `TRANSLATE_KEY`, `DYNAMED_CLIENT_ID/SECRET`, `TWILIO_*`, `API_DYNAMED_URL`.

## Riesgos / hallazgos

1. **`db/schema.rb` desactualizado (version `2022_10_18_123438`)**. Hay 39 migraciones en `db/migrate/`, incluidas las 12 que crean toda la estructura de WhatsApp (`whatsapp_outbounds`, `whatsapp_conversations`, `whatsapp_messages`, `whatsapp_project_panelists`, `invalid_whatsapp_numbers`, campos opt-in en `users`, `internal_users`, etc.) y ninguna esta reflejada en `schema.rb`. **Usar `db:migrate`, no `db:schema:load`**, para levantar la base local.
2. Imagen base `ruby:2.5.1-alpine` esta fuera de soporte; validar que Docker Hub la siga sirviendo antes de asumir que el build funciona.
3. Envio de emails y WhatsApp son llamadas HTTP directas (no pasan por ActionMailer ni ActiveJob adapters conocidos) — se resolvio agregando switches propios (ver seccion siguiente), no bastaba con configuracion estandar de Rails.
4. El directorio de trabajo en EC2 tenia archivos sueltos con datos reales (exports de emails/opt-in de WhatsApp, y un archivo que exponia el hostname de RDS de produccion tras un `psql` fallido). Se eliminaron de esta copia local; no estaban versionados en git.
5. `README.md` del repo esta desactualizado (menciona `bin/start` y un `docker-compose.yml` generico que ya no coinciden con `docker-compose.local.yml`/`Dockerfile.local` actuales). No se modifico; queda como tarea aparte.
6. `vite.config.js` tenia el proxy de `/internal` apuntando a un puerto de un entorno previo (`127.0.0.1:32866`); se corrigio a `localhost:3000` para que funcione contra el servicio `api` del compose local.

## Cambios realizados en este entorno local (lista completa)

- Se elimino de la copia local (no tocan EC2/produccion): 5 archivos CSV/TXT con datos reales sueltos en el working directory, todos los backups numerados de `taskdef-api-new.json`/`taskdef-sidekiq-new.json`, archivos sueltos de restos de shell (`Argentina,`, `Bolivia,`, etc., `[ec2-user@...].save`), y `app/controllers/api/v1/webhooks_controller.rb.bak2`.
- `app/services/whats_app/client.rb`: agregado guard `DISABLE_WHATSAPP_SEND` en `post_message` (si es `'true'`, loguea y devuelve una respuesta simulada en vez de llamar a Meta).
- `app/mailers/application_mailer.rb`: agregado guard `DISABLE_EMAIL_DELIVERY` en `send_email` (si es `'true'`, loguea y devuelve una respuesta simulada en vez de llamar a SendGrid). Se agrego `require 'ostruct'`.
- `whatsapp-inbox-frontend/vite.config.js`: proxy de `/internal` corregido a `http://localhost:3000`.
- `docker-compose.local.yml`: agregado servicio `frontend-build` (Node 20, no persistente, se corre a demanda) para compilar el inbox.
- Nuevo `.env.example` en la raiz del repo.
- Nuevos `docs/ARCHITECTURE.md` (este archivo) y `docs/LOCAL_SETUP.md`.

No se modifico logica de negocio, no se toco `deploy_all.sh`, no se corrio ningun deploy ni migracion contra RDS de produccion.

## Recomendaciones para una futura modernizacion (rama separada, no ahora)

- Actualizar Ruby 2.5 -> version soportada (2.7+ como paso intermedio, luego 3.x) junto con Rails 5.2 -> 6.x como primer salto, dado el volumen de gems con constraints viejos (`sass-rails`, `coffee-rails`, `turbolinks`, `compass-rails`).
- Reemplazar la imagen base `ruby:2.5.1-alpine` por una variante soportada o por `slim`/`bullseye` para evitar problemas de compatibilidad de glibc/musl con gems nativas.
- Migrar el envio de emails a `ActionMailer` con adapter SMTP de SendGrid (en vez de llamadas HTTP directas), para poder usar Letter Opener/Mailcatcher de forma estandar en desarrollo.
- Regenerar `db/schema.rb` corriendo las migraciones pendientes y commiteando el resultado, para que vuelva a ser la fuente de verdad.
- Actualizar `README.md` para que refleje los archivos `.local`/`.release` reales.
- Revisar por que el working directory de EC2 termina acumulando exports de datos reales y backups de task defs — mover esos procesos a un bucket S3 o carpeta fuera del repo de la app.
