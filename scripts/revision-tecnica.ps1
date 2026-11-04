# Revisa la web publicada y genera un informe.
#   ERRORES: algo está roto. La tarea sale en rojo y GitHub avisa por correo.
#   AVISOS:  conviene mirarlo, pero no es urgente. Solo aparecen en el informe.
# No modifica nada en la web: solo la lee.
param([string]$Base = 'https://todocoches.org/')

$ErrorActionPreference = 'Stop'
$hostWeb = ([uri]$Base).Host
$errores = New-Object Collections.Generic.List[string]
$avisos = New-Object Collections.Generic.List[string]
$inicio = Get-Date

function Pedir([string]$url, [string]$metodo = 'GET', [bool]$sinDescomprimir = $false) {
  for ($intento = 1; $intento -le 2; $intento++) {
    $res = [pscustomobject]@{ Status = 0; Location = ''; Encoding = ''; Text = ''; Ms = 0; Error = '' }
    $crono = [Diagnostics.Stopwatch]::StartNew()
    $r = $null
    try {
      $q = [Net.HttpWebRequest]::Create($url)
      $q.Method = $metodo
      $q.AllowAutoRedirect = $false
      $q.Timeout = 30000
      $q.ReadWriteTimeout = 30000
      $q.UserAgent = 'TodocochesRevision/1.0'
      if ($sinDescomprimir) { $q.Headers['Accept-Encoding'] = 'gzip' } else { $q.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate }
      try { $r = $q.GetResponse() } catch [Net.WebException] { if ($_.Exception.Response) { $r = $_.Exception.Response } else { throw } }
      $res.Status = [int]$r.StatusCode
      $res.Location = [string]$r.Headers['Location']
      $res.Encoding = [string]$r.Headers['Content-Encoding']
      if ($metodo -eq 'GET' -and -not $sinDescomprimir) {
        $ms = New-Object IO.MemoryStream
        $r.GetResponseStream().CopyTo($ms)
        $res.Text = [Text.Encoding]::UTF8.GetString($ms.ToArray())
      }
    } catch {
      $res.Error = $_.Exception.Message
    } finally {
      if ($r) { $r.Close() }
      $crono.Stop(); $res.Ms = $crono.ElapsedMilliseconds
    }
    if ($res.Status -ne 0 -and $res.Status -lt 500) { return $res }
    if ($intento -eq 1) { Start-Sleep -Seconds 3 }
  }
  return $res
}
function Comprobar-Redireccion([string]$desde, [string]$hacia) {
  $x = Pedir $desde
  if ($x.Status -ne 301 -or $x.Location.TrimEnd('/') -ne $hacia.TrimEnd('/')) { $errores.Add("Redirección incorrecta: $desde devuelve $($x.Status) hacia '$($x.Location)'; debería ser 301 a $hacia") }
}
function Corto([string]$url) { return $url.Replace($Base, '/') }

# ---------- sitio en general ----------
$portada = Pedir $Base
if ($portada.Status -ne 200) { $errores.Add("La portada responde $($portada.Status) $($portada.Error)") }
elseif ($portada.Ms -gt 3000) { $avisos.Add("La portada ha tardado $($portada.Ms) ms en responder") }

Comprobar-Redireccion "http://$hostWeb/" $Base
Comprobar-Redireccion "https://www.$hostWeb/" $Base

$no = Pedir ($Base + 'pagina-que-no-existe-revision.html')
if ($no.Status -ne 404) { $errores.Add("Una página inexistente responde $($no.Status) en lugar de 404") }

$git = Pedir ($Base + '.git/HEAD')
if ($git.Status -eq 200) { $errores.Add('La carpeta .git está publicada en la web: hay que borrarla del servidor cuanto antes') }

$z = Pedir $Base 'GET' $true
if ($z.Encoding -notmatch 'gzip|br') { $avisos.Add('La compresión de la web no está activa') }

$robots = Pedir ($Base + 'robots.txt')
if ($robots.Status -ne 200) { $errores.Add("robots.txt responde $($robots.Status)") }
else {
  if ($robots.Text -match '(?im)^\s*Disallow:\s*/\s*$') { $errores.Add('robots.txt está bloqueando toda la web') }
  if ($robots.Text -notmatch '(?i)Sitemap:') { $avisos.Add('robots.txt no indica el sitemap') }
}
$ads = Pedir ($Base + 'ads.txt')
if ($ads.Status -ne 200 -or $ads.Text -notmatch 'pub-6927420652429339') { $errores.Add("ads.txt no responde bien o no contiene tu identificador de AdSense (estado $($ads.Status))") }

