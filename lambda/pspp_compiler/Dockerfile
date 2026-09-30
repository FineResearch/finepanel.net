FROM debian:bookworm-slim

# PSPP en Alpine 3.7 (la base de Dockerfile.release) revienta con segfault
# instalandolo O corriendolo, sin importar arquitectura -- ver el
# diagnostico completo en Dockerfile.release. Debian no tiene ese problema
# (confirmado), asi que esta funcion corre en su propio contenedor Debian,
# separado de la imagen principal de la app.
RUN apt-get update && \
    apt-get install -y --no-install-recommends pspp python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages awslambdaric boto3

WORKDIR /var/task
COPY handler.py .

ENTRYPOINT ["python3", "-m", "awslambdaric"]
CMD ["handler.handler"]
