import os
import subprocess

import boto3

# El worker Ruby (ver app/services/export_relabeling/pspp_lambda_client.rb)
# ya deja el .sps listo para correr tal cual -- el FILE HANDLE ya apunta a
# /tmp/data.asc (la convencion fija que usamos de este lado) y ya tiene el
# SAVE OUTFILE agregado al final. Esta funcion no reescribe nada de
# sintaxis, solo baja los 2 archivos de entrada, corre pspp, y sube el
# .sav resultante -- toda la logica de re-etiquetado vive en Ruby (un solo
# lugar, no duplicada en 2 lenguajes).
s3 = boto3.client("s3")

SPS_PATH = "/tmp/input.sps"
DATA_PATH = "/tmp/data.asc"
SAV_PATH = "/tmp/output.sav"
LOG_PATH = "/tmp/pspp.log"


def handler(event, _context):
    bucket = event["bucket"]

    for path in (SPS_PATH, DATA_PATH, SAV_PATH, LOG_PATH):
        if os.path.exists(path):
            os.remove(path)

    s3.download_file(bucket, event["sps_key"], SPS_PATH)
    s3.download_file(bucket, event["data_key"], DATA_PATH)

    result = subprocess.run(
        ["pspp", "-o", LOG_PATH, SPS_PATH],
        capture_output=True,
        text=True,
        timeout=90,
    )

    if not os.path.exists(SAV_PATH):
        log_content = open(LOG_PATH).read() if os.path.exists(LOG_PATH) else "(sin log)"
        # Truncado a proposito -- si pspp termina listando el dataset entero
        # en el log (ej. por un LIST que vino en la sintaxis original de
        # Confirmit), el mensaje de error sin acotar supera el limite de
        # 6MB de respuesta sincronica de Lambda, y el error real termina
        # perdido detras de un generico "ResponseSizeTooLarge".
        raise RuntimeError(
            f"PSPP no genero el .sav esperado. exit={result.returncode} "
            f"stdout={result.stdout[-3000:]} stderr={result.stderr[-3000:]} log={log_content[-3000:]}"
        )

    s3.upload_file(SAV_PATH, bucket, event["sav_key"])

    return {"sav_key": event["sav_key"]}
