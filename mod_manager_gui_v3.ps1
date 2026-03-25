param(
    [string]$RootDir = ""
)
# Crimson Desert - Mod Manager v3 (3-Panel with Toggle Switches)
# LEFT: Available mods | MIDDLE: Active mods | RIGHT: Per-patch toggles

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Configuration ---
if ($RootDir -ne "" -and (Test-Path $RootDir)) {
    $ScriptDir = $RootDir
} else {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
$ModsAll     = Join-Path $ScriptDir "mods"
$ModsEnabled = Join-Path $ModsAll "enabled"
$ModManagerExe = Join-Path $ScriptDir "mod_manager.exe"
$ModManagerPy  = Join-Path $ScriptDir "mod_manager.py"

# Prefer EXE (no Python needed), fall back to Python
$script:UseExe = Test-Path $ModManagerExe
if (-not $script:UseExe) {
    $PythonExe = $null
    foreach ($candidate in @("python", "python3", "E:\Anaconda\python.exe")) {
        try {
            $test = & $candidate --version 2>&1
            if ($test -match "Python") { $PythonExe = $candidate; break }
        } catch {}
    }
    if (-not $PythonExe) {
        [System.Windows.Forms.MessageBox]::Show("mod_manager.exe not found and Python not available.", "Error", "OK", "Error")
        exit 1
    }
}

if (-not (Test-Path $ModsAll))     { New-Item -ItemType Directory -Path $ModsAll     -Force | Out-Null }
if (-not (Test-Path $ModsEnabled)) { New-Item -ItemType Directory -Path $ModsEnabled -Force | Out-Null }

# --- Game Path Detection ---
$script:GameDir = $null
try {
    $steamReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue
    if ($steamReg) {
        $steamPath = $steamReg.InstallPath
        $candidate = Join-Path $steamPath "steamapps\common\Crimson Desert"
        if (Test-Path $candidate) { $script:GameDir = $candidate }
        if (-not $script:GameDir) {
            $vdfPath = Join-Path $steamPath "steamapps\libraryfolders.vdf"
            if (Test-Path $vdfPath) {
                $vdfContent = Get-Content $vdfPath -Raw
                $libPaths = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                foreach ($m in $libPaths) {
                    $libPath = $m.Groups[1].Value -replace '\\\\', '\'
                    $candidate = Join-Path $libPath "steamapps\common\Crimson Desert"
                    if (Test-Path $candidate) { $script:GameDir = $candidate; break }
                }
            }
        }
    }
} catch {}
if (-not $script:GameDir) {
    foreach ($p in @(
        "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert",
        "D:\SteamLibrary\steamapps\common\Crimson Desert",
        "E:\SteamLibrary\steamapps\common\Crimson Desert",
        "G:\SteamLibrary\steamapps\common\Crimson Desert"
    )) {
        if (Test-Path $p) { $script:GameDir = $p; break }
    }
}

$BackupsDir = Join-Path $ScriptDir "backups"
if (-not (Test-Path $BackupsDir)) { New-Item -ItemType Directory -Path $BackupsDir -Force | Out-Null }

# ══════════════════════════════════════════════════════════════════
# THEME
# ══════════════════════════════════════════════════════════════════
$BgDark       = [System.Drawing.Color]::FromArgb(20, 21, 28)
$BgPanel      = [System.Drawing.Color]::FromArgb(28, 30, 38)
$BgCard       = [System.Drawing.Color]::FromArgb(36, 38, 48)
$BgCardHover  = [System.Drawing.Color]::FromArgb(44, 47, 60)
$BgRow        = [System.Drawing.Color]::FromArgb(32, 34, 44)
$BgRowAlt     = [System.Drawing.Color]::FromArgb(28, 30, 40)
$BgRowOff     = [System.Drawing.Color]::FromArgb(38, 30, 30)
$BgRowSel     = [System.Drawing.Color]::FromArgb(40, 50, 70)
$BgRowSelOff  = [System.Drawing.Color]::FromArgb(50, 40, 50)
$BgToggleOn   = [System.Drawing.Color]::FromArgb(40, 160, 70)
$BgToggleOff  = [System.Drawing.Color]::FromArgb(70, 50, 50)
$AccentRed    = [System.Drawing.Color]::FromArgb(200, 50, 50)
$AccentGreen  = [System.Drawing.Color]::FromArgb(50, 180, 80)
$AccentBlue   = [System.Drawing.Color]::FromArgb(60, 120, 220)
$AccentOrange = [System.Drawing.Color]::FromArgb(220, 150, 30)
$AccentCyan   = [System.Drawing.Color]::FromArgb(60, 190, 210)
$AccentPurple = [System.Drawing.Color]::FromArgb(140, 100, 220)
$AccentYellow = [System.Drawing.Color]::FromArgb(210, 190, 60)
$TextWhite    = [System.Drawing.Color]::FromArgb(230, 230, 235)
$TextGray     = [System.Drawing.Color]::FromArgb(140, 145, 160)
$TextMuted    = [System.Drawing.Color]::FromArgb(90, 95, 110)
$TextDim      = [System.Drawing.Color]::FromArgb(110, 115, 130)

# Category color map
$script:CatColors = @{
    "Flight"   = [System.Drawing.Color]::FromArgb(60, 160, 220)
    "Sprint"   = [System.Drawing.Color]::FromArgb(60, 200, 100)
    "Horse"    = [System.Drawing.Color]::FromArgb(200, 150, 60)
    "Climbing" = [System.Drawing.Color]::FromArgb(180, 120, 60)
    "Aerial"   = [System.Drawing.Color]::FromArgb(100, 180, 220)
    "Swing"    = [System.Drawing.Color]::FromArgb(160, 140, 200)
    "Swimming" = [System.Drawing.Color]::FromArgb(60, 180, 190)
    "Dodge"    = [System.Drawing.Color]::FromArgb(180, 180, 80)
    "Guard"    = [System.Drawing.Color]::FromArgb(120, 140, 200)
    "Attack"   = [System.Drawing.Color]::FromArgb(220, 80, 80)
    "Wrestle"  = [System.Drawing.Color]::FromArgb(200, 100, 140)
    "Unarmed"  = [System.Drawing.Color]::FromArgb(200, 140, 100)
    "Mount"    = [System.Drawing.Color]::FromArgb(160, 120, 80)
    "Aux"      = [System.Drawing.Color]::FromArgb(140, 160, 120)
    "Bow"      = [System.Drawing.Color]::FromArgb(120, 180, 120)
    "Special"  = [System.Drawing.Color]::FromArgb(200, 100, 200)
    "Vehicle"  = [System.Drawing.Color]::FromArgb(140, 140, 180)
}

$FontTitle    = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$FontColHdr   = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$FontList     = New-Object System.Drawing.Font("Segoe UI", 9)
$FontListBold = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$FontDetail   = New-Object System.Drawing.Font("Segoe UI", 8.5)
$FontCat      = New-Object System.Drawing.Font("Segoe UI Semibold", 7.5)
$FontName     = New-Object System.Drawing.Font("Segoe UI", 8.5)
$FontValue    = New-Object System.Drawing.Font("Segoe UI", 8)
$FontToggle   = New-Object System.Drawing.Font("Segoe UI Semibold", 7)
$FontButton   = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$FontLog      = New-Object System.Drawing.Font("Cascadia Code,Consolas", 8)
$FontSmall    = New-Object System.Drawing.Font("Segoe UI", 8)
$FontModInfo  = New-Object System.Drawing.Font("Segoe UI", 8.5)

$CharCheck = [char]0x2714
$CharCross = [char]0x2716
$CharRight = [char]0x25B6
$CharLeft  = [char]0x25C0
$CharArrow = [char]0x2192

# ══════════════════════════════════════════════════════════════════
# DATA MODEL
# ══════════════════════════════════════════════════════════════════
$script:AvailableMods = [System.Collections.ArrayList]::new()
$script:ActiveMods    = [System.Collections.ArrayList]::new()
# Use a hashtable container so .GetNewClosure() captures the reference
# and mutations (like .SelectedMod = $mod) are visible inside closures
$script:State = @{ SelectedMod = $null; GameDir = $script:GameDir; SelIndices = @{}; LastClickIdx = -1 }

function Parse-Label {
    param([string]$label)
    $cat = ""
    $name = ""
    $valOld = ""
    $valNew = ""
    if ($label -match '^\[([^\]]+)\]\s+(.+)$') {
        $cat = $Matches[1]
        $rest = $Matches[2]
        $arrowIdx = $rest.LastIndexOf(' -> ')
        if ($arrowIdx -gt 0) {
            $namePart = $rest.Substring(0, $arrowIdx)
            $valNew = $rest.Substring($arrowIdx + 4)
            $spaceIdx = $namePart.LastIndexOf(' ')
            if ($spaceIdx -gt 0) {
                $name = $namePart.Substring(0, $spaceIdx)
                $valOld = $namePart.Substring($spaceIdx + 1)
            } else {
                $name = $namePart
            }
        } else {
            $name = $rest
        }
    } else {
        $name = $label
    }
    return @{ Category = $cat; Name = $name; OldVal = $valOld; NewVal = $valNew }
}

function Load-AllMods {
    $mods = [System.Collections.ArrayList]::new()
    $files = @()
    $files += Get-ChildItem -Path $ModsAll -File -Filter "*.json" -ErrorAction SilentlyContinue
    $files += Get-ChildItem -Path $ModsAll -File -Filter "*.modpatch" -ErrorAction SilentlyContinue
    $files += Get-ChildItem -Path $ModsEnabled -File -Filter "*.json" -ErrorAction SilentlyContinue
    $files += Get-ChildItem -Path $ModsEnabled -File -Filter "*.modpatch" -ErrorAction SilentlyContinue

    $seen = @{}
    foreach ($f in $files) {
        if ($seen.ContainsKey($f.Name)) { continue }
        $seen[$f.Name] = $true
        try {
            $raw = Get-Content $f.FullName -Raw -Encoding UTF8
            $json = $raw | ConvertFrom-Json
            $changes = [System.Collections.ArrayList]::new()
            foreach ($p in $json.patches) {
                foreach ($c in $p.changes) {
                    [void]$changes.Add(@{
                        offset    = $c.offset
                        label     = $c.label
                        original  = $c.original
                        patched   = $c.patched
                        game_file = $p.game_file
                        enabled   = $true
                    })
                }
            }
            $modName = $json.name
            if (-not $modName) { $modName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
            $modVer = $json.version
            if (-not $modVer) { $modVer = "-" }
            $modDesc = $json.description
            if (-not $modDesc) { $modDesc = "" }

            [void]$mods.Add(@{
                FileName    = $f.Name
                SourcePath  = $f.FullName
                Name        = $modName
                Version     = $modVer
                Description = $modDesc
                Json        = $json
                Changes     = $changes
            })
        } catch {}
    }
    return $mods
}

# ══════════════════════════════════════════════════════════════════
# BUILD FORM
# ══════════════════════════════════════════════════════════════════
$form = New-Object System.Windows.Forms.Form
$form.Text = "Crimson Desert - Mod Manager"
$form.Size = New-Object System.Drawing.Size(1280, 780)
$form.MinimumSize = New-Object System.Drawing.Size(960, 580)
$form.StartPosition = "CenterScreen"
$form.BackColor = $BgDark
$form.ForeColor = $TextWhite
$form.Font = $FontList

$prop = $form.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"Instance,NonPublic")
if ($prop) { $prop.SetValue($form, $true, $null) }

# --- Header (compact, no overlap) ---
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = "Top"
$headerPanel.Height = 40
$headerPanel.BackColor = $BgPanel
$form.Controls.Add($headerPanel)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "CRIMSON DESERT - MOD MANAGER"
$lblTitle.Font = $FontTitle
$lblTitle.ForeColor = $AccentRed
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(14, 8)
$headerPanel.Controls.Add($lblTitle)

$sepHeader = New-Object System.Windows.Forms.Panel
$sepHeader.Dock = "Top"
$sepHeader.Height = 2
$sepHeader.BackColor = $AccentRed
$form.Controls.Add($sepHeader)

# --- Game Path Bar ---
$gamePathBar = New-Object System.Windows.Forms.Panel
$gamePathBar.Dock = "Top"
$gamePathBar.Height = 26
$gamePathBar.BackColor = $BgPanel
$form.Controls.Add($gamePathBar)

$lblGameIcon = New-Object System.Windows.Forms.Label
$lblGameIcon.Text = [string][char]0x25C9
$lblGameIcon.Font = $FontSmall
$lblGameIcon.ForeColor = $TextMuted
$lblGameIcon.AutoSize = $true
$lblGameIcon.Location = New-Object System.Drawing.Point(14, 4)
$gamePathBar.Controls.Add($lblGameIcon)

$lblGamePath = New-Object System.Windows.Forms.Label
$lblGamePath.Font = $FontSmall
$lblGamePath.AutoSize = $false
$lblGamePath.Size = New-Object System.Drawing.Size(900, 20)
$lblGamePath.Location = New-Object System.Drawing.Point(30, 4)
$lblGamePath.TextAlign = "MiddleLeft"
if ($script:GameDir) {
    $lblGamePath.Text = "Game: " + $script:GameDir
    $lblGamePath.ForeColor = $AccentGreen
} else {
    $lblGamePath.Text = "Game: NOT DETECTED - click Browse to set path"
    $lblGamePath.ForeColor = $AccentRed
}
$gamePathBar.Controls.Add($lblGamePath)

$btnBrowseGame = New-Object System.Windows.Forms.Button
$btnBrowseGame.Text = "Browse..."
$btnBrowseGame.Font = $FontSmall
$btnBrowseGame.Size = New-Object System.Drawing.Size(70, 20)
$btnBrowseGame.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnBrowseGame.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 90), 3)
$btnBrowseGame.FlatStyle = "Flat"
$btnBrowseGame.FlatAppearance.BorderSize = 0
$btnBrowseGame.BackColor = $BgCard
$btnBrowseGame.ForeColor = $TextGray
$btnBrowseGame.Cursor = "Hand"
$gamePathBar.Controls.Add($btnBrowseGame)

