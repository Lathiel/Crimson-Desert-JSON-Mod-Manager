# Crimson Desert — JSON Mod Manager

A standalone mod manager for Crimson Desert that applies byte-level patches to game files using a safe overlay system. No game files are permanently modified — all changes go into a separate overlay directory that the game loads on top of the originals.

## Features

- **Single EXE** — just double-click `mod_manager.exe`, no Python or other dependencies required
- **Dark-themed 3-panel GUI**: Available Mods → Active Mods → Per-Patch Toggles
- **Per-patch control** — enable or disable individual changes within a mod
- **Color-coded categories** (Flight, Sprint, Horse, Climbing, Aerial, Swing, Swimming, Dodge, Guard, Attack, etc.)
- **Automatic Steam game directory detection**
- **One-click Apply / Uninstall**
- **Automatic backup** of original `0.papgt` before any changes
- **One-click Restore** from backup
- **Safe overlay system** — original game files are never touched

## How It Works

The mod manager uses an **overlay system**. Instead of modifying the game's original PAZ archives, it:

1. Reads the original compressed game files from `0008/`
2. Decompresses them (LZ4), applies your chosen byte patches, and recompresses
3. Writes the patched files into a new overlay directory (`0036/`)
4. Registers the overlay in `meta/0.papgt` so the game loads patched files on top of originals

Uninstalling simply removes the overlay and restores the original `0.papgt` from backup.

## Installation

### Option A: Standalone EXE (recommended)

1. Download `mod_manager.exe` from the [Releases](../../releases) page
2. Place it in a folder with a `mods/` subfolder containing your `.json` mod files
3. Double-click `mod_manager.exe`
4. The GUI will auto-detect your Crimson Desert install (Steam). If not found, click **Browse**
5. Select mods, toggle individual patches if desired, click **APPLY**

### Option B: Run from source

Requires Python 3.10+ with `lz4`:

```bash
pip install lz4
python mod_manager.py
```

Or run the GUI directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mod_manager_gui_v3.ps1
```

## Uninstalling Mods

Click **UNINSTALL** in the mod manager — this removes the overlay directory and restores your original `0.papgt`. Your game is back to 100% vanilla.

## Folder Structure

```
mod_manager.exe          — the mod manager (double-click to run)
mod_manager.py           — Python source (not needed with EXE)
mod_manager_gui_v3.ps1   — PowerShell GUI source (bundled in EXE)
pamt_patcher.py          — PAMT file parser
pa_checksum.py           — PA Jenkins Lookup3 hash
mods/                    — place your .json mod files here
  enabled/               — mods moved here are active
backups/                 — automatic backup of original 0.papgt
```

## Requirements

- Windows 10/11
- Crimson Desert (Steam)
- **Source version**: Python 3.10+ with `lz4` (`pip install lz4`)

## Compatibility

After a game update, byte offsets may shift. If the mod manager detects that original bytes don't match at the expected offsets, it will skip those patches and report which ones failed. Mod JSONs will need to be updated for the new game version.

## Antivirus Note

The standalone EXE is built with [PyInstaller](https://pyinstaller.org/) and may trigger false positive virus alerts. This is a [known issue](https://github.com/pyinstaller/pyinstaller/issues/6754) with PyInstaller-packaged executables. The full source code is available in this repository — you can review it and build the EXE yourself:

```bash
pip install pyinstaller lz4
pyinstaller --onefile --hidden-import lz4 --hidden-import lz4.block --add-data "mod_manager_gui_v3.ps1;." mod_manager.py
```

## License

MIT
