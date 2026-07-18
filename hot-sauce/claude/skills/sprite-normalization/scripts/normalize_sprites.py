#!/usr/bin/env python3
"""
Normalize spritesheet frames for a character.

Ensures all spritesheets for a character have:
1. Identical frame dimensions (padded to max across all sprites)
2. Consistent character art size (scaled to match a reference sprite)
3. Consistent horizontal centering

Usage:
    python3 normalize_sprites.py <sprite_dir> <grid_cols> <grid_rows> [--reference <name>] [--dry-run]

Arguments:
    sprite_dir   Directory containing .png spritesheets for ONE character
    grid_cols    Number of columns in the spritesheet grid (e.g., 6)
    grid_rows    Number of rows in the spritesheet grid (e.g., 6)

Options:
    --reference <name>   Sprite name (without extension) to use as the size/position
                         reference. Defaults to the first sprite alphabetically.
    --dry-run            Analyze and report without modifying files.
    --webp-quality <q>   WebP quality (default: 80).

Requires: Pillow (pip install Pillow), cwebp (brew install webp)
"""

import argparse
import os
import subprocess
import sys

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required. Install with: pip install Pillow")
    sys.exit(1)


def get_content_bbox(img, frame_w, frame_h):
    """Get bounding box of non-transparent content in the first frame."""
    frame = img.crop((0, 0, frame_w, frame_h))
    alpha = frame.getchannel("A")
    return alpha.getbbox()


def analyze_sprites(sprite_dir, grid_cols, grid_rows, ref_frame_h=None):
    """Analyze all PNG spritesheets in a directory.

    If ref_frame_h is provided, auto-detect rows per sprite by dividing
    image height by ref_frame_h. This handles sprites with fewer rows
    (e.g., 6x3 for 18-frame animations alongside 6x6 for 36-frame ones).
    """
    sprites = {}
    skipped_non_spritesheets = []
    for f in sorted(os.listdir(sprite_dir)):
        if not f.endswith(".png") or f.startswith("."):
            continue
        name = f[:-4]
        path = os.path.join(sprite_dir, f)
        img = Image.open(path)

        if img.mode != "RGBA":
            img = img.convert("RGBA")

        w, h = img.size

        # Skip non-spritesheet images (face avatars, sitting poses, etc.)
        # A valid spritesheet must be at least grid_cols frames wide and
        # grid_rows frames tall (i.e. width >= grid_cols * 2 pixels per frame)
        min_spritesheet_w = grid_cols * 10  # at least 10px per frame
        min_spritesheet_h = grid_rows * 10
        if w < min_spritesheet_w or h < min_spritesheet_h:
            skipped_non_spritesheets.append((name, w, h))
            continue

        # Also skip if grid division produces unreasonably small frames
        fw_candidate = w // grid_cols
        fh_candidate = h // grid_rows
        if fw_candidate < 50 or fh_candidate < 50:
            skipped_non_spritesheets.append((name, w, h))
            continue

        fw = w // grid_cols

        # Auto-detect rows if reference frame height is known
        if ref_frame_h and h != ref_frame_h * grid_rows:
            actual_rows = round(h / ref_frame_h)
            if actual_rows > 0 and abs(h / actual_rows - ref_frame_h) < 2:
                fh = h // actual_rows
            else:
                fh = h // grid_rows
            sprite_rows = actual_rows
        else:
            fh = h // grid_rows
            sprite_rows = grid_rows

        bbox = get_content_bbox(img, fw, fh)
        if not bbox:
            print(f"  WARNING: {name} has no visible content in first frame, skipping")
            continue

        content_h = bbox[3] - bbox[1]
        content_w = bbox[2] - bbox[0]
        center_x = (bbox[0] + bbox[2]) / 2

        sprites[name] = {
            "path": path,
            "img_size": (w, h),
            "frame_size": (fw, fh),
            "actual_rows": sprite_rows,
            "content_bbox": bbox,
            "content_size": (content_w, content_h),
            "center_x": center_x,
        }

    if skipped_non_spritesheets:
        for sname, sw, sh in skipped_non_spritesheets:
            print(f"  Skipping {sname}.png ({sw}x{sh}) — not a spritesheet")

    return sprites


def print_analysis(sprites, reference_name, target_fw, target_fh):
    """Print analysis report."""
    ref = sprites[reference_name]
    ref_h = ref["content_size"][1]
    ref_cx = ref["center_x"]

    print(f"\nReference sprite: {reference_name}")
    print(f"  Content height: {ref_h}px, center_x: {ref_cx:.1f}")
    print(f"  Target frame: {target_fw}x{target_fh}")

    print(f"\n{'Sprite':<30} {'Frame':>10} {'Content H':>10} {'Center X':>10} {'Issues'}")
    print("-" * 85)

    for name, info in sorted(sprites.items()):
        fw, fh = info["frame_size"]
        ch = info["content_size"][1]
        cx = info["center_x"]

        issues = []
        if fw != target_fw or fh != target_fh:
            issues.append(f"frame {fw}x{fh}")
        h_diff = abs(ch - ref_h) / ref_h * 100
        if h_diff > 0:
            issues.append(f"height {h_diff:+.1f}%")
        x_diff = abs(cx - ref_cx)
        if x_diff > 0:
            issues.append(f"center off by {x_diff:.1f}px")

        marker = " *" if issues else ""
        print(
            f"{name:<30} {fw}x{fh:>4} {ch:>10} {cx:>10.1f} {', '.join(issues)}{marker}"
        )


