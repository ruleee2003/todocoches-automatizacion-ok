# Escribe los precios del día dentro del HTML de la portada, la página de precios y las páginas de
# provincia, y actualiza su fecha en el sitemap. Así Google ve el dato fresco sin depender de JavaScript.
#
# Solo cambia lo que hay entre marcas <!--dato:clave-->...<!--/dato--> y las etiquetas de descripción.
# Parte siempre de la página publicada, de modo que el diseño se sigue editando en el repositorio de la web.
# Si algo no cuadra en una página, esa página no se toca y la tarea termina en rojo.
param(
  [Parameter(Mandatory = $true)][string]$Salida,          # carpeta con precios.json y detalle-provincias.json
  [Parameter(Mandatory = $true)][string]$Historico,       # precios-historico.json
  [Parameter(Mandatory = $true)][string]$HistProvincias,  # histórico por provincia
  [Parameter(Mandatory = $true)][string]$WebEntrada,      # carpeta con las páginas y el sitemap publicados
  [Parameter(Mandatory = $true)][string]$WebSalida        # carpeta donde dejar lo que hay que subir
)
$ErrorActionPreference = 'Stop'
$rutas = @{}
foreach ($v in 'Salida', 'Historico', 'HistProvincias', 'WebEntrada', 'WebSalida') { $rutas[$v] = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Get-Variable $v -ValueOnly)) }
$inv = [Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object Text.UTF8Encoding($false)
$base = 'https://todocoches.org/'
$provincias = [ordered]@{ '28' = 'precio-gasolina-madrid.html'; '08' = 'precio-gasolina-barcelona.html'; '46' = 'precio-gasolina-valencia.html'; '41' = 'precio-gasolina-sevilla.html'; '50' = 'precio-gasolina-zaragoza.html' }
$meses = 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'

function LeerJson([string]$p) { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function F([object]$n, [int]$d = 3) { if ($null -eq $n) { return '—' }; return ([double]$n).ToString(('0.' + ('0' * $d)), $inv).Replace('.', ',') }
function Esc([string]$s) { return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function Nombre([string]$s) { return $inv.TextInfo.ToTitleCase($s.ToLowerInvariant()) }
function Dato([string]$h, [string]$clave, [string]$valor) {
  $a = "<!--dato:$clave-->"; $z = '<!--/dato-->'
  if (-not $h.Contains($a)) { throw "Falta la marca $clave" }
  $pos = 0
  while (($i = $h.IndexOf($a, $pos)) -ge 0) {
    $j = $h.IndexOf($z, $i); if ($j -lt 0) { throw "Marca sin cerrar: $clave" }
    $h = $h.Substring(0, $i + $a.Length) + $valor + $h.Substring($j)
    $pos = $i + $a.Length + $valor.Length
  }
  return $h
}
function Meta([string]$h, [string]$selector, [string]$valor) {
  $m = [regex]::Match($h, '<meta\s+' + $selector + '\s+content="[^"]*"\s*/?>')
  if (-not $m.Success) { throw "Falta la etiqueta $selector" }
  return $h.Replace($m.Value, '<meta ' + $selector + ' content="' + (Esc $valor) + '">')
}
function Descripcion([string]$h, [string]$v) {
  $h = Meta $h 'name="description"' $v
  $h = Meta $h 'property="og:description"' $v
  return Meta $h 'name="twitter:description"' $v
}
function Grafico($serie) {
  if (@($serie).Count -lt 2) { return '<p style="font-size:14px; color:var(--muted);">Empezamos a guardar este histórico en noviembre de 2026. El gráfico aparecerá en cuanto haya varios días de datos y cada mañana sumará uno más.</p>' }
  $W = 640; $H = 240; $izq = 44; $der = 12; $arr = 12; $aba = 26
  $vals = @(); foreach ($d in $serie) { foreach ($k in 'g95', 'diesel') { if ($null -ne $d.$k) { $vals += [double]$d.$k } } }
  $min = ($vals | Measure-Object -Minimum).Minimum; $max = ($vals | Measure-Object -Maximum).Maximum
  $marg = [math]::Max(($max - $min) * 0.15, 0.01); $min -= $marg; $max += $marg
  $n = @($serie).Count
  $fx = { param($i) $izq + $i * ($W - $izq - $der) / ($n - 1) }
  $fy = { param($v) $arr + ($max - $v) * ($H - $arr - $aba) / ($max - $min) }
  $linea = {
    param($k) $pts = @(); for ($i = 0; $i -lt $n; $i++) { $v = $serie[$i].$k; if ($null -ne $v) { $pts += ((& $fx $i).ToString('0.0', $inv) + ',' + (& $fy ([double]$v)).ToString('0.0', $inv)) } }
    return ($pts -join ' ')
  }
  $s = '<svg viewBox="0 0 ' + $W + ' ' + $H + '" role="img" aria-label="Evolución del precio medio de la gasolina 95 y el diésel">'
  for ($i = 0; $i -lt 4; $i++) {
    $v = $min + ($max - $min) * $i / 3; $y = (& $fy $v)
    $s += '<line x1="' + $izq + '" x2="' + ($W - $der) + '" y1="' + $y.ToString('0.0', $inv) + '" y2="' + $y.ToString('0.0', $inv) + '" stroke="var(--line)"/>'
    $s += '<text x="' + ($izq - 6) + '" y="' + ($y + 4).ToString('0.0', $inv) + '" text-anchor="end" font-size="11" fill="var(--muted)">' + (F $v 2) + '</text>'
  }
  $s += '<polyline fill="none" stroke="var(--accent)" stroke-width="2.5" points="' + (& $linea 'g95') + '"/>'
  $s += '<polyline fill="none" stroke="var(--teal)" stroke-width="2.5" points="' + (& $linea 'diesel') + '"/>'
  $fe = { param($t) $p = ([string]$t).Split('-'); $p[2] + '/' + $p[1] }
  $s += '<text x="' + $izq + '" y="' + ($H - 8) + '" font-size="11" fill="var(--muted)">' + (& $fe $serie[0].f) + '</text>'
  $s += '<text x="' + ($W - $der) + '" y="' + ($H - 8) + '" text-anchor="end" font-size="11" fill="var(--muted)">' + (& $fe $serie[$n - 1].f) + '</text></svg>'
  $s += '<div class="pg-leyenda"><span><i style="background:var(--accent)"></i>Gasolina 95</span><span><i style="background:var(--teal)"></i>Diésel</span></div>'
  return $s
}

$d = LeerJson (Join-Path $rutas.Salida 'precios.json')
$det = LeerJson (Join-Path $rutas.Salida 'detalle-provincias.json')
$hist = @(); foreach ($h in (LeerJson $rutas.Historico)) { $hist += [pscustomobject]@{ f = [string]$h.f; g95 = $h.g95; diesel = $h.diesel } }
$histP = @(); foreach ($h in (LeerJson $rutas.HistProvincias)) { $histP += $h }
$hoyD = [datetime]::ParseExact([string]$d.fecha, 'yyyy-MM-dd', $inv)
$fechaLarga = '{0} de {1} de {2}' -f $hoyD.Day, $meses[$hoyD.Month - 1], $hoyD.Year
$fechaCorta = '{0} de {1}' -f $hoyD.Day, $meses[$hoyD.Month - 1]
$lista = @($d.provincias)

# variación: céntimos respecto a un día concreto, solo si hay dato de ese día
function Dif([string]$k, [int]$dias) {
  $f = $hoyD.AddDays(-$dias).ToString('yyyy-MM-dd')
  $e = $hist | Where-Object { $_.f -eq $f } | Select-Object -First 1
  if (-not $e -or $null -eq $e.$k) { return $null }
  return ([double]$d.nacional.$k - [double]$e.$k) * 100
}
function Cts($v) {
  if ($null -eq $v) { return 'sin datos aún' }
  $r = [math]::Round([double]$v, 1)
  if ($r -eq 0) { return 'igual' }
  $signo = if ($r -gt 0) { '+' } else { '−' }
  return $signo + (F ([math]::Abs($r)) 1) + ' cént.'
}

function Portada([string]$h) {
  $h = Dato $h 'hoy-g95' (F $d.nacional.g95)
  $h = Dato $h 'hoy-diesel' (F $d.nacional.diesel)
  $h = Dato $h 'hoy-fecha' $fechaCorta
  $h = Dato $h 'hoy-var95' (Cts (Dif 'g95' 1))
  $h = Dato $h 'hoy-vardiesel' (Cts (Dif 'diesel' 1))
  $h = Dato $h 'panel-g95' (F $d.nacional.g95)
  $h = Dato $h 'panel-diesel' (F $d.nacional.diesel)
  if ($d.luz) { $h = Dato $h 'panel-luz' (F $d.luz.media) }
  $nota = 'Medias de España del ' + ([string]$d.actualizado).Split(' ')[0] + '.'
  if ($d.luz -and $d.luz.min) { $hh = ([string]$d.luz.min.h).Split('-'); $nota += ' Hoy, la hora más barata de la tarifa regulada de luz es de ' + [int]$hh[0] + ' a ' + [int]$hh[1] + ' h.' }
  return Dato $h 'panel-nota' $nota
}

function Principal([string]$h) {
  $h = Dato $h 'fecha' ([string]$d.actualizado)
  $h = Dato $h 'estaciones' (([int]$d.estaciones).ToString('N0', $inv).Replace(',', '.'))
  foreach ($k in 'g95', 'diesel', 'g98', 'glp') { $h = Dato $h $k ((F $d.nacional.$k) + ' €') }
  $h = Dato $h 'dep95' ((F ([double]$d.nacional.g95 * 50) 2) + ' €')
  $h = Dato $h 'depdiesel' ((F ([double]$d.nacional.diesel * 50) 2) + ' €')
  foreach ($k in 'g95', 'diesel') {
    $h = Dato $h "ayer-$k" (Cts (Dif $k 1))
    $h = Dato $h "semana-$k" (Cts (Dif $k 7))
  }
  $orden = @($lista | Sort-Object { [double]$_.g95 })
  $li = { param($p) $n = Esc $p.nombre; $u = $provincias[[string]$p.id]; if ($u) { $n = '<a href="' + $u + '">' + $n + '</a>' }; '<li>' + $n + ': <strong>' + (F $p.g95) + ' €</strong></li>' }
  $h = Dato $h 'baratas' ((@($orden | Select-Object -First 5) | ForEach-Object { & $li $_ }) -join '')
  $caras = @($orden | Select-Object -Last 5); [array]::Reverse($caras)
  $h = Dato $h 'caras' (($caras | ForEach-Object { & $li $_ }) -join '')
  $filas = @()
  foreach ($p in ($lista | Sort-Object { $_.nombre })) {
    $n = Esc $p.nombre; $u = $provincias[[string]$p.id]; if ($u) { $n = '<a href="' + $u + '">' + $n + '</a>' }
    $filas += '<tr><td>' + $n + '</td><td>' + (F $p.g95) + '</td><td>' + (F $p.diesel) + '</td><td>' + (F $p.g98) + '</td><td>' + (F $p.glp) + '</td></tr>'
  }
  $h = Dato $h 'filas' ($filas -join '')
  $h = Descripcion $h ("Hoy, $($fechaCorta): gasolina 95 a $(F $d.nacional.g95) € y diésel a $(F $d.nacional.diesel) € de media en España. Precio por provincia y la gasolinera más barata, con datos oficiales.")
  return [regex]::Replace($h, '"dateModified":\s*"[\d-]+"', '"dateModified": "' + $d.fecha + '"')
}

function Provincia([string]$h, [string]$id) {
  $p = $lista | Where-Object { [string]$_.id -eq $id } | Select-Object -First 1
  if (-not $p) { throw "Sin datos de la provincia $id" }
  $x = $det.$id
  if (-not $x) { throw "Sin detalle de la provincia $id" }
  $h = Dato $h 'fecha' ([string]$d.actualizado)
  foreach ($k in 'g95', 'diesel', 'g98', 'glp') { $h = Dato $h $k ((F $p.$k) + ' €') }
  $h = Dato $h 'estaciones' ([string]$p.estaciones)
  $puesto = 1 + @($lista | Where-Object { [double]$_.g95 -lt [double]$p.g95 }).Count
  $dif = ([double]$p.g95 - [double]$d.nacional.g95) * 100
  $comp = if ([math]::Abs($dif) -lt 0.05) { 'en la media de España' } elseif ($dif -lt 0) { (F ([math]::Abs($dif)) 1) + ' céntimos por debajo de la media de España' } else { (F $dif 1) + ' céntimos por encima de la media de España' }
  $h = Dato $h 'comparacion' ("La gasolina 95 está hoy $comp. Es la provincia número $puesto de 52, contando desde la más barata.")
  $h = Dato $h 'dep95' ((F ([double]$p.g95 * 50) 2) + ' €')
  $h = Dato $h 'depdiesel' ((F ([double]$p.diesel * 50) 2) + ' €')
  foreach ($c in @(@('g95', 'tabla95', 'ahorro95'), @('diesel', 'tabladiesel', 'ahorrodiesel'))) {
    $filas = @(); foreach ($e in @($x.($c[0]))) { $filas += '<tr><td>' + (Esc ([string]$e.rotulo)) + '</td><td>' + (Esc (Nombre ([string]$e.direccion))) + ', ' + (Esc ([string]$e.municipio)) + '</td><td>' + (F $e.precio) + ' €</td></tr>' }
    $h = Dato $h $c[1] ($filas -join '')
    $primera = @($x.($c[0]))[0]
    $ahorro = if ($primera) { ([double]$p.($c[0]) - [double]$primera.precio) * 50 } else { 0 }
    $h = Dato $h $c[2] ((F $ahorro 2) + ' €')
  }
  $serie = @(); foreach ($e in $histP) { $v = $e.p.$id; if ($v) { $serie += [pscustomobject]@{ f = [string]$e.f; g95 = $v[0]; diesel = $v[1] } } }
  $h = Dato $h 'grafico' (Grafico $serie)
  $h = Descripcion $h ("Hoy en $($p.nombre): gasolina 95 a $(F $p.g95) € y diésel a $(F $p.diesel) € de media. Las gasolineras más baratas de la provincia y la evolución del precio, con datos oficiales.")
  return [regex]::Replace($h, '"dateModified":\s*"[\d-]+"', '"dateModified": "' + $d.fecha + '"')
}

# ---------- proceso ----------
New-Item -ItemType Directory -Force -Path $rutas.WebSalida | Out-Null
$archivos = @('index.html', 'precio-gasolina-hoy.html') + @($provincias.Values)
$idDe = @{}; foreach ($id in $provincias.Keys) { $idDe[$provincias[$id]] = $id }
$hechas = @(); $fallos = @()
foreach ($archivo in $archivos) {
  try {
    $ruta = Join-Path $rutas.WebEntrada $archivo
    if (-not (Test-Path -LiteralPath $ruta)) { throw 'no se ha podido descargar' }
    $antes = [IO.File]::ReadAllText($ruta, [Text.Encoding]::UTF8)
    if ($antes -notmatch '</html>\s*$') { throw 'la página descargada parece incompleta' }
    if ($archivo -eq 'index.html') { $despues = Portada $antes }
    elseif ($archivo -eq 'precio-gasolina-hoy.html') { $despues = Principal $antes }
    else { $despues = Provincia $antes $idDe[$archivo] }
    $ratio = $despues.Length / $antes.Length
    if ($ratio -lt 0.7 -or $ratio -gt 1.6) { throw "tamaño sospechoso (x$($ratio.ToString('0.00', $inv)))" }
    [IO.File]::WriteAllText((Join-Path $rutas.WebSalida $archivo), $despues, $utf8)
    $hechas += $archivo
    "OK  $archivo"
  } catch { $fallos += $archivo; Write-Warning "$archivo sin cambios: $($_.Exception.Message)" }
}

# ---------- sitemap: fecha real solo en lo que ha cambiado ----------
$sm = Join-Path $rutas.WebEntrada 'sitemap.xml'
if ((Test-Path -LiteralPath $sm) -and $hechas.Count) {
  $x = [IO.File]::ReadAllText($sm, [Text.Encoding]::UTF8)
  foreach ($archivo in $hechas) {
    $loc = if ($archivo -eq 'index.html') { $base } else { $base + $archivo }
    $x = [regex]::Replace($x, '(<loc>' + [regex]::Escape($loc) + '</loc>\s*<lastmod>)[^<]*(</lastmod>)', ('${1}' + $d.fecha + '${2}'))
  }
  if ($x -match '<loc>' -and $x -match '</urlset>\s*$') { [IO.File]::WriteAllText((Join-Path $rutas.WebSalida 'sitemap.xml'), $x, $utf8); 'OK  sitemap.xml' } else { $fallos += 'sitemap.xml' }
}
if ($fallos.Count) { Write-Output "::error::Páginas sin actualizar: $($fallos -join ', ')"; exit 1 }