# --- Status Bar ---
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = "Bottom"
$statusPanel.Height = 24
$statusPanel.BackColor = $BgPanel
$form.Controls.Add($statusPanel)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "  Ready"
$lblStatus.Font = $FontSmall
$lblStatus.ForeColor = $TextGray
$lblStatus.Dock = "Fill"
$lblStatus.TextAlign = "MiddleLeft"
$statusPanel.Controls.Add($lblStatus)

# --- Bottom Buttons ---
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Dock = "Bottom"
$buttonPanel.Height = 46
$buttonPanel.BackColor = $BgDark
$form.Controls.Add($buttonPanel)

function New-Btn {
    param([string]$Text, [int]$X, [int]$W, $Bg, $Fg)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Font = $FontButton
    $b.Size = New-Object System.Drawing.Size($W, 32)
    $b.Location = New-Object System.Drawing.Point($X, 7)
    $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Bg; $b.ForeColor = $Fg; $b.Cursor = "Hand"
    return $b
}

$btnApply     = New-Btn ($CharCheck + " APPLY MODS") 12 145 $AccentGreen $TextWhite
$btnUninstall = New-Btn ($CharCross + " UNINSTALL") 165 125 $AccentRed $TextWhite
$btnRestore   = New-Btn "RESTORE 0.papgt" 298 130 $AccentOrange $TextWhite
$btnRefresh   = New-Btn "REFRESH" 436 90 $AccentBlue $TextWhite
$btnOpenDir   = New-Btn "MODS DIR" 534 90 $BgCard $TextGray
$buttonPanel.Controls.AddRange(@($btnApply, $btnUninstall, $btnRestore, $btnRefresh, $btnOpenDir))

