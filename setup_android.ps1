# ==============================================================================
# ANDROID SETUP v4.1 - ENTERPRISE EDITION
# Taskbar & SecondScreen + Otimizacoes Avancadas para Carlink/Android Auto
# Para uso profissional em centrais multimidia (Geely EX2, etc.)
# ==============================================================================

$ErrorActionPreference = "SilentlyContinue"
$Host.UI.RawUI.WindowTitle = "Android Setup v5.3 - AI Enhanced Edition"
$ScriptVersion = "5.3"

# ------------------------------------------------------------------------------
# CONFIGURACOES GLOBAIS
# ------------------------------------------------------------------------------
$BackupFolder = "$env:USERPROFILE\Documents\AndroidBackups"
$ApkFolder = "$PSScriptRoot\apks"
$LogFile = "$PSScriptRoot\setup_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Apps removidos para possivel restauracao
$script:RemovedApps = @()

# Informacoes do dispositivo (global para uso em funcoes)
$script:DeviceSDK = 0

# ------------------------------------------------------------------------------
# FUNCOES DE LOG E STATUS
# ------------------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    $colors = @{ "Info" = "Cyan"; "Success" = "Green"; "Warning" = "Yellow"; "Error" = "Red" }
    $prefix = @{ "Info" = "[>]"; "Success" = "[OK]"; "Warning" = "[!]"; "Error" = "[X]" }
    Write-Host "$($prefix[$Type]) $Message" -ForegroundColor $colors[$Type]
    Write-Log "[$Type] $Message"
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Log "=== $Title ==="
}

function Write-XiaomiWarning {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Yellow
    Write-Host "  [!] AVISO IMPORTANTE PARA XIAOMI/POCO/REDMI (HyperOS/MIUI)" -ForegroundColor Yellow
    Write-Host "  ============================================================" -ForegroundColor Yellow
    Write-Host "  Para que comandos como 'wm density' e 'settings put'" -ForegroundColor White
    Write-Host "  funcionem corretamente, voce DEVE ativar:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Configuracoes > Opcoes do Desenvolvedor >" -ForegroundColor Cyan
    Write-Host "  'Depuracao USB (Configuracoes de Seguranca)'" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Sem isso, o ADB retornara 'Permission Denied'." -ForegroundColor DarkGray
    Write-Host "  ============================================================" -ForegroundColor Yellow
    Write-Host ""
}

# ------------------------------------------------------------------------------
# FUNCOES DE ADB E CONEXAO
# ------------------------------------------------------------------------------

function Get-AdbPath {
    $sysAdb = Get-Command "adb" -ErrorAction SilentlyContinue
    if ($sysAdb) { return $sysAdb.Source }
    
    $tempAdb = "$env:TEMP\platform-tools\adb.exe"
    if (Test-Path $tempAdb) { return $tempAdb }
    
    $commonPaths = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe",
        "C:\platform-tools\adb.exe"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Install-Adb {
    Write-Status "ADB nao encontrado. Baixando Android Platform Tools..." "Warning"
    $url = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
    $zipPath = "$env:TEMP\platform-tools.zip"
    $destPath = "$env:TEMP"
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $destPath -Force
        Remove-Item $zipPath -ErrorAction SilentlyContinue
        Write-Status "ADB instalado em: $destPath\platform-tools" "Success"
        return "$destPath\platform-tools\adb.exe"
    }
    catch {
        Write-Status "Falha ao baixar ADB: $_" "Error"
        exit 1
    }
}

function Wait-ForDevice {
    param([string]$AdbPath, [int]$MaxAttempts = 30)
    
    Write-Status "Aguardando dispositivo Android..." "Info"
    Write-Host "   Conecte seu celular via USB e aceite a depuracao." -ForegroundColor DarkGray
    
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $devicesOutput = & $AdbPath devices 2>$null
        
        # Verificar se esta unauthorized (pendente de autorizacao)
        $unauthorized = $devicesOutput | Select-String -Pattern "\tunauthorized$"
        if ($unauthorized) {
            Write-Host ""
            Write-Status "Dispositivo detectado, mas NAO AUTORIZADO!" "Warning"
            Write-Host "   >>> Verifique a tela do celular e toque em 'PERMITIR' <<<" -ForegroundColor Yellow
            Write-Host "   >>> Marque 'Sempre permitir deste computador' <<<" -ForegroundColor Yellow
            Write-Host ""
            Start-Sleep -Seconds 3
            continue
        }
        
        # Verificar se esta autorizado
        $authorized = $devicesOutput | Select-String -Pattern "\tdevice$"
        if ($authorized) {
            $deviceId = ($authorized -split "`t")[0]
            Write-Status "Dispositivo conectado e autorizado: $deviceId" "Success"
            Write-Log "Device ID: $deviceId"
            
            # MELHORIA V4.1: Aguardar dispositivo estar realmente pronto (HyperOS fix)
            Write-Host "   Aguardando sistema estar pronto..." -NoNewline -ForegroundColor DarkGray
            & $AdbPath wait-for-device 2>$null
            Start-Sleep -Milliseconds 500
            Write-Host " OK" -ForegroundColor Green
            
            return $true
        }
        
        Write-Host "`r   Tentativa $i/$MaxAttempts... (Ctrl+C para cancelar)" -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
    }
    Write-Host ""
    Write-Status "Timeout: Nenhum dispositivo detectado." "Error"
    return $false
}

function Get-DeviceInfo {
    param([string]$AdbPath)
    
    # Garantir que o dispositivo esta pronto antes de consultar
    & $AdbPath wait-for-device 2>$null
    
    $info = @{
        Brand        = (& $AdbPath shell getprop ro.product.brand 2>$null).Trim().ToLower()
        Model        = (& $AdbPath shell getprop ro.product.model 2>$null).Trim()
        Android      = (& $AdbPath shell getprop ro.build.version.release 2>$null).Trim()
        SDK          = (& $AdbPath shell getprop ro.build.version.sdk 2>$null).Trim()
        Manufacturer = (& $AdbPath shell getprop ro.product.manufacturer 2>$null).Trim().ToLower()
        Device       = (& $AdbPath shell getprop ro.product.device 2>$null).Trim()
    }
    
    # Armazenar SDK globalmente para verificacoes
    $script:DeviceSDK = [int]$info.SDK
    
    Write-Log "Device Info: Brand=$($info.Brand), Model=$($info.Model), Android=$($info.Android), SDK=$($info.SDK)"
    return $info
}

function Get-InstalledApps {
    param([string]$AdbPath)
    
    $appDefinitions = @{
        "Taskbar"      = @("com.farmerbb.taskbar", "com.farmerbb.taskbar.paid", "com.geeforce.taskbar")
        "SecondScreen" = @("com.farmerbb.secondscreen.free", "com.farmerbb.secondscreen", "com.advasoft.secondscreen")
        "Shizuku"      = @("moe.shizuku.privileged.api")
    }
    
    $installedPackages = & $AdbPath shell pm list packages 2>$null
    $foundApps = @()
    
    foreach ($appName in $appDefinitions.Keys) {
        foreach ($pkg in $appDefinitions[$appName]) {
            if ($installedPackages -match $pkg) {
                $foundApps += @{ Name = $appName; Package = $pkg }
                break
            }
        }
    }
    return $foundApps
}

