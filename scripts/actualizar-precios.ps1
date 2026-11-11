# A partir de los precios oficiales de carburantes (JSON del Ministerio) genera dos archivos pequeños para la web:
#   precios.json            medias de hoy (España y provincias) y gasolinera más barata por provincia
#   precios-historico.json  una media nacional por día, que crece con el tiempo
#
# Si los datos no parecen correctos, el script falla SIN escribir nada: la web conserva
# el último dato bueno y GitHub avisa por correo.
param(
  [Parameter(Mandatory = $true)][string]$Entrada,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [Parameter(Mandatory = $true)][string]$HistoricoPath,
  [string]$EntradaLuz = '',
  [string]$LuzHistoricoPath = '',
  [string]$LuzInicial = '',
  [string]$HistProvinciasPath = ''
)

# Impuestos de la luz: si el Gobierno los cambia, solo hay que tocar estas dos líneas.
$ivaLuz = 21
$impuestoElectrico = 5.11269632
$ErrorActionPreference = 'Stop'
$Entrada = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Entrada)
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
$HistoricoPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HistoricoPath)
foreach ($v in 'EntradaLuz', 'LuzHistoricoPath', 'LuzInicial', 'HistProvinciasPath') {
  $val = Get-Variable $v -ValueOnly
  if ($val) { Set-Variable $v ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($val)) }
}

