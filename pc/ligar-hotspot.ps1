# Liga o Hotspot móvel do Windows sem precisar de administrador (mesma API do botão em Configurações).
# Chamado pelo "Iniciar ConecTorno.bat". Se não conseguir, só avisa: o professor pode ligar à mão.
$ErrorActionPreference = 'Stop'

function Manual {
    Write-Host '   Ligue à mão: Configurações > Rede e Internet > Hotspot móvel > Ativado.'
}

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    # Converte as operações assíncronas do Windows (WinRT) em tarefas que o PowerShell consegue esperar.
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    function Aguardar($operacao, [Type]$tipo) {
        $tarefa = $asTask.MakeGenericMethod($tipo).Invoke($null, @($operacao))
        $null = $tarefa.Wait(-1)
        $tarefa.Result
    }

    $perfil = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
    if (-not $perfil) {
        Write-Host '   AVISO: este computador está sem internet, e o Windows só liga o hotspot com uma conexão (cabo ou Wi-Fi).'
        Manual
        exit 2
    }
    $hotspot = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($perfil)
    $config = $hotspot.GetCurrentAccessPointConfiguration()

    # Estado: 1 = ligado, 2 = desligado, 3 = mudando.
    if ($hotspot.TetheringOperationalState -eq 1) {
        Write-Host "   Hotspot já estava ligado (rede ""$($config.Ssid)"")."
    } else {
        $resultado = Aguardar ($hotspot.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
        if ($resultado.Status -eq 0) {
            Write-Host "   Hotspot ligado (rede ""$($config.Ssid)"")."
        } else {
            Write-Host "   AVISO: o Windows não ligou o hotspot ($($resultado.Status) $($resultado.AdditionalErrorMessage))."
            Manual
            exit 1
        }
    }

    # O Raspberry Pi 3 só enxerga 2,4 GHz (Band: 0 = qualquer, 1 = 2,4 GHz, 2 = 5 GHz; só no Windows 11).
    try {
        if ($config.Band -ne 1) {
            Write-Host '   ATENÇÃO: escolha a banda 2,4 GHz em Hotspot móvel > Editar, senão o Raspberry pode não achar a rede.'
        }
    } catch { }
} catch {
    Write-Host "   AVISO: não consegui ligar o hotspot automaticamente ($($_.Exception.Message))."
    Manual
    exit 1
}
