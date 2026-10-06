# Native Windows bootstrap. The installation workflow stays in POSIX sh.
param(
    [string]$Template = 'https://github.com/ypolosov/workbench.git',
    [string]$Repo = '', [string]$Dir = '', [string]$BinDir = '',
    [string]$Project = '', [string]$PathStore = '',
    [switch]$Local, [switch]$Yes, [switch]$NoLaunch, [switch]$CoreOnly
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$wbToolsRoot = Join-Path $env:LOCALAPPDATA 'workbench\tools'
New-Item -ItemType Directory -Path $wbToolsRoot -Force | Out-Null
function Get-WorkbenchPackage([string]$Uri,[string]$Sha,[string]$Destination) {
    $wbPackagePart = $Destination + '.part'
    $wbSystemCurl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path -LiteralPath $wbSystemCurl) {
        & $wbSystemCurl --fail --location --retry 3 --connect-timeout 20 --silent --show-error $Uri --output $wbPackagePart
        if ($LASTEXITCODE -ne 0) { throw 'Could not download the Windows runtime' }
    } else {
        $wbDownloaded = $false
        for ($wbAttempt = 0; $wbAttempt -lt 3; $wbAttempt++) {
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $wbPackagePart
                $wbDownloaded = $true; break
            } catch { if ($wbAttempt -eq 2) { throw }; Start-Sleep -Seconds 1 }
        }
        if (-not $wbDownloaded) { throw 'Could not download the Windows runtime' }
    }
    if ((Get-FileHash -LiteralPath $wbPackagePart -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha) {
        throw 'Downloaded component failed its checksum check'
    }
    Move-Item -LiteralPath $wbPackagePart -Destination $Destination -Force
}
$wbGitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
$wbGitRoot = ''
if ($wbGitCommand) {
    $wbGitDirectory = Split-Path $wbGitCommand.Source -Parent
    foreach ($wbGitCandidate in @((Join-Path $wbGitDirectory '..'),(Join-Path $wbGitDirectory '..\..'))) {
        if (Test-Path -LiteralPath (Join-Path $wbGitCandidate 'bin\sh.exe')) {
            $wbGitRoot = [IO.Path]::GetFullPath($wbGitCandidate); break
        }
    }
}
if (-not $wbGitRoot) {
    Write-Host 'workbench: preparing the Windows runtime'
    $wbGitRoot = Join-Path $wbToolsRoot 'git'
    if (-not (Test-Path -LiteralPath (Join-Path $wbGitRoot 'bin\sh.exe'))) {
        $wbArchitecture = $env:PROCESSOR_ARCHITECTURE
        if ($env:PROCESSOR_ARCHITEW6432) { $wbArchitecture = $env:PROCESSOR_ARCHITEW6432 }
        if ($wbArchitecture -eq 'ARM64') {
            $wbGitAsset = 'PortableGit-2.56.0.2-arm64.7z.exe'
            $wbGitSha = '0f21e681bd33e006e0348dfa1a2be6769efd77e3bfdb247320314facde23a46c'
        } else {
            $wbGitAsset = 'PortableGit-2.56.0.2-64-bit.7z.exe'
            $wbGitSha = '075e158ef8e1f0ab80b347e245405d3eca735c2dc88fd8e032e137d0ca61f61b'
        }
        $wbGitArchive = Join-Path $wbToolsRoot $wbGitAsset
        Get-WorkbenchPackage ('https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/'+$wbGitAsset) $wbGitSha $wbGitArchive
        $wbExtract = Start-Process -FilePath $wbGitArchive -ArgumentList @('-y',('-o"'+$wbGitRoot+'"')) -WindowStyle Hidden -Wait -PassThru
        if ($wbExtract.ExitCode -ne 0) { throw 'Could not prepare the Windows runtime' }
    }
}
$env:WORKBENCH_GIT_SH = Join-Path $wbGitRoot 'bin\sh.exe'
if (-not $env:CLAUDE_CODE_GIT_BASH_PATH -or -not (Test-Path -LiteralPath $env:CLAUDE_CODE_GIT_BASH_PATH)) {
    $env:CLAUDE_CODE_GIT_BASH_PATH = Join-Path $wbGitRoot 'bin\bash.exe'
}
$env:Path = (Join-Path $wbGitRoot 'cmd') + ';' + $env:Path
if ($PathStore) { $env:WORKBENCH_PATH_STORE = $PathStore }
$wbStage = Join-Path ([IO.Path]::GetTempPath()) ('workbench-source-'+[Guid]::NewGuid().ToString('N'))
& (Join-Path $wbGitRoot 'cmd\git.exe') clone --quiet $Template $wbStage
if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve the workbench installer' }
$wbArguments = @((Join-Path $wbStage 'install.sh').Replace('\','/'),'--template',$Template)
if ($Repo) { $wbArguments += @('--repo',$Repo) }
if ($Dir) { $wbArguments += @('--dir',$Dir) }
if ($BinDir) { $wbArguments += @('--bin-dir',$BinDir) }
if ($Project) { $wbArguments += @('--project',$Project) }
if ($Local) { $wbArguments += '--local' }
if ($Yes) { $wbArguments += '--yes' }
$wbArguments += '--no-launch'
if ($CoreOnly) { $wbArguments += '--core-only' }
& $env:WORKBENCH_GIT_SH @wbArguments
$wbInstallExit = $LASTEXITCODE
if ($PathStore) {
    $env:Path = [IO.File]::ReadAllText($PathStore) + ';' + $env:Path
} else {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
if ($wbInstallExit -ne 0) { throw ('workbench installation did not complete: '+$wbInstallExit) }
if (-not $NoLaunch -and -not $CoreOnly -and -not [Console]::IsInputRedirected) {
    Write-Host 'workbench: opening the prepared terminal'
    $wbParent = Get-CimInstance Win32_Process -Filter ('ProcessId='+(Get-CimInstance Win32_Process -Filter ('ProcessId='+$PID)).ParentProcessId)
    if ($wbParent.Name -ieq 'cmd.exe') { & $env:ComSpec /d }
    elseif ($wbParent.Name -ieq 'pwsh.exe') { & $wbParent.ExecutablePath -NoLogo -NoProfile -NoExit }
    else { & powershell.exe -NoLogo -NoProfile -NoExit }
}
