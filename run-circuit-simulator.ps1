param(
    [switch]$Configure,
    [ValidateSet('native','java','web')]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageRoot = $scriptRoot
$parentRoot = Split-Path -Parent $scriptRoot
$scriptLeaf = Split-Path -Leaf $scriptRoot
$powerShellExe = "powershell"
if ($env:SystemRoot) {
    $defaultPowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $defaultPowerShellExe) {
        $powerShellExe = $defaultPowerShellExe
    }
}

function Test-PathSafe {
    param([string]$LiteralPath)

    if ([string]::IsNullOrWhiteSpace($LiteralPath)) {
        return $false
    }

    return Test-Path -LiteralPath $LiteralPath
}

function Ensure-Directory {
    param([string]$LiteralPath)

    if ([string]::IsNullOrWhiteSpace($LiteralPath)) {
        return
    }

    [System.IO.Directory]::CreateDirectory($LiteralPath) | Out-Null
}

function Start-ProcessPortable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        [switch]$Hidden
    )

    $originalDirectory = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $originalDirectory = [System.IO.Directory]::GetCurrentDirectory()
            [System.IO.Directory]::SetCurrentDirectory($WorkingDirectory)
        }

        $startProcessParams = @{
            FilePath = $FilePath
        }
        if ($ArgumentList -and $ArgumentList.Count -gt 0) {
            $startProcessParams.ArgumentList = $ArgumentList
        }
        if ($Hidden) {
            $startProcessParams.WindowStyle = 'Hidden'
        }

        Start-Process @startProcessParams | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $originalDirectory) {
            try {
                [System.IO.Directory]::SetCurrentDirectory($originalDirectory)
            } catch {
            }
        }
    }
}

function Test-PortableRoot {
    param([string]$Root)
    if (-not $Root) {
        return $false
    }

    $markers = @(
        (Join-Path $Root "Circuit Simulator.exe"),
        (Join-Path $Root "Circuit Simulator\Circuit Simulator.exe"),
        (Join-Path $Root "circuitjs-offline-web-release.zip"),
        (Join-Path $Root "tools\circuitjs-offline-web-release.zip")
    )

    foreach ($marker in $markers) {
        if (Test-PathSafe -LiteralPath $marker) {
            return $true
        }
    }
    return $false
}

if (($scriptLeaf -ieq "tools") -and (Test-PortableRoot -Root $parentRoot)) {
    $packageRoot = $parentRoot
} elseif (-not (Test-PortableRoot -Root $packageRoot) -and (Test-PortableRoot -Root $parentRoot)) {
    $packageRoot = $parentRoot
}

$portableDataRoot = Join-Path $packageRoot ".circuit-simulator"
$configDir = Join-Path $portableDataRoot "config"
Ensure-Directory -LiteralPath $configDir
$configPath = Join-Path $configDir "circuit-simulator-startup.json"
$legacyConfigPaths = @(
    (Join-Path $scriptRoot "circuit-simulator-startup.json")
)
if ($packageRoot -ne $scriptRoot) {
    $legacyConfigPaths += (Join-Path $packageRoot "circuit-simulator-startup.json")
}
$userConfigPath = $null
if ($env:LOCALAPPDATA) {
    $userConfigPath = Join-Path $env:LOCALAPPDATA "CircuitSimulator\circuit-simulator-startup.json"
}

function Get-DefaultConfig {
    return @{
        mode = "web"
        simple = $false
        port = 19084
    }
}

