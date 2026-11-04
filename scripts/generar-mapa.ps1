# Genera los datos del mapa de gasolineras (mapa-gasolineras.html) a partir del JSON del Ministerio:
# un archivo por provincia y un índice. Cada fila es
# [lat, lon, rótulo, dirección, municipio, horario, gasolina 95, diésel, gasolina 98, GLP]
param(
  [Parameter(Mandatory = $true)][string]$Entrada,
  [Parameter(Mandatory = $true)][string]$Precios,   # precios.json ya generado: de aquí salen los nombres de provincia
  [Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$u8 = New-Object Text.UTF8Encoding($false)

function Num($v, [int]$dec = 3) {
  if ([string]::IsNullOrWhiteSpace($v)) { return $null }
  $n = 0.0
  if ([double]::TryParse(([string]$v -replace ',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$n)) { return [math]::Round($n, $dec) }
  return $null
}
function Precio($v) { $n = Num $v; if ($null -eq $n -or $n -le 0) { return $null }; return $n }
function Titulo([string]$s) { return $inv.TextInfo.ToTitleCase($s.Trim().ToLowerInvariant()) }
function Texto($v) { return ([regex]::Replace([string]$v, '[\x00-\x1F]+', ' ')).Replace('\', '\\').Replace('"', '\"').Trim() }
function EnEspana($la, $lo) { return ($la -ge 27 -and $la -le 44.5 -and $lo -ge -18.5 -and $lo -le 5) }

$nombres = @{}
foreach ($p in ([IO.File]::ReadAllText($Precios, [Text.Encoding]::UTF8) | ConvertFrom-Json).provincias) { $nombres[[string]$p.id] = $p.nombre }
$j = [IO.File]::ReadAllText($Entrada, [Text.Encoding]::UTF8) | ConvertFrom-Json

$por = @{}; $descartadas = 0; $giradas = 0; $total = 0
foreach ($e in $j.ListaEESSPrecio) {
  $lat = Num $e.Latitud 5; $lon = Num $e.'Longitud (WGS84)' 5
  if ($null -eq $lat -or $null -eq $lon) { $descartadas++; continue }
  if (-not (EnEspana $lat $lon)) {
    # alguna gasolinera llega con la latitud y la longitud cambiadas
    if (EnEspana $lon $lat) { $t = $lat; $lat = $lon; $lon = $t; $giradas++ } else { $descartadas++; continue }
  }
  $pr = @((Precio $e.'Precio Gasolina 95 E5'), (Precio $e.'Precio Gasoleo A'), (Precio $e.'Precio Gasolina 98 E5'), (Precio $e.'Precio Gases licuados del petróleo'))
  if (@($pr | Where-Object { $null -ne $_ }).Count -eq 0) { continue }
  $id = [string]$e.IDProvincia
  if (-not $por.ContainsKey($id)) { $por[$id] = New-Object Collections.Generic.List[object] }
  $por[$id].Add([pscustomobject]@{
      lat = $lat; lon = $lon; provincia = [string]$e.Provincia
      txt = @((Texto $e.'Rótulo'), (Texto (Titulo ([string]$e.'Dirección'))), (Texto $e.Municipio), (Texto $e.Horario))
      pr = $pr
    })
  $total++
}
if ($por.Keys.Count -lt 50 -or $total -lt 8000) { throw "Datos sospechosos: $($por.Keys.Count) provincias y $total gasolineras. No se genera el mapa." }

function Cifra($v) { if ($null -eq $v) { return 'null' }; return ([double]$v).ToString('R', $inv) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$indice = @()
foreach ($id in $por.Keys) {
  $l = $por[$id]
  $filas = foreach ($r in $l) {
    '[' + (Cifra $r.lat) + ',' + (Cifra $r.lon) + ',"' + ($r.txt -join '","') + '",' + ((@($r.pr) | ForEach-Object { Cifra $_ }) -join ',') + ']'
  }
  [IO.File]::WriteAllText((Join-Path $OutDir "$id.json"), ('[' + ($filas -join ',') + ']'), $u8)
  $nombre = $nombres[$id]; if (-not $nombre) { $nombre = Titulo $l[0].provincia }
  $indice += [ordered]@{
    id = $id; nombre = $nombre; n = $l.Count
    lat = [math]::Round(($l | ForEach-Object { $_.lat } | Measure-Object -Average).Average, 3)
    lon = [math]::Round(($l | ForEach-Object { $_.lon } | Measure-Object -Average).Average, 3)
  }
}
$indice = @($indice | Sort-Object { $_.nombre })
$fecha = ([string]$j.Fecha) -replace '^(\d\d/\d\d/\d{4} \d{1,2}:\d\d):\d\d$', '$1'
$meta = [ordered]@{ actualizado = $fecha; total = $total; provincias = $indice }
[IO.File]::WriteAllText((Join-Path $OutDir 'indice.json'), (ConvertTo-Json -InputObject $meta -Depth 4 -Compress), $u8)
"Mapa: $total gasolineras en $($por.Keys.Count) provincias; $giradas con coordenadas corregidas y $descartadas descartadas por no tener una ubicación válida."
