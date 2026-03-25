"""
Crimson Desert — Mod Manager
==============================
Merges ALL enabled modpatch JSON files into a single overlay (0036/).

Usage:
    python mod_manager.py                 # apply all mods from mods/enabled/
    python mod_manager.py --list          # list enabled mods
    python mod_manager.py --uninstall     # restore original game files

Mod JSON format:
{
  "name": "...",
  "patches": [{
    "game_file": "gamedata/skill.pabgb",
    "changes": [{"offset": 123, "original": "aabb", "patched": "ccdd"}]
  }]
}
"""
import os, sys, struct, json, glob, shutil, subprocess, tempfile
from collections import defaultdict

import lz4.block

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pa_checksum import pa_checksum
from pamt_patcher import read_pamt_raw, resolve_filename, resolve_dirname

# ─── Configuration ──────────────────────────────────────────────────────

# Auto-detect game directory
_STEAM_PATHS = [
    r"C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert",
    r"C:\Program Files\Steam\steamapps\common\Crimson Desert",
    r"D:\SteamLibrary\steamapps\common\Crimson Desert",
    r"E:\SteamLibrary\steamapps\common\Crimson Desert",
    r"G:\SteamLibrary\steamapps\common\Crimson Desert",
]
GAME_DIR = None
for _p in _STEAM_PATHS:
    if os.path.isdir(_p):
        GAME_DIR = _p
        break
if GAME_DIR is None:
    GAME_DIR = r"G:\SteamLibrary\steamapps\common\Crimson Desert"
    print(f"WARNING: Game directory not auto-detected, using default: {GAME_DIR}")

SOURCE_GROUP = "0008"  # group containing original game data
MOD_DIR_NAME = "0036"  # overlay directory name
PAZ_ALIGNMENT = 16
PAMT_UNKNOWN = 0x610E0232
PAPGT_LANG_ALL = 0x3FFF

if getattr(sys, 'frozen', False):
    SCRIPT_DIR = os.path.dirname(os.path.abspath(sys.executable))
else:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODS_DIR = os.path.join(SCRIPT_DIR, "mods", "enabled")


# ─── File resolution ────────────────────────────────────────────────────

def build_file_index(pamt_info):
    """Build index: simplified_path -> (full_vfs_path, dir_path, filename, file_record)"""
    fn_data = pamt_info['fn_data']
    dir_data = pamt_info['raw'][
        pamt_info['dir_block_offset'] + 4:
        pamt_info['dir_block_offset'] + 4 + pamt_info['dir_block_size']
    ]

    index = {}  # simplified -> info
    full_index = {}  # full_path -> info

    for he in pamt_info['hash_entries']:
        dir_path = resolve_dirname(dir_data, he['name_offset'])
        for i in range(he['file_start_index'], he['file_start_index'] + he['file_count']):
            fr = pamt_info['file_records'][i]
            fname = resolve_filename(fn_data, fr['name_offset'])
            full_path = f"{dir_path}/{fname}" if dir_path else fname

            info = {
                'full_path': full_path,
                'dir_path': dir_path,
                'filename': fname,
                'record': fr,
                'record_index': i,
            }

            full_index[full_path] = info

            # Build simplified path: strip intermediate dirs -> "gamedata/filename.ext"
            parts = dir_path.split('/') if dir_path else []
            if parts:
                simplified = f"{parts[0]}/{fname}"
            else:
                simplified = fname
            # Only add if not ambiguous (first match wins)
            if simplified not in index:
                index[simplified] = info

    return index, full_index


def resolve_game_file(simplified, file_index, full_index):
    """Resolve a modpatch game_file path to full VFS info."""
    # Try exact match on full path first
    if simplified in full_index:
        return full_index[simplified]
    # Try simplified index
    if simplified in file_index:
        return file_index[simplified]
    return None


# ─── Load modpatch files ────────────────────────────────────────────────

