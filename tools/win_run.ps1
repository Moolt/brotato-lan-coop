# Starts the shipped game on a Windows test PC (see docs/testing.md, "Shipped game and Windows").
# Copy it next to the test copy: <dir>\win_run.ps1, <dir>\game\Brotato.exe (+ .pck files, mods\).
# Runs the game as a scheduled task in the logged-in desktop session: started directly from an ssh
# session it would get no window and no OpenGL. Each name gets its own APPDATA (save, logs,
# lan_coop.cfg) under <dir>\appdata\<name>; stdout goes to <dir>\logs\<name>.log, ending with
# "exit <code>". Screenshots go to <dir>\shots.
# Usage: win_run.ps1 <name> <role> ["K=V K2=V2" driver options] ["extra game args"]
param([string]$name, [string]$role, [string]$envs = "", [string]$extra = "")
$t = $PSScriptRoot
New-Item -ItemType Directory -Force "$t\appdata\$name", "$t\logs", "$t\shots" | Out-Null
$lines = @("@echo off", "cd /d $t\game", "set SHOT_DIR=$t\shots", "set APPDATA=$t\appdata\$name")
foreach ($kv in ($envs -split " " | Where-Object { $_ -ne "" })) { $lines += "set $kv" }
$lines += "Brotato.exe $extra -- $role > $t\logs\$name.log 2>&1"
$lines += "echo exit %ERRORLEVEL% >> $t\logs\$name.log"
Set-Content -Encoding ASCII "$t\$name.cmd" $lines
schtasks /create /tn "BrotatoTest_$name" /tr "$t\$name.cmd" /sc once /st 23:59 /it /f | Out-Null
schtasks /run /tn "BrotatoTest_$name" | Out-Null