# ══════════════════════════════════════════════════════════════════
# 3-COLUMN LAYOUT
# ══════════════════════════════════════════════════════════════════
$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Dock = "Fill"
$mainPanel.BackColor = $BgDark
$mainPanel.Padding = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
$form.Controls.Add($mainPanel)

$table = New-Object System.Windows.Forms.TableLayoutPanel
$table.Dock = "Fill"
$table.ColumnCount = 5
$table.RowCount = 1
$table.BackColor = $BgDark
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 20)))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 40)))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 20)))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 6)))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 60)))
[void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100)))
$mainPanel.Controls.Add($table)

# ──────────────────────────────────────────────────
# LEFT: Available Mods (owner-drawn listbox)
# ──────────────────────────────────────────────────
$leftPanel = New-Object System.Windows.Forms.Panel
$leftPanel.Dock = "Fill"; $leftPanel.BackColor = $BgDark

$lblLeft = New-Object System.Windows.Forms.Label
$lblLeft.Text = "AVAILABLE"
$lblLeft.Font = $FontColHdr; $lblLeft.ForeColor = $TextMuted
$lblLeft.Dock = "Top"; $lblLeft.Height = 22; $lblLeft.Padding = New-Object System.Windows.Forms.Padding(4,2,0,0)
$leftPanel.Controls.Add($lblLeft)

$lstAvailable = New-Object System.Windows.Forms.ListBox
$lstAvailable.Dock = "Fill"
$lstAvailable.DrawMode = "OwnerDrawFixed"
$lstAvailable.ItemHeight = 42
$lstAvailable.BackColor = $BgCard
$lstAvailable.ForeColor = $TextWhite
$lstAvailable.Font = $FontList
$lstAvailable.BorderStyle = "None"
$lstAvailable.IntegralHeight = $false
$leftPanel.Controls.Add($lstAvailable)
# Fix dock z-order: Fill at index 0 = processed last = gets remaining space
$leftPanel.Controls.SetChildIndex($lstAvailable, 0)

$lstAvailable.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $e.DrawBackground()
    $isSelected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
    $bg = if ($isSelected) { $BgCardHover } else { $BgCard }
    $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $e.Bounds)

    $mod = $script:AvailableMods[$e.Index]
    if ($null -ne $mod) {
        $r = $e.Bounds
        $e.Graphics.DrawString($mod.Name, $FontListBold, (New-Object System.Drawing.SolidBrush($TextWhite)), ($r.X + 6), ($r.Y + 4))
        $sub = "v" + $mod.Version + "  |  " + $mod.Changes.Count + " patches"
        $e.Graphics.DrawString($sub, $FontSmall, (New-Object System.Drawing.SolidBrush($TextDim)), ($r.X + 6), ($r.Y + 23))
    }
    $e.Graphics.DrawLine((New-Object System.Drawing.Pen($BgDark)), $e.Bounds.Left, ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1))
}.GetNewClosure())

$table.Controls.Add($leftPanel, 0, 0)

# ──────────────────────────────────────────────────
# Arrow buttons
# ──────────────────────────────────────────────────
$arrowPanel = New-Object System.Windows.Forms.Panel
$arrowPanel.Dock = "Fill"; $arrowPanel.BackColor = $BgDark

$btnActivate = New-Object System.Windows.Forms.Button
$btnActivate.Text = [string]$CharRight
$btnActivate.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$btnActivate.Size = New-Object System.Drawing.Size(32, 32)
$btnActivate.Location = New-Object System.Drawing.Point(4, 70)
$btnActivate.FlatStyle = "Flat"
$btnActivate.FlatAppearance.BorderSize = 1
$btnActivate.FlatAppearance.BorderColor = $TextMuted
$btnActivate.BackColor = $BgCard; $btnActivate.ForeColor = $AccentGreen; $btnActivate.Cursor = "Hand"
$arrowPanel.Controls.Add($btnActivate)

$btnDeactivate = New-Object System.Windows.Forms.Button
$btnDeactivate.Text = [string]$CharLeft
$btnDeactivate.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$btnDeactivate.Size = New-Object System.Drawing.Size(32, 32)
$btnDeactivate.Location = New-Object System.Drawing.Point(4, 112)
$btnDeactivate.FlatStyle = "Flat"
$btnDeactivate.FlatAppearance.BorderSize = 1
$btnDeactivate.FlatAppearance.BorderColor = $TextMuted
$btnDeactivate.BackColor = $BgCard; $btnDeactivate.ForeColor = $AccentRed; $btnDeactivate.Cursor = "Hand"
$arrowPanel.Controls.Add($btnDeactivate)

$table.Controls.Add($arrowPanel, 1, 0)

# ──────────────────────────────────────────────────
# MIDDLE: Active Mods (owner-drawn)
# ──────────────────────────────────────────────────
$midPanel = New-Object System.Windows.Forms.Panel
$midPanel.Dock = "Fill"; $midPanel.BackColor = $BgDark

$lblMid = New-Object System.Windows.Forms.Label
$lblMid.Text = "ACTIVE"
$lblMid.Font = $FontColHdr; $lblMid.ForeColor = $AccentGreen
$lblMid.Dock = "Top"; $lblMid.Height = 22; $lblMid.Padding = New-Object System.Windows.Forms.Padding(4,2,0,0)
$midPanel.Controls.Add($lblMid)

$lstActive = New-Object System.Windows.Forms.ListBox
$lstActive.Dock = "Fill"
$lstActive.DrawMode = "OwnerDrawFixed"
$lstActive.ItemHeight = 42
$lstActive.BackColor = $BgCard
$lstActive.ForeColor = $AccentGreen
$lstActive.Font = $FontList
$lstActive.BorderStyle = "None"
$lstActive.IntegralHeight = $false
$midPanel.Controls.Add($lstActive)
$midPanel.Controls.SetChildIndex($lstActive, 0)