def normalize_sprites(
    sprite_dir, grid_cols, grid_rows, reference_name, webp_quality, dry_run
):
    """Main normalization routine."""
    print(f"Analyzing sprites in: {sprite_dir}")
    print(f"Grid: {grid_cols}x{grid_rows}")

    # First pass: analyze with assumed grid to find reference frame height
    sprites = analyze_sprites(sprite_dir, grid_cols, grid_rows)
    if not sprites:
        print("No valid sprites found.")
        return

    # Determine reference
    if reference_name and reference_name not in sprites:
        print(f"ERROR: Reference sprite '{reference_name}' not found.")
        print(f"Available: {', '.join(sorted(sprites.keys()))}")
        sys.exit(1)

    if not reference_name:
        reference_name = sorted(sprites.keys())[0]

    ref_frame_h = sprites[reference_name]["frame_size"][1]

    # Second pass: re-analyze with auto-detected rows per sprite
    sprites = analyze_sprites(sprite_dir, grid_cols, grid_rows, ref_frame_h)
    if reference_name not in sprites:
        print(f"ERROR: Reference sprite '{reference_name}' lost in re-analysis.")
        sys.exit(1)

    ref = sprites[reference_name]
    ref_content_h = ref["content_size"][1]
    ref_center_x = ref["center_x"]

    # Target frame = max dimensions across all sprites
    target_fw = max(info["frame_size"][0] for info in sprites.values())
    target_fh = max(info["frame_size"][1] for info in sprites.values())

    print_analysis(sprites, reference_name, target_fw, target_fh)

    if dry_run:
        print("\n[DRY RUN] No files modified.")
        return

    modified = 0
    for name, info in sorted(sprites.items()):
        src_fw, src_fh = info["frame_size"]
        actual_rows = info["actual_rows"]
        content_h = info["content_size"][1]
        center_x = info["center_x"]

        needs_pad = src_fw != target_fw or src_fh != target_fh
        h_diff = abs(content_h - ref_content_h)
        needs_scale = h_diff > 0
        x_diff = abs(center_x - ref_center_x)
        needs_recenter = x_diff > 0

        if not needs_pad and not needs_scale and not needs_recenter:
            continue

        print(f"\nProcessing {name} ({grid_cols}x{actual_rows} grid)...")
        img = Image.open(info["path"])
        if img.mode != "RGBA":
            img = img.convert("RGBA")

        scale_factor = ref_content_h / content_h if needs_scale else 1.0
        if needs_scale:
            print(f"  Scaling by {scale_factor:.4f} (content {content_h} -> ~{ref_content_h})")

        # Output uses actual_rows for this sprite (preserves original row count)
        target_w = target_fw * grid_cols
        target_h = target_fh * actual_rows

        new_img = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))

        for row in range(actual_rows):
            for col in range(grid_cols):
                src_x = col * src_fw
                src_y = row * src_fh
                frame = img.crop((src_x, src_y, src_x + src_fw, src_y + src_fh))

                if needs_scale and scale_factor != 1.0:
                    new_frame_w = round(src_fw * scale_factor)
                    new_frame_h = round(src_fh * scale_factor)
                    frame = frame.resize((new_frame_w, new_frame_h), Image.LANCZOS)
                else:
                    new_frame_w = src_fw
                    new_frame_h = src_fh

                dst_cell_x = col * target_fw
                dst_cell_y = row * target_fh

                # Horizontal: always align content center with reference center
                scaled_center = center_x * scale_factor if needs_scale else center_x
                x_offset = round(ref_center_x - scaled_center)

                # Vertical: bottom-align
                y_offset = target_fh - new_frame_h

                new_img.paste(frame, (dst_cell_x + x_offset, dst_cell_y + y_offset))

        png_path = info["path"]
        new_img.save(png_path, "PNG", optimize=True)
        print(f"  Saved {png_path}")

        # Generate WebP
        webp_path = png_path.rsplit(".", 1)[0] + ".webp"
        if os.path.exists(webp_path) or True:
            result = subprocess.run(
                ["cwebp", "-q", str(webp_quality), png_path, "-o", webp_path],
                capture_output=True,
            )
            if result.returncode == 0:
                print(f"  Saved {webp_path}")
            else:
                print(f"  WARNING: cwebp failed for {webp_path}")

        modified += 1

    print(f"\nDone. Modified {modified}/{len(sprites)} sprites.")
    print(f"All frames now: {target_fw}x{target_fh}")


def main():
    parser = argparse.ArgumentParser(
        description="Normalize spritesheet frames for a character"
    )
    parser.add_argument("sprite_dir", help="Directory containing .png spritesheets")
    parser.add_argument("grid_cols", type=int, help="Grid columns (e.g., 6)")
    parser.add_argument("grid_rows", type=int, help="Grid rows (e.g., 6)")
    parser.add_argument("--reference", help="Reference sprite name (without .png)")
    parser.add_argument("--dry-run", action="store_true", help="Analyze only")
    parser.add_argument("--webp-quality", type=int, default=80, help="WebP quality")

    args = parser.parse_args()

    if not os.path.isdir(args.sprite_dir):
        print(f"ERROR: {args.sprite_dir} is not a directory")
        sys.exit(1)

    normalize_sprites(
        args.sprite_dir,
        args.grid_cols,
        args.grid_rows,
        args.reference,
        args.webp_quality,
        args.dry_run,
    )


if __name__ == "__main__":
    main()
