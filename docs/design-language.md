# Kaji Design Language

Kaji is a native utility. The UI should feel calm beside Wi-Fi, battery, and
other system status items.

## Direction

```text
paper-first utility + graphite data + restrained blue
playful utility + warm paper + muted orange
```

The old bright orange made the product feel louder than its job. Kaji now has
three deliberate visual modes: **Mono** as the default product face,
**Calm** as the restrained blue alternate, and **Playful** as the warmer orange
alternate.

## Palette

| Token | Calm Light | Calm Dark | Role |
| --- | --- | --- | --- |
| Background | `#F7F9FA` | `#111416` | App ground |
| Surface | `#FEFFFF` | `#1D2226` | Popover and controls |
| Text | `#22262A` | `#EEF2F4` | Primary labels and values |
| Secondary | `#69727A` | `#98A2AA` | Captions and metadata |
| Track | `#E3E8EB` | `#30383F` | Ring background |
| Value | `#607D96` | `#8FA9BA` | Normal quota arc |
| Warning | `#426C8B` | `#5F86A2` | Near-limit arc |
| Accent | `#5C86A3` | `#7EA3BB` | Identity dot and Calm controls |

| Token | Playful Light | Playful Dark | Role |
| --- | --- | --- | --- |
| Background | `#FAF7F2` | `#151311` | App ground |
| Surface | `#FFFDF8` | `#242019` | Popover and controls |
| Text | `#28231F` | `#F0ECE5` | Primary labels and values |
| Secondary | `#756B61` | `#A2998F` | Captions and metadata |
| Track | `#E8DFD3` | `#393229` | Ring background |
| Value | `#B87343` | `#D08A55` | Normal quota arc |
| Warning | `#D46F37` | `#D46F37` | Near-limit arc |

| Token | Mono Light | Mono Dark | Role |
| --- | --- | --- | --- |
| Background | `#F8F8F6` | `#121212` | App ground |
| Surface | `#FFFFFF` | `#202020` | Popover and controls |
| Text | `#20201D` | `#F0F0EC` | Primary labels and values |
| Secondary | `#70706A` | `#A0A09A` | Captions and metadata |
| Track | `#E5E5E1` | `#333330` | Ring background |
| Value | `#666660` | `#D2D2CC` | Normal quota arc |
| Warning | `#3D3D39` | `#F0F0EC` | Near-limit arc |

## Rules

- Default to Mono in the product and screenshots.
- Use restrained blue for normal quota data in Calm.
- Keep warning states inside the current mode's hue family.
- Use muted orange only in Playful.
- Keep Mono strict black/white/gray.
- Keep tracks neutral. Never tint the entire gauge orange/copper.
- Calm and Playful are opt-in.
- Use stronger warning color only for real threshold pressure.
- Avoid decorative gradients, glow, bokeh, or bright orange marketing accents.
- Keep surfaces native-adjacent: small radius, quiet contrast, dense but readable.

## Reference Direction

- Mobbin / Pinterest mood: native utility, low-saturation, restrained surfaces.
- macOS desktop widget mood: glanceable cards, light-first surfaces, one clear
  data story per component.
- Raycast / Linear mood: calm dark surfaces, sharp hierarchy, minimal accent use.

Kaji should not look like a dashboard. It should look like a trustworthy signal.
