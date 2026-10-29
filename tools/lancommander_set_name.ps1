# Sets the LAN Coop player name from LANCommander (e.g. as its Name Change script).
# Writes $PlayerName as player_name into %APPDATA%\Brotato\lan_coop.cfg, the mod's config
# (net/net_config.gd). An existing file keeps every other setting; a missing one is created with
# only the name (the mod fills in the rest at its next save).
# Run it while the game is closed: the game writes the whole file whenever a setting changes.

# The host cuts names to NetProtocol.MAX_NAME_LENGTH characters.
$maxNameLength = 16

$name = "$PlayerName".Trim()
if ($name -eq "") {
	Write-Warning "PlayerName is empty, lan_coop.cfg left unchanged."
	return
}
if ($name.Length -gt $maxNameLength) {
	$name = $name.Substring(0, $maxNameLength).Trim()
}

$dir = Join-Path $env:APPDATA "Brotato"
$path = Join-Path $dir "lan_coop.cfg"

# A Godot ConfigFile string: quoted, with backslashes and quotes escaped.
$escaped = $name.Replace('\', '\\').Replace('"', '\"')
$nameLine = "player_name=`"$escaped`""

$lines = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $path) {
	foreach ($line in [System.IO.File]::ReadAllLines($path)) {
		$lines.Add($line)
	}
}

# Replace player_name in the [lan_coop] section; add the line (and the section) if missing.
$sectionStart = -1
$nameIndex = -1
$section = ""
for ($i = 0; $i -lt $lines.Count; $i++) {
	$trimmed = $lines[$i].Trim()
	if ($trimmed -match '^\[(.+)\]$') {
		$section = $Matches[1]
		if ($section -eq "lan_coop") {
			$sectionStart = $i
		}
	}
	elseif ($section -eq "lan_coop" -and $trimmed -match '^player_name\s*=') {
		$nameIndex = $i
	}
}

if ($nameIndex -ge 0) {
	$lines[$nameIndex] = $nameLine
}
elseif ($sectionStart -ge 0) {
	$lines.Insert($sectionStart + 1, $nameLine)
}
else {
	$lines.Insert(0, "[lan_coop]")
	$lines.Insert(1, "")
	$lines.Insert(2, $nameLine)
	if ($lines.Count -gt 3) {
		$lines.Insert(3, "")
	}
}

New-Item -ItemType Directory -Force -Path $dir | Out-Null
# UTF-8 without a BOM: Godot's ConfigFile can't parse a BOM, and the mod would then pick a random
# name and overwrite the file.
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, ($lines -join "`r`n") + "`r`n", $utf8)
Write-Host "LAN Coop player name set to '$name' in $path"