def load_modpatches(mods_dir):
    """Load all JSON modpatch files from the enabled mods directory."""
    mods = []
    if not os.path.isdir(mods_dir):
        os.makedirs(mods_dir, exist_ok=True)
        return mods

    for path in sorted(glob.glob(os.path.join(mods_dir, "*.json"))):
        with open(path, 'r', encoding='utf-8-sig') as f:
            mod = json.load(f)
        mod['_path'] = path
        mods.append(mod)

    # Also support .modpatch (JSON format)
    for path in sorted(glob.glob(os.path.join(mods_dir, "*.modpatch"))):
        try:
            with open(path, 'r', encoding='utf-8-sig') as f:
                mod = json.load(f)
            mod['_path'] = path
            mods.append(mod)
        except json.JSONDecodeError:
            print(f"  SKIP: {os.path.basename(path)} (not valid JSON)")

    return mods


# ─── Multi-file PAMT builder ────────────────────────────────────────────

def build_multi_pamt(files, paz_data_len):
    """Build PAMT for multiple modded files in one overlay.

    Args:
        files: list of dicts with keys:
            dir_path, filename, comp_size, decomp_size, paz_offset
        paz_data_len: total aligned PAZ file size
    """
    # Step 1: Build DirBlock — collect all unique directory segments
    dir_block = bytearray()
    segment_offsets = {}  # partial_path -> offset in dir_block

    unique_dirs = sorted(set(f['dir_path'] for f in files))

    for dir_path in unique_dirs:
        parts = dir_path.split('/')
        for i, part in enumerate(parts):
            partial_path = '/'.join(parts[:i + 1])
            if partial_path in segment_offsets:
                continue

            offset = len(dir_block)
            segment_offsets[partial_path] = offset

            if i == 0:
                parent = 0xFFFFFFFF
                name = part
            else:
                parent_path = '/'.join(parts[:i])
                parent = segment_offsets[parent_path]
                name = '/' + part

            name_bytes = name.encode('utf-8')
            dir_block += struct.pack('<I', parent)
            dir_block += struct.pack('B', len(name_bytes)) + name_bytes

    # Step 2: Group files by directory, build FilenameBlock + records
    dir_files = defaultdict(list)
    for f in files:
        dir_files[f['dir_path']].append(f)

    fn_block = bytearray()
    hash_entries = []
    file_records = []
    file_index = 0

    for dir_path in sorted(dir_files.keys()):
        dir_hash = pa_checksum(dir_path.encode('utf-8'))
        dir_name_offset = segment_offsets[dir_path]

        file_start = file_index

        for f in dir_files[dir_path]:
            fn_off = len(fn_block)
            fn_block += struct.pack('<I', 0xFFFFFFFF)
            name_bytes = f['filename'].encode('utf-8')
            fn_block += struct.pack('B', len(name_bytes)) + name_bytes

            file_records.append(struct.pack('<IIIIHH',
                fn_off,
                f['paz_offset'],
                f['comp_size'],
                f['decomp_size'],
                0,       # paz_index (always 0)
                0x0002,  # flags: LZ4 compressed
            ))
            file_index += 1

        hash_entries.append(struct.pack('<IIII',
            dir_hash,
            dir_name_offset,
            file_start,
            len(dir_files[dir_path]),
        ))

    # Step 3: Assemble PAMT
    paz_info = struct.pack('<III', 0, 0, paz_data_len)

    body = bytearray()
    body += struct.pack('<II', 1, PAMT_UNKNOWN)
    body += paz_info
    body += struct.pack('<I', len(dir_block)) + dir_block
    body += struct.pack('<I', len(fn_block)) + fn_block
    body += struct.pack('<I', len(hash_entries))
    for he in hash_entries:
        body += he
    body += struct.pack('<I', len(file_records))
    for fr in file_records:
        body += fr

    header_crc = pa_checksum(bytes(body[8:]))
    return struct.pack('<I', header_crc) + bytes(body)