$inv = [Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object Text.UTF8Encoding($false)

$provincias = @{
  '01'='Álava'; '02'='Albacete'; '03'='Alicante'; '04'='Almería'; '05'='Ávila'; '06'='Badajoz'; '07'='Baleares'; '08'='Barcelona';
  '09'='Burgos'; '10'='Cáceres'; '11'='Cádiz'; '12'='Castellón'; '13'='Ciudad Real'; '14'='Córdoba'; '15'='A Coruña'; '16'='Cuenca';
  '17'='Girona'; '18'='Granada'; '19'='Guadalajara'; '20'='Gipuzkoa'; '21'='Huelva'; '22'='Huesca'; '23'='Jaén'; '24'='León';
  '25'='Lleida'; '26'='La Rioja'; '27'='Lugo'; '28'='Madrid'; '29'='Málaga'; '30'='Murcia'; '31'='Navarra'; '32'='Ourense';
  '33'='Asturias'; '34'='Palencia'; '35'='Las Palmas'; '36'='Pontevedra'; '37'='Salamanca'; '38'='Santa Cruz de Tenerife'; '39'='Cantabria'; '40'='Segovia';
  '41'='Sevilla'; '42'='Soria'; '43'='Tarragona'; '44'='Teruel'; '45'='Toledo'; '46'='Valencia'; '47'='Valladolid'; '48'='Bizkaia';
  '49'='Zamora'; '50'='Zaragoza'; '51'='Ceuta'; '52'='Melilla'
}
$campos = @{ g95 = 'Precio Gasolina 95 E5'; diesel = 'Precio Gasoleo A'; g98 = 'Precio Gasolina 98 E5'; glp = 'Precio Gases licuados del petróleo' }

function Convert-Precio($v) {
  if ([string]::IsNullOrWhiteSpace($v)) { return $null }
  $n = 0.0
  if ([double]::TryParse(($v -replace ',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$n)) {
    if ($n -ge 0.3 -and $n -le 5) { return $n }
  }
  return $null
}
function Get-Media($lista) { if ($lista.Count -eq 0) { return $null }; return [math]::Round(($lista | Measure-Object -Average).Average, 3) }

# --- datos descargados previamente con curl ---
$datos = [IO.File]::ReadAllText($Entrada, [Text.Encoding]::UTF8) | ConvertFrom-Json
if ($datos.ResultadoConsulta -ne 'OK') { throw "ResultadoConsulta: $($datos.ResultadoConsulta)" }

$fechaApi = [datetime]::ParseExact($datos.Fecha, 'dd/MM/yyyy H:mm:ss', $inv)
$estaciones = @($datos.ListaEESSPrecio | Where-Object { $_.'Tipo Venta' -eq 'P' })

# --- medias ---
$nac = @{}; foreach ($k in $campos.Keys) { $nac[$k] = New-Object Collections.Generic.List[double] }
$prov = @{}
foreach ($e in $estaciones) {
  $id = [string]$e.IDProvincia
  if (-not $prov.ContainsKey($id)) { $prov[$id] = @{ g95 = (New-Object Collections.Generic.List[double]); diesel = (New-Object Collections.Generic.List[double]); g98 = (New-Object Collections.Generic.List[double]); glp = (New-Object Collections.Generic.List[double]); n = 0; barata_g95 = $null; barata_diesel = $null; todas_g95 = (New-Object Collections.Generic.List[object]); todas_diesel = (New-Object Collections.Generic.List[object]) } }
  $p = $prov[$id]; $p.n++
  foreach ($k in $campos.Keys) {
    $v = Convert-Precio $e.($campos[$k])
    if ($null -eq $v) { continue }
    $nac[$k].Add($v); $p[$k].Add($v)
    if ($k -in 'g95', 'diesel') {
      $p["todas_$k"].Add([pscustomobject]@{ precio = $v; rotulo = ([string]$e.'Rótulo').Trim(); municipio = ([string]$e.Municipio).Trim(); direccion = ([string]$e.'Dirección').Trim() })
      $b = "barata_$k"
      if ($null -eq $p[$b] -or $v -lt $p[$b].precio) {
        $p[$b] = [ordered]@{ precio = $v; rotulo = ([string]$e.'Rótulo').Trim(); municipio = ([string]$e.Municipio).Trim(); direccion = ([string]$e.'Dirección').Trim() }
      }
    }
  }
}

$nacional = [ordered]@{ g95 = Get-Media $nac.g95; diesel = Get-Media $nac.diesel; g98 = Get-Media $nac.g98; glp = Get-Media $nac.glp }

# --- comprobaciones: si algo no cuadra, no se publica nada ---
if ($estaciones.Count -lt 8000) { throw "Muy pocas estaciones: $($estaciones.Count)" }
if ($prov.Count -ne 52) { throw "Provincias inesperadas: $($prov.Count)" }
foreach ($k in 'g95', 'diesel') { if ($nacional[$k] -lt 0.9 -or $nacional[$k] -gt 3.5) { throw "Media fuera de rango en ${k}: $($nacional[$k])" } }
foreach ($id in $prov.Keys) { if (-not $provincias.ContainsKey($id)) { throw "Provincia desconocida: $id" } }

$listaProv = foreach ($id in ($prov.Keys | Sort-Object { $provincias[$_] })) {
  $p = $prov[$id]
  [ordered]@{ id = $id; nombre = $provincias[$id]; estaciones = $p.n; g95 = Get-Media $p.g95; diesel = Get-Media $p.diesel; g98 = Get-Media $p.g98; glp = Get-Media $p.glp; barata_g95 = $p.barata_g95; barata_diesel = $p.barata_diesel }
}

# --- luz: precio regulado (PVPC) hora a hora, en euros/kWh y sin impuestos ---
# Si hoy falla la descarga, se mantiene el último dato bueno: un fallo aquí no debe frenar los carburantes.
$luz = $null
if ($LuzHistoricoPath) {
  $factorLuz = (1 + $impuestoElectrico / 100) * (1 + $ivaLuz / 100)
  $histLuz = @()
  $origen = if (Test-Path -LiteralPath $LuzHistoricoPath) { $LuzHistoricoPath } elseif ($LuzInicial -and (Test-Path -LiteralPath $LuzInicial)) { $LuzInicial } else { $null }
  if ($origen) { foreach ($h in ([IO.File]::ReadAllText($origen, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $histLuz += [ordered]@{ f = [string]$h.f; media = $h.media; noche = $h.noche } } }

  $horas = @(); $fechaLuz = $null
  try {
    if ($EntradaLuz -and (Test-Path -LiteralPath $EntradaLuz)) {
      foreach ($r in ([IO.File]::ReadAllText($EntradaLuz, [Text.Encoding]::UTF8) | ConvertFrom-Json).PVPC) {
        $v = [double]::Parse(([string]$r.PCB).Replace(',', '.'), $inv) / 1000
        if ($v -lt -0.2 -or $v -gt 1.5) { throw "Precio de la luz fuera de rango: $v" }
        $horas += [ordered]@{ h = [string]$r.Hora; p = [math]::Round($v, 4) }
        $fechaLuz = [datetime]::ParseExact([string]$r.Dia, 'dd/MM/yyyy', $inv).ToString('yyyy-MM-dd')
      }
      if ($horas.Count -lt 23 -or $horas.Count -gt 25) { throw "Número de horas inesperado: $($horas.Count)" }
    }
  } catch { Write-Warning "Luz: se mantiene el último dato bueno. $($_.Exception.Message)"; $horas = @(); $fechaLuz = $null }

  $min = $null; $max = $null
  if ($horas.Count) {
    $media = [math]::Round(($horas | ForEach-Object { $_.p } | Measure-Object -Average).Average, 4)
    $noche = [math]::Round(($horas | Where-Object { [int]$_.h.Substring(0, 2) -lt 8 } | ForEach-Object { $_.p } | Measure-Object -Average).Average, 4)
    $min = $horas | Sort-Object { $_.p } | Select-Object -First 1
    $max = $horas | Sort-Object { $_.p } | Select-Object -Last 1
    $histLuz = @($histLuz | Where-Object { $_.f -ne $fechaLuz })
    $histLuz += [ordered]@{ f = $fechaLuz; media = $media; noche = $noche }
    $histLuz = @($histLuz | Sort-Object { $_.f } | Select-Object -Last 400)
  }
  if ($histLuz.Count) {
    $ultimo = $histLuz[-1]
    $tramo = @($histLuz | Select-Object -Last 30)
    $luz = [ordered]@{
      fecha = $ultimo.f; media = $ultimo.media; noche = $ultimo.noche
      hogar = [math]::Round(($tramo | ForEach-Object { $_.noche } | Measure-Object -Average).Average * $factorLuz, 3)
      dias = $tramo.Count; iva = $ivaLuz; impuesto = $impuestoElectrico
      min = $min; max = $max; horas = @($horas)
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LuzHistoricoPath) | Out-Null
    [IO.File]::WriteAllText($LuzHistoricoPath, (ConvertTo-Json -InputObject @($histLuz) -Depth 3 -Compress), $utf8)
  }
}

$hoy = $fechaApi.ToString('yyyy-MM-dd')
$salida = [ordered]@{
  fecha = $hoy
  actualizado = $fechaApi.ToString('dd/MM/yyyy HH:mm')
  fuente = 'Ministerio para la Transición Ecológica y el Reto Demográfico'
  estaciones = $estaciones.Count
  nacional = $nacional
  luz = $luz
  provincias = @($listaProv)
}

# --- histórico: una entrada por día, sin duplicar ---
$historico = @()
if (Test-Path -LiteralPath $HistoricoPath) {
  $previo = [IO.File]::ReadAllText($HistoricoPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  foreach ($h in $previo) {
    $dia = if ($h.f -is [datetime]) { $h.f.ToString('yyyy-MM-dd') } else { [string]$h.f }
    if ($dia -ne $hoy) { $historico += [ordered]@{ f = $dia; g95 = $h.g95; diesel = $h.diesel } }
  }
}
$historico += [ordered]@{ f = $hoy; g95 = $nacional.g95; diesel = $nacional.diesel }
$historico = @($historico | Sort-Object { $_.f })

# --- detalle por provincia: las 5 gasolineras más baratas de cada combustible (no se publica como JSON) ---
$detalle = [ordered]@{}
$capitales = [ordered]@{ '28' = 'Madrid'; '08' = 'Barcelona'; '46' = 'Valencia'; '41' = 'Sevilla'; '50' = 'Zaragoza' }
foreach ($id in $prov.Keys) {
  $pp = $prov[$id]
  $detalle[$id] = [ordered]@{
    g95 = @($pp.todas_g95 | Sort-Object precio, rotulo | Select-Object -First 5)
    diesel = @($pp.todas_diesel | Sort-Object precio, rotulo | Select-Object -First 5)
  }
  # capital de las provincias con pagina propia: media, extremos y las 5 mas baratas de la ciudad
  if ($capitales.Contains($id)) {
    $cap = $capitales[$id]
    $c95 = @($pp.todas_g95 | Where-Object { $_.municipio -eq $cap } | Sort-Object precio, rotulo)
    $cdi = @($pp.todas_diesel | Where-Object { $_.municipio -eq $cap } | Sort-Object precio, rotulo)
    if ($c95.Count -ge 5 -and $cdi.Count -ge 5) {
      $detalle[$id]['ciudad'] = [ordered]@{
        nombre = $cap; n95 = $c95.Count; ndiesel = $cdi.Count
        g95 = Get-Media @($c95 | ForEach-Object { $_.precio }); diesel = Get-Media @($cdi | ForEach-Object { $_.precio })
        max95 = $c95[-1].precio; maxdiesel = $cdi[-1].precio
        baratas95 = @($c95 | Select-Object -First 5); baratasdiesel = @($cdi | Select-Object -First 5)
      }
    }
  }
}

# --- histórico por provincia: [gasolina 95, diésel] de cada día ---
if ($HistProvinciasPath) {
  $hp = @()
  if (Test-Path -LiteralPath $HistProvinciasPath) { foreach ($e in ([IO.File]::ReadAllText($HistProvinciasPath, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { if ([string]$e.f -ne $hoy) { $hp += $e } } }
  $hoyP = [ordered]@{}; foreach ($x in $listaProv) { $hoyP[[string]$x.id] = @($x.g95, $x.diesel) }
  $hp += [pscustomobject]@{ f = $hoy; p = $hoyP }
  $hp = @($hp | Sort-Object { [string]$_.f } | Select-Object -Last 400)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $HistProvinciasPath) | Out-Null
  [IO.File]::WriteAllText($HistProvinciasPath, (ConvertTo-Json -InputObject $hp -Depth 5 -Compress), $utf8)
}

# --- escritura ---
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
[IO.File]::WriteAllText((Join-Path $OutDir 'detalle-provincias.json'), (ConvertTo-Json -InputObject $detalle -Depth 5 -Compress), $utf8)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $HistoricoPath) | Out-Null
$jsonHist = ConvertTo-Json -InputObject $historico -Depth 4 -Compress
[IO.File]::WriteAllText((Join-Path $OutDir 'precios.json'), (ConvertTo-Json -InputObject $salida -Depth 7 -Compress), $utf8)
[IO.File]::WriteAllText((Join-Path $OutDir 'precios-historico.json'), $jsonHist, $utf8)
[IO.File]::WriteAllText($HistoricoPath, $jsonHist, $utf8)

if ($luz) { "Luz del $($luz.fecha): media = $($luz.media) | madrugada = $($luz.noche) €/kWh sin impuestos | hogar = $($luz.hogar) €/kWh con impuestos ($($luz.dias) días)" } else { Write-Warning 'Sin datos de luz' }
"Datos del $($salida.actualizado): 95 = $($nacional.g95) | diésel = $($nacional.diesel) | 98 = $($nacional.g98) | GLP = $($nacional.glp) | $($estaciones.Count) estaciones"
