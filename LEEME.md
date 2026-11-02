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
