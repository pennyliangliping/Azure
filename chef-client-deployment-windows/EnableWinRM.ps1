cmd.exe /c "winrm quickconfig -force" >> C:\log.txt
echo "-----------------------" >> C:\log.txt
cmd.exe /c 'winrm set winrm/config/client/auth @{Basic="true"}' >> C:\log.txt
echo "-----------------------" >> C:\log.txt
cmd.exe /c 'winrm set winrm/config/service/auth @{Basic="true"}' >> C:\log.txt
echo "-----------------------" >> C:\log.txt
cmd.exe /c 'winrm set winrm/config/service @{AllowUnencrypted="true"}' >> C:\log.txt
echo "-----------------------" >> C:\log.txt
$res = Get-NetConnectionProfile
$res >> C:\log.txt
Set-NetConnectionProfile -InterfaceIndex $res.InterfaceIndex -NetworkCategory Private
