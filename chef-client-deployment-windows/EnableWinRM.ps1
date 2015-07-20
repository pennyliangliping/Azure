cmd.exe /c "winrm quickconfig -force"
cmd.exe /c 'winrm set winrm/config/client/auth @{Basic="true"}'
cmd.exe /c 'winrm set winrm/config/service/auth @{Basic="true"}'
cmd.exe /c 'winrm set winrm/config/service @{AllowUnencrypted="true"}'

