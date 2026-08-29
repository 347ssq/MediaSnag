# MediaSnag - Windows URL Scheme Registration
# Registers ytdl:// and ytdla:// protocol handlers in the current user's registry

$installDir = "$env:LOCALAPPDATA\ytdlp"
$handlerPath = "$installDir\url_handler.bat"

# Register ytdl:// (video)
$ytdlKey = "HKCU:\Software\Classes\ytdl"
if (!(Test-Path $ytdlKey)) { New-Item -Path $ytdlKey -Force | Out-Null }
Set-ItemProperty -Path $ytdlKey -Name "(Default)" -Value "URL:MediaSnag"
Set-ItemProperty -Path $ytdlKey -Name "URL Protocol" -Value ""

$ytdlCommand = "$ytdlKey\shell\open\command"
if (!(Test-Path $ytdlCommand)) { New-Item -Path $ytdlCommand -Force | Out-Null }
Set-ItemProperty -Path $ytdlCommand -Name "(Default)" -Value "`"$handlerPath`" `"%1`""

# Register ytdla:// (audio)
$ytdlaKey = "HKCU:\Software\Classes\ytdla"
if (!(Test-Path $ytdlaKey)) { New-Item -Path $ytdlaKey -Force | Out-Null }
Set-ItemProperty -Path $ytdlaKey -Name "(Default)" -Value "URL:MediaSnag Audio"
Set-ItemProperty -Path $ytdlaKey -Name "URL Protocol" -Value ""

$ytdlaCommand = "$ytdlaKey\shell\open\command"
if (!(Test-Path $ytdlaCommand)) { New-Item -Path $ytdlaCommand -Force | Out-Null }
Set-ItemProperty -Path $ytdlaCommand -Name "(Default)" -Value "`"$handlerPath`" `"%1`""

Write-Host "  URL Scheme 已注册: ytdl:// ytdla://"
