---
name: sprite-normalization
description: "Normalize spritesheet frames for Phaser game characters. Use when adding new character sprites, fixing sprite jumping/size inconsistencies, or when sprites from different sources need uniform frame dimensions and character art sizes. Triggers: sprite size mismatch, animation jumping, character size differences, new sprite integration, spritesheet normalization."
---

# Sprite Normalization

Normalize spritesheets so all animations for a character have identical frame dimensions and consistent character art size. Prevents visual jumping when Phaser switches between animations.

## Why Sprites Jump

Phaser calculates sprite scale once from the first spritesheet's `frameHeight`. When an animation plays from a spritesheet with different frame dimensions, the same scale is applied but the native size differs — causing visible size/position shifts. With origin `(0.5, 1)` (bottom-center), the character's feet stay fixed but height changes.

## Three Problems to Fix

1. **Frame dimensions** — all spritesheets for a character must have the same `frameWidth x frameHeight`
2. **Character art scale** — the visible character must be the same pixel height across all spritesheets (>2% difference is visible)
3. **Horizontal centering** — the character's center of mass must be at the same X position across spritesheets (any difference causes lateral jumping)

## Workflow

### 1. Analyze

Run the bundled script in dry-run mode to identify issues:

```bash
python3 ~/.claude/skills/sprite-normalization/scripts/normalize_sprites.py \
  <sprite_dir> <grid_cols> <grid_rows> \
  --reference <blink_sprite_name> \
  --dry-run
```

- `sprite_dir`: directory containing `.png` spritesheets for ONE character
- `grid_cols`/`grid_rows`: spritesheet grid (typically `6 6` for 36-frame sheets)
- `--reference`: the "blink" or base idle sprite — all others will match its character size and centering

The script reports frame dimensions, character content height, and center X for each sprite, flagging mismatches.

### 2. Normalize

Remove `--dry-run` to apply fixes. The script will:
- Pad all frames to the max dimensions (transparent pixels)
- Scale character art to match the reference sprite's content height
- Re-center horizontally to match the reference sprite's center X
- Bottom-align vertically (feet anchored)
- Regenerate `.webp` files via `cwebp`

### 3. Update Metadata

After normalizing, update `sprite-metadata.config.ts` so all entries for the character use the new uniform `frameWidth` and `frameHeight`.

### 4. Reseed

Run `bun run seed` to propagate updated metadata to the database.

### 5. Verify

Visually inspect the first frame of the reference sprite and 2-3 fixed sprites using the Read tool to confirm consistent sizing.

## Project-Specific Context

- Sprite metadata: `packages/shared/src/game-config/sprite-metadata.config.ts`
- Sprite images: `packages/web/public/assets/sprites/<characterId>/`
- Seed command: `bun run seed`
- Phaser scaling: `(canvasHeight * targetHeightPercent / frameHeight) * scaleFactor` — calculated once from first spritesheet
- Sprite origin: `(0.5, 1)` — bottom-center anchor
- Grid: 6x6 (36 frames) for all current characters

## Thresholds

- Any content height difference from reference: scale to match (perfect overlap, no tolerance)
- Any center X difference from reference: re-center (perfect overlap, no tolerance)
- Any frame dimension mismatch: pad to max
