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
$forceCompatConfig = ($env:CIRSIM_FORCE_CONFIG_COMPAT -eq "1")
$hasConvertFromJson = (-not $forceCompatConfig) -and ($null -ne (Get-Command ConvertFrom-Json -ErrorAction SilentlyContinue))
$hasConvertToJson = (-not $forceCompatConfig) -and ($null -ne (Get-Command ConvertTo-Json -ErrorAction SilentlyContinue))
$hasExpandArchive = ($null -ne (Get-Command Expand-Archive -ErrorAction SilentlyContinue))

function Test-PathSafe {
    param([string]$LiteralPath)

    if (($null -eq $LiteralPath) -or ($LiteralPath -eq "")) {
        return $false
    }

    return Test-Path -LiteralPath $LiteralPath
}

function Ensure-Directory {
    param([string]$LiteralPath)

    if (($null -eq $LiteralPath) -or ($LiteralPath -eq "")) {
        return
    }

    [System.IO.Directory]::CreateDirectory($LiteralPath) | Out-Null
}

function Read-TextFile {
    param([string]$LiteralPath)

    if (-not (Test-PathSafe -LiteralPath $LiteralPath)) {
        return ""
    }

    try {
        return [System.IO.File]::ReadAllText($LiteralPath)
    } catch {
        return ""
    }
}

function Write-TextFileUtf8 {
    param(
        [string]$LiteralPath,
        [string]$Content
    )

    $parent = Split-Path -Parent $LiteralPath
    Ensure-Directory -LiteralPath $parent
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Content, $utf8NoBom)
}

