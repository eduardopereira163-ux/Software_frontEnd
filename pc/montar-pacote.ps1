# Monta a pasta ConecTorno-PC (e o .zip) para copiar no computador do professor.
# Roda na máquina de desenvolvimento, com internet, uma vez por versão. O PC do professor só recebe o resultado.
# Uso (PowerShell, na pasta do projeto):  powershell -ExecutionPolicy Bypass -File pc\montar-pacote.ps1
# Resultado: dist\ConecTorno-PC\  e  dist\ConecTorno-PC.zip
param(
    [string]$VersaoPython = '3.12.10'   # Python "embeddable" oficial: um zip, sem instalador
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # deixa os downloads bem mais rápidos no PowerShell 5
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$projeto = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $projeto 'dist'
$downloads = Join-Path $dist 'downloads'      # arquivos baixados ficam separados dos scripts
$pacote = Join-Path $dist 'ConecTorno-PC'
$zip = Join-Path $dist 'ConecTorno-PC.zip'

New-Item -ItemType Directory -Force $downloads | Out-Null
if (Test-Path $pacote) { Remove-Item -Recurse -Force $pacote }
New-Item -ItemType Directory -Force $pacote | Out-Null

function Baixar($url, $destino) {
    if (Test-Path $destino) { Write-Host "   (já baixado) $(Split-Path -Leaf $destino)"; return }
    Write-Host "   baixando $url"
    Invoke-WebRequest -Uri $url -OutFile $destino -UseBasicParsing
}

Write-Host "==> Python portátil $VersaoPython"
$pyZip = Join-Path $downloads "python-$VersaoPython-embed-amd64.zip"
Baixar "https://www.python.org/ftp/python/$VersaoPython/python-$VersaoPython-embed-amd64.zip" $pyZip
Expand-Archive -Path $pyZip -DestinationPath (Join-Path $pacote 'python')

Write-Host '==> Conversor de PDF (Poppler para Windows, portátil)'
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/oschwartz10612/poppler-windows/releases/latest' -UseBasicParsing
$arquivo = $release.assets | Where-Object { $_.name -like 'Release-*.zip' } | Select-Object -First 1
if (-not $arquivo) { throw 'Não achei o zip do Poppler na última versão do GitHub.' }
Write-Host "   versão $($release.tag_name)"
$popZip = Join-Path $downloads $arquivo.name
Baixar $arquivo.browser_download_url $popZip
Expand-Archive -Path $popZip -DestinationPath (Join-Path $pacote 'poppler')
$pdftoppm = Get-ChildItem -Path (Join-Path $pacote 'poppler') -Recurse -Filter 'pdftoppm.exe' | Select-Object -First 1
if (-not $pdftoppm) { throw 'pdftoppm.exe não veio no zip do Poppler.' }

Write-Host '==> Sistema ConecTorno'
Copy-Item -Recurse (Join-Path $projeto 'servidor') $pacote
Get-ChildItem -Path (Join-Path $pacote 'servidor') -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
Copy-Item -Recurse (Join-Path $projeto 'static') $pacote
foreach ($nome in 'Iniciar ConecTorno.bat', 'ligar-hotspot.ps1', 'LEIA-ME.txt') {
    Copy-Item (Join-Path $PSScriptRoot $nome) $pacote
}

Write-Host '==> Conferindo'
& (Join-Path $pacote 'python\python.exe') -c "import http.server, json, hashlib, secrets, uuid; print('   Python ok')"
& $pdftoppm.FullName -v 2>&1 | Select-Object -First 1 | ForEach-Object { Write-Host "   $_" }

Write-Host '==> Compactando'
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pacote '*') -DestinationPath $zip
$tamanho = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ""
Write-Host "Pronto: $zip ($tamanho MB)"
Write-Host 'Copie o zip para o PC do professor, extraia e abra "Iniciar ConecTorno".'
