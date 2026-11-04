# Libera o ConecTorno no Firewall do Windows, para os Raspberry e celulares acessarem este computador.
# Chamado pelo "Iniciar ConecTorno.bat" toda vez; só pede administrador quando ainda falta liberar.
# O que faz (como administrador): apaga os bloqueios que o Windows criou para o python.exe desta pasta
# e cria a regra "ConecTorno (servidor)" liberando a porta do sistema para esse python.exe.
param(
    [Parameter(Mandatory = $true)][string]$Programa,   # caminho do python\python.exe do pacote
    [int]$Porta = 8080,
    [switch]$Elevado,       # uso interno: já está rodando como administrador
    [switch]$SoVerificar    # só mostra a situação, sem pedir administrador nem alterar nada
)
$ErrorActionPreference = 'Stop'
$Programa = (Resolve-Path -LiteralPath $Programa).Path
$NomeRegra = 'ConecTorno (servidor)'

# Regras de entrada ligadas que valem para este python.exe (o Windows guarda o caminho em minúsculas).
function RegrasDoPrograma {
    Get-NetFirewallApplicationFilter | Where-Object { $_.Program -eq $Programa } |
        Get-NetFirewallRule | Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' }
}
function Situacao {
    $regras = @(RegrasDoPrograma)
    [pscustomobject]@{
        Bloqueios = @($regras | Where-Object Action -eq 'Block')
        # Qualquer regra que libere este python.exe serve (a do script ou uma criada à mão pelo TI).
        Liberado  = [bool]($regras | Where-Object Action -eq 'Allow')
    }
}
function Administrador {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
function AvisarTI {
    Write-Host '   Peça ao TI para abrir o "Iniciar ConecTorno" uma vez como administrador'
    Write-Host '   (botão direito > Executar como administrador): isso libera o firewall neste PC.'
}

try {
    $antes = Situacao
    if (-not $antes.Bloqueios.Count -and $antes.Liberado) {
        Write-Host '   Firewall já liberado para o ConecTorno.'
        exit 0
    }
    if ($SoVerificar) {
        Write-Host "   Firewall: $($antes.Bloqueios.Count) bloqueio(s); liberação do ConecTorno: $(if ($antes.Liberado) {'sim'} else {'não'})."
        exit 1
    }

    if ($Elevado -or (Administrador)) {
        # Como administrador: tira os bloqueios deste python.exe e cria a liberação.
        $antes.Bloqueios | Remove-NetFirewallRule
        Get-NetFirewallRule -DisplayName $NomeRegra -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        New-NetFirewallRule -DisplayName $NomeRegra -Description 'Raspberry e celulares acessam o ConecTorno neste PC.' `
            -Direction Inbound -Action Allow -Profile Any -Program $Programa -Protocol TCP -LocalPort $Porta | Out-Null
        Write-Host "   Firewall liberado para o ConecTorno (porta $Porta)."
        # Em PCs de domínio, a política da empresa pode mandar ignorar regras criadas no próprio PC.
        $ignora = Get-NetFirewallProfile -PolicyStore ActiveStore | Where-Object AllowLocalFirewallRules -eq 'False'
        if ($ignora) {
            Write-Host "   ATENÇÃO: a política da rede ($(($ignora.Name) -join ', ')) ignora regras locais;"
            Write-Host '   o TI precisa liberar o ConecTorno pela política do domínio.'
        }
        if ($Elevado) { Start-Sleep -Seconds 3 }   # dá tempo de ler a janela de administrador
        exit 0
    }

    # Sem administrador: pede uma vez (janela de "Deseja permitir...?" do Windows).
    Write-Host '   O Firewall do Windows está bloqueando os Raspberry. Pedindo permissão de administrador...'
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Programa `"$Programa`" -Porta $Porta -Elevado"
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -Verb RunAs -Wait
    } catch {
        Write-Host '   AVISO: a permissão de administrador não foi dada; os Raspberry não vão conseguir acessar este PC.'
        AvisarTI
        exit 1
    }
    $depois = Situacao
    if (-not $depois.Bloqueios.Count -and $depois.Liberado) {
        Write-Host '   Firewall liberado.'
        exit 0
    }
    Write-Host '   AVISO: o firewall continua bloqueando o ConecTorno.'
    AvisarTI
    exit 1
} catch {
    Write-Host "   AVISO: não consegui verificar o firewall ($($_.Exception.Message))."
    AvisarTI
    exit 1
}