$lstActive.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $e.DrawBackground()
    $isSelected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
    $bg = if ($isSelected) { $BgCardHover } else { $BgCard }
    $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $e.Bounds)

    $mod = $script:ActiveMods[$e.Index]
    if ($null -ne $mod) {
        $r = $e.Bounds
        if ($isSelected) {
            $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($AccentGreen)), $r.X, $r.Y, 3, $r.Height)
        }
        $e.Graphics.DrawString($mod.Name, $FontListBold, (New-Object System.Drawing.SolidBrush($AccentGreen)), ($r.X + 8), ($r.Y + 4))
        $en = 0
        foreach ($c in $mod.Changes) { if ($c.enabled) { $en++ } }
        $sub = $en.ToString() + " / " + $mod.Changes.Count.ToString() + " patches enabled"
        $clr = if ($en -eq $mod.Changes.Count) { $TextDim } else { $AccentOrange }
        $e.Graphics.DrawString($sub, $FontSmall, (New-Object System.Drawing.SolidBrush($clr)), ($r.X + 8), ($r.Y + 23))
    }
    $e.Graphics.DrawLine((New-Object System.Drawing.Pen($BgDark)), $e.Bounds.Left, ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1))
}.GetNewClosure())

$table.Controls.Add($midPanel, 2, 0)

# Spacer
$spacer = New-Object System.Windows.Forms.Panel
$spacer.Dock = "Fill"; $spacer.BackColor = $BgDark
$table.Controls.Add($spacer, 3, 0)

# ──────────────────────────────────────────────────
# RIGHT: Patch Detail Panel (toggle rows)
# ──────────────────────────────────────────────────
$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Dock = "Fill"; $rightPanel.BackColor = $BgDark

# Right header with title + All ON/OFF + count
$rightHdr = New-Object System.Windows.Forms.Panel
$rightHdr.Dock = "Top"; $rightHdr.Height = 56; $rightHdr.BackColor = $BgDark

$lblRight = New-Object System.Windows.Forms.Label
$lblRight.Text = "PATCHES"
$lblRight.Font = $FontColHdr; $lblRight.ForeColor = $AccentOrange
$lblRight.Location = New-Object System.Drawing.Point(4, 2); $lblRight.AutoSize = $true
$rightHdr.Controls.Add($lblRight)

$lblPatchCount = New-Object System.Windows.Forms.Label
$lblPatchCount.Text = ""
$lblPatchCount.Font = $FontSmall; $lblPatchCount.ForeColor = $TextMuted
$lblPatchCount.Location = New-Object System.Drawing.Point(80, 4); $lblPatchCount.AutoSize = $true
$rightHdr.Controls.Add($lblPatchCount)

$lblModInfo = New-Object System.Windows.Forms.Label
$lblModInfo.Text = "Select an active mod to view patches."
$lblModInfo.Font = $FontModInfo; $lblModInfo.ForeColor = $TextGray
$lblModInfo.Location = New-Object System.Drawing.Point(4, 20)
$lblModInfo.Size = New-Object System.Drawing.Size(600, 16)
$rightHdr.Controls.Add($lblModInfo)

$btnAllOn = New-Object System.Windows.Forms.Button
$btnAllOn.Text = "ALL ON"; $btnAllOn.Font = $FontSmall
$btnAllOn.Size = New-Object System.Drawing.Size(56, 22)
$btnAllOn.Location = New-Object System.Drawing.Point(4, 38)
$btnAllOn.FlatStyle = "Flat"; $btnAllOn.FlatAppearance.BorderSize = 0
$btnAllOn.BackColor = $BgCard; $btnAllOn.ForeColor = $AccentGreen; $btnAllOn.Cursor = "Hand"
$rightHdr.Controls.Add($btnAllOn)

$btnAllOff = New-Object System.Windows.Forms.Button
$btnAllOff.Text = "ALL OFF"; $btnAllOff.Font = $FontSmall
$btnAllOff.Size = New-Object System.Drawing.Size(56, 22)
$btnAllOff.Location = New-Object System.Drawing.Point(64, 38)
$btnAllOff.FlatStyle = "Flat"; $btnAllOff.FlatAppearance.BorderSize = 0
$btnAllOff.BackColor = $BgCard; $btnAllOff.ForeColor = $AccentRed; $btnAllOff.Cursor = "Hand"
$rightHdr.Controls.Add($btnAllOff)

$btnSelOn = New-Object System.Windows.Forms.Button
$btnSelOn.Text = "SEL ON"; $btnSelOn.Font = $FontSmall
$btnSelOn.Size = New-Object System.Drawing.Size(56, 22)
$btnSelOn.Location = New-Object System.Drawing.Point(136, 38)
$btnSelOn.FlatStyle = "Flat"; $btnSelOn.FlatAppearance.BorderSize = 0
$btnSelOn.BackColor = $BgCard; $btnSelOn.ForeColor = $AccentGreen; $btnSelOn.Cursor = "Hand"
$rightHdr.Controls.Add($btnSelOn)

$btnSelOff = New-Object System.Windows.Forms.Button
$btnSelOff.Text = "SEL OFF"; $btnSelOff.Font = $FontSmall
$btnSelOff.Size = New-Object System.Drawing.Size(56, 22)
$btnSelOff.Location = New-Object System.Drawing.Point(196, 38)
$btnSelOff.FlatStyle = "Flat"; $btnSelOff.FlatAppearance.BorderSize = 0
$btnSelOff.BackColor = $BgCard; $btnSelOff.ForeColor = $AccentRed; $btnSelOff.Cursor = "Hand"
$rightHdr.Controls.Add($btnSelOff)

$rightPanel.Controls.Add($rightHdr)

# Scrollable patch list (FlowLayoutPanel)
$patchScroll = New-Object System.Windows.Forms.FlowLayoutPanel
$patchScroll.Dock = "Fill"
$patchScroll.AutoScroll = $true
$patchScroll.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 34)
$patchScroll.FlowDirection = "TopDown"
$patchScroll.WrapContents = $false
$patchScroll.Padding = New-Object System.Windows.Forms.Padding(0)
$rightPanel.Controls.Add($patchScroll)

# Log at bottom
$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Dock = "Bottom"; $logPanel.Height = 130; $logPanel.BackColor = $BgDark

$lblLogHdr = New-Object System.Windows.Forms.Label
$lblLogHdr.Text = "LOG"
$lblLogHdr.Font = $FontColHdr; $lblLogHdr.ForeColor = $TextMuted
$lblLogHdr.Dock = "Top"; $lblLogHdr.Height = 18
$logPanel.Controls.Add($lblLogHdr)

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Dock = "Fill"
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(16, 17, 22)
$txtLog.ForeColor = $TextGray; $txtLog.Font = $FontLog
$txtLog.ReadOnly = $true; $txtLog.BorderStyle = "None"; $txtLog.ScrollBars = "Vertical"
$logPanel.Controls.Add($txtLog)
$logPanel.Controls.SetChildIndex($txtLog, 0)

$rightPanel.Controls.Add($logPanel)

# Fix dock z-order: Fill (patchScroll) must end up at index 0 (processed last)
# SetChildIndex(x, 0) pushes previous index-0 controls up
$rightPanel.Controls.SetChildIndex($rightHdr, 0)
$rightPanel.Controls.SetChildIndex($logPanel, 0)
$rightPanel.Controls.SetChildIndex($patchScroll, 0)

