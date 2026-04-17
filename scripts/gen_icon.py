#!/usr/bin/env python3
"""Generate CuePrompt app icon at all required macOS sizes.

Resizes Sources/Resources/AppIcon-source.png (the approved AI-generated
icon with transparent background) into the full .iconset and converts
to .icns via iconutil.
"""

from PIL import Image
import os


def main():
    project = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source_path = os.path.join(project, "Sources", "Resources", "AppIcon-source.png")
    iconset_dir = os.path.join(project, "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    source = Image.open(source_path).convert("RGBA")
    assert source.size[0] >= 1024, f"Source icon must be at least 1024px, got {source.size}"

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for name, px in sizes:
        resized = source.resize((px, px), Image.LANCZOS)
        path = os.path.join(iconset_dir, name)
        resized.save(path, "PNG")
        print(f"  {name} ({px}x{px})")

    # Convert to .icns
    icns_path = os.path.join(project, "CuePrompt.app", "Contents", "Resources", "AppIcon.icns")
    os.makedirs(os.path.dirname(icns_path), exist_ok=True)

    ret = os.system(f'iconutil -c icns -o "{icns_path}" "{iconset_dir}"')
    if ret == 0:
        print(f"\nIcon installed: {icns_path}")
    else:
        print(f"\niconutil failed (exit {ret}). PNGs are in {iconset_dir}")

    # Save a 1024px preview
    preview_path = os.path.join(project, "icon_preview.png")
    source.save(preview_path, "PNG")
    print(f"Preview: {preview_path}")

    if ret == 0:
        import shutil
        shutil.rmtree(iconset_dir)


if __name__ == "__main__":
    main()
