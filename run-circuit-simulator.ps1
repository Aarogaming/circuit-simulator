param(
    [switch]$Configure,
    [ValidateSet('native','java','web')]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$portableDataRoot = Join-Path $scriptRoot ".circuit-simulator"
$configDir = Join-Path $portableDataRoot "config"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}
$configPath = Join-Path $configDir "circuit-simulator-startup.json"
$legacyConfigPath = Join-Path $scriptRoot "circuit-simulator-startup.json"
$userConfigPath = Join-Path $env:LOCALAPPDATA "CircuitSimulator\circuit-simulator-startup.json"

function Get-DefaultConfig {
    return @{
        mode = "native"
        simple = $false
        port = 19084
    }
}

function Load-Config {
    if (-not (Test-Path $configPath) -and (Test-Path $legacyConfigPath)) {
        try {
            Copy-Item -Path $legacyConfigPath -Destination $configPath -Force
        } catch {
        }
    }
    if (-not (Test-Path $configPath) -and (Test-Path $userConfigPath)) {
        try {
            Copy-Item -Path $userConfigPath -Destination $configPath -Force
        } catch {
        }
    }

    if (-not (Test-Path $configPath)) {
        $default = Get-DefaultConfig
        Save-Config -Config $default
        return $default
    }

    try {
        $json = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        $parsed = @{
            mode = if ($json.mode) { [string]$json.mode } else { "native" }
            simple = if ($null -ne $json.simple) { [bool]$json.simple } else { $false }
            port = if ($json.port) { [int]$json.port } else { 19084 }
        }
        return $parsed
    } catch {
        $default = Get-DefaultConfig
        Save-Config -Config $default
        return $default
    }
}

function Save-Config {
    param([hashtable]$Config)
    ($Config | ConvertTo-Json) | Set-Content -Path $configPath -Encoding utf8
}

function Configure-Startup {
    param([hashtable]$Config)

    Write-Host "Circuit Simulator Startup Options"
    Write-Host "1) Native offline executable (recommended)"
    Write-Host "2) Java offline fallback"
    Write-Host "3) Web offline package"
    Write-Host "Current mode: $($Config.mode)"
    $choice = Read-Host "Choose startup mode (1-3, Enter keeps current)"

    switch ($choice) {
        '1' { $Config.mode = 'native' }
        '2' { $Config.mode = 'java' }
        '3' { $Config.mode = 'web' }
        '' {}
        default { Write-Host "Unknown choice, keeping current mode." }
    }

    $simpleChoice = Read-Host "Start web mode in simple view? (y/N, current=$($Config.simple))"
    if ($simpleChoice -match '^(?i)y') {
        $Config.simple = $true
    } elseif ($simpleChoice -match '^(?i)n|^$') {
        $Config.simple = $false
    }

    $portChoice = Read-Host "Web mode port (current=$($Config.port), Enter keeps current)"
    if ($portChoice -match '^\d+$') {
        $Config.port = [int]$portChoice
    }

    Save-Config -Config $Config
    Write-Host "Saved startup config to $configPath"
}

function Configure-StartupGui {
    param([hashtable]$Config)

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    } catch {
        return $false
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Circuit Simulator Startup Options"
    $form.Size = New-Object System.Drawing.Size(420, 270)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $labelMode = New-Object System.Windows.Forms.Label
    $labelMode.Text = "Startup mode"
    $labelMode.Location = New-Object System.Drawing.Point(20, 20)
    $labelMode.AutoSize = $true

    $comboMode = New-Object System.Windows.Forms.ComboBox
    $comboMode.Location = New-Object System.Drawing.Point(20, 45)
    $comboMode.Size = New-Object System.Drawing.Size(360, 24)
    $comboMode.DropDownStyle = "DropDownList"
    [void]$comboMode.Items.Add("native")
    [void]$comboMode.Items.Add("java")
    [void]$comboMode.Items.Add("web")
    $comboMode.SelectedItem = $Config.mode
    if (-not $comboMode.SelectedItem) {
        $comboMode.SelectedItem = "native"
    }

    $checkSimple = New-Object System.Windows.Forms.CheckBox
    $checkSimple.Text = "Simple view for web mode (hide sidebar)"
    $checkSimple.Location = New-Object System.Drawing.Point(20, 88)
    $checkSimple.AutoSize = $true
    $checkSimple.Checked = [bool]$Config.simple

    $labelPort = New-Object System.Windows.Forms.Label
    $labelPort.Text = "Web mode port"
    $labelPort.Location = New-Object System.Drawing.Point(20, 122)
    $labelPort.AutoSize = $true

    $textPort = New-Object System.Windows.Forms.TextBox
    $textPort.Location = New-Object System.Drawing.Point(20, 145)
    $textPort.Size = New-Object System.Drawing.Size(120, 24)
    $textPort.Text = [string]$Config.port

    $buttonSave = New-Object System.Windows.Forms.Button
    $buttonSave.Text = "Save"
    $buttonSave.Location = New-Object System.Drawing.Point(214, 190)
    $buttonSave.Size = New-Object System.Drawing.Size(80, 30)
    $buttonSave.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Text = "Cancel"
    $buttonCancel.Location = New-Object System.Drawing.Point(300, 190)
    $buttonCancel.Size = New-Object System.Drawing.Size(80, 30)
    $buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.Add($labelMode)
    $form.Controls.Add($comboMode)
    $form.Controls.Add($checkSimple)
    $form.Controls.Add($labelPort)
    $form.Controls.Add($textPort)
    $form.Controls.Add($buttonSave)
    $form.Controls.Add($buttonCancel)
    $form.AcceptButton = $buttonSave
    $form.CancelButton = $buttonCancel

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $true
    }

    $port = 19084
    if ($textPort.Text -match '^\d+$') {
        $port = [int]$textPort.Text
    }

    $Config.mode = [string]$comboMode.SelectedItem
    $Config.simple = [bool]$checkSimple.Checked
    $Config.port = $port
    Save-Config -Config $Config

    [System.Windows.Forms.MessageBox]::Show(
        "Startup options saved.",
        "Circuit Simulator",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    return $true
}