$table.Controls.Add($rightPanel, 4, 0)

# Fix form-level dock z-order: mainPanel (Fill) must be at index 0
$form.Controls.SetChildIndex($mainPanel, 0)

# ══════════════════════════════════════════════════════════════════
# LOGIC
# ══════════════════════════════════════════════════════════════════

function Write-Log {
    param([string]$Text, [System.Drawing.Color]$Color)
    if (-not $Color) { $Color = $TextGray }
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionColor = $Color
    $txtLog.AppendText($Text + "`r`n")
    $txtLog.ScrollToCaret()
}

function Get-CatColor {
    param([string]$cat)
    if ($script:CatColors.ContainsKey($cat)) { return $script:CatColors[$cat] }
    return $TextGray
}

function Update-PatchCount {
    if ($null -eq $script:State.SelectedMod) { return }
    $mod = $script:State.SelectedMod
    $total = $mod.Changes.Count
    $en = 0
    for ($i = 0; $i -lt $total; $i++) {
        if ($mod.Changes[$i].enabled) { $en++ }
    }
    $lblPatchCount.Text = "(" + $en.ToString() + " / " + $total.ToString() + ")"
}

function Refresh-AvailableList {
    $lstAvailable.Items.Clear()
    foreach ($m in $script:AvailableMods) {
        [void]$lstAvailable.Items.Add($m.Name)
    }
    $lblLeft.Text = "AVAILABLE (" + $script:AvailableMods.Count + ")"
}

function Refresh-ActiveList {
    $prevIdx = $lstActive.SelectedIndex
    $lstActive.Items.Clear()
    foreach ($m in $script:ActiveMods) {
        [void]$lstActive.Items.Add($m.Name)
    }
    $lblMid.Text = "ACTIVE (" + $script:ActiveMods.Count + ")"
    if ($prevIdx -ge 0 -and $prevIdx -lt $lstActive.Items.Count) {
        $lstActive.SelectedIndex = $prevIdx
    }
}

function Refresh-Lists {
    $allMods = Load-AllMods
    $script:AvailableMods.Clear()
    $activeNames = @{}
    foreach ($m in $script:ActiveMods) { $activeNames[$m.FileName] = $true }
    foreach ($m in $allMods) {
        if (-not $activeNames.ContainsKey($m.FileName)) {
            [void]$script:AvailableMods.Add($m)
        }
    }
    Refresh-AvailableList
    Refresh-ActiveList
}

# Helper: update a single row's visual state without rebuilding the list
function Update-RowVisual {
    param($row, $changeData, [bool]$isSelected)
    $isOn = $changeData.enabled
    if ($isSelected) {
        $row.BackColor = if ($isOn) { $BgRowSel } else { $BgRowSelOff }
    } else {
        $row.BackColor = if ($isOn) { $BgRow } else { $BgRowOff }
    }
    foreach ($ctrl in $row.Controls) {
        if ($ctrl.Size.Width -eq 40 -and $ctrl.Size.Height -eq 20) {
            # Toggle switch
            $ctrl.Tag = $isOn
            $ctrl.Invalidate()
        }
        if ($ctrl -is [System.Windows.Forms.Label] -and $ctrl.BackColor -eq [System.Drawing.Color]::Transparent) {
            if ($ctrl.Location.Y -lt 10) {
                $ctrl.ForeColor = if ($isOn) { $TextWhite } else { $TextMuted }
            } else {
                $ctrl.ForeColor = if ($isOn) { $AccentCyan } else { $TextMuted }
            }
        }
    }
}

# Shared TOGGLE click handler - only fires on the toggle switch panel
$script:ToggleClick = {
    param($sender, $e)
    $ctl = $sender
    while ($null -ne $ctl -and $null -ne $ctl.Parent) {
        if ($ctl.Parent -is [System.Windows.Forms.FlowLayoutPanel]) { break }
        $ctl = $ctl.Parent
    }
    if ($null -eq $ctl -or $null -eq $ctl.Tag) { return }
    $ci = [int]$ctl.Tag
    $mod = $script:State.SelectedMod
    if ($null -eq $mod) { return }
    if ($ci -lt 0 -or $ci -ge $mod.Changes.Count) { return }
    $mod.Changes[$ci].enabled = -not $mod.Changes[$ci].enabled
    $isSel = $script:State.SelIndices.ContainsKey($ci)
    Update-RowVisual $ctl $mod.Changes[$ci] $isSel
    Update-PatchCount
    $lstActive.Invalidate()
}.GetNewClosure()