function Grant-Permission {
    param([string]$AdbPath, [string]$Package, [string]$Permission)
    $result = & $AdbPath shell pm grant $Package $Permission 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Enable-FreeformMode {
    param([string]$AdbPath)
    & $AdbPath shell settings put global enable_freeform_support 1 2>$null
    & $AdbPath shell settings put global force_resizable_activities 1 2>$null
    return $true
}

function Get-CurrentDpi {
    param([string]$AdbPath)
    # No Android 15, a saída do 'wm density' pode variar. Usamos um regex mais flexível.
    $density = & $AdbPath shell wm density 2>$null
    if ($density -match "(\d+)") { return $Matches[1] }
    return "Não detectado (verifique as Opções de Desenvolvedor)"
}

function Set-Dpi {
    param([string]$AdbPath, [int]$Dpi)
    & $AdbPath shell wm density $Dpi 2>$null
    Write-Log "DPI set to $Dpi"
}

# ------------------------------------------------------------------------------
# FUNCOES ENTERPRISE - PERSISTENCIA E OTIMIZACAO
# ------------------------------------------------------------------------------

function Add-BatteryWhitelist {
    param([string]$AdbPath, [string]$Package)
    # Adiciona app a whitelist de economia de bateria (impede suspensao)
    & $AdbPath shell dumpsys deviceidle whitelist +$Package 2>$null
    & $AdbPath shell cmd appops set $Package RUN_IN_BACKGROUND allow 2>$null
    & $AdbPath shell cmd appops set $Package RUN_ANY_IN_BACKGROUND allow 2>$null
}

function Start-Shizuku {
    param([string]$AdbPath)
    
    Write-Section "INICIALIZACAO DO SHIZUKU"
    
    # Verificar se Shizuku esta instalado
    $shizukuInstalled = & $AdbPath shell pm list packages 2>$null | Select-String "moe.shizuku.privileged.api"
    
    if (-not $shizukuInstalled) {
        Write-Status "Shizuku nao esta instalado. Pulando..." "Info"
        return $false
    }
    
    Write-Host "   -> Iniciando servico Shizuku via ADB..." -NoNewline
    
    # Tentar iniciar Shizuku (varios metodos)
    & $AdbPath shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh 2>$null
    & $AdbPath shell sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/files/start.sh 2>$null
    
    Write-Host " [OK]" -ForegroundColor Green
    Write-Status "Shizuku iniciado! Abra o app para verificar o status." "Success"
    return $true
}

function Set-NightMode {
    param([string]$AdbPath, [int]$Mode)
    # 0 = Auto, 1 = Off (Claro), 2 = On (Escuro)
    & $AdbPath shell settings put secure ui_night_mode $Mode 2>$null
    Write-Log "Night mode set to $Mode"
}

function Set-Overscan {
    param([string]$AdbPath, [int]$Left, [int]$Top, [int]$Right, [int]$Bottom)
    
    # MELHORIA V4.1: Verificar SDK antes de executar (removido no Android 11+)
    if ($script:DeviceSDK -ge 30) {
        Write-Status "Overscan NAO suportado em Android 11+ (SDK $script:DeviceSDK)" "Warning"
        Write-Host "   Alternativa: Ajuste o DPI ou configure na propria central Carlink." -ForegroundColor DarkGray
        return $false
    }
    
    & $AdbPath shell wm overscan $Left, $Top, $Right, $Bottom 2>$null
    Write-Log "Overscan set to $Left,$Top,$Right,$Bottom"
    return $true
}

function Reset-Overscan {
    param([string]$AdbPath)
    
    if ($script:DeviceSDK -ge 30) {
        Write-Status "Overscan NAO suportado em Android 11+ (SDK $script:DeviceSDK)" "Warning"
        return $false
    }
    
    & $AdbPath shell wm overscan reset 2>$null
    return $true
}

# ------------------------------------------------------------------------------
# FUNCOES CARLINK - V4.1
# ------------------------------------------------------------------------------

function Fix-CarlinkPrompt {
    param([string]$AdbPath)
    Write-Section "CORRECAO: PROMPT DE ESPELHAMENTO CARLINK"
    
    # Lista de pacotes que NUNCA sao Carlink (Blacklist)
    $blackList = "linkedin|steam|tplink|bridge|wallpaper|system|camera"
    
    $allInstalled = & $AdbPath shell pm list packages 2>$null
    $foundPackages = @()

    # Busca apenas candidatos provaveis
    $candidates = $allInstalled | Select-String -Pattern "link|zlink" | Where-Object { $_ -notmatch $blackList }

    foreach ($line in $candidates) {
        $cleanPkg = $line.ToString().Replace("package:", "").Trim()
        $foundPackages += $cleanPkg
    }

    if ($foundPackages.Count -gt 0) {
        $foundPackages = $foundPackages | Select-Object -Unique
        foreach ($pkg in $foundPackages) {
            Write-Host "   -> Aplicando fix no pacote identificado: $pkg" -NoNewline
            & $AdbPath shell appops set $pkg PROJECT_MEDIA allow 2>$null
            & $AdbPath shell appops set $pkg SYSTEM_ALERT_WINDOW allow 2>$null
            Add-BatteryWhitelist -AdbPath $AdbPath -Package $pkg
            Write-Host " [OK]" -ForegroundColor Green
        }
    }
    else {
        Write-Status "Nenhum pacote Carlink detectado automaticamente." "Warning"
    }
}

function Reset-Carlink {
    param([string]$AdbPath)
    
    Write-Section "RESET DO CARLINK"
    Write-Host "   Util quando a conexao trava ou o espelhamento para de funcionar." -ForegroundColor Yellow
    
    $carlinkPackages = @(
        "com.zjinnova.zlink",
        "com.zjinnova.zlinka",
        "com.syu.carlink",
        "com.lincofun.carlinkPlay",
        "com.autokit.autokit"
    )
    
    $installedPackages = & $AdbPath shell pm list packages 2>$null
    $found = $false
    
    foreach ($pkg in $carlinkPackages) {
        if ($installedPackages -match $pkg) {
            Write-Host "   -> Resetando $pkg..." -NoNewline
            
            # Forcar parada do app
            & $AdbPath shell am force-stop $pkg 2>$null
            
            # Limpar cache (nao dados!)
            & $AdbPath shell pm clear --cache-only $pkg 2>$null
            
            Write-Host " [OK]" -ForegroundColor Green
            $found = $true
        }
    }
    
    if ($found) {
        Write-Status "Carlink resetado. Reconecte o cabo USB no carro." "Success"
    }
    else {
        Write-Status "Nenhum app Carlink encontrado." "Warning"
    }
}

# ------------------------------------------------------------------------------
# FUNCOES DE OTIMIZACAO POR MARCA
# ------------------------------------------------------------------------------

function Optimize-Xiaomi {
    param([string]$AdbPath)
    Write-Section "OTIMIZACOES XIAOMI/POCO/REDMI (HyperOS/MIUI)"
    
    $appsToRemove = @("com.miui.msa.global", "com.miui.analytics", "com.xiaomi.joyose", "com.xiaomi.daemon")
    
    Write-Host "   -> Removendo telemetria e anuncios..." -NoNewline
    foreach ($app in $appsToRemove) {
        # Tenta desinstalar e joga qualquer erro para o "lixo" ($null)
        & $AdbPath shell pm uninstall -k --user 0 $app > $null 2>&1
    }
    Write-Host " [OK ou JA REMOVIDO]" -ForegroundColor Green

    # Restante das otimizacoes (Animacoes e Refresh Rate)
    & $AdbPath shell settings put global window_animation_scale 0.5 2>$null
    & $AdbPath shell settings put global transition_animation_scale 0.5 2>$null
    & $AdbPath shell settings put global animator_duration_scale 0.5 2>$null
    
    # Refresh Rate (120Hz)
    & $AdbPath shell settings put system peak_refresh_rate 120.0 2>$null
    & $AdbPath shell settings put system min_refresh_rate 120.0 2>$null
    & $AdbPath shell settings put system user_refresh_rate 120 2>$null
    
    Write-Host "   -> Otimizacoes de interface aplicadas (120Hz + 0.5x)." -ForegroundColor Green
}

function Toggle-MiuiOptimization {
    param([string]$AdbPath, [bool]$Disable)
    
    Write-Section "MIUI OPTIMIZATION TOGGLE"
    
    if ($Disable) {
        Write-Host "   [!] AVISO: Desativar MIUI Optimization pode:" -ForegroundColor Yellow
        Write-Host "       - Resetar permissoes de alguns apps" -ForegroundColor DarkGray
        Write-Host "       - Causar bugs em janelas flutuantes nativas" -ForegroundColor DarkGray
        Write-Host "       - Afetar o comportamento do sistema" -ForegroundColor DarkGray
        
        $confirm = Read-Host "   Deseja continuar? (S/N)"
        if ($confirm -notmatch "^[Ss]") {
            Write-Status "Operacao cancelada." "Info"
            return
        }
        
        & $AdbPath shell settings put global miui_optimization_disable 1 2>$null
        Write-Status "MIUI Optimization DESATIVADA. Reinicie o celular." "Success"
    }
    else {
        & $AdbPath shell settings put global miui_optimization_disable 0 2>$null
        Write-Status "MIUI Optimization REATIVADA. Reinicie o celular." "Success"
    }
}

function Optimize-Samsung {
    param([string]$AdbPath)
    
    Write-Section "OTIMIZACOES SAMSUNG (One UI)"
    
    # Multi-window
    Write-Host "   -> Habilitando multi-janela avancada..." -NoNewline
    & $AdbPath shell settings put global enable_freeform_support 1 2>$null
    & $AdbPath shell settings put global multi_window_menu_column_count 3 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    # Sensibilidade de toque
    Write-Host "   -> Aumentando sensibilidade do toque..." -NoNewline
    & $AdbPath shell settings put system touch_sensitivity_mode 1 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    # Desativar GOS (Game Optimizing Service)
    Write-Host "   -> Desativando throttling termico (GOS)..." -NoNewline
    & $AdbPath shell pm uninstall -k --user 0 com.samsung.android.game.gos 2>$null
    & $AdbPath shell pm uninstall -k --user 0 com.samsung.android.game.gametools 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    # DeX otimizacoes
    Write-Host "   -> Configurando DeX para alta resolucao..." -NoNewline
    & $AdbPath shell settings put global desktop_mode_auto_enter 1 2>$null
    Write-Host " [OK]" -ForegroundColor Green
}

function Optimize-Generic {
    param([string]$AdbPath)
    
    Write-Section "OTIMIZACOES GENERICAS"
    
    Write-Host "   -> Otimizando velocidade de animacoes..." -NoNewline
    & $AdbPath shell settings put global window_animation_scale 0.5 2>$null
    & $AdbPath shell settings put global transition_animation_scale 0.5 2>$null
    & $AdbPath shell settings put global animator_duration_scale 0.5 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    # Limpar buffer de logs
    Write-Host "   -> Limpando buffer de logs..." -NoNewline
    & $AdbPath shell logcat -c 2>$null
    Write-Host " [OK]" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# FUNCOES DE DEBLOAT E RESTAURACAO
# ------------------------------------------------------------------------------

function Get-AllBloatApps {
    param([string]$Brand)
    
    $bloatApps = @()
    
    # Apps universais
    $universal = @(
        @{ Name = "Facebook Services"; Pkg = "com.facebook.services" },
        @{ Name = "Facebook App Manager"; Pkg = "com.facebook.appmanager" },
        @{ Name = "Facebook Installer"; Pkg = "com.facebook.system" },
        @{ Name = "LinkedIn"; Pkg = "com.linkedin.android" },
        @{ Name = "Netflix (pre-instalado)"; Pkg = "com.netflix.partner.activation" },
        @{ Name = "Spotify (pre-instalado)"; Pkg = "com.spotify.music" }
    )
    $bloatApps += $universal
    
    # Xiaomi-specific
    if ($Brand -match "xiaomi|poco|redmi") {
        $miuiBloat = @(
            @{ Name = "Mi Browser"; Pkg = "com.mi.globalbrowser" },
            @{ Name = "Mi Video"; Pkg = "com.miui.videoplayer" },
            @{ Name = "Mi Music"; Pkg = "com.miui.player" },
            @{ Name = "GetApps (Mi Store)"; Pkg = "com.xiaomi.mipicks" },
            @{ Name = "ShareMe"; Pkg = "com.xiaomi.midrop" },
            @{ Name = "Mi AI"; Pkg = "com.miui.voiceassist" },
            @{ Name = "Joyose (Ads)"; Pkg = "com.xiaomi.joyose" },
            @{ Name = "MSA (Ads)"; Pkg = "com.miui.msa.global" },
            @{ Name = "Analytics"; Pkg = "com.miui.analytics" }
        )
        $bloatApps += $miuiBloat
    }
    
    # Samsung-specific
    if ($Brand -eq "samsung") {
        $samsungBloat = @(
            @{ Name = "Bixby Voice"; Pkg = "com.samsung.android.bixby.agent" },
            @{ Name = "Bixby Routines"; Pkg = "com.samsung.android.app.routines" },
            @{ Name = "Bixby Vision"; Pkg = "com.samsung.android.visionintelligence" },
            @{ Name = "Samsung Free"; Pkg = "com.samsung.android.app.spage" },
            @{ Name = "Samsung Pay"; Pkg = "com.samsung.android.spay" },
            @{ Name = "AR Zone"; Pkg = "com.samsung.android.arzone" },
            @{ Name = "Game Optimizer"; Pkg = "com.samsung.android.game.gos" }
        )
        $bloatApps += $samsungBloat
    }
    
    return $bloatApps
}

function Show-DebloatMenu {
    param([string]$AdbPath, [string]$Brand)
    
    Write-Section "REMOCAO DE BLOATWARE (SEGURO)"
    Write-Host "   Apps serao desativados apenas para seu usuario." -ForegroundColor DarkGray
    Write-Host "   Use a opcao 'Restaurar Apps' no menu para recuperar." -ForegroundColor DarkGray
    
    $bloatApps = Get-AllBloatApps -Brand $Brand
    
    Write-Host "`n   Apps disponiveis para remocao:"
    for ($i = 0; $i -lt $bloatApps.Count; $i++) {
        Write-Host "     $($i+1). $($bloatApps[$i].Name)"
    }
    Write-Host "     A. Remover TODOS"
    Write-Host "     N. Nao remover nada"
    
    $choice = Read-Host "`n   Escolha (numeros separados por virgula, A ou N)"
    
    if ($choice -match "^[Nn]$") {
        Write-Status "Debloat cancelado." "Info"
        return
    }
    
    $appsToRemove = @()
    
    if ($choice -match "^[Aa]$") {
        $appsToRemove = $bloatApps
    }
    else {
        $indices = $choice -split "," | ForEach-Object { [int]$_.Trim() - 1 }
        foreach ($idx in $indices) {
            if ($idx -ge 0 -and $idx -lt $bloatApps.Count) {
                $appsToRemove += $bloatApps[$idx]
            }
        }
    }
    
    foreach ($app in $appsToRemove) {
        Write-Host "   Removendo $($app.Name)..." -NoNewline
        $result = & $AdbPath shell pm uninstall -k --user 0 $app.Pkg 2>&1
        if ($result -match "Success") {
            $script:RemovedApps += $app
            Write-Host " [OK]" -ForegroundColor Green
        }
        else {
            Write-Host " [PULADO]" -ForegroundColor DarkGray
        }
    }
}

function Show-RestoreMenu {
    param([string]$AdbPath, [string]$Brand)
    
    Write-Section "RESTAURAR APPS REMOVIDOS"
    Write-Host "   Recupera apps desativados pelo debloat." -ForegroundColor DarkGray
    
    $bloatApps = Get-AllBloatApps -Brand $Brand
    
    Write-Host "`n   Apps que podem ser restaurados:"
    for ($i = 0; $i -lt $bloatApps.Count; $i++) {
        Write-Host "     $($i+1). $($bloatApps[$i].Name)"
    }
    Write-Host "     A. Restaurar TODOS"
    Write-Host "     N. Cancelar"
    
    $choice = Read-Host "`n   Escolha (numeros separados por virgula, A ou N)"
    
    if ($choice -match "^[Nn]$") {
        Write-Status "Restauracao cancelada." "Info"
        return
    }
    
    $appsToRestore = @()
    
    if ($choice -match "^[Aa]$") {
        $appsToRestore = $bloatApps
    }
    else {
        $indices = $choice -split "," | ForEach-Object { [int]$_.Trim() - 1 }
        foreach ($idx in $indices) {
            if ($idx -ge 0 -and $idx -lt $bloatApps.Count) {
                $appsToRestore += $bloatApps[$idx]
            }
        }
    }
    
    $restored = 0
    foreach ($app in $appsToRestore) {
        Write-Host "   Restaurando $($app.Name)..." -NoNewline
        $result = & $AdbPath shell cmd package install-existing $app.Pkg 2>&1
        if ($result -match "installed" -or $LASTEXITCODE -eq 0) {
            $restored++
            Write-Host " [OK]" -ForegroundColor Green
        }
        else {
            Write-Host " [NAO DISPONIVEL]" -ForegroundColor DarkGray
        }
    }
    
    Write-Status "$restored app(s) restaurado(s)." "Success"
}

# ------------------------------------------------------------------------------
# FUNCOES EXTRAS
# ------------------------------------------------------------------------------

function Enable-ImmersiveMode {
    param([string]$AdbPath)
    
    Write-Section "MODO IMERSIVO (ESCONDER BARRAS)"
    Write-Host "   1. Esconder apenas barra de navegacao"
    Write-Host "   2. Esconder apenas barra de status"
    Write-Host "   3. Esconder ambas (tela cheia total)"
    Write-Host "   4. Desativar modo imersivo"
    Write-Host "   5. Cancelar"
    
    $choice = Read-Host "   Escolha (1-5)"
    
    switch ($choice) {
        "1" { 
            & $AdbPath shell settings put global policy_control "immersive.navigation=*" 2>$null
            Write-Status "Barra de navegacao oculta." "Success"
        }
        "2" { 
            & $AdbPath shell settings put global policy_control "immersive.status=*" 2>$null
            Write-Status "Barra de status oculta." "Success"
        }
        "3" { 
            & $AdbPath shell settings put global policy_control "immersive.full=*" 2>$null
            Write-Status "Tela cheia ativada." "Success"
        }
        "4" { 
            & $AdbPath shell settings put global policy_control "immersive.off=*" 2>$null
            Write-Status "Modo imersivo desativado." "Success"
        }
    }
}

function Show-DisplayMenu {
    param([string]$AdbPath)
    
    Write-Section "CONFIGURACOES DE TELA (CARLINK)"
    Write-Host "   1. Modo Noturno (Escuro) - Recomendado para carro"
    Write-Host "   2. Modo Diurno (Claro)"
    Write-Host "   3. Modo Automatico"
    if ($script:DeviceSDK -lt 30) {
        Write-Host "   4. Ajustar Overscan (bordas cortadas)"
        Write-Host "   5. Resetar Overscan"
    }
    else {
        Write-Host "   4. Ajustar Overscan (NAO DISPONIVEL - Android 11+)" -ForegroundColor DarkGray
        Write-Host "   5. Resetar Overscan (NAO DISPONIVEL - Android 11+)" -ForegroundColor DarkGray
    }
    Write-Host "   6. Cancelar"
    
    $choice = Read-Host "   Escolha (1-6)"
    
    switch ($choice) {
        "1" { 
            Set-NightMode -AdbPath $AdbPath -Mode 2
            Write-Status "Modo Noturno (Escuro) ativado." "Success"
        }
        "2" { 
            Set-NightMode -AdbPath $AdbPath -Mode 1
            Write-Status "Modo Diurno (Claro) ativado." "Success"
        }
        "3" { 
            Set-NightMode -AdbPath $AdbPath -Mode 0
            Write-Status "Modo Automatico ativado." "Success"
        }
        "4" {
            if ($script:DeviceSDK -ge 30) {
                Write-Status "Overscan removido no Android 11+. Ajuste via DPI ou central." "Warning"
                return
            }
            Write-Host "`n   Ajuste de Overscan (para corrigir bordas cortadas)"
            Write-Host "   Valores positivos = reduzir area visivel"
            Write-Host "   Valores negativos = expandir area visivel"
            $overscan = Read-Host "   Digite os valores (ex: 20,10,20,10)"
            if ($overscan -match "^(-?\d+),(-?\d+),(-?\d+),(-?\d+)$") {
                Set-Overscan -AdbPath $AdbPath -Left $Matches[1] -Top $Matches[2] -Right $Matches[3] -Bottom $Matches[4]
                Write-Status "Overscan ajustado." "Success"
            }
            else {
                Write-Status "Formato invalido." "Error"
            }
        }
        "5" {
            if ($script:DeviceSDK -ge 30) {
                Write-Status "Overscan removido no Android 11+." "Warning"
                return
            }
            Reset-Overscan -AdbPath $AdbPath
            Write-Status "Overscan resetado." "Success"
        }
    }
}

function Setup-WirelessAdb {
    param([string]$AdbPath)
    
    Write-Section "CONFIGURAR ADB SEM FIO (WIRELESS)"
    Write-Host "   Isso permite usar o script sem cabo USB." -ForegroundColor DarkGray
    
    $ip = & $AdbPath shell ip route 2>$null | Select-String -Pattern "src (\d+\.\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    
    if (-not $ip) {
        Write-Status "Nao foi possivel detectar o IP. Verifique se o Wi-Fi esta ativo." "Error"
        return
    }
    
    Write-Host "   IP detectado: $ip" -ForegroundColor Cyan
    
    & $AdbPath tcpip 5555 2>$null
    Start-Sleep -Seconds 2
    
    Write-Status "ADB Wireless ativado na porta 5555!" "Success"
    Write-Host "`n   Para conectar sem fio no futuro, use:" -ForegroundColor Yellow
    Write-Host "   adb connect ${ip}:5555" -ForegroundColor White
    Write-Log "Wireless ADB enabled on $ip:5555"
}

function Backup-InstalledApks {
    param([string]$AdbPath)
    
    Write-Section "BACKUP DE APKs IMPORTANTES"
    
    if (-not (Test-Path $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
    }
    
    $appsToBackup = @(
        "com.farmerbb.taskbar",
        "com.farmerbb.secondscreen.free"
    )
    
    foreach ($pkg in $appsToBackup) {
        $apkPath = & $AdbPath shell pm path $pkg 2>$null
        if ($apkPath -match "package:(.+)") {
            $remotePath = $Matches[1]
            $localPath = "$BackupFolder\$pkg.apk"
            Write-Host "   Salvando $pkg..." -NoNewline
            & $AdbPath pull $remotePath $localPath 2>$null
            Write-Host " [OK]" -ForegroundColor Green
        }
    }
    
    Write-Status "Backups salvos em: $BackupFolder" "Success"
}

function Install-ApksFromFolder {
    param([string]$AdbPath)
    
    Write-Section "INSTALACAO EM LOTE DE APKs"
    
    if (-not (Test-Path $ApkFolder)) {
        New-Item -ItemType Directory -Path $ApkFolder -Force | Out-Null
        Write-Status "Pasta criada: $ApkFolder" "Info"
        Write-Host "   Coloque seus APKs nesta pasta e execute novamente." -ForegroundColor DarkGray
        return
    }
    
    $apks = Get-ChildItem -Path $ApkFolder -Filter "*.apk" -ErrorAction SilentlyContinue
    
    if ($apks.Count -eq 0) {
        Write-Status "Nenhum APK encontrado em: $ApkFolder" "Warning"
        return
    }
    
    Write-Host "   Encontrados $($apks.Count) APK(s):"
    foreach ($apk in $apks) {
        Write-Host "   -> Instalando $($apk.Name)..." -NoNewline
        & $AdbPath install -r $apk.FullName 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host " [OK]" -ForegroundColor Green
        }
        else {
            Write-Host " [FALHA]" -ForegroundColor Red
        }
    }
}

function Clear-SystemLogs {
    param([string]$AdbPath)
    
    Write-Section "LIMPEZA DE LOGS DO SISTEMA"
    
    Write-Host "   -> Limpando buffer do logcat..." -NoNewline
    & $AdbPath shell logcat -c 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    Write-Host "   -> Limpando cache de logs antigos..." -NoNewline
    & $AdbPath shell rm -rf /data/log/* 2>$null
    & $AdbPath shell rm -rf /data/vendor/log/* 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    Write-Status "Logs limpos. Memoria RAM liberada." "Success"
}

# ------------------------------------------------------------------------------
# MODO DE DIAGNOSTICO - V4.2
# Monitoramento em tempo real para uso no carro
# ------------------------------------------------------------------------------

function Get-BatteryInfo {
    param([string]$AdbPath)
    
    $batteryDump = & $AdbPath shell dumpsys battery 2>$null
    
    $info = @{
        Level       = 0
        Temperature = 0
        Voltage     = 0
        Status      = "Unknown"
        Health      = "Unknown"
        Plugged     = "None"
    }
    
    if ($batteryDump -match "level:\s*(\d+)") { $info.Level = [int]$Matches[1] }
    if ($batteryDump -match "temperature:\s*(\d+)") { $info.Temperature = [int]$Matches[1] / 10.0 }
    if ($batteryDump -match "voltage:\s*(\d+)") { $info.Voltage = [int]$Matches[1] / 1000.0 }
    
    if ($batteryDump -match "status:\s*(\d+)") {
        $statusCode = [int]$Matches[1]
        $info.Status = switch ($statusCode) {
            1 { "Unknown" }
            2 { "Carregando" }
            3 { "Descarregando" }
            4 { "Nao Carregando" }
            5 { "Cheio" }
            default { "Unknown" }
        }
    }
    
    if ($batteryDump -match "health:\s*(\d+)") {
        $healthCode = [int]$Matches[1]
        $info.Health = switch ($healthCode) {
            1 { "Unknown" }
            2 { "Boa" }
            3 { "Superaquecida" }
            4 { "Morta" }
            5 { "Sobretensao" }
            6 { "Falha" }
            7 { "Fria" }
            default { "Unknown" }
        }
    }
    
    if ($batteryDump -match "plugged:\s*(\d+)") {
        $pluggedCode = [int]$Matches[1]
        $info.Plugged = switch ($pluggedCode) {
            0 { "Desconectado" }
            1 { "AC" }
            2 { "USB" }
            4 { "Wireless" }
            default { "Unknown" }
        }
    }
    
    # Tentativa de ler corrente (mA)
    $currentNow = & $AdbPath shell "cat /sys/class/power_supply/battery/current_now 2>/dev/null"
    if ($currentNow -match "^-?\d+$") { 
        # Geralmente em microamperes
        $info.Current = [math]::Round([int]$currentNow / 1000) 
    }
    else {
        $info.Current = "N/A"
    }
    
    return $info
}

function Get-CpuFreq {
    param([string]$AdbPath)
    
    # Tenta ler frequencia atual dos cores (0 e 7 geralmente sao representativos de little/big)
    $freq0 = & $AdbPath shell "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null"
    $freq4 = & $AdbPath shell "cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq 2>/dev/null"
    $freq7 = & $AdbPath shell "cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq 2>/dev/null"
    
    $info = @{
        Core0 = if ($freq0 -match "^\d+$") { [math]::Round([int]$freq0 / 1000) } else { 0 }
        Core4 = if ($freq4 -match "^\d+$") { [math]::Round([int]$freq4 / 1000) } else { 0 }
        Core7 = if ($freq7 -match "^\d+$") { [math]::Round([int]$freq7 / 1000) } else { 0 }
    }
    return $info
}

function Get-CpuUsage {
    param([string]$AdbPath)
    
    # Metodo 1: top simplificado
    $topOutput = & $AdbPath shell "top -n 1 -b | head -5" 2>$null
    
    $cpuUsage = 0
    if ($topOutput -match "(\d+)%cpu") {
        $cpuUsage = [int]$Matches[1]
    }
    elseif ($topOutput -match "cpu.*?(\d+)%idle") {
        $cpuUsage = 100 - [int]$Matches[1]
    }
    
    return $cpuUsage
}

function Get-MemoryInfo {
    param([string]$AdbPath)
    
    $memInfo = & $AdbPath shell "cat /proc/meminfo | head -3" 2>$null
    
    $info = @{
        TotalMB     = 0
        FreeMB      = 0
        AvailableMB = 0
        UsedPercent = 0
    }
    
    if ($memInfo -match "MemTotal:\s*(\d+)") { $info.TotalMB = [math]::Round([int]$Matches[1] / 1024) }
    if ($memInfo -match "MemFree:\s*(\d+)") { $info.FreeMB = [math]::Round([int]$Matches[1] / 1024) }
    if ($memInfo -match "MemAvailable:\s*(\d+)") { $info.AvailableMB = [math]::Round([int]$Matches[1] / 1024) }
    
    if ($info.TotalMB -gt 0) {
        $info.UsedPercent = [math]::Round((($info.TotalMB - $info.AvailableMB) / $info.TotalMB) * 100)
    }
    
    return $info
}

function Get-ThermalInfo {
    param([string]$AdbPath)
    
    $thermals = @()
    
    # Tentar ler zonas termicas
    $zones = & $AdbPath shell "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -5" 2>$null
    
    if ($zones) {
        $zoneArray = $zones -split "`n" | Where-Object { $_ -match "^\d+$" }
        foreach ($temp in $zoneArray) {
            $tempC = [int]$temp / 1000.0
            if ($tempC -gt 0 -and $tempC -lt 150) {
                $thermals += $tempC
            }
        }
    }
    
    return $thermals
}

function Get-TemperatureColor {
    param([double]$Temp)
    
    if ($Temp -lt 35) { return "Green" }
    elseif ($Temp -lt 40) { return "Yellow" }
    elseif ($Temp -lt 45) { return "DarkYellow" }
    else { return "Red" }
}

function Get-ProgressBar {
    param([int]$Percent, [int]$Width = 20)
    
    $filled = [math]::Round($Percent * $Width / 100)
    $empty = $Width - $filled
    
    $bar = "[" + ("=" * $filled) + (" " * $empty) + "]"
    return $bar
}

function Show-DiagnosticMode {
    param([string]$AdbPath, [hashtable]$DeviceInfo)
    
    Write-Section "MODO DE DIAGNOSTICO - Monitoramento em Tempo Real"
    Write-Host "   Ideal para monitorar o celular guardado no console do carro." -ForegroundColor DarkGray
    Write-Host "   Pressione 'Q' para sair do monitoramento." -ForegroundColor Yellow
    Write-Host ""
    
    $refreshInterval = 2 # segundos
    
    Write-Host "   Iniciando monitoramento (atualizacao a cada ${refreshInterval}s)..." -ForegroundColor Cyan
    Start-Sleep -Seconds 1
    
    $running = $true
    $samples = @()
    $maxSamples = 30
    
    while ($running) {
        # Verificar se 'Q' foi pressionado
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Q') {
                $running = $false
                continue
            }
        }
        
        # Coletar dados
        $battery = Get-BatteryInfo -AdbPath $AdbPath
        $cpu = Get-CpuUsage -AdbPath $AdbPath
        $cpuFreq = Get-CpuFreq -AdbPath $AdbPath
        $memory = Get-MemoryInfo -AdbPath $AdbPath
        $thermals = Get-ThermalInfo -AdbPath $AdbPath
        
        # Armazenar amostra
        $sample = @{
            Time        = Get-Date
            BatteryTemp = $battery.Temperature
            CPU         = $cpu
        }
        $samples += $sample
        if ($samples.Count -gt $maxSamples) { $samples = $samples[ - $maxSamples..-1] }
        
        # Limpar tela e reposicionar cursor
        Clear-Host
        
        # Header
        Write-Host "============================================================" -ForegroundColor Magenta
        Write-Host "  DIAGNOSTICO - $($DeviceInfo.Model) ($($DeviceInfo.Brand.ToUpper()))" -ForegroundColor White
        Write-Host "  $(Get-Date -Format 'HH:mm:ss') | Pressione 'Q' para sair" -ForegroundColor DarkGray
        Write-Host "============================================================" -ForegroundColor Magenta
        Write-Host ""
        
        # BATERIA
        Write-Host "  [BATERIA]" -ForegroundColor Cyan
        $batteryBar = Get-ProgressBar -Percent $battery.Level
        Write-Host "    Nivel:       $batteryBar $($battery.Level)%"
        
        $tempColor = Get-TemperatureColor -Temp $battery.Temperature
        Write-Host "    Temperatura: " -NoNewline
        Write-Host "$($battery.Temperature)C" -ForegroundColor $tempColor -NoNewline
        if ($battery.Temperature -ge 45) {
            Write-Host "  [ALERTA: SUPERAQUECIMENTO!]" -ForegroundColor Red
        }
        elseif ($battery.Temperature -ge 40) {
            Write-Host "  [Atencao: Temperatura elevada]" -ForegroundColor Yellow
        }
        else {
            Write-Host "  [Normal]" -ForegroundColor Green
        }
        
        Write-Host "    Voltagem:    $($battery.Voltage)V"
        Write-Host "    Status:      $($battery.Status) | Saude: $($battery.Health)"
        Write-Host "    Fonte:       $($battery.Plugged)"
        if ($battery.Current -ne "N/A") {
            $ma = $battery.Current
            $watts = if ($ma -ne 0) { [math]::Round([math]::Abs($ma * $battery.Voltage) / 1000, 1) } else { 0 }
            Write-Host "    Corrente:    ${ma}mA (${watts}W)"
        }
        Write-Host ""
        
        # CPU
        Write-Host "  [CPU]" -ForegroundColor Cyan
        $cpuBar = Get-ProgressBar -Percent $cpu
        $cpuColor = if ($cpu -lt 50) { "Green" } elseif ($cpu -lt 80) { "Yellow" } else { "Red" }
        Write-Host "    Uso Total:   $cpuBar " -NoNewline
        Write-Host "$cpu%" -ForegroundColor $cpuColor
        
        if ($cpuFreq.Core0 -gt 0) {
            Write-Host "    Freq Cores:  " -NoNewline
            Write-Host "$($cpuFreq.Core0)MHz (Little) " -NoNewline -ForegroundColor DarkGray
            if ($cpuFreq.Core7 -gt 0) {
                Write-Host "| $($cpuFreq.Core7)MHz (Big)" -NoNewline -ForegroundColor White
            }
            Write-Host ""
        }
        Write-Host ""
        
        # MEMORIA
        Write-Host "  [MEMORIA]" -ForegroundColor Cyan
        $memBar = Get-ProgressBar -Percent $memory.UsedPercent
        $memColor = if ($memory.UsedPercent -lt 70) { "Green" } elseif ($memory.UsedPercent -lt 85) { "Yellow" } else { "Red" }
        Write-Host "    Uso:         $memBar " -NoNewline
        Write-Host "$($memory.UsedPercent)%" -ForegroundColor $memColor
        Write-Host "    Disponivel:  $($memory.AvailableMB) MB / $($memory.TotalMB) MB"
        Write-Host ""
        
        # TEMPERATURAS ADICIONAIS
        if ($thermals.Count -gt 0) {
            Write-Host "  [SENSORES TERMICOS]" -ForegroundColor Cyan
            $maxTemp = ($thermals | Measure-Object -Maximum).Maximum
            $avgTemp = [math]::Round(($thermals | Measure-Object -Average).Average, 1)
            
            $maxTempColor = Get-TemperatureColor -Temp $maxTemp
            Write-Host "    Maxima:      " -NoNewline
            Write-Host "${maxTemp}C" -ForegroundColor $maxTempColor
            Write-Host "    Media:       ${avgTemp}C"
            Write-Host ""
        }
        
        # ALERTAS
        if ($battery.Temperature -ge 45 -or ($thermals.Count -gt 0 -and ($thermals | Measure-Object -Maximum).Maximum -ge 50)) {
            Write-Host "  ============================================================" -ForegroundColor Red
            Write-Host "  [!!!] ALERTA DE TEMPERATURA CRITICA [!!!]" -ForegroundColor Red
            Write-Host "  Considere:" -ForegroundColor Yellow
            Write-Host "    - Remover o celular do console" -ForegroundColor Yellow
            Write-Host "    - Desligar o carregador" -ForegroundColor Yellow
            Write-Host "    - Ligar o ar condicionado" -ForegroundColor Yellow
            Write-Host "  ============================================================" -ForegroundColor Red
            
            # Alerta sonoro (Windows)
            [Console]::Beep(1000, 500)
        }
        
        # Mini grafico de tendencia (ultimas amostras)
        if ($samples.Count -ge 5) {
            Write-Host "  [TENDENCIA DE TEMPERATURA (ultimos $([ math]::Min($samples.Count, 10)) pontos)]" -ForegroundColor Cyan
            $recentSamples = $samples[-10..-1]
            $tempTrend = ""
            foreach ($s in $recentSamples) {
                $tempTrend += if ($s.BatteryTemp -lt 35) { "_" } 
                elseif ($s.BatteryTemp -lt 40) { "-" }
                elseif ($s.BatteryTemp -lt 45) { "^" }
                else { "!" }
            }
            Write-Host "    $tempTrend (baixa=_ media=- alta=^ critica=!)"
        }
        
        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  Atualizando em ${refreshInterval}s... (Q=Sair)" -ForegroundColor DarkGray
        
        # Log para arquivo
        Write-Log "DIAG: Temp=$($battery.Temperature)C, CPU=$cpu%, RAM=$($memory.UsedPercent)%, Bat=$($battery.Level)%"
        
        Start-Sleep -Seconds $refreshInterval
    }
    
    Write-Host ""
    Write-Status "Monitoramento encerrado." "Info"
    
    # Resumo final
    if ($samples.Count -gt 0) {
        $avgTemp = [math]::Round(($samples | ForEach-Object { $_.BatteryTemp } | Measure-Object -Average).Average, 1)
        $maxTemp = ($samples | ForEach-Object { $_.BatteryTemp } | Measure-Object -Maximum).Maximum
        $avgCpu = [math]::Round(($samples | ForEach-Object { $_.CPU } | Measure-Object -Average).Average)
        
        Write-Host ""
        Write-Host "  [RESUMO DA SESSAO]" -ForegroundColor Cyan
        Write-Host "    Amostras coletadas: $($samples.Count)"
        Write-Host "    Temperatura media:  ${avgTemp}C"
        Write-Host "    Temperatura maxima: ${maxTemp}C"
        Write-Host "    CPU media:          ${avgCpu}%"
    }
}

# ------------------------------------------------------------------------------
# FUNCOES DE INSTALACAO E OTIMIZACAO (V5.0)
# ------------------------------------------------------------------------------

function Download-EssentialApps {
    param([string]$AdbPath)
    Write-Section "DOWNLOAD E INSTALACAO DE APPS (ULTIMATE 2026)"
    
    # Forçar TLS 1.2 e 1.3 para evitar erros de conexão
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

    $apps = @(
        @{ Name = "Shizuku"; Url = "https://github.com/RikkaApps/Shizuku/releases/download/v13.6.0/shizuku-v13.6.0.r1086.2650830c-release.apk" },
        @{ Name = "Taskbar"; Url = "https://github.com/farmerbb/Taskbar/releases/download/v6.1.1/Taskbar-v6.1.1-release.apk" },
        @{ Name = "SecondScreen"; Url = "https://github.com/farmerbb/SecondScreen/releases/download/v2.9.4/SecondScreen-2.9.4.apk" },
        @{ Name = "MacroDroid"; Url = "https://f-droid.org/repo/com.arlosoft.macrodroid_56004.apk" }
    )

    if (-not (Test-Path $ApkFolder)) { New-Item -ItemType Directory -Path $ApkFolder | Out-Null }

    foreach ($app in $apps) {
        $dest = "$ApkFolder\$($app.Name).apk"
        Write-Status "Verificando $($app.Name)..." "Info"
        
        if (-not (Test-Path $dest)) {
            Write-Host "   -> Tentando download seguro..." -NoNewline
            try {
                # Download com UserAgent de navegador para evitar bloqueio do GitHub
                $webClient = New-Object System.Net.WebClient
                $webClient.Headers.Add("User-Agent", "Mozilla/5.0")
                $webClient.DownloadFile($app.Url, $dest)
                Write-Host " [OK]" -ForegroundColor Green
            }
            catch {
                Write-Host " [FALHA: $_]" -ForegroundColor Red
                continue
            }
        }
        
        Write-Host "   -> Instalando no Poco X6 Pro..." -NoNewline
        # -g concede todas as permissões no Android 15
        $installResult = & $AdbPath install -r -g "$dest" 2>&1
        if ($installResult -match "Success") { Write-Host " [INSTALADO]" -ForegroundColor Green }
        else { Write-Host " [JA ATUALIZADO OU REQUER UNINSTALL MANUAL]" -ForegroundColor DarkGray }
    }
}

function Set-GeelyOptimize {
    param([string]$AdbPath)
    Write-Section "OTIMIZACAO FINAL: GEELY EX2 + CARLINK"
    
    # 1. DPI para Modo Tablet (280 é o "Sweet Spot" para o Geely)
    Write-Host "   -> Definindo DPI 280 (Modo Desktop)..." -NoNewline
    & $AdbPath shell wm density 280 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    # 2. Permissões de Overlay (Aparecer sobre outros apps)
    Write-Host "   -> Concedendo permissoes de sobreposicao..." -NoNewline
    & $AdbPath shell appops set com.arlosoft.macrodroid SYSTEM_ALERT_WINDOW allow 2>$null
    & $AdbPath shell appops set com.farmerbb.taskbar SYSTEM_ALERT_WINDOW allow 2>$null
    & $AdbPath shell appops set com.farmerbb.secondscreen.free SYSTEM_ALERT_WINDOW allow 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    # 3. Forçar modo desktop no navegador/sistema
    Write-Host "   -> Ajustando policy de tela cheia..." -NoNewline
    & $AdbPath shell settings put global policy_control immersive.full=* 2>$null
    Write-Host " [OK]" -ForegroundColor Green
    
    # 4. Configurar aplicativos de motorista (Permissao de localizacao background se possivel)
    # Nota: Android 11+ bloqueia isso via ADB user 0 para alguns casos, mas tentamos
    $driverApps = @("com.driver99.driver", "com.ubercab.driver", "com.gigu.driver", "com.waze", "com.google.android.apps.maps")
    foreach ($pkg in $driverApps) {
        & $AdbPath shell cmd appops set $pkg ACCESS_FINE_LOCATION allow 2>$null
    }

    Write-Status "Ambiente Geely preparado (DPI 280 + Permissoes)." "Success"
    Write-Status "Ambiente Geely preparado (DPI 280 + Permissoes)." "Success"
}

function Invoke-SystemReset {
    param([string]$AdbPath, [hashtable]$DeviceInfo)
    
    Write-Section "OPERACAO CLEAN SLATE: RESTAURANDO PADROES"
    Write-Host "   Isso removera todas as customizacoes feitas pelo script." -ForegroundColor Yellow
    $confirm = Read-Host "   Tem certeza que deseja resetar o sistema? (S/N)"
    if ($confirm -notmatch "^[Ss]") { return }

    Write-Status "Iniciando limpeza profunda..." "Info"

    # 1. Reset de Tela e Interface
    Write-Host "   -> Resetando DPI e Overscan..." -NoNewline
    & $AdbPath shell wm density reset 2>$null
    if ($script:DeviceSDK -lt 30) { & $AdbPath shell wm overscan reset 2>$null }
    Write-Host " [OK]" -ForegroundColor Green

    # 2. Reset de Configuracoes Globais
    Write-Host "   -> Restaurando Modo Noturno e Imersivo..." -NoNewline
    & $AdbPath shell settings put secure ui_night_mode 0 2>$null
    & $AdbPath shell settings put global policy_control null 2>$null
    & $AdbPath shell settings put global enable_freeform_support 0 2>$null
    & $AdbPath shell settings put global force_resizable_activities 0 2>$null
    Write-Host " [OK]" -ForegroundColor Green

    # 3. Reset de Animacoes (Volta para 1.0x)
    Write-Host "   -> Restaurando velocidade das animacoes..." -NoNewline
    & $AdbPath shell settings put global window_animation_scale 1 2>$null
    & $AdbPath shell settings put global transition_animation_scale 1 2>$null
    & $AdbPath shell settings put global animator_duration_scale 1 2>$null
    Write-Host " [OK]" -ForegroundColor Green

    # 4. Limpeza de Permissoes e Whitelists (Apps principais)
    $appsToReset = @("com.farmerbb.taskbar", "com.farmerbb.secondscreen.free", "com.arlosoft.macrodroid")
    Write-Host "   -> Resetando AppOps e Whitelists de Bateria..." -NoNewline
    foreach ($pkg in $appsToReset) {
        & $AdbPath shell appops reset $pkg 2>$null
        & $AdbPath shell dumpsys deviceidle whitelist -$pkg 2>$null
    }
    Write-Host " [OK]" -ForegroundColor Green

    # 5. Reset Especifico por Marca
    if ($DeviceInfo.Brand -match "xiaomi|poco|redmi") {
        Write-Host "   -> Reativando MIUI Optimization e logs..." -NoNewline
        & $AdbPath shell settings put global miui_optimization_disable 0 2>$null
        & $AdbPath shell start logd 2>$null
        Write-Host " [OK]" -ForegroundColor Green
    }

    # 6. Restaurar Bloatware (Opcional, mas garante limpeza)
    $respBloat = Read-Host "`n   Deseja reativar todos os apps de fabrica (Bloatware)? (S/N)"
    if ($respBloat -match "^[Ss]") {
        Show-RestoreMenu -AdbPath $AdbPath -Brand $DeviceInfo.Brand
    }

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Status "LIMPEZA CONCLUIDA COM SUCESSO!" "Success"
    Write-Host "   Recomendamos REINICIAR o aparelho agora antes de"
    Write-Host "   aplicar as novas configuracoes do Script v5.0."
    Write-Host "============================================================" -ForegroundColor Cyan
    
    $reboot = Read-Host "   Deseja reiniciar agora? (S/N)"
    if ($reboot -match "^[Ss]") { & $AdbPath reboot }
}

# ------------------------------------------------------------------------------
# MENU AVANCADO
# ------------------------------------------------------------------------------

function Show-AdvancedMenu {
    param([string]$AdbPath, [hashtable]$DeviceInfo)
    
    while ($true) {
        Write-Host "`n============================================================" -ForegroundColor Magenta
        Write-Host "  MENU AVANCADO - Ultimate v$ScriptVersion" -ForegroundColor White
        Write-Host "============================================================" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  [TELA]" -ForegroundColor Cyan
        Write-Host "  1. Ajustar DPI (Densidade)"
        Write-Host "  2. Modo Imersivo (Esconder Barras)"
        Write-Host "  3. Configuracoes de Tela (Noturno/Overscan)"
        Write-Host ""
        Write-Host "  [CARLINK]" -ForegroundColor Cyan
        Write-Host "  4. Fix Prompt 'Iniciar Agora' (PROJECT_MEDIA)"
        Write-Host "  5. Reset Carlink (Conexao Travada)"
        Write-Host ""
        Write-Host "  [APPS]" -ForegroundColor Cyan
        Write-Host "  6. Remover Bloatware"
        Write-Host "  7. Restaurar Apps Removidos"
        Write-Host "  8. Iniciar Shizuku"
        Write-Host ""
        Write-Host "  [SISTEMA]" -ForegroundColor Cyan
        Write-Host "  9. Configurar ADB Wireless"
        Write-Host "  A. Download & Install Apps (Taskbar, MacroDroid...)" -ForegroundColor Green
        Write-Host "  B. Backup de APKs"
        Write-Host "  I. Instalar APKs da pasta"
        Write-Host "  L. Limpar Logs (Liberar RAM)"
        Write-Host "  O. Re-aplicar otimizacoes"
        if ($DeviceInfo.Brand -match "xiaomi|poco|redmi") {
            Write-Host "  M. Toggle MIUI Optimization (Avancado)" -ForegroundColor DarkYellow
        }
        Write-Host ""
        Write-Host "  [DIAGNOSTICO]" -ForegroundColor Cyan
        Write-Host "  D. Monitoramento em Tempo Real (Temperatura/CPU/RAM)" -ForegroundColor Green
        Write-Host ""
        Write-Host "  [ESPECIAL]" -ForegroundColor Cyan
        Write-Host "  G. Geely Optimize (DPI 280 + Overlay)" -ForegroundColor Green
        Write-Host "  X. CLEAN SLATE (Reset total das customizacoes)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  [CONTROLE]" -ForegroundColor Cyan
        Write-Host "  R. Reiniciar dispositivo"
        Write-Host "  0. Sair"
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
        
        $choice = Read-Host "Opcao"
        
        switch ($choice.ToUpper()) {
            "1" {
                $currentDpi = Get-CurrentDpi -AdbPath $AdbPath
                Write-Host "`n   DPI Atual: $currentDpi"
                Write-Host "   1. DPI 280 (Ultra compacto)"
                Write-Host "   2. DPI 320 (Tablet - Recomendado)"
                Write-Host "   3. DPI 360 (Intermediario)"
                Write-Host "   4. DPI 400 (Normal)"
                Write-Host "   5. Restaurar padrao"
                Write-Host "   6. Valor personalizado"
                
                $dpiChoice = Read-Host "   Escolha"
                switch ($dpiChoice) {
                    "1" { Set-Dpi -AdbPath $AdbPath -Dpi 280; Write-Status "DPI: 280" "Success" }
                    "2" { Set-Dpi -AdbPath $AdbPath -Dpi 320; Write-Status "DPI: 320" "Success" }
                    "3" { Set-Dpi -AdbPath $AdbPath -Dpi 360; Write-Status "DPI: 360" "Success" }
                    "4" { Set-Dpi -AdbPath $AdbPath -Dpi 400; Write-Status "DPI: 400" "Success" }
                    "5" { & $AdbPath shell wm density reset; Write-Status "DPI restaurado" "Success" }
                    "6" { 
                        $custom = Read-Host "   Digite o DPI"
                        if ($custom -match "^\d+$") { Set-Dpi -AdbPath $AdbPath -Dpi ([int]$custom) }
                    }
                }
            }
            "2" { Enable-ImmersiveMode -AdbPath $AdbPath }
            "3" { Show-DisplayMenu -AdbPath $AdbPath }
            "4" { Fix-CarlinkPrompt -AdbPath $AdbPath }
            "5" { Reset-Carlink -AdbPath $AdbPath }
            "6" { Show-DebloatMenu -AdbPath $AdbPath -Brand $DeviceInfo.Brand }
            "7" { Show-RestoreMenu -AdbPath $AdbPath -Brand $DeviceInfo.Brand }
            "8" { Start-Shizuku -AdbPath $AdbPath }
            "9" { Setup-WirelessAdb -AdbPath $AdbPath }
            "A" { Download-EssentialApps -AdbPath $AdbPath }
            "B" { Backup-InstalledApks -AdbPath $AdbPath }
            "I" { Install-ApksFromFolder -AdbPath $AdbPath }
            "L" { Clear-SystemLogs -AdbPath $AdbPath }
            "O" {
                $brand = $DeviceInfo.Brand
                if ($brand -match "xiaomi|poco|redmi") { Optimize-Xiaomi -AdbPath $AdbPath }
                elseif ($brand -eq "samsung") { Optimize-Samsung -AdbPath $AdbPath }
                else { Optimize-Generic -AdbPath $AdbPath }
            }
            "G" { Set-GeelyOptimize -AdbPath $AdbPath }
            "X" { Invoke-SystemReset -AdbPath $AdbPath -DeviceInfo $DeviceInfo }
            "M" {
                if ($DeviceInfo.Brand -match "xiaomi|poco|redmi") {
                    Write-Host "`n   1. Desativar MIUI Optimization"
                    Write-Host "   2. Reativar MIUI Optimization"
                    $miuiChoice = Read-Host "   Escolha"
                    if ($miuiChoice -eq "1") { Toggle-MiuiOptimization -AdbPath $AdbPath -Disable $true }
                    elseif ($miuiChoice -eq "2") { Toggle-MiuiOptimization -AdbPath $AdbPath -Disable $false }
                }
            }
            "D" {
                Show-DiagnosticMode -AdbPath $AdbPath -DeviceInfo $DeviceInfo
            }
            "R" {
                Write-Status "Reiniciando dispositivo..." "Warning"
                & $AdbPath reboot
            }
            "0" { return }
        }
    }
}

# ------------------------------------------------------------------------------
# SCRIPT PRINCIPAL
# ------------------------------------------------------------------------------

Clear-Host
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  ANDROID SETUP v$ScriptVersion - ULTIMATE CONNECTION" -ForegroundColor Magenta
Write-Host "  Taskbar + SecondScreen + Geely Optimization + Clean Slate" -ForegroundColor DarkMagenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host ""
Write-Log "=== Script started v$ScriptVersion ==="

# ETAPA 1: ADB
Write-Host "[ETAPA 1/7] Verificando ADB..." -ForegroundColor White
$adb = Get-AdbPath
if (-not $adb) { $adb = Install-Adb }
else { Write-Status "ADB: $adb" "Success" }

& $adb start-server 2>$null | Out-Null

# ETAPA 2: Dispositivo
Write-Host "`n[ETAPA 2/7] Conectando ao dispositivo..." -ForegroundColor White
if (-not (Wait-ForDevice -AdbPath $adb -MaxAttempts 30)) {
    Write-Host "`nDicas:" -ForegroundColor Yellow
    Write-Host "  1. Ative 'Depuracao USB'"
    Write-Host "  2. Use 'Transferencia de arquivos'"
    Write-Host "  3. Aceite o prompt no celular"
    exit 1
}

# ETAPA 3: Info do Dispositivo
Write-Host "`n[ETAPA 3/7] Coletando informacoes do dispositivo..." -ForegroundColor White
$deviceInfo = Get-DeviceInfo -AdbPath $adb
Write-Status "Marca: $($deviceInfo.Brand.ToUpper())" "Success"
Write-Status "Modelo: $($deviceInfo.Model)" "Success"
Write-Status "Android: $($deviceInfo.Android) (SDK $($deviceInfo.SDK))" "Success"

# AVISO XIAOMI
if ($deviceInfo.Brand -match "xiaomi|poco|redmi") {
    Write-XiaomiWarning
    $continuar = Read-Host "Pressione ENTER para continuar (ou 'N' para sair)"
    if ($continuar -match "^[Nn]") { exit 0 }
}

# ETAPA 4: Apps
Write-Host "`n[ETAPA 4/7] Detectando aplicativos..." -ForegroundColor White
$apps = Get-InstalledApps -AdbPath $adb
if ($apps.Count -eq 0) {
    Write-Status "Nenhum app principal encontrado" "Warning"
}
else {
    foreach ($app in $apps) {
        Write-Status "$($app.Name): $($app.Package)" "Success"
    }
}

# ETAPA 4.5: Garantir que os apps essenciais existam
Download-EssentialApps -AdbPath $adb

# ETAPA 5: Permissoes, Freeform e Persistencia
Write-Host "`n[ETAPA 5/7] Aplicando permissoes e persistencia..." -ForegroundColor White
$permission = "android.permission.WRITE_SECURE_SETTINGS"

foreach ($app in $apps) {
    if ($app.Name -eq "Shizuku") { continue }
    
    Write-Host "   $($app.Name)..." -NoNewline
    
    # Permissao WRITE_SECURE_SETTINGS
    Grant-Permission -AdbPath $adb -Package $app.Package -Permission $permission | Out-Null
    
    # Whitelist de bateria (impede o sistema de matar o app)
    Add-BatteryWhitelist -AdbPath $adb -Package $app.Package
    
    Write-Host " [OK]" -ForegroundColor Green
}

Enable-FreeformMode -AdbPath $adb | Out-Null
Write-Status "Modo Freeform ativado" "Success"

# ETAPA 6: Carlink Fix + Shizuku
Write-Host "`n[ETAPA 6/7] Configurando Carlink e Shizuku..." -ForegroundColor White

# Fix Carlink automatico
Fix-CarlinkPrompt -AdbPath $adb

# Shizuku (se instalado)
$shizukuApp = $apps | Where-Object { $_.Name -eq "Shizuku" }
if ($shizukuApp) {
    Start-Shizuku -AdbPath $adb
}

# ETAPA 7: Otimizacoes por Marca
Write-Host "`n[ETAPA 7/7] Aplicando otimizacoes especificas..." -ForegroundColor White
$brand = $deviceInfo.Brand

if ($brand -match "xiaomi|poco|redmi") {
    Optimize-Xiaomi -AdbPath $adb
}
elseif ($brand -eq "samsung") {
    Optimize-Samsung -AdbPath $adb
}
else {
    Optimize-Generic -AdbPath $adb
}

# Modo Noturno para Carlink
Write-Host "`n   -> Ativando modo noturno (ideal para carro)..." -NoNewline
Set-NightMode -AdbPath $adb -Mode 2
Write-Host " [OK]" -ForegroundColor Green

# RESULTADO FINAL
Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "  CONFIGURACAO ENTERPRISE CONCLUIDA!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Magenta

$currentDpi = Get-CurrentDpi -AdbPath $adb
Write-Host "`n  DPI Atual: $currentDpi" -ForegroundColor Cyan
Write-Host "  Modo Noturno: ATIVADO" -ForegroundColor Cyan
Write-Host "  Carlink Fix: APLICADO" -ForegroundColor Cyan
Write-Host "  Log salvo em: $LogFile" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  IMPORTANTE: Reinicie o celular para ativar o Freeform!" -ForegroundColor Yellow

Write-Log "=== Configuration completed ==="

# Menu Avancado
$resp = Read-Host "`nDeseja acessar o Menu Avancado? (S/N)"
if ($resp -match "^[Ss]") {
    Show-AdvancedMenu -AdbPath $adb -DeviceInfo $deviceInfo
}

Write-Host "`n>>> Script finalizado. Pressione qualquer tecla..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
