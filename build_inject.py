#!/usr/bin/env python3
"""
Inject VibeTokHD.dylib into TikTok.ipa while preserving original compression.
This avoids file size bloat by NOT re-compressing already-compressed files.
"""
import zipfile
import os
import sys
import shutil

WORK_DIR = os.environ.get("WORK_DIR", ".")
ORIG_IPA = os.path.join(WORK_DIR, "TikTok.ipa")
DYLIB_PATH = os.environ.get("DYLIB_PATH", "")
OUT_IPA = os.path.join(WORK_DIR, "VibeTokHD-signed.ipa")

# Target path inside IPA
TARGET_DYLIB = "Payload/TikTok.app/Frameworks/VibeTok.dylib"

if not os.path.exists(ORIG_IPA):
    print(f"ERROR: {ORIG_IPA} not found")
    sys.exit(1)

if not os.path.exists(DYLIB_PATH):
    print(f"ERROR: dylib not found at {DYLIB_PATH}")
    sys.exit(1)

print(f"Original IPA: {ORIG_IPA}")
print(f"Dylib: {DYLIB_PATH}")
print(f"Output: {OUT_IPA}")

# Read dylib
with open(DYLIB_PATH, 'rb') as f:
    dylib_data = f.read()

print(f"Dylib size: {len(dylib_data)} bytes")

# Build new IPA, preserving compression per-file
with zipfile.ZipFile(ORIG_IPA, 'r') as orig:
    with zipfile.ZipFile(OUT_IPA, 'w') as out:
        copied = 0
        for item in orig.infolist():
            # Read original data
            data = orig.read(item.filename)
            # Preserve original compression method per file
            new_info = zipfile.ZipInfo(item.filename, date_time=item.date_time)
            new_info.compress_type = item.compress_type
            new_info.external_attr = item.external_attr
            out.writestr(new_info, data)
            copied += 1
        print(f"Copied {copied} files from original")

        # Add VibeTok.dylib
        new_info = zipfile.ZipInfo(TARGET_DYLIB, date_time=(2026, 10, 3, 0, 0, 0))
        new_info.compress_type = zipfile.ZIP_STORED  # Don't compress dylib
        out.writestr(new_info, dylib_data)
        print(f"Added {TARGET_DYLIB}")

# Report
orig_size = os.path.getsize(ORIG_IPA)
out_size = os.path.getsize(OUT_IPA)
print(f"\n=== Results ===")
print(f"Original: {orig_size:,} bytes ({orig_size/1024/1024:.2f} MB)")
print(f"Output:   {out_size:,} bytes ({out_size/1024/1024:.2f} MB)")
print(f"Diff:     {out_size - orig_size:+,} bytes ({(out_size - orig_size)/1024/1024:+.2f} MB)")