# Shared ROW SELECT click handler - selects rows, supports Shift for range
$script:RowSelectClick = {
    param($sender, $e)
    $ctl = $sender
    while ($null -ne $ctl -and $null -ne $ctl.Parent) {
        if ($ctl.Parent -is [System.Windows.Forms.FlowLayoutPanel]) { break }
        $ctl = $ctl.Parent
    }
    if ($null -eq $ctl -or $null -eq $ctl.Tag) { return }
    $ci = [int]$ctl.Tag
    $mod = $script:State.SelectedMod
    if ($null -eq $mod) { return }

    $shift = ([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Shift) -ne 0
    $ctrl  = ([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) -ne 0

    if ($shift -and $script:State.LastClickIdx -ge 0) {
        $from = [Math]::Min($script:State.LastClickIdx, $ci)
        $to   = [Math]::Max($script:State.LastClickIdx, $ci)
        if (-not $ctrl) { $script:State.SelIndices = @{} }
        for ($ii = $from; $ii -le $to; $ii++) { $script:State.SelIndices[$ii] = $true }
    } elseif ($ctrl) {
        if ($script:State.SelIndices.ContainsKey($ci)) {
            $script:State.SelIndices.Remove($ci)
        } else {
            $script:State.SelIndices[$ci] = $true
        }
    } else {
        $script:State.SelIndices = @{ $ci = $true }
    }
    $script:State.LastClickIdx = $ci

    # Update all rows visual selection
    $flow = $ctl.Parent
    foreach ($row in $flow.Controls) {
        if ($row -isnot [System.Windows.Forms.Panel] -or $null -eq $row.Tag) { continue }
        $ridx = [int]$row.Tag
        if ($ridx -lt 0 -or $ridx -ge $mod.Changes.Count) { continue }
        $isSel = $script:State.SelIndices.ContainsKey($ridx)
        Update-RowVisual $row $mod.Changes[$ridx] $isSel
    }
}.GetNewClosure()

# Create a single toggle-row panel for one patch
function New-PatchRow {
    param($changeIdx, $changeData, [int]$rowWidth)

    $parsed = Parse-Label $changeData.label
    $isOn = $changeData.enabled

    $row = New-Object System.Windows.Forms.Panel
    $row.Size = New-Object System.Drawing.Size($rowWidth, 32)
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 1)
    $row.BackColor = if ($isOn) { $BgRow } else { $BgRowOff }
    $row.Tag = $changeIdx
    $row.Cursor = "Hand"

    # Toggle switch (custom painted)
    $toggle = New-Object System.Windows.Forms.Panel
    $toggle.Size = New-Object System.Drawing.Size(40, 20)
    $toggle.Location = New-Object System.Drawing.Point(6, 6)
    $toggle.Tag = $isOn
    $toggle.Cursor = "Hand"

    $toggle.Add_Paint({
        param($sender, $pe)
        $g = $pe.Graphics
        $g.SmoothingMode = "AntiAlias"
        $on = $sender.Tag
        $bg = if ($on) { $BgToggleOn } else { $BgToggleOff }
        $brush = New-Object System.Drawing.SolidBrush($bg)
        $g.FillRectangle($brush, 0, 2, 40, 16)
        $knobX = if ($on) { 22 } else { 2 }
        $knobColor = if ($on) { $TextWhite } else { $TextMuted }
        $g.FillEllipse((New-Object System.Drawing.SolidBrush($knobColor)), $knobX, 3, 14, 14)
        $txt = if ($on) { "ON" } else { "OFF" }
        $txtX = if ($on) { 4 } else { 20 }
        $txtColor = if ($on) { [System.Drawing.Color]::FromArgb(200,255,200) } else { [System.Drawing.Color]::FromArgb(200,150,150) }
        $g.DrawString($txt, $FontToggle, (New-Object System.Drawing.SolidBrush($txtColor)), $txtX, 4)
        $brush.Dispose()
    }.GetNewClosure())

    $row.Controls.Add($toggle)

    # Category badge
    $catColor = Get-CatColor $parsed.Category
    $catW = 0
    if ($parsed.Category) {
        $lblCat = New-Object System.Windows.Forms.Label
        $catText = $parsed.Category.ToUpper()
        $catW = [int]([System.Windows.Forms.TextRenderer]::MeasureText($catText, $FontCat).Width) + 10
        if ($catW -lt 44) { $catW = 44 }
        $lblCat.Text = $catText
        $lblCat.Font = $FontCat
        $lblCat.ForeColor = $BgDark
        $lblCat.BackColor = $catColor
        $lblCat.Size = New-Object System.Drawing.Size($catW, 18)
        $lblCat.Location = New-Object System.Drawing.Point(52, 7)
        $lblCat.TextAlign = "MiddleCenter"
        $row.Controls.Add($lblCat)
    }

    # Name label
    $nameX = 52 + $catW + 6
    $maxLabelW = $rowWidth - $nameX - 8
    if ($maxLabelW -lt 60) { $maxLabelW = 60 }
    $lblName = New-Object System.Windows.Forms.Label
    $nameText = $parsed.Name
    $nameText = $nameText.Replace('_', ' ')
    $lblName.Text = $nameText
    $lblName.Font = $FontName
    $lblName.ForeColor = if ($isOn) { $TextWhite } else { $TextMuted }
    $lblName.AutoSize = $false
    $lblName.Size = New-Object System.Drawing.Size($maxLabelW, 15)
    $lblName.Location = New-Object System.Drawing.Point($nameX, 3)
    $lblName.BackColor = [System.Drawing.Color]::Transparent
    $row.Controls.Add($lblName)

    # Values label
    if ($parsed.OldVal -and $parsed.NewVal) {
        $valText = $parsed.OldVal + " " + $CharArrow + " " + $parsed.NewVal
        $lblVal = New-Object System.Windows.Forms.Label
        $lblVal.Text = $valText
        $lblVal.Font = $FontValue
        $lblVal.ForeColor = if ($isOn) { $AccentCyan } else { $TextMuted }
        $lblVal.AutoSize = $false
        $lblVal.Size = New-Object System.Drawing.Size($maxLabelW, 14)
        $lblVal.Location = New-Object System.Drawing.Point($nameX, 17)
        $lblVal.BackColor = [System.Drawing.Color]::Transparent
        $row.Controls.Add($lblVal)
    }

    # Toggle switch only toggles ON/OFF
    $toggle.Add_Click($script:ToggleClick)
    # Row and labels do selection (Shift for range, Ctrl for toggle selection)
    $row.Add_Click($script:RowSelectClick)
    foreach ($ctrl in $row.Controls) {
        if ($ctrl -is [System.Windows.Forms.Label]) {
            $ctrl.Add_Click($script:RowSelectClick)
        }
    }

    return $row
}

function Show-Patches {
    param($mod)
    $script:State.SelectedMod = $mod
    $script:State.SelIndices = @{}
    $script:State.LastClickIdx = -1
    $patchScroll.SuspendLayout()
    $patchScroll.Controls.Clear()

    if ($null -eq $mod) {
        $lblModInfo.Text = "Select an active mod to view patches."
        $lblPatchCount.Text = ""
        $patchScroll.ResumeLayout()
        return
    }

    $infoText = $mod.Name + " v" + $mod.Version + " - " + $mod.Description
    if ($infoText.Length -gt 120) { $infoText = $infoText.Substring(0, 120) + "..." }
    $lblModInfo.Text = $infoText

    $rowW = $patchScroll.ClientSize.Width - 20
    if ($rowW -lt 300) { $rowW = 300 }

    for ($i = 0; $i -lt $mod.Changes.Count; $i++) {
        $row = New-PatchRow $i $mod.Changes[$i] $rowW
        $patchScroll.Controls.Add($row)
    }

    Update-PatchCount
    $patchScroll.ResumeLayout()
}

# ══════════════════════════════════════════════════════════════════
# EVENT HANDLERS
# ══════════════════════════════════════════════════════════════════

$btnActivate.Add_Click({
    $idx = $lstAvailable.SelectedIndex
    if ($idx -lt 0) { return }
    $mod = $script:AvailableMods[$idx]
    $script:AvailableMods.RemoveAt($idx)
    [void]$script:ActiveMods.Add($mod)
    Refresh-AvailableList
    Refresh-ActiveList
    $lstActive.SelectedIndex = $script:ActiveMods.Count - 1
    $lblStatus.Text = "  Activated: " + $mod.Name
    $lblStatus.ForeColor = $AccentGreen
}.GetNewClosure())

$lstAvailable.Add_DoubleClick({
    $btnActivate.PerformClick()
}.GetNewClosure())

$btnDeactivate.Add_Click({
    $idx = $lstActive.SelectedIndex
    if ($idx -lt 0) { return }
    $mod = $script:ActiveMods[$idx]
    foreach ($c in $mod.Changes) { $c.enabled = $true }
    $script:ActiveMods.RemoveAt($idx)
    [void]$script:AvailableMods.Add($mod)
    Refresh-AvailableList
    Refresh-ActiveList
    Show-Patches $null
    $lblStatus.Text = "  Deactivated: " + $mod.Name
    $lblStatus.ForeColor = $AccentOrange
}.GetNewClosure())

$lstActive.Add_DoubleClick({
    $btnDeactivate.PerformClick()
}.GetNewClosure())

$lstActive.Add_SelectedIndexChanged({
    $idx = $lstActive.SelectedIndex
    if ($idx -lt 0 -or $idx -ge $script:ActiveMods.Count) {
        Show-Patches $null
        return
    }
    Show-Patches $script:ActiveMods[$idx]
}.GetNewClosure())

$btnAllOn.Add_Click({
    if ($null -eq $script:State.SelectedMod) { return }
    $mod = $script:State.SelectedMod
    foreach ($c in $mod.Changes) { $c.enabled = $true }
    foreach ($row in $patchScroll.Controls) {
        if ($row -isnot [System.Windows.Forms.Panel] -or $null -eq $row.Tag) { continue }
        $ridx = [int]$row.Tag
        if ($ridx -ge 0 -and $ridx -lt $mod.Changes.Count) {
            $isSel = $script:State.SelIndices.ContainsKey($ridx)
            Update-RowVisual $row $mod.Changes[$ridx] $isSel
        }
    }
    Update-PatchCount
    $lstActive.Invalidate()
}.GetNewClosure())

$btnAllOff.Add_Click({
    if ($null -eq $script:State.SelectedMod) { return }
    $mod = $script:State.SelectedMod
    foreach ($c in $mod.Changes) { $c.enabled = $false }
    foreach ($row in $patchScroll.Controls) {
        if ($row -isnot [System.Windows.Forms.Panel] -or $null -eq $row.Tag) { continue }
        $ridx = [int]$row.Tag
        if ($ridx -ge 0 -and $ridx -lt $mod.Changes.Count) {
            $isSel = $script:State.SelIndices.ContainsKey($ridx)
            Update-RowVisual $row $mod.Changes[$ridx] $isSel
        }
    }
    Update-PatchCount
    $lstActive.Invalidate()
}.GetNewClosure())

$btnSelOn.Add_Click({
    if ($null -eq $script:State.SelectedMod) { return }
    $mod = $script:State.SelectedMod
    foreach ($key in @($script:State.SelIndices.Keys)) {
        $idx = [int]$key
        if ($idx -ge 0 -and $idx -lt $mod.Changes.Count) {
            $mod.Changes[$idx].enabled = $true
        }
    }
    foreach ($row in $patchScroll.Controls) {
        if ($row -isnot [System.Windows.Forms.Panel] -or $null -eq $row.Tag) { continue }
        $ridx = [int]$row.Tag
        if ($ridx -ge 0 -and $ridx -lt $mod.Changes.Count) {
            $isSel = $script:State.SelIndices.ContainsKey($ridx)
            Update-RowVisual $row $mod.Changes[$ridx] $isSel
        }
    }
    Update-PatchCount
    $lstActive.Invalidate()
}.GetNewClosure())

$btnSelOff.Add_Click({
    if ($null -eq $script:State.SelectedMod) { return }
    $mod = $script:State.SelectedMod
    foreach ($key in @($script:State.SelIndices.Keys)) {
        $idx = [int]$key
        if ($idx -ge 0 -and $idx -lt $mod.Changes.Count) {
            $mod.Changes[$idx].enabled = $false
        }
    }
    foreach ($row in $patchScroll.Controls) {
        if ($row -isnot [System.Windows.Forms.Panel] -or $null -eq $row.Tag) { continue }
        $ridx = [int]$row.Tag
        if ($ridx -ge 0 -and $ridx -lt $mod.Changes.Count) {
            $isSel = $script:State.SelIndices.ContainsKey($ridx)
            Update-RowVisual $row $mod.Changes[$ridx] $isSel
        }
    }
    Update-PatchCount
    $lstActive.Invalidate()
}.GetNewClosure())

$btnRefresh.Add_Click({
    $script:ActiveMods.Clear()
    $script:State.SelectedMod = $null
    $patchScroll.Controls.Clear()
    $lblModInfo.Text = "Select an active mod to view patches."
    $lblPatchCount.Text = ""
    Refresh-Lists
    Write-Log "Mod list refreshed." $AccentBlue
    $lblStatus.Text = "  Refreshed"
    $lblStatus.ForeColor = $TextGray
}.GetNewClosure())

$btnOpenDir.Add_Click({
    Start-Process "explorer.exe" $ModsAll
}.GetNewClosure())

$patchScroll.Add_Resize({
    $newW = $patchScroll.ClientSize.Width - 20
    if ($newW -lt 300) { $newW = 300 }
    foreach ($ctrl in $patchScroll.Controls) {
        if ($ctrl -is [System.Windows.Forms.Panel]) {
            $ctrl.Width = $newW
        }
    }
}.GetNewClosure())

# ──────────────────────────────────────────────────
# APPLY MODS
# ──────────────────────────────────────────────────
$btnApply.Add_Click({
    if ($script:ActiveMods.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No active mods. Move mods from Available to Active first.", "No Active Mods", "OK", "Warning")
        return
    }

    $lblStatus.Text = "  Applying mods..."
    $lblStatus.ForeColor = $AccentOrange
    $form.Refresh()

    $txtLog.Clear()
    Write-Log "============================================" $AccentBlue
    Write-Log "  APPLYING MODS" $AccentBlue
    Write-Log "============================================" $AccentBlue
    Write-Log ""

    # --- Backup 0.papgt before modding ---
    if ($script:State.GameDir) {
        $papgtSrc = Join-Path $script:State.GameDir "meta\0.papgt"
        $papgtBak = Join-Path $BackupsDir "0.papgt.original"
        if (Test-Path $papgtSrc) {
            if (-not (Test-Path $papgtBak)) {
                try {
                    Copy-Item -Path $papgtSrc -Destination $papgtBak -Force
                    Write-Log ("  Backup: meta/0.papgt -> backups/0.papgt.original") $AccentGreen
                } catch {
                    Write-Log ("  WARNING: Could not backup 0.papgt: " + $_.ToString()) $AccentOrange
                }
            } else {
                Write-Log "  Backup: 0.papgt.original already exists (skipping)" $TextGray
            }
        } else {
            Write-Log "  WARNING: meta/0.papgt not found at game path" $AccentOrange
        }
    } else {
        Write-Log "  WARNING: Game path not set - cannot backup 0.papgt" $AccentOrange
    }
    Write-Log ""

    Get-ChildItem -Path $ModsEnabled -File -ErrorAction SilentlyContinue | Remove-Item -Force

    $modCount = 0
    foreach ($mod in $script:ActiveMods) {
        $enabledChanges = [System.Collections.ArrayList]::new()
        foreach ($c in $mod.Changes) {
            if ($c.enabled) {
                [void]$enabledChanges.Add(@{
                    offset   = $c.offset
                    label    = $c.label
                    original = $c.original
                    patched  = $c.patched
                })
            }
        }

        if ($enabledChanges.Count -eq 0) {
            Write-Log ("  SKIP: " + $mod.Name + " (0 patches enabled)") $AccentOrange
            continue
        }

        $gameFileGroups = @{}
        foreach ($c in $mod.Changes) {
            if (-not $c.enabled) { continue }
            $gf = $c.game_file
            if (-not $gameFileGroups.ContainsKey($gf)) {
                $gameFileGroups[$gf] = [System.Collections.ArrayList]::new()
            }
            [void]$gameFileGroups[$gf].Add(@{
                offset   = $c.offset
                label    = $c.label
                original = $c.original
                patched  = $c.patched
            })
        }

        $patches = [System.Collections.ArrayList]::new()
        foreach ($gf in $gameFileGroups.Keys) {
            [void]$patches.Add(@{
                game_file = $gf
                changes   = $gameFileGroups[$gf]
            })
        }

        $filteredJson = @{
            name        = $mod.Name
            version     = $mod.Version
            description = $mod.Description
            patches     = $patches
        }

        $outPath = Join-Path $ModsEnabled $mod.FileName
        $jsonText = $filteredJson | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($outPath, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
        $modCount++
        Write-Log ("  " + $mod.Name + ": " + $enabledChanges.Count + "/" + $mod.Changes.Count + " patches") $AccentGreen
    }

    if ($modCount -eq 0) {
        Write-Log "" $TextGray
        Write-Log "No patches to apply!" $AccentOrange
        $lblStatus.Text = "  No patches to apply"
        $lblStatus.ForeColor = $AccentOrange
        return
    }

    Write-Log "" $TextGray
    Write-Log "Running mod_manager..." $TextWhite

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        if ($script:UseExe) {
            $pinfo.FileName = $ModManagerExe
            $pinfo.Arguments = "--apply"
        } else {
            $pinfo.FileName = $PythonExe
            $pinfo.Arguments = ('"' + $ModManagerPy + '"' + ' --apply')
        }
        $pinfo.WorkingDirectory = $ScriptDir
        $pinfo.UseShellExecute = $false
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $sout = $proc.StandardOutput.ReadToEnd()
        $serr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($sout) {
            foreach ($line in $sout -split "`r?`n") {
                if ($line -match "ERROR|SKIP|WARNING") {
                    Write-Log $line $AccentRed
                } elseif ($line -match "Applied|Wrote|Loaded|merged") {
                    Write-Log $line $AccentGreen
                } else {
                    Write-Log $line $TextGray
                }
            }
        }
        if ($serr) {
            Write-Log "" $TextGray
            Write-Log "ERRORS:" $AccentRed
            foreach ($line in $serr -split "`r?`n") {
                Write-Log ("  " + $line) $AccentRed
            }
        }

        if ($proc.ExitCode -eq 0) {
            Write-Log "" $TextGray
            Write-Log ($CharCheck + " Mods applied! Restart the game.") $AccentGreen
            $lblStatus.Text = "  " + $CharCheck + " Applied successfully"
            $lblStatus.ForeColor = $AccentGreen
        } else {
            Write-Log "" $TextGray
            Write-Log ($CharCross + " mod_manager.py exited with code " + $proc.ExitCode) $AccentRed
            $lblStatus.Text = "  " + $CharCross + " Error applying mods"
            $lblStatus.ForeColor = $AccentRed
        }
    } catch {
        Write-Log ($CharCross + " Failed to run Python: " + $_.ToString()) $AccentRed
        $lblStatus.Text = "  " + $CharCross + " Failed"
        $lblStatus.ForeColor = $AccentRed
    }
}.GetNewClosure())

# ──────────────────────────────────────────────────
# UNINSTALL
# ──────────────────────────────────────────────────
$btnUninstall.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Remove all mods and restore original game files?",
        "Confirm Uninstall", "YesNo", "Question"
    )
    if ($result -ne "Yes") { return }

    $lblStatus.Text = "  Uninstalling..."
    $lblStatus.ForeColor = $AccentOrange
    $form.Refresh()

    $txtLog.Clear()
    Write-Log "============================================" $AccentRed
    Write-Log "  UNINSTALLING MODS" $AccentRed
    Write-Log "============================================" $AccentRed

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        if ($script:UseExe) {
            $pinfo.FileName = $ModManagerExe
            $pinfo.Arguments = "--uninstall"
        } else {
            $pinfo.FileName = $PythonExe
            $pinfo.Arguments = ('"' + $ModManagerPy + '"' + " --uninstall")
        }
        $pinfo.WorkingDirectory = $ScriptDir
        $pinfo.UseShellExecute = $false
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $sout = $proc.StandardOutput.ReadToEnd()
        $serr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($sout) {
            foreach ($line in $sout -split "`r?`n") { Write-Log $line $TextGray }
        }
        Write-Log "" $TextGray
        Write-Log ($CharCheck + " Mods uninstalled. Game restored.") $AccentGreen
        $lblStatus.Text = "  " + $CharCheck + " Mods uninstalled"
        $lblStatus.ForeColor = $AccentGreen
    } catch {
        Write-Log ($CharCross + " Failed: " + $_.ToString()) $AccentRed
        $lblStatus.Text = "  " + $CharCross + " Error"
        $lblStatus.ForeColor = $AccentRed
    }
}.GetNewClosure())

