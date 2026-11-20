---
name: Hone
description: A quiet graphite instrument for prompts and selected text, native to macOS.
colors:
  accent: "#5D63E8"
  on-accent: "#FFFFFF"
  ground: "#F4F5F9"
  ground-dark: "#1F1F23"
  ground-alt: "#ECEEF4"
  ground-alt-dark: "#26262B"
  field-fill: "#FFFFFF"
  field-fill-dark: "#2E2E34"
  input-fill: "#F1F2F6"
  input-fill-dark: "#27272C"
  track: "#D9DCE5"
  track-dark: "#3A3A41"
  hairline: "rgba(0, 0, 0, 0.09)"
  hairline-dark: "rgba(255, 255, 255, 0.09)"
  muted: "rgba(0, 0, 0, 0.63)"
  muted-dark: "rgba(255, 255, 255, 0.63)"
  dot: "#7C89F5"
  dot-dark: "#8997FC"
  sunrise-dawn: "#D6E4F6"
  sunrise-dawn-dark: "#EEF1F7"
  sunrise-sky: "#C5E3FB"
  sunrise-blue: "#86C3F9"
  sunrise-gold: "#F6D35A"
  sunrise-amber: "#F4B04F"
  sunrise-ember: "#F08C4B"
typography:
  title:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
    fontFeature: "tnum"
  headline:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 700
  body:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  body-mono:
    fontFamily: "SF Mono, ui-monospace, Menlo, monospace"
    fontSize: "13px"
    fontWeight: 400
  callout:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 400
rounded:
  handle: "3px"
  value-box: "9px"
  field: "12px"
  pill: "9999px"
spacing:
  hair: "6px"
  tight: "8px"
  snug: "10px"
  base: "12px"
  well: "14px"
  pane: "16px"
  rule: "18px"
  pane-wide: "20px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
  button-quiet:
    textColor: "{colors.muted}"
  field-result:
    backgroundColor: "{colors.field-fill}"
    rounded: "{rounded.field}"
    padding: "{spacing.well}"
  field-input:
    backgroundColor: "{colors.input-fill}"
    rounded: "{rounded.field}"
    padding: "{spacing.tight}"
  score-value:
    backgroundColor: "{colors.field-fill}"
    typography: "{typography.title}"
    rounded: "{rounded.value-box}"
    padding: "4px 10px"
  score-track:
    backgroundColor: "{colors.track}"
    rounded: "{rounded.pill}"
    height: "20px"
  score-track-compact:
    backgroundColor: "{colors.track}"
    rounded: "{rounded.pill}"
    height: "12px"
  score-handle:
    backgroundColor: "{colors.on-accent}"
    rounded: "{rounded.handle}"
    width: "7px"
---

# Design System: Hone

## Overview

**Creative North Star: "The Graphite Dial"**