def update_pamt_paz_crc(pamt_data, paz_crc):
    """Update PAZ CRC in the first PazInfo entry and recalculate header CRC."""
    data = bytearray(pamt_data)
    struct.pack_into('<I', data, 16, paz_crc)
    new_crc = pa_checksum(bytes(data[12:]))
    struct.pack_into('<I', data, 0, new_crc)
    return bytes(data)


# ─── PAPGT builder ──────────────────────────────────────────────────────

def build_papgt_with_mod(papgt_path, mod_dir_name, pamt_crc):
    """Build PAPGT with mod overlay registered at position [0]."""
    with open(papgt_path, 'rb') as f:
        orig = f.read()

    gc = orig[8]
    sbo = 12 + gc * 12
    str_data = orig[sbo + 4:]

    entries = []
    names = []
    for i in range(gc):
        off = 12 + i * 12
        e = {
            'is_optional': orig[off],
            'lang_type': struct.unpack_from('<H', orig, off + 1)[0],
            'zero': orig[off + 3],
            'name_offset': struct.unpack_from('<I', orig, off + 4)[0],
            'pamt_crc': struct.unpack_from('<I', orig, off + 8)[0],
        }
        entries.append(e)
        noff = e['name_offset']
        end = str_data.find(b'\x00', noff)
        names.append(str_data[noff:end].decode('ascii'))

    pairs = list(zip(entries, names))

    mod_idx = next((i for i, n in enumerate(names) if n == mod_dir_name), None)
    if mod_idx is not None:
        pairs[mod_idx][0]['pamt_crc'] = pamt_crc
    else:
        new_entry = {'is_optional': 0, 'lang_type': PAPGT_LANG_ALL, 'zero': 0,
                     'name_offset': 0, 'pamt_crc': pamt_crc}
        pairs.insert(0, (new_entry, mod_dir_name))

    new_gc = len(pairs)
    str_block = bytearray()
    name_offsets = []
    for _, name in pairs:
        name_offsets.append(len(str_block))
        str_block += name.encode('ascii') + b'\x00'

    entry_block = bytearray()
    for i, (e, _) in enumerate(pairs):
        entry_block += struct.pack('B', e['is_optional'])
        entry_block += struct.pack('<H', e['lang_type'])
        entry_block += struct.pack('B', e['zero'])
        entry_block += struct.pack('<I', name_offsets[i])
        entry_block += struct.pack('<I', e['pamt_crc'])

    payload = entry_block + struct.pack('<I', len(str_block)) + str_block
    file_crc = pa_checksum(bytes(payload))
    header = struct.pack('<I', struct.unpack_from('<I', orig, 0)[0])
    header += struct.pack('<I', file_crc)
    header += struct.pack('B', new_gc)
    header += struct.pack('<H', struct.unpack_from('<H', orig, 9)[0])
    header += struct.pack('B', orig[11])
    return header + payload


# ─── Main logic ─────────────────────────────────────────────────────────

def cmd_list():
    """List enabled mods."""
    mods = load_modpatches(MODS_DIR)
    if not mods:
        print("No mods in mods/enabled/")
        print(f"  Place .json modpatch files in: {MODS_DIR}")
        return

    print(f"Enabled mods ({len(mods)}):")
    for mod in mods:
        name = mod.get('name', '?')
        desc = mod.get('description', '')[:60]
        files = set()
        for p in mod.get('patches', []):
            files.add(p['game_file'])
        print(f"  [{name}] {desc}")
        print(f"    Files: {', '.join(sorted(files))}")


def cmd_uninstall():
    """Restore original game files."""
    papgt_path = os.path.join(GAME_DIR, 'meta', '0.papgt')
    papgt_bak = papgt_path + '.bak'
    mod_dir = os.path.join(GAME_DIR, MOD_DIR_NAME)

    if os.path.exists(papgt_bak):
        shutil.copy2(papgt_bak, papgt_path)
        print("  Restored: meta/0.papgt from backup")
    else:
        print("  WARNING: No backup found!")

    if os.path.isdir(mod_dir):
        shutil.rmtree(mod_dir)
        print(f"  Removed: {MOD_DIR_NAME}/")

    print("\nDone — original game restored. Restart the game.")


