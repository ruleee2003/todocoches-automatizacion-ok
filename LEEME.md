# Automatización de Todocoches

Cada mañana, GitHub ejecuta una tarea que:

1. Descarga los precios oficiales de carburantes del Ministerio.
2. Genera `precios.json` y `precios-historico.json`.
3. Sube **solo esos dos archivos** a la raíz de la web en IONOS.
4. Guarda el histórico en `datos/`.

Si los datos no parecen correctos, no sube nada: la web conserva el último dato bueno y GitHub avisa por correo.

## Secretos que hay que crear en GitHub

Settings → Secrets and variables → Actions → New repository secret

| Nombre | Qué es | Dónde está |
|---|---|---|
| `SFTP_HOST` | Servidor SFTP, sin `sftp://` | Panel de IONOS → Hosting → SFTP y SSH |
| `SFTP_USER` | Usuario SFTP | El mismo sitio |
| `SFTP_PASSWORD` | Contraseña SFTP | La que tengas o una nueva |
| `SFTP_PATH` | Carpeta de la web en el servidor (donde está `index.html`). Normalmente `/` | Tu programa de subida de archivos |

Las contraseñas no se escriben en ningún archivo de este proyecto.

## Lanzarlo a mano

Actions → Actualizar precios de combustible → Run workflow

## Probarlo en el ordenador

```powershell
curl.exe -o datos-ministerio.json -H "Accept: application/json" "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/"
.\scripts\actualizar-precios.ps1 -Entrada datos-ministerio.json -OutDir salida -HistoricoPath datos\precios-historico.json
```

## Revisión técnica semanal

Cada lunes, `scripts/revision-tecnica.ps1` revisa la web publicada: páginas del sitemap, enlaces y archivos internos, redirecciones, `robots.txt`, `ads.txt`, certificado HTTPS, compresión y precios del día. Solo lee, no modifica nada.

- **Verde:** no hay errores. Los avisos, si los hay, están en el resumen de la ejecución.
- **Rojo:** hay algo roto y GitHub avisa por correo. El informe está en el resumen de la ejecución.

**Al actualizar este repositorio, no vuelvas a subir la carpeta `datos`:** borrarías días del histórico de precios.

## Informe de Search Console

Cada lunes, `scripts/informe-search-console.py` guarda clics, impresiones y páginas indexadas. La lista de páginas sin indexar queda en `datos/paginas-sin-indexar.csv`. Sale en rojo y avisa por correo si las indexadas caen más de un 20 % o, si la semana anterior superó las 500 impresiones, estas caen más de un 50 %. Necesita el secreto `GSC_CREDENCIALES`, con el contenido del archivo JSON de la cuenta de servicio de Google.

## Precios dentro de las páginas

Cada mañana, tras generar los precios, `scripts/actualizar-paginas.ps1` descarga la portada, `precio-gasolina-hoy.html` y las páginas de provincia publicadas, escribe los datos entre las marcas `<!--dato:clave-->...<!--/dato-->` y actualiza su fecha en el sitemap. El diseño se edita en el repositorio de la web; esas marcas no deben borrarse. Si alguna página falla, no se toca y la tarea sale en rojo.

## Mapa de gasolineras

Al final de la tarea diaria, `scripts/generar-mapa.ps1` crea un archivo por provincia y un índice, y se suben a la carpeta `datos-gasolineras/` del servidor (no están en ningún repositorio). La página `mapa-gasolineras.html` se edita en el repositorio de la web. La revisión semanal avisa si los datos llevan más de 2 días sin actualizarse.

La tarea `Permitir la ubicación en el mapa` solo hace falta una vez: cambia en el `.htaccess` del servidor `geolocation=()` por `geolocation=(self)` para que funcione «Cerca de mí», y deja una copia en `.htaccess.antes-mapa`.

La tarea `Redirigir subpáginas unidas a sus fichas` solo hace falta una vez, después de publicar la web: añade al `.htaccess` del servidor las redirecciones 301 de las 7 subpáginas integradas en sus fichas y deja una copia en `.htaccess.antes-redirecciones`.