Hone is a quiet instrument for text, its look adopted from Dial (the owner's binding reference, 2026-11-20). The work reads as calm, hairline-ruled sections on cool graphite grounds (mist in light mode), and the result is always the brightest thing on screen. Everything the user operates is a standard macOS control: native sidebar, menus, segmented pickers, toggles, grouped Forms, system buttons. The world lends only palette, density, the label-left/value-right row, and one signature move.

That signature is the ScoreMeter: the prompt's score drawn as Dial's sunrise-gradient track, holding the "before" score dimmed while the model works, then sweeping up to the "after" value with a tick left at the starting point. It is the one place colour gets warm and the one place motion is long.

Depth is tonal, not lifted: grounds, wells and the result step up in brightness, separated by hairlines. Appearance follows the system light/dark setting, and every token below has a dark sibling.

**Key Characteristics:**
- Cool graphite / mist grounds, two neutral layers (input side and output side).
- Text wells with gently curved continuous corners and a hairline border; the result well is the brightest surface.
- Hairline rules between sections; muted labels on the left, values and controls on the right.
- One periwinkle accent for selection and the single primary action per area.
- Native macOS controls and navigation throughout.
- ScoreMeter: the sunrise gradient across 0–100, the only warm colour in the app.

## Colors

Cool, low-chroma graphite neutrals around one deep periwinkle accent, with a warm sunrise reserved for the score.

### Primary
- **Deep Periwinkle** (accent): the AccentColor asset, identical in both appearances and set as `NSAccentColorName`. It fills the one `.borderedProminent` button per area (Improve prompt / Run, Copy, Replace), the history selection, and selected-state tints. White label text on it passes WCAG AA.

### Secondary
- **Periwinkle Marker** (dot / dot-dark): list bullets in the report sections and the brand dot beside "Hone" in the quick panel header. Decorative only.

### Tertiary
- **Sunrise** (sunrise-dawn through sunrise-ember): six stops at 0, 0.22, 0.42, 0.64, 0.82 and 1.0 across the score track, so a higher score reaches warmer light. The dawn stop has a lighter dark-mode sibling; the rest are fixed.

### Neutral
- **Mist / Graphite Ground** (ground / ground-dark): input pane, quick panel and Settings; it also runs up under the transparent toolbar over the detail column.
- **Second Ground** (ground-alt / ground-alt-dark): the output pane, one step darker than the input side so the two halves read as distinct.
- **Result Well** (field-fill / field-fill-dark): the result text well and the score value box; the brightest surface on screen.
- **Input Well** (input-fill / input-fill-dark): the editor well, one step quieter than results.
- **Track** (track / track-dark): the unfilled part of the score track.
- **Hairline** (primary at 9%): well borders, track outline, value-box border.
- **Muted** (primary at 74%; primary is labelColor at 85%, so about 63% effective, near #5B5B5B on mist and #ACACAC on graphite): all secondary text: row labels, captions, character counts, provider names, quiet buttons, placeholders.

### Named Rules
**The Brightest Well Rule.** The result well is the brightest surface on any screen. Input wells take the quieter input fill; grounds sit below both.

**The One Accent, One Action Rule.** The accent appears on selection and on exactly one `.borderedProminent` action per area. Every other action is bordered or a quiet borderless text button in muted.

**The Marker Is Never Text Rule.** Periwinkle markers decorate; they never carry words.

**The One Sunrise Rule.** The sunrise gradient appears only in the ScoreMeter.

## Typography

**Body Font:** SF Pro (system font, macOS text styles)
**Mono Font:** SF Mono, for prompt text in the editor and the improved-prompt well

**Character:** The system face at native macOS sizes, with no display type. Hierarchy comes from weight and from muted versus primary colour, not from size.

### Hierarchy
- **Title** (semibold, 15px / `.title3`, tabular digits): the score value in the main window's value box. The compact meter in the quick panel uses semibold body.
- **Headline** (bold, 13px / `.headline`): section titles: Score, Improved prompt, Refine, Diagnosis, Questions, and "Hone" in the panel header.
- **Body** (regular, 13px): result and input text, history titles (medium weight). Result text adds 3px of line spacing.
- **Body Mono** (regular, 13px; callout size in the panel): prompt drafts and improved prompts. Plain text actions stay in proportional body.
- **Callout** (regular, 12px): the score delta ("from 12, +68", tabular), hints, panel source text.
- **Label** (regular, 10px / `.caption`): metadata in muted: character count, provider name, history scores and times, Settings footnotes.

### Named Rules
**The Muted, Not Secondary Rule.** Secondary text uses muted (primary at 74%, about 5.8:1 or better on every ground), never the system `.secondary` (about 4:1).

**The Drawn Placeholder Rule.** Text-field hints are drawn by `placeholder(_:when:)` in muted over an empty field, because the macOS placeholder grey fails AA and cannot be styled.

**The Red Icon Rule.** Errors put red on the warning icon only; message text stays in the primary colour.

## Layout

A three-column native split: the history sidebar (200–240px), the input pane (minimum 340px, ideal 420px) on ground, and the output pane (minimum 400px) on the second ground. The main window opens at least 1000 × 640. The toolbar background is hidden: the ground extends under the transparent toolbar over the detail column only, so the toolbar band matches the panes and the native sidebar runs full height. The quick panel is a fixed 560px column; Settings is 600 × 520 in grouped Forms.

The input pane stacks in three bands divided by full-width dividers: the editor (action menu, count, Paste, then the input well filling the height), the option rows (Goal, Target, Depth, Techniques), and a footer with the provider name on the left and the primary action on the right. Panes pad 16px (input) and 20px (output); the quick panel pads 14px.

Inside the output pane, sections are separated by SectionRule, a divider with 18px above and below. Within sections, spacing steps 6, 8, 10 and 12px. Option rows put a muted label on the left and the value or control on the right, aligned on the first text baseline, with at least 12px between them.

Footers follow Dial: quiet text actions on the left (18px apart in the quick panel), the real choices on the right, the primary action last.

## Elevation & Depth

Hone is flat. Depth comes from tonal layering (ground, second ground, input well, result well) and 1px hairlines, never from drop shadows. Native window chrome, popovers and menus keep their system shadows.

### Shadow Vocabulary
- **Handle lift** (`0 0.5px 1.5px rgba(0,0,0,0.25)`): only on the ScoreMeter's white handle, so it reads as sitting on the track.

### Named Rules
**The Hairline Rule.** Wells and tracks are separated by a 9% hairline and a tone step. If a surface needs to stand out, make it brighter, not raised.

## Shapes

Gently curved continuous corners on text wells (12px), a slightly tighter curve on the score value box (9px), and full capsules for the score track and the Techniques chips. The handle is a narrow 7px bar with 3px corners. Native controls keep their system shapes. Every custom shape is a continuous (squircle) rounded rectangle.

## Components

### Buttons
Native macOS buttons only; the world restyles none of them.
- **Primary:** `.borderedProminent` in the accent, one per area. The main window's Run button is `.controlSize(.large)` with an SF Symbol; Copy and Replace carry symbols that swap with a symbol-replace transition on success.
- **Secondary:** `.bordered` (Paste, quick-panel action grid, Copy beside Replace, the custom-action icon picker).
- **Quiet:** `.borderless` in muted for navigational or optional actions (Use as input, Actions, Open in App); `.link` small for "Clear" in Techniques.
- **Keyboard:** primary actions carry their shortcuts (⌘↩ to run, ⇧⌘C to copy, Return to replace).

### Chips
- **Techniques:** native button-style toggles, small, capsule-bordered, each with an SF Symbol and its instruction as a tooltip, in a flowing wrap layout (6px gaps). The system draws the on state.

### Cards / Containers
- **Text wells:** the `field` modifier: field-radius continuous corners, result fill by default (input fill for the editor), hairline border, 14px padding for results and 8–10px for inputs. No shadow.

### Inputs / Fields
- **Single-line fields:** native `.roundedBorder` text fields with drawn placeholders.
- **Editor:** a TextEditor inside an input well, monospaced for prompts.
- **Pickers:** native menu picker for Target, segmented picker for Depth, radio group in Settings.

### Navigation
- **Main window:** native `NavigationSplitView` with a History sidebar list; selection in the accent with white text; rows show a medium-weight title over a muted caption line (score "12→80" and relative time).
- **Settings:** native tabs and grouped Forms on the ground colour.
- **Quick panel:** a header row (periwinkle dot, "Hone", provider name in muted), the source text, a hairline, then a three-column action grid with numeric shortcuts, or the result and a Dial footer.

### OptionRow
The Dial row: a muted label on the left, a spacer of at least 12px, and the value or control on the right, aligned on the first baseline. Use it for every label/value pair outside grouped Forms.

### ScoreMeter (signature)
The prompt score as Dial's sunrise track.
- **Header:** "Score" (headline in the window, muted body in the compact panel variant), a progress spinner while running, the muted delta "from B, +N" in tabular callout, then the value in a hairlined result-fill box (9px corners).
- **Track:** a capsule in the track colour (20px tall, 12px compact) with a hairline outline. Small dots (4px, muted at 40%) mark each tenth of the unfilled part. The sunrise gradient spans the full width and is masked to the score, so colour reflects absolute position.
- **States:** while running, the fill holds the before score at 45% opacity; when the after score lands, the fill sweeps to it at full opacity and a 2px dark tick (black at 32%) marks the before position. A 7px white handle with corners of 3px stands 6px taller than the track at the fill edge.
- **Motion:** the sweep is a 0.7s smooth animation, and the value uses a numeric-text transition. Both are dropped under Reduce Motion.
- **Accessibility:** one element, labelled "Prompt score", valued "80 out of 100, up from 12" (or "Pending").

### Motion
Layout changes (sections appearing in the output) use a 0.22s smooth animation through the `motion(_:)` modifier, keyed on section presence so streamed text never animates chunk by chunk. All animation is removed when Reduce Motion is on.

## Do's and Don'ts

### Do:
- **Do** use native macOS controls and navigation for everything the user operates.
- **Do** give each area exactly one `.borderedProminent` accent action; make the rest bordered or quiet borderless text in muted.
- **Do** put results in the brightest well (field-fill) and inputs in the quieter input-fill well, both with 12px continuous corners and a hairline.
- **Do** separate sections with a hairline divider and 18px of space on each side.
- **Do** lay out label/value pairs as OptionRows: muted label left, control right.
- **Do** use muted (primary at 74%) for every secondary text, and draw placeholders with `placeholder(_:when:)`.
- **Do** define every new colour as a light/dark pair.
- **Do** route animation through `motion(_:)` or check Reduce Motion directly.

### Don't:
- **Don't** use system `.secondary` or `.tertiary` for text; it fails WCAG AA here.
- **Don't** use the sunrise gradient anywhere but the ScoreMeter.
- **Don't** add drop shadows to surfaces; the handle lift is the only one.
- **Don't** set text in periwinkle marker colour or in red.
- **Don't** add a second accent colour or a second prominent button in the same area.
- **Don't** replace native controls with custom-drawn buttons, toggles or tabs.
