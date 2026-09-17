# Design notes

## Tokens (`AnteStyle`)

- **Accent** amber `#F5C56B`: the cursor colour of Ante Dark, reused for the focus ring and banner
  icon so there is exactly one "Ante" colour.
- **Surfaces** three near-black steps for dark (`#0B0D12` panes / `#0E1015` sidebar / `#0B0D12`
  toolbar) and three warm off-whites for light. Sidebar is one step lighter than panes in dark
  and one step darker in light — the same relationship in both.
- **Hairlines** at 8% white (dark) / 10% black (light). Dividers, unfocused pane rings.
- **Status dots** blue = command running, green = last command ok, red = last command failed,
  gray = exited. 7pt; legible without being a traffic light.
- **Type** SF 12.5 for rows, 10.5 semibold tracked caps for section labels, 11 mono for paths.
- **Rhythm** 28pt rows, 38pt toolbar, 10pt pane inset, 7pt radius.

## Patterns

- Sidebar sections with uppercase tracked labels and a per-section "+", the way a workspace
  app groups its projects.
- Unified top bar that starts beside the traffic lights, no separate title bar.
- No decoration: the terminal is the content, chrome is hairlines and one accent.

## Deliberately not done

- No second tab bar. The sidebar *is* the tab strip; ⌘1–9 and ⌘⇧[ ] move through it.
- No coloured project icons or avatars. Projects are labels; sessions are the unit.
- No solid overlay boxes. Exited / failed / banner states use material so the terminal shows through.

## Rule

The chrome follows the terminal theme's appearance, never the system's. A dark palette under
light chrome reads as two apps stitched together.
