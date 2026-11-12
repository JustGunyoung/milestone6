<#
Sets up this project on Windows. Run it from the project folder with:

    powershell -ExecutionPolicy Bypass -File .\setup.ps1

1. Finds a 64-bit Python 3.14. If there is none, downloads the official
   installer from python.org, checks its SHA-256 and installs it for this user
   only. Other Python versions stay installed, and PATH and the program that
   opens .py files are not changed.
2. Builds .venv with that Python and installs requirements.txt into it.
3. Creates .env from .env.example if .env doesn't exist yet.

Why 3.14: web3 depends on ckzg, a C library whose prebuilt Windows packages
cover 64-bit Python 3.9-3.14 only. On a newer or 32-bit Python, pip tries to
compile it and fails unless a C compiler is installed.

Safe to run again: it keeps a .venv that is already correct.
#>

$ErrorActionPreference = 'Stop'

# Official installer and its SHA-256, as listed on
# https://www.python.org/downloads/release/python-31410/
$InstallerUrl = 'https://www.python.org/ftp/python/3.14.10/python-3.14.10-amd64.exe'
$InstallerSha256 = '92480239264744FE0386A1BD8275786FEFA126E3129E56A68E22B52C73329965'

$VenvDir = Join-Path $PSScriptRoot '.venv'
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'


function Get-PythonInfo([string]$Exe) {
    # Ask an interpreter what it is. Returns $null if it doesn't run.
    $ErrorActionPreference = 'Continue'
    $code = "import sys, sysconfig; print(sys.version.split()[0], sysconfig.get_platform(), int(bool(sysconfig.get_config_var('Py_GIL_DISABLED'))), int(sys.prefix != sys.base_prefix))"
    try { $out = & $Exe -c $code 2>$null } catch { return $null }
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    $version, $platform, $freeThreaded, $isVenv = "$($out | Select-Object -Last 1)".Trim() -split ' '
    [pscustomobject]@{
        Exe          = $Exe
        Version      = $version
        Platform     = $platform
        FreeThreaded = $freeThreaded -eq '1'
        IsVenv       = $isVenv -eq '1'
    }
}


function Test-Usable($Info) {
    # 64-bit x64 CPython 3.14, standard build. The free-threaded build is
    # excluded because not every dependency ships packages for it.
    $Info -and $Info.Version -like '3.14.*' -and $Info.Platform -eq 'win-amd64' -and -not $Info.FreeThreaded
}


function Find-Python314 {
    $candidates = New-Object System.Collections.Generic.List[string]

    # Registry entries that python.org installers write (PEP 514).
    foreach ($root in 'HKCU:\Software\Python\PythonCore', 'HKLM:\Software\Python\PythonCore') {
        foreach ($key in Get-ChildItem $root -ErrorAction SilentlyContinue) {
            if ($key.PSChildName -notlike '3.14*') { continue }
            $installPath = Get-ItemProperty (Join-Path $key.PSPath 'InstallPath') -ErrorAction SilentlyContinue
            if (-not $installPath) { continue }
            if ($installPath.ExecutablePath) { $candidates.Add($installPath.ExecutablePath) }
            if ($installPath.'(default)') { $candidates.Add((Join-Path $installPath.'(default)' 'python.exe')) }
        }
    }

    # Default install folders: python.org per-user, all-users, Python install manager.
    $candidates.Add("$env:LOCALAPPDATA\Programs\Python\Python314\python.exe")
    $candidates.Add("$env:ProgramFiles\Python314\python.exe")
    $candidates.Add("$env:LOCALAPPDATA\Python\pythoncore-3.14-64\python.exe")

    # Anything on PATH. Microsoft Store stubs are skipped because running one
    # can open the Store instead of Python.
    Get-Command python, python3, python3.14 -All -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*\WindowsApps\*' } |
        ForEach-Object { $candidates.Add($_.Source) }

    foreach ($exe in $candidates | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        $info = Get-PythonInfo $exe
        # A venv's python is skipped; the new .venv should come from a real install.
        if ((Test-Usable $info) -and -not $info.IsVenv) { return $info }
    }
    return $null
}


function Test-Pip([string]$Exe) {
    $ErrorActionPreference = 'Continue'
    try { & $Exe -m pip --version *> $null } catch { return $false }
    $LASTEXITCODE -eq 0
}


function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    # With 'Stop', Windows PowerShell turns any stderr line (such as a pip
    # warning) into a terminating error when output is redirected, even if the
    # command succeeds. Use the exit code instead.
    # Its output goes to the host so only the result is returned.
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments | ForEach-Object { Write-Host $_ }
    $LASTEXITCODE -eq 0
}


function Install-Python314 {
    # A fresh folder, so a partial download is always cleaned up and nothing
    # else sits next to the installer when it runs.
    $dir = Join-Path $env:TEMP ('python-setup-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir | Out-Null
    try {
        $installer = Join-Path $dir $InstallerUrl.Split('/')[-1]
        Write-Host "Downloading $InstallerUrl"
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'  # the progress bar slows downloads a lot in Windows PowerShell
        Invoke-WebRequest $InstallerUrl -OutFile $installer -UseBasicParsing

        $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
        if ($hash -ne $InstallerSha256) {
            throw "Downloaded installer has SHA-256 $hash, expected $InstallerSha256. Not running it."
        }
        Write-Host 'Installing Python 3.14 for this user. Other Python versions, PATH and .py file associations are left as they are.'
        $arguments = '/quiet', 'InstallAllUsers=0', 'PrependPath=0', 'AssociateFiles=0', 'Include_launcher=0', 'Include_test=0'
        $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -notin 0, 3010) {
            throw "Python installer failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This project needs 64-bit Windows: the packages it uses have no 32-bit builds.'
}

# 1-2. Python 3.14 and .venv
$venv = $null
if (Test-Path -LiteralPath $VenvPython) { $venv = Get-PythonInfo $VenvPython }

if ((Test-Usable $venv) -and $venv.IsVenv -and (Test-Pip $VenvPython)) {
    Write-Host "Keeping the existing .venv (Python $($venv.Version))."
}
else {
    $python = Find-Python314
    if (-not $python) {
        Write-Host 'No 64-bit Python 3.14 found.'
        Install-Python314
        $python = Find-Python314
        if (-not $python) { throw 'Python 3.14 was installed but could not be found afterwards.' }
    }
    Write-Host "Using Python $($python.Version) at $($python.Exe)"

    if (Test-Path -LiteralPath $VenvDir) {
        Write-Host 'Rebuilding .venv: it is not a working 64-bit Python 3.14 environment with pip.'
        Remove-Item -LiteralPath $VenvDir -Recurse -Force
    }
    if (-not (Invoke-Native $python.Exe '-m', 'venv', $VenvDir)) { throw 'Creating .venv failed.' }
}

$requirements = Join-Path $PSScriptRoot 'requirements.txt'
if (-not (Invoke-Native $VenvPython '-m', 'pip', 'install', '--disable-pip-version-check', '-r', $requirements)) {
    throw 'Installing requirements failed. See the pip output above.'
}

# 3. .env
$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '.env.example') -Destination $envFile
    Write-Host 'Created .env. Open it and paste your key after API_KEY=.'
}

Write-Host ''
Write-Host 'Setup complete. Run the script with:'
Write-Host '    .venv\Scripts\python read_pool.py'