# ──────────────────────────────────────────────────
# RESTORE 0.papgt
# ──────────────────────────────────────────────────
$btnRestore.Add_Click({
    $papgtBak = Join-Path $BackupsDir "0.papgt.original"
    if (-not (Test-Path $papgtBak)) {
        [System.Windows.Forms.MessageBox]::Show(
            "No backup found at:" + [Environment]::NewLine + $papgtBak + [Environment]::NewLine + [Environment]::NewLine + "Run APPLY at least once to create a backup.",
            "No Backup", "OK", "Warning"
        )
        return
    }
    if (-not $script:State.GameDir) {
        [System.Windows.Forms.MessageBox]::Show("Game path not set. Use Browse to set the game directory.", "No Game Path", "OK", "Warning")
        return
    }
    $papgtDst = Join-Path $script:State.GameDir "meta\0.papgt"
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Restore original 0.papgt from backup?" + [Environment]::NewLine + [Environment]::NewLine + "From: " + $papgtBak + [Environment]::NewLine + "To: " + $papgtDst,
        "Confirm Restore", "YesNo", "Question"
    )
    if ($result -ne "Yes") { return }
    try {
        Copy-Item -Path $papgtBak -Destination $papgtDst -Force
        Write-Log ("Restored: 0.papgt from backup") $AccentGreen
        $lblStatus.Text = "  " + $CharCheck + " 0.papgt restored"
        $lblStatus.ForeColor = $AccentGreen
    } catch {
        Write-Log ("Failed to restore 0.papgt: " + $_.ToString()) $AccentRed
        $lblStatus.Text = "  " + $CharCross + " Restore failed"
        $lblStatus.ForeColor = $AccentRed
    }
}.GetNewClosure())