def cmd_apply():
    """Apply all enabled mods."""
    papgt_path = os.path.join(GAME_DIR, 'meta', '0.papgt')
    papgt_bak = papgt_path + '.bak'
    pamt_path = os.path.join(GAME_DIR, SOURCE_GROUP, '0.pamt')
    mod_dir = os.path.join(GAME_DIR, MOD_DIR_NAME)

    # ── Step 1: Load all modpatches ──
    mods = load_modpatches(MODS_DIR)
    if not mods:
        print("No mods found in mods/enabled/")
        print(f"  Place .json modpatch files in: {MODS_DIR}")
        return

    print(f"Loaded {len(mods)} mod(s):")
    for m in mods:
        print(f"  - {m.get('name', '?')}")

    # ── Step 2: Group all changes by game_file ──
    # merged[game_file] = list of (mod_name, change)
    merged = defaultdict(list)
    for mod in mods:
        mod_name = mod.get('name', '?')
        for patch in mod.get('patches', []):
            gf = patch['game_file']
            for change in patch['changes']:
                merged[gf].append((mod_name, change))

    print(f"\nTarget files ({len(merged)}):")
    for gf, changes in sorted(merged.items()):
        mods_involved = sorted(set(m for m, _ in changes))
        print(f"  {gf}: {len(changes)} patches from [{', '.join(mods_involved)}]")

    # ── Step 3: Build file index from 0008 PAMT ──
    print(f"\nReading {SOURCE_GROUP}/0.pamt...")
    pamt_info = read_pamt_raw(pamt_path)
    file_index, full_index = build_file_index(pamt_info)

    # ── Step 4: For each game file, load original → patch → compress ──
    paz_buf = bytearray()
    overlay_files = []  # for PAMT builder

    for game_file, changes in sorted(merged.items()):
        info = resolve_game_file(game_file, file_index, full_index)
        if info is None:
            print(f"\n  ERROR: Cannot find '{game_file}' in {SOURCE_GROUP}/0.pamt!")
            print(f"  Skipping...")
            continue

        fr = info['record']
        full_path = info['full_path']
        dir_path = info['dir_path']
        filename = info['filename']

        print(f"\n  Processing: {full_path}")
        print(f"    Source: {SOURCE_GROUP}/{fr['paz_index']}.paz @ 0x{fr['paz_offset']:08X}")
        print(f"    Size: {fr['comp_size']} compressed, {fr['decomp_size']} decompressed")

        # Read original compressed data
        src_paz = os.path.join(GAME_DIR, SOURCE_GROUP, f"{fr['paz_index']}.paz")
        with open(src_paz, 'rb') as f:
            f.seek(fr['paz_offset'])
            comp_data = f.read(fr['comp_size'])

        # Decompress
        buf = bytearray(lz4.block.decompress(comp_data, uncompressed_size=fr['decomp_size']))

        # Apply all patches for this file
        applied = 0
        skipped = 0
        for mod_name, change in changes:
            offset = change['offset']
            orig_bytes = bytes.fromhex(change['original'])
            patch_bytes = bytes.fromhex(change['patched'])
            label = change.get('label', f'@{offset}')

            current = bytes(buf[offset:offset + len(orig_bytes)])
            if current == orig_bytes:
                buf[offset:offset + len(patch_bytes)] = patch_bytes
                applied += 1
            else:
                print(f"    SKIP [{mod_name}] {label}: expected {orig_bytes.hex()}, got {current.hex()}")
                skipped += 1

        print(f"    Applied: {applied}, Skipped: {skipped}")

        # Recompress
        new_comp = lz4.block.compress(bytes(buf), store_size=False)
        print(f"    Recompressed: {len(buf)} -> {len(new_comp)} bytes")

        # Add to PAZ buffer
        paz_offset = len(paz_buf)
        paz_buf += new_comp

        # Align
        remainder = len(paz_buf) % PAZ_ALIGNMENT
        if remainder:
            paz_buf += b'\x00' * (PAZ_ALIGNMENT - remainder)

        overlay_files.append({
            'dir_path': dir_path,
            'filename': filename,
            'comp_size': len(new_comp),
            'decomp_size': fr['decomp_size'],
            'paz_offset': paz_offset,
        })

    if not overlay_files:
        print("\nNo files to patch!")
        return

    # ── Step 5: Write PAZ ──
    os.makedirs(mod_dir, exist_ok=True)
    paz_path = os.path.join(mod_dir, '0.paz')
    with open(paz_path, 'wb') as f:
        f.write(paz_buf)
    paz_crc = pa_checksum(bytes(paz_buf))
    print(f"\n  Wrote: {MOD_DIR_NAME}/0.paz ({len(paz_buf)} bytes, CRC=0x{paz_crc:08X})")

    # ── Step 6: Build and write PAMT ──
    pamt_data = build_multi_pamt(overlay_files, len(paz_buf))
    pamt_data = update_pamt_paz_crc(pamt_data, paz_crc)
    pamt_crc = struct.unpack_from('<I', pamt_data, 0)[0]

    pamt_out = os.path.join(mod_dir, '0.pamt')
    with open(pamt_out, 'wb') as f:
        f.write(pamt_data)
    print(f"  Wrote: {MOD_DIR_NAME}/0.pamt ({len(pamt_data)} bytes, CRC=0x{pamt_crc:08X})")

    # ── Step 7: Update PAPGT ──
    if not os.path.exists(papgt_bak):
        shutil.copy2(papgt_path, papgt_bak)
        print(f"  Backed up: meta/0.papgt -> 0.papgt.bak")
    else:
        shutil.copy2(papgt_bak, papgt_path)

    new_papgt = build_papgt_with_mod(papgt_path, MOD_DIR_NAME, pamt_crc)
    with open(papgt_path, 'wb') as f:
        f.write(new_papgt)
    print(f"  Wrote: meta/0.papgt ({len(new_papgt)} bytes)")

    # ── Summary ──
    print(f"\n{'='*60}")
    print(f"  {len(mods)} mod(s) merged into {MOD_DIR_NAME}/")
    print(f"  {len(overlay_files)} game file(s) patched:")
    for of in overlay_files:
        print(f"    - {of['dir_path']}/{of['filename']}")
    print(f"  Restart the game to apply.")
    print(f"{'='*60}")