# certificado HTTPS
try {
  $tcp = New-Object Net.Sockets.TcpClient($hostWeb, 443)
  $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false)
  $ssl.AuthenticateAsClient($hostWeb)
  $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
  $dias = [int]($cert.NotAfter - (Get-Date)).TotalDays
  $ssl.Close(); $tcp.Close()
  if ($dias -lt 7) { $errores.Add("El certificado HTTPS caduca en $dias días") }
  elseif ($dias -lt 21) { $avisos.Add("El certificado HTTPS caduca en $dias días") }
} catch { $errores.Add("No se puede comprobar el certificado HTTPS: $($_.Exception.Message)") }

# precios del día
$pr = Pedir ($Base + 'precios.json')
if ($pr.Status -ne 200) { $errores.Add("precios.json responde $($pr.Status)") }
else {
  try {
    $dp = $pr.Text | ConvertFrom-Json
    $edad = ((Get-Date).Date - [datetime]::ParseExact([string]$dp.fecha, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).Days
    if ($edad -gt 2) { $errores.Add("Los precios llevan $edad días sin actualizarse (último dato: $($dp.fecha))") }
    if (-not $dp.luz) { $avisos.Add('precios.json no incluye el precio de la luz') }
    else {
      $edadLuz = ((Get-Date).Date - [datetime]::ParseExact([string]$dp.luz.fecha, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).Days
      if ($edadLuz -gt 2) { $avisos.Add("El precio de la luz lleva $edadLuz días sin actualizarse (último dato: $($dp.luz.fecha))") }
    }
  } catch { $errores.Add("precios.json no se puede leer: $($_.Exception.Message)") }
}

$pag = Pedir ($Base + 'precio-gasolina-hoy.html')
if ($pag.Status -eq 200) {
  $mf = [regex]::Match($pag.Text, '<!--dato:fecha-->(\d\d/\d\d/\d{4})')
  if (-not $mf.Success) { $avisos.Add('La página de precios no lleva la fecha escrita en el HTML') }
  else {
    $edadHtml = ((Get-Date).Date - [datetime]::ParseExact($mf.Groups[1].Value, 'dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture)).Days
    if ($edadHtml -gt 2) { $errores.Add("La página de precios lleva $edadHtml días sin reescribirse") }
  }
}

# ---------- sitemap ----------
$sm = Pedir ($Base + 'sitemap.xml')
if ($sm.Status -ne 200) { throw "sitemap.xml responde $($sm.Status): no se puede continuar" }
$paginas = @([regex]::Matches($sm.Text, '<loc>\s*([^<\s]+)\s*</loc>') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
if ($paginas.Count -lt 100) { $errores.Add("El sitemap solo tiene $($paginas.Count) páginas") }

# ---------- cada página del sitemap ----------
$enSitemap = @{}; foreach ($p in $paginas) { $enSitemap[$p] = 1 }
$titulos = @{}
$destinos = @{}
$largos = 0; $descLargas = 0
foreach ($url in $paginas) {
  $x = Pedir $url
  $c = Corto $url
  if ($x.Status -ne 200) { $errores.Add("Página del sitemap no disponible: $c responde $($x.Status) $($x.Error)"); continue }
  $h = $x.Text
  if ($h -match '<meta[^>]+name="robots"[^>]+noindex') { $errores.Add("Página del sitemap con noindex: $c") }

  $can = [regex]::Match($h, '<link[^>]+rel="canonical"[^>]+href="([^"]*)"').Groups[1].Value
  if (-not $can) { $errores.Add("Sin canonical: $c") } elseif ($can -ne $url) { $errores.Add("Canonical distinta en ${c}: $can") }

  $ti = [regex]::Match($h, '(?is)<title>(.*?)</title>').Groups[1].Value.Trim()
  if (-not $ti) { $errores.Add("Sin título: $c") } else { if (-not $titulos.ContainsKey($ti)) { $titulos[$ti] = @() }; $titulos[$ti] += $c; if ($ti.Length -gt 65) { $largos++ } }

  $de = [regex]::Match($h, '<meta\s+name="description"\s+content="([^"]*)"')
  if (-not $de.Success -or -not $de.Groups[1].Value) { $errores.Add("Sin descripción: $c") } elseif ($de.Groups[1].Value.Length -gt 165) { $descLargas++ }

  $h1 = ([regex]::Matches($h, '(?i)<h1[\s>]')).Count
  if ($h1 -ne 1) { $avisos.Add("${c} tiene $h1 títulos H1") }

  if ($h -notmatch 'google-adsense-account') { $avisos.Add("${c} no lleva la etiqueta de AdSense") }
  if ($h -notmatch 'data-framework="TCFv2\.2"') { $avisos.Add("${c} no lleva Cookiebot con TCF") }

  foreach ($m in [regex]::Matches($h, '(?is)<script[^>]+application/ld\+json[^>]*>(.*?)</script>')) {
    try { $null = $m.Groups[1].Value | ConvertFrom-Json } catch { $errores.Add("Datos estructurados (JSON-LD) no válidos en $c") }
  }

  # enlaces y recursos internos; se ignora el JavaScript porque contiene plantillas, no enlaces reales
  $limpio = [regex]::Replace($h, '(?is)<!--.*?-->', '')
  $limpio = [regex]::Replace($limpio, '(?is)<script\b(?![^>]*\bsrc=)[^>]*>.*?</script>', '')
  $refs = @()
  foreach ($m in [regex]::Matches($limpio, '(?i)<(?:a|link|img|script|source)\b[^>]*?\b(?:href|src)\s*=\s*"([^"]+)"')) { $refs += $m.Groups[1].Value }
  foreach ($m in [regex]::Matches($limpio, '(?i)<meta[^>]+(?:og:image|twitter:image)"[^>]+content="([^"]+)"')) { $refs += $m.Groups[1].Value }
  foreach ($ref in $refs) {
    $ref = [Net.WebUtility]::HtmlDecode($ref).Trim()
    if ($ref -match '^(mailto:|tel:|javascript:|data:|#)') { continue }
    try { $abs = New-Object Uri((New-Object Uri($url)), $ref) } catch { $errores.Add("Enlace mal escrito en ${c}: $ref"); continue }
    if ($abs.Host -ne $hostWeb) { continue }
    $dest = $abs.GetLeftPart([UriPartial]::Path)
    if (-not $destinos.ContainsKey($dest)) { $destinos[$dest] = New-Object Collections.Generic.List[string] }
    if (-not $destinos[$dest].Contains($c)) { $destinos[$dest].Add($c) }
  }
}
foreach ($t in $titulos.Keys) { if ($titulos[$t].Count -gt 1) { $avisos.Add("Título repetido en $($titulos[$t] -join ', '): $t") } }
if ($largos) { $avisos.Add("$largos páginas con el título demasiado largo (más de 65 caracteres)") }
if ($descLargas) { $avisos.Add("$descLargas páginas con la descripción demasiado larga (más de 165 caracteres)") }

# ---------- destinos internos ----------
$rotos = 0
foreach ($dest in $destinos.Keys) {
  if ($enSitemap.ContainsKey($dest)) { continue }
  $esHtml = $dest -match '\.html$'
  $metodo = 'HEAD'; if ($esHtml) { $metodo = 'GET' }
  $x = Pedir $dest $metodo
  if ($x.Status -in 403, 405, 501) { $x = Pedir $dest }
  $origen = $destinos[$dest]
  $donde = $origen[0]; if ($origen.Count -gt 1) { $donde += " y $($origen.Count - 1) más" }
  if ($x.Status -ge 300 -and $x.Status -lt 400) { $avisos.Add("Enlace que redirige: $(Corto $dest) (en $donde)") }
  elseif ($x.Status -ne 200) { $rotos++; $errores.Add("Enlace o archivo roto: $(Corto $dest) responde $($x.Status) (en $donde)") }
  elseif ($esHtml) {
    if ($x.Text -match '<meta[^>]+name="robots"[^>]+noindex') { $avisos.Add("Una página indexable enlaza a una con noindex: $(Corto $dest) (en $donde)") }
    else {
      $canDest = [regex]::Match($x.Text, '<link[^>]+rel="canonical"[^>]+href="([^"]*)"').Groups[1].Value
      if (-not $enSitemap.ContainsKey($canDest)) { $avisos.Add("Página sin incluir en el sitemap: $(Corto $dest) (en $donde)") }
    }
  }
}

# ---------- informe ----------
$min = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)
$inf = New-Object Collections.Generic.List[string]
if ($errores.Count -eq 1) { $inf.Add('# Revisión técnica: 1 error') } elseif ($errores.Count) { $inf.Add("# Revisión técnica: $($errores.Count) errores") } else { $inf.Add('# Revisión técnica: todo correcto') }
$inf.Add('')
$inf.Add("Revisadas **$($paginas.Count) páginas** y **$($destinos.Count) enlaces y archivos internos** en $min minutos. Errores: **$($errores.Count)**. Avisos: **$($avisos.Count)**.")
$inf.Add('')
$inf.Add('Los enlaces a otras webs no se revisan, porque muchas bloquean las comprobaciones automáticas y darían falsas alarmas.')
if ($errores.Count) { $inf.Add(''); $inf.Add('## Errores'); $inf.Add(''); $errores | Sort-Object | ForEach-Object { $inf.Add("- $_") } }
if ($avisos.Count) { $inf.Add(''); $inf.Add('## Avisos'); $inf.Add(''); $avisos | Sort-Object | ForEach-Object { $inf.Add("- $_") } }
$texto = $inf -join "`n"
Write-Output $texto
if ($env:GITHUB_STEP_SUMMARY) { [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $texto + "`n", (New-Object Text.UTF8Encoding($false))) }
if ($errores.Count) { exit 1 }
