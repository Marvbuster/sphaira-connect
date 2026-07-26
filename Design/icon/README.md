# Icon assets

Layers for **Icon Composer**
(`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`).

| File | Contents |
|---|---|
| `sphere.svg` | Sphere, radial gradient, light offset towards the upper left |
| `arrow.svg` | Downward arrow, subtle vertical gradient |
| `device.svg` | Abstract handheld console, same gradient as the arrow |

All three are 1024 × 1024, free-standing on a transparent background, and share the
same coordinate system — stacked on top of each other, the arrow sits centred on
the sphere.

**Deliberately absent:** specular highlights, drop shadows, opacity and the icon's
corner rounding. Icon Composer applies those itself; baking them in here means
getting them twice.

## Dimensions

- Sphere: centre 512/512, radius 340
- Arrow: horizontally centred, y from 210 to 830, shaft 180 wide, head 380 wide
- Device: scaled by 7 and offset by 162/162, so it too ends up centred

## Recolouring

Change only the `stop-color` values in the `<defs>` block. The sphere has four
stops (light → dark), the arrow and the device two each.

## Attribution

`device.svg` is derived from third-party artwork licensed CC BY 3.0 — see
[`NOTICE.md`](../../NOTICE.md) in the repository root.