# ──────────────────────────────────────────────────
# BROWSE GAME DIR
# ──────────────────────────────────────────────────
$btnBrowseGame.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select Crimson Desert game folder (contains meta/0.papgt)"
    if ($script:State.GameDir) { $fbd.SelectedPath = $script:State.GameDir }
    if ($fbd.ShowDialog() -eq "OK") {
        $sel = $fbd.SelectedPath
        $papgtCheck = Join-Path $sel "meta\0.papgt"
        if (Test-Path $papgtCheck) {
            $script:State.GameDir = $sel
            $lblGamePath.Text = "Game: " + $sel
            $lblGamePath.ForeColor = $AccentGreen
            Write-Log ("Game path set: " + $sel) $AccentGreen
            $lblStatus.Text = "  Game path updated"
            $lblStatus.ForeColor = $AccentGreen
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Invalid game directory." + [Environment]::NewLine + "meta\0.papgt not found in selected folder.",
                "Invalid Path", "OK", "Warning"
            )
        }
    }
}.GetNewClosure())

# ══════════════════════════════════════════════════════════════════
# LAUNCH
# ══════════════════════════════════════════════════════════════════
Refresh-Lists
Write-Log "Mod Manager loaded." $AccentBlue
Write-Log ("Found " + $script:AvailableMods.Count + " mod(s) in mods/ folder.") $TextGray
if ($script:State.GameDir) {
    Write-Log ("Game: " + $script:State.GameDir) $AccentGreen
} else {
    Write-Log "Game: NOT DETECTED - use Browse to set path" $AccentRed
}
Write-Log "Move mods to Active, toggle patches, then Apply." $TextGray

$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)

