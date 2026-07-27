# Asset Notes

## App icon

`Resources/AppIcon-1024.png` is an original image generated specifically for
Codex Pulse on 2026-07-27 with OpenAI image generation. It does not use an
Apple SF Symbol, OpenAI logo, Codex logo, or another third-party brand mark.

The production `Resources/AppIcon.icns` is derived from that PNG using
`Scripts/build_icns.swift`.

Generation brief:

> An original macOS app icon for a local developer dashboard, using three
> asymmetric flowing pulse arcs and a cluster of data dots, with a midnight
> navy, mint, and cyan palette; no text, logos, Apple system icons, OpenAI
> knot, or copied gauge symbol.

These project-specific icon assets are distributed with the source under the
same MIT License.

## README hero

`Assets/codex-pulse-hero.png` is a 2400 × 1200 sRGB PNG rendered at 2×
resolution from the project's real SwiftUI and WidgetKit views. It uses a
fixed synthetic snapshot with `DEMO` plan data, generic task titles, and no
user account information.

Regenerate it from the repository root with:

```bash
bash Scripts/render_readme_hero.sh
```

The renderer reuses the original app icon and the same widget components that
ship in the extension. It does not upscale a screenshot or contain captured
user data.

## Social preview

`Assets/codex-pulse-social-preview.png` is a 1280 × 640 sRGB PNG for the
repository's GitHub social media preview. It uses a solid dark background for
predictable rendering across platforms and stays below GitHub's 1 MB upload
limit.

Regenerate it from the repository root with:

```bash
bash Scripts/render_social_preview.sh
```

The social preview uses the same original app icon, real SwiftUI widget
components, and fixed synthetic `DEMO` snapshot as the README hero. It does
not contain captured user data.

## Interface icons

Runtime interface icons use Apple's SF Symbols through system APIs and are not
redistributed as standalone image assets.
