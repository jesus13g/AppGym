#!/usr/bin/env python3
"""Genera `assets/instrucciones.en.json` desde el dataset original.

El catálogo que se versiona (`assets/ejercicios.es.json`) trae los pasos solo en
español. El dataset de origen —https://github.com/hasaneyldrm/exercises-dataset,
datos con licencia MIT— los trae en diez idiomas dentro de `instruction_steps`,
y su `es` coincide **exactamente** con el nuestro, así que el asset español no
hay que tocarlo: basta con una capa aparte con el inglés.

Se genera un fichero propio y no un `ejercicios.en.json` completo porque lo
único que cambia son los pasos: duplicar el megabyte entero para repetir ids,
músculos y rutas de imagen sería tirar 300 KB por nada.

    python3 tool/instrucciones_en.py

Comprueba que los ids coincidan con los del catálogo y aborta si no. El fichero
resultante se versiona, igual que `assets/musculatura.json`: es un dato de
entrada de la app, no un artefacto de compilación.
"""

import json
import pathlib
import sys
import urllib.request

ORIGEN = (
    'https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/'
    'main/data/exercises.json'
)
RAIZ = pathlib.Path(__file__).resolve().parent.parent
CATALOGO = RAIZ / 'assets' / 'ejercicios.es.json'
SALIDA = RAIZ / 'assets' / 'instrucciones.en.json'


def main() -> int:
    catalogo = json.loads(CATALOGO.read_text(encoding='utf-8'))
    ids = {e['id'] for e in catalogo}

    print(f'Descargando {ORIGEN}…')
    with urllib.request.urlopen(ORIGEN) as respuesta:
        upstream = json.loads(respuesta.read().decode('utf-8'))

    pasos: dict[str, list[str]] = {}
    for registro in upstream:
        clave = registro['id']
        if clave not in ids:
            continue
        en = (registro.get('instruction_steps') or {}).get('en')
        if en:
            pasos[clave] = en

    faltan = ids - pasos.keys()
    if faltan:
        print(f'ERROR: {len(faltan)} ejercicios sin pasos en inglés', file=sys.stderr)
        return 1

    # Se comprueba de paso que el español del origen siga siendo el nuestro: si
    # el dataset cambiara de redacción, este script lo diría en vez de dejar los
    # dos idiomas desalineados en silencio.
    por_id = {e['id']: e for e in catalogo}
    distintos = [
        r['id']
        for r in upstream
        if r['id'] in ids
        and (r.get('instruction_steps') or {}).get('es') != por_id[r['id']]['pasos']
    ]
    if distintos:
        print(
            f'AVISO: {len(distintos)} ejercicios ya no coinciden con el español '
            'del origen (p. ej. ' + ', '.join(distintos[:5]) + ')',
            file=sys.stderr,
        )

    SALIDA.write_text(
        json.dumps(pasos, ensure_ascii=False, sort_keys=True),
        encoding='utf-8',
    )
    print(f'{SALIDA.relative_to(RAIZ)}: {len(pasos)} ejercicios, '
          f'{SALIDA.stat().st_size // 1024} KB')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
