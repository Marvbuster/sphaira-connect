# Third-party notices

Sphaira Connect itself is licensed under [GPL-3.0](LICENSE). The components listed
here keep their own licenses and are **not** covered by that grant.

---

## App icon artwork

> "nintendo switch" by **Mikicon** from the
> [Noun Project](https://thenounproject.com/browse/icons/term/nintendo-switch/),
> licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).

Modifications: the caption embedded in the original SVG was removed, the artwork
was centred on a 1024 × 1024 canvas and its fill replaced with a gradient. The
attribution moved here, into [`README.md`](README.md) and into the app's About
panel, which is where CC BY 3.0 requires it to be reachable for anyone using the
work.

Source file: [`Design/icon/device.svg`](Design/icon/device.svg)

## libusb

[libusb](https://libusb.info) is licensed under
[LGPL-2.1-or-later](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html) and is
**linked statically** into the shipped binary.

The LGPL requires that you be able to replace this library with your own build.
Because the entire application is GPL-3.0 and its complete source is published, you
can do exactly that: adjust `OTHER_LDFLAGS`, rebuild, and you have a binary linked
against your own libusb. No separate object files are needed for that.

## Sphaira

The USB protocol implementation is derived from `tools/usb_install.py` in
[Sphaira](https://github.com/ITotalJustice/sphaira) by
[ITotalJustice](https://github.com/ITotalJustice), licensed under
[GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html).

This derivation is the reason Sphaira Connect is GPL-3.0 rather than a permissive
license — it is an obligation, not a preference.

## RCM payload injection

The RCM payload layout and USB flow are based on the publicly documented
Fusée Gelée protocol. The implementation in
[ironfoil](https://github.com/sermuns/ironfoil) by sermuns served as a reference.
ironfoil is dual-licensed under
[Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0) or
[MIT](https://opensource.org/license/mit).

The 92-byte intermezzo relocator embedded in `Core/RCMPayload.swift` is the
standard relocator distributed with Fusée Gelée implementations, including
ironfoil.

## Not affiliated

Nintendo, Nintendo Switch and related marks belong to Nintendo. This project is
neither affiliated with nor endorsed by Nintendo, and ships none of their code,
keys or assets.