function Load-Config {
    if (-not (Test-PathSafe -LiteralPath $configPath)) {
        foreach ($legacyConfigPath in $legacyConfigPaths) {
            if (-not (Test-PathSafe -LiteralPath $legacyConfigPath)) {
                continue
            }
            try {
                Copy-Item -LiteralPath $legacyConfigPath -Destination $configPath -Force
                break
            } catch {
            }
        }
    }
    if ($userConfigPath -and (-not (Test-PathSafe -LiteralPath $configPath)) -and (Test-PathSafe -LiteralPath $userConfigPath)) {
        try {
            Copy-Item -LiteralPath $userConfigPath -Destination $configPath -Force
        } catch {
        }
    }

    if (-not (Test-PathSafe -LiteralPath $configPath)) {
        $default = Get-DefaultConfig
        Save-Config -Config $default
        return $default
    }

    try {
        $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $parsed = @{
            mode = if ($json.mode) { [string]$json.mode } else { "web" }
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
    ($Config | ConvertTo-Json) | Set-Content -LiteralPath $configPath -Encoding utf8
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
        (Join-Path $packageRoot "dist-native\Circuit Simulator\Circuit Simulator.exe"),
        (Join-Path $scriptRoot "dist-native\Circuit Simulator\Circuit Simulator.exe"),
        (Join-Path $packageRoot "Circuit Simulator\Circuit Simulator.exe"),
        (Join-Path $packageRoot "Circuit Simulator.exe"),
        (Join-Path $scriptRoot "Circuit Simulator\Circuit Simulator.exe"),
        (Join-Path $scriptRoot "Circuit Simulator.exe"),
        (Join-Path $scriptRoot "..\Circuit Simulator.exe"),
        (Join-Path $scriptRoot "..\Circuit Simulator\Circuit Simulator.exe")
    )

    $exe = $null
    foreach ($candidate in $nativeCandidates) {
        if (Test-PathSafe -LiteralPath $candidate) {
            $exe = $candidate
            break
        }
    }

    if ($exe -and (Test-PathSafe -LiteralPath $exe)) {
        $exeDir = Split-Path -Parent $exe
        return Start-ProcessPortable -FilePath $exe -WorkingDirectory $exeDir
    }
    return $false
}

function Start-Java {
    $javaCandidates = @(
        (Join-Path $packageRoot "run-circuitjs-offline.bat"),
        (Join-Path $scriptRoot "run-circuitjs-offline.bat"),
        (Join-Path $scriptRoot "..\run-circuitjs-offline.bat")
    )

    foreach ($bat in $javaCandidates) {
        if (Test-PathSafe -LiteralPath $bat) {
            $batDir = Split-Path -Parent $bat
            if (Start-ProcessPortable -FilePath $bat -WorkingDirectory $batDir) {
                return $true
            }
        }
    }
    return $false
}

function Start-Web {
    param([hashtable]$Config)

    function Resolve-WebWorkspace {
        $directRoots = @($packageRoot, $scriptRoot)
        foreach ($root in $directRoots | Select-Object -Unique) {
            $directLauncher = Join-Path $root "run-circuitjs-offline-web.ps1"
            $legacyDirectLauncher = Join-Path $root "offline-web-launcher.ps1"
            $directHtml = Join-Path $root "circuitjs.html"
            if (((Test-PathSafe -LiteralPath $directLauncher) -or (Test-PathSafe -LiteralPath $legacyDirectLauncher)) -and (Test-PathSafe -LiteralPath $directHtml)) {
                return $root
            }
        }

        $zipCandidates = @()
        $releaseZipPaths = @(
            (Join-Path $packageRoot "circuitjs-offline-web-release.zip"),
            (Join-Path $scriptRoot "circuitjs-offline-web-release.zip"),
            (Join-Path $packageRoot "tools\circuitjs-offline-web-release.zip"),
            (Join-Path $scriptRoot "tools\circuitjs-offline-web-release.zip")
        )
        foreach ($releaseZipPath in $releaseZipPaths | Select-Object -Unique) {
            if (Test-PathSafe -LiteralPath $releaseZipPath) {
                $zipCandidates += Get-Item -LiteralPath $releaseZipPath
            }
        }

        $distDirs = @(
            (Join-Path $packageRoot "dist"),
            (Join-Path $scriptRoot "dist")
        )
        foreach ($distDir in $distDirs | Select-Object -Unique) {
            if (Test-PathSafe -LiteralPath $distDir) {
                $distReleaseZip = Join-Path $distDir "circuitjs-offline-web-release.zip"
                if (Test-PathSafe -LiteralPath $distReleaseZip) {
                    $zipCandidates += Get-Item -LiteralPath $distReleaseZip
                }
                $zipCandidates += Get-ChildItem -LiteralPath $distDir -Filter "circuitjs-offline-web*.zip" -ErrorAction SilentlyContinue
            }
        }

        $searchDirs = @(
            $packageRoot,
            $scriptRoot,
            (Join-Path $packageRoot "tools"),
            (Join-Path $scriptRoot "tools")
        )
        foreach ($searchDir in $searchDirs | Select-Object -Unique) {
            if (Test-PathSafe -LiteralPath $searchDir) {
                $zipCandidates += Get-ChildItem -LiteralPath $searchDir -Filter "circuitjs-offline-web*.zip" -ErrorAction SilentlyContinue
            }
        }

        $zip = $zipCandidates |
            Sort-Object FullName -Unique |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $zip) {
            return $null
        }

        $cacheRoot = Join-Path $portableDataRoot "offline-web-cache"
        Ensure-Directory -LiteralPath $cacheRoot

        $zipStamp = "$($zip.BaseName)-$($zip.Length)-$([int64]$zip.LastWriteTimeUtc.ToFileTimeUtc())"
        $zipStamp = ($zipStamp -replace '[^A-Za-z0-9._-]', '_')
        $target = Join-Path $cacheRoot $zipStamp
        if (Test-PathSafe -LiteralPath $target) {
            $launcherPath = Join-Path $target "run-circuitjs-offline-web.ps1"
            $legacyLauncherPath = Join-Path $target "offline-web-launcher.ps1"
            if ((Test-PathSafe -LiteralPath $launcherPath) -or (Test-PathSafe -LiteralPath $legacyLauncherPath)) {
                return $target
            }
        }
        try {
            if (Test-PathSafe -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName, $target)
        } catch {
            return $null
        }

        $launcherPath = Join-Path $target "run-circuitjs-offline-web.ps1"
        $legacyLauncherPath = Join-Path $target "offline-web-launcher.ps1"
        if ((Test-PathSafe -LiteralPath $launcherPath) -or (Test-PathSafe -LiteralPath $legacyLauncherPath)) {
            return $target
        }

        return $null
    }

    $workspace = Resolve-WebWorkspace
    if (-not $workspace) {
        return $false
    }

    $launcher = Join-Path $workspace "run-circuitjs-offline-web.ps1"
    if (-not (Test-PathSafe -LiteralPath $launcher)) {
        $launcher = Join-Path $workspace "offline-web-launcher.ps1"
    }
    if (-not (Test-PathSafe -LiteralPath $launcher)) {
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

    return Start-ProcessPortable -FilePath $powerShellExe -ArgumentList $args -WorkingDirectory $workspace -Hidden
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