function Start-Native {
    $nativeCandidates = @(
        (Join-Path $scriptRoot "dist-native\Circuit Simulator\Circuit Simulator.exe"),
        (Join-Path $scriptRoot "Circuit Simulator\Circuit Simulator.exe"),
        (Join-Path $scriptRoot "Circuit Simulator.exe")
    )

    $exe = $null
    foreach ($candidate in $nativeCandidates) {
        if (Test-Path $candidate) {
            $exe = $candidate
            break
        }
    }

    if ($exe -and (Test-Path $exe)) {
        $exeDir = Split-Path -Parent $exe
        try {
            Start-Process -FilePath $exe -WorkingDirectory $exeDir | Out-Null
            return $true
        } catch {
            return $false
        }
    }
    return $false
}

function Start-Java {
    $bat = Join-Path $scriptRoot "run-circuitjs-offline.bat"
    if (Test-Path $bat) {
        try {
            Start-Process -FilePath $bat -WorkingDirectory $scriptRoot | Out-Null
            return $true
        } catch {
            return $false
        }
    }
    return $false
}

function Start-Web {
    param([hashtable]$Config)

    function Resolve-WebWorkspace {
        $directLauncher = Join-Path $scriptRoot "run-circuitjs-offline-web.ps1"
        $legacyDirectLauncher = Join-Path $scriptRoot "offline-web-launcher.ps1"
        $directHtml = Join-Path $scriptRoot "circuitjs.html"
        if (((Test-Path $directLauncher) -or (Test-Path $legacyDirectLauncher)) -and (Test-Path $directHtml)) {
            return $scriptRoot
        }

        $distDir = Join-Path $scriptRoot "dist"
        $zipCandidates = @()
        $portableReleaseZip = Join-Path $scriptRoot "circuitjs-offline-web-release.zip"
        if (Test-Path $portableReleaseZip) {
            $zipCandidates += Get-Item $portableReleaseZip
        }

        if (Test-Path $distDir) {
            $distReleaseZip = Join-Path $distDir "circuitjs-offline-web-release.zip"
            if (Test-Path $distReleaseZip) {
                $zipCandidates += Get-Item $distReleaseZip
            }
            $zipCandidates += Get-ChildItem -Path $distDir -Filter "circuitjs-offline-web*.zip" -ErrorAction SilentlyContinue
        }

        $zipCandidates += Get-ChildItem -Path $scriptRoot -Filter "circuitjs-offline-web*.zip" -ErrorAction SilentlyContinue
        $zip = $zipCandidates |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $zip) {
            return $null
        }

        $cacheRoot = Join-Path $portableDataRoot "offline-web-cache"
        if (-not (Test-Path $cacheRoot)) {
            New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
        }

        $target = Join-Path $cacheRoot ($zip.BaseName)
        if (Test-Path $target) {
            $launcherPath = Join-Path $target "run-circuitjs-offline-web.ps1"
            $legacyLauncherPath = Join-Path $target "offline-web-launcher.ps1"
            if ((Test-Path $launcherPath) -or (Test-Path $legacyLauncherPath)) {
                return $target
            }
        }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Expand-Archive -Path $zip.FullName -DestinationPath $target -Force

        $launcherPath = Join-Path $target "run-circuitjs-offline-web.ps1"
        $legacyLauncherPath = Join-Path $target "offline-web-launcher.ps1"
        if ((Test-Path $launcherPath) -or (Test-Path $legacyLauncherPath)) {
            return $target
        }

        return $null
    }

    $workspace = Resolve-WebWorkspace
    if (-not $workspace) {
        return $false
    }

    $launcher = Join-Path $workspace "run-circuitjs-offline-web.ps1"
    if (-not (Test-Path $launcher)) {
        $launcher = Join-Path $workspace "offline-web-launcher.ps1"
    }
    if (-not (Test-Path $launcher)) {
        return $false
    }

    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $launcher)
    $args += "-Silent"
    if ($Config.simple) {
        $args += "-Simple"
    }
    if ($Config.port -gt 0) {
        $args += "-Port", "$($Config.port)"
    }

    try {
        Start-Process -FilePath "powershell" -ArgumentList $args -WorkingDirectory $workspace -WindowStyle Hidden | Out-Null
        return $true
    } catch {
        return $false
    }
}

$config = Load-Config

if ($Mode) {
    $config.mode = $Mode
    Save-Config -Config $config
}

if ($Configure) {
    if (-not (Configure-StartupGui -Config $config)) {
        Configure-Startup -Config $config
    }
    exit 0
}

$started = $false
switch ($config.mode) {
    'native' { $started = Start-Native }
    'java' { $started = Start-Java }
    'web' { $started = Start-Web -Config $config }
}

if (-not $started) {
    $started = Start-Native
    if (-not $started) {
        $started = Start-Java
    }
    if (-not $started) {
        $started = Start-Web -Config $config
    }
}

if (-not $started) {
    throw "No launch mode is available. Build native package or ensure offline launchers are present."
}