# ─── GUI Launcher ───────────────────────────────────────────────────────

def launch_gui():
    """Extract bundled PS1 and launch it, pointing at EXE's directory."""
    if getattr(sys, 'frozen', False):
        bundle_dir = sys._MEIPASS
    else:
        bundle_dir = SCRIPT_DIR

    ps1_source = os.path.join(bundle_dir, "mod_manager_gui_v3.ps1")
    if not os.path.isfile(ps1_source):
        print(f"ERROR: GUI script not found at {ps1_source}")
        sys.exit(1)

    # Write PS1 to a temp file so $ScriptDir doesn't matter
    tmp_fd, tmp_path = tempfile.mkstemp(suffix='.ps1')
    try:
        with open(ps1_source, 'r', encoding='utf-8') as src:
            content = src.read()
        os.write(tmp_fd, content.encode('utf-8'))
        os.close(tmp_fd)

        subprocess.run([
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", tmp_path,
            "-RootDir", SCRIPT_DIR
        ])
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


# ─── CLI ────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]

    if '--list' in args:
        cmd_list()
    elif '--uninstall' in args:
        cmd_uninstall()
    elif '--apply' in args:
        cmd_apply()
    elif len(args) == 0:
        launch_gui()
    else:
        cmd_apply()


if __name__ == '__main__':
    main()
