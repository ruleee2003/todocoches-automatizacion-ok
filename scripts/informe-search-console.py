"""Informe semanal de Search Console: clics, impresiones e indexación página a página.

Solo lee datos. Sale con error, y GitHub avisa por correo, si las páginas indexadas
o las impresiones caen de golpe respecto a la semana anterior.
"""
import collections
import csv
import datetime as dt
import json
import os
import re
import sys
import time
import urllib.parse

import requests
from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

WEB = "https://todocoches.org/"
PROPIEDADES = ["sc-domain:todocoches.org", "https://todocoches.org/", "https://www.todocoches.org/"]
HISTORICO = "datos/search-console.json"
SIN_INDEXAR = "datos/paginas-sin-indexar.csv"
RETRASO_DATOS = 3  # Search Console tarda unos días en consolidar los datos

info = json.loads(os.environ["GSC_CREDENCIALES"])
creds = service_account.Credentials.from_service_account_info(
    info, scopes=["https://www.googleapis.com/auth/webmasters.readonly"]
)
s = AuthorizedSession(creds)


def elegir_propiedad():
    r = s.get("https://www.googleapis.com/webmasters/v3/sites", timeout=60)
    r.raise_for_status()
    disponibles = [e["siteUrl"] for e in r.json().get("siteEntry", [])]
    for p in PROPIEDADES:
        if p in disponibles:
            return p
    sys.exit(
        "La cuenta de servicio no tiene acceso a la web en Search Console. "
        f"Añade este correo como usuario: {info.get('client_email')}"
    )


def consulta(propiedad, inicio, fin, dimensiones=None, filas=10, pagina_contiene=None):
    cuerpo = {"startDate": inicio.isoformat(), "endDate": fin.isoformat(), "type": "web", "rowLimit": filas}
    if dimensiones:
        cuerpo["dimensions"] = dimensiones
    if pagina_contiene:
        cuerpo["dimensionFilterGroups"] = [{"filters": [{"dimension": "page", "operator": "contains", "expression": pagina_contiene}]}]
    url = "https://www.googleapis.com/webmasters/v3/sites/" + urllib.parse.quote(propiedad, safe="") + "/searchAnalytics/query"
    r = s.post(url, json=cuerpo, timeout=120)
    r.raise_for_status()
    return r.json().get("rows", [])


def totales(propiedad, inicio, fin):
    filas = consulta(propiedad, inicio, fin)
    if not filas:
        return {"clics": 0, "impresiones": 0, "posicion": None}
    f = filas[0]
    return {"clics": int(f["clicks"]), "impresiones": int(f["impressions"]), "posicion": round(f["position"], 1)}


def inspeccionar(propiedad, urls):
    resultado, errores = [], 0
    for u in urls:
        try:
            r = s.post(
                "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect",
                json={"inspectionUrl": u, "siteUrl": propiedad, "languageCode": "es-ES"},
                timeout=60,
            )
            r.raise_for_status()
            i = r.json()["inspectionResult"]["indexStatusResult"]
            resultado.append((u, i.get("verdict", ""), i.get("coverageState", "Desconocido"), i.get("lastCrawlTime", "")[:10]))
        except Exception as e:  # una página fallida no debe frenar el informe
            errores += 1
            print(f"No se pudo inspeccionar {u}: {e}")
        time.sleep(0.25)
    return resultado, errores


propiedad = elegir_propiedad()
hoy = dt.date.today()
fin = hoy - dt.timedelta(days=RETRASO_DATOS)
inicio = fin - dt.timedelta(days=6)
fin_prev = inicio - dt.timedelta(days=1)
inicio_prev = fin_prev - dt.timedelta(days=6)
actual = totales(propiedad, inicio, fin)
previo = totales(propiedad, inicio_prev, fin_prev)
top_paginas = consulta(propiedad, inicio, fin, ["page"], 10)
top_consultas = consulta(propiedad, inicio, fin, ["query"], 10)
precio_paginas = consulta(propiedad, inicio, fin, ["page"], 20, "precio-gasolina")
precio_consultas = consulta(propiedad, inicio, fin, ["query"], 15, "precio-gasolina")

mapa = requests.get(WEB + "sitemap.xml", timeout=60)
mapa.raise_for_status()
urls = re.findall(r"<loc>\s*([^<\s]+)\s*</loc>", mapa.text)
paginas, fallos = inspeccionar(propiedad, urls)
indexadas = sum(1 for p in paginas if p[1] == "PASS")
sin_indexar = [p for p in paginas if p[1] != "PASS"]
motivos = collections.Counter(p[2] for p in sin_indexar)