function Convert-ConfigToJsonText {
    param([hashtable]$Config)

    if ($hasConvertToJson) {
        try {
            return ($Config | ConvertTo-Json -Compress)
        } catch {
        }
    }

    $mode = [string]$Config.mode
    if (($null -eq $mode) -or ($mode -eq "")) {
        $mode = "web"
    }
    $modeEscaped = $mode.Replace('\', '\\').Replace('"', '\"')
    $simpleValue = if ([bool]$Config.simple) { "true" } else { "false" }
    $portValue = [int]$Config.port
    return "{`"mode`":`"$modeEscaped`",`"simple`":$simpleValue,`"port`":$portValue}"
}

function Convert-JsonTextToConfig {
    param(
        [string]$Text,
        [hashtable]$Default
    )

    $result = @{
        mode = [string]$Default.mode
        simple = [bool]$Default.simple
        port = [int]$Default.port
    }

    if ($hasConvertFromJson) {
        try {
            $json = $Text | ConvertFrom-Json
            if ($json.mode) {
                $result.mode = [string]$json.mode
            }
            if ($null -ne $json.simple) {
                $result.simple = [bool]$json.simple
            }
            if ($json.port) {
                $result.port = [int]$json.port
            }
            return $result
        } catch {
        }
    }

    if ($Text -match '"mode"\s*:\s*"([^"]+)"') {
        $result.mode = [string]$matches[1]
    }
    if ($Text -match '"simple"\s*:\s*(true|false)') {
        $result.simple = ([string]$matches[1]).ToLowerInvariant() -eq "true"
    }
    if ($Text -match '"port"\s*:\s*(\d+)') {
        $result.port = [int]$matches[1]
    }
    return $result
}

function Patch-WebLauncherCompatibility {
    param([string]$LauncherPath)

    if (-not (Test-PathSafe -LiteralPath $LauncherPath)) {
        return
    }

    $original = Read-TextFile -LiteralPath $LauncherPath
    if (($null -eq $original) -or ($original -eq "")) {
        return
    }

    $patched = $original
    $patched = $patched.Replace('Test-Path $shellFile', 'Test-Path -LiteralPath $shellFile')
    $patched = $patched.Replace('Test-Path $launchFile', 'Test-Path -LiteralPath $launchFile')
    $patched = $patched.Replace('Test-Path $runtimeDir', 'Test-Path -LiteralPath $runtimeDir')
    $patched = $patched.Replace('Set-Content -Path $serverScript', 'Set-Content -LiteralPath $serverScript')
    $patched = $patched.Replace('Test-Path $filePath -PathType Container', 'Test-Path -LiteralPath $filePath -PathType Container')
    $patched = $patched.Replace('Test-Path $filePath -PathType Leaf', 'Test-Path -LiteralPath $filePath -PathType Leaf')

    if ($patched -ne $original) {
        Write-TextFileUtf8 -LiteralPath $LauncherPath -Content $patched
    }
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
        if (($null -ne $WorkingDirectory) -and ($WorkingDirectory -ne "")) {
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
            try {
                Start-Process @startProcessParams | Out-Null
                return $true
            } catch {
                $null = $startProcessParams.Remove('WindowStyle')
            }
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

function Expand-ZipPortable {
    param(
        [string]$ZipPath,
        [string]$DestinationPath
    )

    if (-not (Test-PathSafe -LiteralPath $ZipPath)) {
        return $false
    }

    Ensure-Directory -LiteralPath $DestinationPath

    if ($hasExpandArchive) {
        try {
            Expand-Archive -LiteralPath $ZipPath -DestinationPath $DestinationPath -Force
            return $true
        } catch {
        }
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinationPath)
        return $true
    } catch {
    }

    try {
        $shell = New-Object -ComObject Shell.Application
        $zipNamespace = $shell.NameSpace($ZipPath)
        $targetNamespace = $shell.NameSpace($DestinationPath)
        if (($null -eq $zipNamespace) -or ($null -eq $targetNamespace)) {
            return $false
        }

        $targetNamespace.CopyHere($zipNamespace.Items(), 16)
        $timeout = [DateTime]::UtcNow.AddSeconds(30)
        while (([DateTime]::UtcNow -lt $timeout) -and ($targetNamespace.Items().Count -lt $zipNamespace.Items().Count)) {
            Start-Sleep -Milliseconds 200
        }
        return $true
    } catch {
        return $false
    }
}

function Test-PortAvailable {
    param([int]$Port)

    if (($Port -lt 1) -or ($Port -gt 65535)) {
        return $false
    }

    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) {
            try {
                $listener.Stop()
            } catch {
            }
        }
    }
}

function Resolve-WebPort {
    param([int]$PreferredPort)

    if (Test-PortAvailable -Port $PreferredPort) {
        return $PreferredPort
    }

    $candidates = @(
        ($PreferredPort + 1),
        ($PreferredPort + 2),
        19084,
        19085,
        19086,
        18080,
        8080
    )
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-PortAvailable -Port $candidate) {
            return $candidate
        }
    }
    return $PreferredPort
}

function Test-HttpPortReady {
    param(
        [int]$Port,
        [int]$Attempts = 40
    )

    for ($i = 0; $i -lt $Attempts; $i++) {
        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(250)) {
                $client.EndConnect($iar)
                return $true
            }
        } catch {
        } finally {
            if ($client) {
                $client.Dispose()
            }
        }
        Start-Sleep -Milliseconds 120
    }

    return $false
}

function Ensure-EmbeddedServerScript {
    param([string]$RuntimeDir)

    Ensure-Directory -LiteralPath $RuntimeDir
    $scriptPath = Join-Path $RuntimeDir "embedded-http-server.ps1"
    if (Test-PathSafe -LiteralPath $scriptPath) {
        return $scriptPath
    }

    $serverScript = @'
param(
    [string]$RootPath,
    [int]$Port
)

$ErrorActionPreference = "Stop"
$rootFull = [System.IO.Path]::GetFullPath($RootPath)

function Decode-RelativePath {
    param([string]$RawPath)

    $decoded = $RawPath
    try {
        $decoded = [System.Uri]::UnescapeDataString($RawPath.Replace('+', '%20'))
    } catch {
    }

    if (($null -eq $decoded) -or ($decoded -eq "")) {
        return "circuitjs.html"
    }
    return $decoded
}

function Get-MimeType {
    param([string]$Path)

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.html' { return 'text/html; charset=utf-8' }
        '.js' { return 'application/javascript; charset=utf-8' }
        '.css' { return 'text/css; charset=utf-8' }
        '.json' { return 'application/json; charset=utf-8' }
        '.txt' { return 'text/plain; charset=utf-8' }
        '.xml' { return 'application/xml; charset=utf-8' }
        '.svg' { return 'image/svg+xml' }
        '.png' { return 'image/png' }
        '.jpg' { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.gif' { return 'image/gif' }
        '.ico' { return 'image/x-icon' }
        '.woff' { return 'font/woff' }
        '.woff2' { return 'font/woff2' }
        default { return 'application/octet-stream' }
    }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $relative = Decode-RelativePath -RawPath ($context.Request.Url.AbsolutePath.TrimStart('/'))
            $relative = $relative.Replace('/', '\')
            $candidate = Join-Path $rootFull $relative
            $fullPath = [System.IO.Path]::GetFullPath($candidate)

            if (($fullPath.Length -lt $rootFull.Length) -or ($fullPath.Substring(0, $rootFull.Length).ToLowerInvariant() -ne $rootFull.ToLowerInvariant())) {
                $context.Response.StatusCode = 403
                $context.Response.Close()
                continue
            }

            if (Test-Path -LiteralPath $fullPath -PathType Container) {
                $fullPath = Join-Path $fullPath "index.html"
            }

            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                $context.Response.StatusCode = 404
                $context.Response.Close()
                continue
            }

            $bytes = [System.IO.File]::ReadAllBytes($fullPath)
            $context.Response.StatusCode = 200
            $context.Response.ContentType = Get-MimeType -Path $fullPath
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $context.Response.OutputStream.Flush()
            $context.Response.Close()
        } catch {
            try {
                $context.Response.StatusCode = 500
                $context.Response.Close()
            } catch {
            }
        }
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
'@

    Write-TextFileUtf8 -LiteralPath $scriptPath -Content $serverScript
    return $scriptPath
}

function Start-WebEmbedded {
    param(
        [string]$Workspace,
        [hashtable]$Config
    )

    $offlineHome = Join-Path $Workspace "offline-home.html"
    $launchFile = if (Test-PathSafe -LiteralPath $offlineHome) { $offlineHome } else { Join-Path $Workspace "circuitjs.html" }
    if (-not (Test-PathSafe -LiteralPath $launchFile)) {
        return $false
    }

    $requestedPort = 19084
    if ($Config.port -gt 0) {
        $requestedPort = [int]$Config.port
    }
    $resolvedPort = Resolve-WebPort -PreferredPort $requestedPort
    if ($resolvedPort -le 0) {
        return $false
    }
    if ($Config.port -ne $resolvedPort) {
        $Config.port = $resolvedPort
        try {
            Save-Config -Config $Config
        } catch {
        }
    }

    $runtimeDir = Join-Path $portableDataRoot "web-runtime"
    $serverScript = Ensure-EmbeddedServerScript -RuntimeDir $runtimeDir
    if (-not (Test-PathSafe -LiteralPath $serverScript)) {
        return $false
    }

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $serverScript,
        "-RootPath", $Workspace,
        "-Port", "$resolvedPort"
    )
    if (-not (Start-ProcessPortable -FilePath $powerShellExe -ArgumentList $args -WorkingDirectory $runtimeDir -Hidden)) {
        return $false
    }

    if (-not (Test-HttpPortReady -Port $resolvedPort -Attempts 45)) {
        return $false
    }

    $launchName = [System.IO.Path]::GetFileName($launchFile)
    $url = "http://127.0.0.1:$resolvedPort/$launchName"
    if ($Config.simple) {
        if ($launchName -eq "offline-home.html") {
            $url = "http://127.0.0.1:$resolvedPort/circuitjs.html"
        }
        if ($url.Contains('?')) {
            $url += "&hideSidebar=true"
        } else {
            $url += "?hideSidebar=true"
        }
    }

    try {
        Start-Process $url | Out-Null
        return $true
    } catch {
        return $false
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
        $default = Get-DefaultConfig
        $rawText = Read-TextFile -LiteralPath $configPath
        return Convert-JsonTextToConfig -Text $rawText -Default $default
    } catch {
        $default = Get-DefaultConfig
        Save-Config -Config $default
        return $default
    }
}

function Save-Config {
    param([hashtable]$Config)
    $jsonText = Convert-ConfigToJsonText -Config $Config
    Write-TextFileUtf8 -LiteralPath $configPath -Content $jsonText
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
            if (-not (Expand-ZipPortable -ZipPath $zip.FullName -DestinationPath $target)) {
                return $null
            }
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
    if ($env:CIRSIM_ENABLE_EMBEDDED_SERVER -eq "1") {
        if (Start-WebEmbedded -Workspace $workspace -Config $Config) {
            return $true
        }
    }

    $launcher = Join-Path $workspace "run-circuitjs-offline-web.ps1"
    if (-not (Test-PathSafe -LiteralPath $launcher)) {
        $launcher = Join-Path $workspace "offline-web-launcher.ps1"
    }
    if (-not (Test-PathSafe -LiteralPath $launcher)) {
        return $false
    }
    Patch-WebLauncherCompatibility -LauncherPath $launcher

    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $launcher)
    $args += "-NoServer"
    $args += "-Silent"
    if ($Config.simple) {
        $args += "-Simple"
    }
    $requestedPort = 19084
    if ($Config.port -gt 0) {
        $requestedPort = [int]$Config.port
    }
    $resolvedPort = Resolve-WebPort -PreferredPort $requestedPort
    if ($resolvedPort -gt 0) {
        if ($Config.port -ne $resolvedPort) {
            $Config.port = $resolvedPort
            try {
                Save-Config -Config $Config
            } catch {
            }
        }
        $args += "-Port", "$resolvedPort"
    }

    $originalPath = $env:Path
    $originalLocalAppData = $env:LOCALAPPDATA
    try {
        if (($null -eq $env:LOCALAPPDATA) -or ($env:LOCALAPPDATA -eq "")) {
            $fallbackLocalAppData = Join-Path $portableDataRoot "localappdata"
            Ensure-Directory -LiteralPath $fallbackLocalAppData
            $env:LOCALAPPDATA = $fallbackLocalAppData
        }

        if ($env:SystemRoot) {
            $psDir = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0"
            if (Test-PathSafe -LiteralPath $psDir) {
                if (($null -eq $env:Path) -or ($env:Path -eq "")) {
                    $env:Path = $psDir
                } elseif ($env:Path.ToLowerInvariant().IndexOf($psDir.ToLowerInvariant()) -lt 0) {
                    $env:Path = "$psDir;$env:Path"
                }
            }
        }

        return Start-ProcessPortable -FilePath $powerShellExe -ArgumentList $args -WorkingDirectory $workspace -Hidden
    } finally {
        $env:Path = $originalPath
        if (($null -eq $originalLocalAppData) -or ($originalLocalAppData -eq "")) {
            Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
        } else {
            $env:LOCALAPPDATA = $originalLocalAppData
        }
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