historial = []
if os.path.exists(HISTORICO):
    with open(HISTORICO, encoding="utf-8") as f:
        historial = json.load(f)
anterior = historial[-1] if historial else None

os.makedirs("datos", exist_ok=True)
historial = [h for h in historial if h["fecha"] != hoy.isoformat()]
historial.append({"fecha": hoy.isoformat(), **actual, "indexadas": indexadas, "revisadas": len(paginas)})
with open(HISTORICO, "w", encoding="utf-8") as f:
    json.dump(historial, f, ensure_ascii=False, indent=0)
with open(SIN_INDEXAR, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["url", "motivo", "ultimo_rastreo"])
    for p in sorted(sin_indexar, key=lambda x: (x[2], x[0])):
        w.writerow([p[0], p[2], p[3]])


def variacion(a, b):
    return "sin datos previos" if not b else f"{(a - b) / b * 100:+.0f} %"


alertas = []
if anterior and fallos == 0 and anterior.get("indexadas") and indexadas < anterior["indexadas"] * 0.8:
    alertas.append(f"Las páginas indexadas han caído de {anterior['indexadas']} a {indexadas}.")
if previo["impresiones"] >= 500 and actual["impresiones"] < previo["impresiones"] * 0.5:
    alertas.append(f"Las impresiones han caído de {previo['impresiones']} a {actual['impresiones']}.")

L = [f"# Search Console: semana del {inicio:%d/%m} al {fin:%d/%m/%Y}", ""]
if alertas:
    L += ["## Alertas", ""] + [f"- {a}" for a in alertas] + [""]
L += [
    "| Dato | Esta semana | Semana anterior | Cambio |",
    "|---|---|---|---|",
    f"| Clics | {actual['clics']} | {previo['clics']} | {variacion(actual['clics'], previo['clics'])} |",
    f"| Impresiones | {actual['impresiones']} | {previo['impresiones']} | {variacion(actual['impresiones'], previo['impresiones'])} |",
    f"| Posición media | {actual['posicion'] or '—'} | {previo['posicion'] or '—'} | |",
    "",
    f"**Páginas indexadas: {indexadas} de {len(paginas)}**" + (f" (la última vez, {anterior['indexadas']})" if anterior and anterior.get("indexadas") is not None else ""),
]
if fallos:
    L.append(f"\nNo se han podido revisar {fallos} páginas.")
if motivos:
    L += ["", "## Por qué no se indexan", "", "| Motivo | Páginas |", "|---|---|"] + [f"| {m} | {n} |" for m, n in motivos.most_common()]
    L += ["", f"La lista completa está en `{SIN_INDEXAR}`."]
estado_precios = [p for p in paginas if "precio-gasolina" in p[0]]
L += ["", "## Páginas de precios de la gasolina", ""]
if estado_precios:
    L += ["| Página | ¿Indexada? |", "|---|---|"]
    L += [f"| {p[0].replace(WEB, '/')} | {'Sí' if p[1] == 'PASS' else p[2]} |" for p in estado_precios]
if precio_paginas:
    L += ["", "| Página | Clics | Impresiones | Posición |", "|---|---|---|---|"]
    L += [f"| {r['keys'][0].replace(WEB, '/')} | {int(r['clicks'])} | {int(r['impressions'])} | {r['position']:.1f} |" for r in precio_paginas]
else:
    L += ["", "Sin impresiones esta semana."]
if precio_consultas:
    L += ["", "| Búsqueda | Clics | Impresiones | Posición |", "|---|---|---|---|"]
    L += [f"| {r['keys'][0]} | {int(r['clicks'])} | {int(r['impressions'])} | {r['position']:.1f} |" for r in precio_consultas]
if top_paginas:
    L += ["", "## Páginas con más impresiones", "", "| Página | Clics | Impresiones |", "|---|---|---|"]
    L += [f"| {r['keys'][0].replace(WEB, '/')} | {int(r['clicks'])} | {int(r['impressions'])} |" for r in top_paginas]
if top_consultas:
    L += ["", "## Búsquedas con más impresiones", "", "| Búsqueda | Clics | Impresiones |", "|---|---|---|"]
    L += [f"| {r['keys'][0]} | {int(r['clicks'])} | {int(r['impressions'])} |" for r in top_consultas]
texto = "\n".join(L)
print(texto)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
        f.write(texto + "\n")
if alertas:
    sys.exit(1)
