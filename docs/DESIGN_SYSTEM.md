# Pillr Design System — Seline

> Quiet analyst's desk on warm paper

Implemented on branch `ui/seline-rewrite`. This is the reference for anyone
adding UI to Pillr. The previous Hellotime system was removed entirely — if you
find `AppColors`, `AppTypography` or a `Pillr*` widget anywhere, it is dead code.

## The one-paragraph version

The page is **warm stone** (`#fafaf9`); cards are **white** and float on it with
a soft shadow. Every neutral is warm-tinted, and there is exactly **one
chromatic colour** — a cyan reserved for actions and links. Display type is Inter
Tight at **weight 400**, even at 52px: authority comes from size and negative
tracking, not from boldness. Buttons are pills; cards are 10px. Body is
**14px / 400 / 1.64**, and that rhythm dominates the whole interface.

## Import

```dart
import 'package:the_pillr/design/seline.dart';
```

One barrel gives you tokens and components. Never hardcode a colour, size or
radius.

## Tokens

### Colour — `Sel`

| Token | Hex | Use |
|---|---|---|
| `Sel.canvas` | `#FAFAF9` | **The page.** Warm, reads as paper |
| `Sel.card` | `#FFFFFF` | Card surfaces, inputs, nav fills |
| `Sel.border` | `#E8E6E5` | **The default hairline** — the primary structural device |
| `Sel.borderMuted` | `#D6D3D1` | Input borders, secondary separators |
| `Sel.ash` | `#A8A29E` | Icon strokes, disabled, captions |
| `Sel.warm` | `#78716C` | Body text, nav links, metadata |
| `Sel.ink` | `#0C0A09` | Headings, emphasised body |
| `Sel.soot` | `#1C1917` | Inverted surfaces, active pills |
| `Sel.cyan` | `#3BA6F1` | **The only fill colour.** Primary CTA |
| `Sel.cyanEdge` | `#3398E1` | Outlined actions, links. Never a fill |
| `Sel.skyWash` | `#C1E1F7` | Highlight-span background |

### Colour — semantic state

Seline's own reference spends its whole budget on one cyan. That holds for a
marketing page; it does not hold for a product whose core loop is approve /
send back / blocked. A row someone must *fix* has to separate from one they can
ignore — and on bulk import, where every row is a state, monochrome failed
outright.

So state gets colour, warm and desaturated so it sits with the stone rather
than shouting off it. None of these is a fill for an action, so the cyan button
is still the loudest thing on any screen.

| Token | Hex | State |
|---|---|---|
| `Sel.success` | `#4D7C5F` | moss — settled, correct |
| `Sel.warning` | `#B8862B` | ochre — waiting on you |
| `Sel.danger` | `#A8453A` | clay — failed, blocked |
| `Sel.info` | `#3398E1` | cyan edge — neutral notice |

Each has a `…Wash` companion for chip backgrounds (`successWash`, etc.).

### Colour — partnership arms

Arms are the one genuinely categorical dimension: a handful per church, stable,
appearing across ledgers, goals and charts. Each gets a swatch from
`Sel.armPalette`, **assigned by `sortOrder`** via `armColorsProvider`.

Use `ArmLabel` / `ArmDot` from `lib/screens/arm_palette.dart` — never colour an
arm by hand. Hashing the arm id was the first attempt and it collided: with
four arms drawing from eight swatches, two pairs landed on the same hue and the
dots stopped distinguishing anything.

A church that sets its own `colorHex` on an arm keeps that colour; the palette
only fills the gaps.

### Colour — money direction

`SelCell.numeric(text, tone: …)` tints a figure by meaning: `SelTone.positive`
for amounts that counted toward totals, `negative` for rejected or reversed,
`neutral` (the default) for counts, targets and dates.

**The rules that get broken:** the page is canvas and cards are white — never
inverted. Cyan is for **actions**; the semantic set is for **state**; neither
borrows the other's job.

### Type — `SelType`

Two families, bundled locally (no CDN fetch).

- `InterTight` → display, 18px and up, **always weight 400**
- `Inter` → body, labels, buttons, ledger cells

| Style | Size / weight | Use |
|---|---|---|
| `hero` | 52 / 400 / -1.09 | Overview only |
| `title` | 32 / 400 / -0.8 | Screen titles |
| `subtitle` | 20 / 400 / -0.1 | Card and panel titles |
| `lead` | 16 / 400 / 1.69 | Prose, hero subtext |
| `body` | **14 / 400 / 1.64** | **The dominant rhythm** |
| `bodyMedium` | 14 / 500 | Names, active nav, emphasis |
| `bodyMuted` | 14 / 400 warm | Secondary copy |
| `small` | 12 / 400 | Helper text, timestamps |
| `tag` | 12 / 500 | Chips |
| `caption` | 10 / 500 caps | Ledger column captions — the *one* place caps are correct |

Use the responsive helpers so 52px does not become four words per line:

```dart
Text(title, style: SelType.heroFor(MediaQuery.sizeOf(context).width));
```

### Spacing & shape

4px base: `x1:4 · x2:8 · x3:12 · x4:16 · x6:24 · x8:32 · x12:48 · x16:64`, plus
`section: 96`. Compact controls, generous section rhythm — that contrast is what
makes it editorial rather than merely dense.

Radii: `icon:4 · input:6 · card:10 · feature:16 · pill:9999`. Buttons and tags
are fully round; cards stay at 10. Do not "harmonise" them.

### Elevation — `SelShadow`

Unusually for a flat-looking system, shadows are used — softly, with a strict
hierarchy. `SelShadow.card` is the everyday lift. `SelShadow.floating` (the deep
45px blur) is **one element per screen at most** — currently only the entry
detail record card.

## Layout: the bare canvas rail

The shell is two columns on one continuous sheet of paper. The nav rail has **no
fill, no border, no divider and no panel** — links sit directly on the canvas
like margin notes. The active link is the exception: it gets a white card, so
the selected destination reads as continuous with the content beside it.

Utility controls (search, notifications, account) float top-right *on the
canvas*, not in a bar. `SelPageBody` reserves 72px of headroom for them.

Below 900px the rail is replaced by a bottom bar — the only place navigation
uses a surface.

## Information architecture

Twelve destinations were consolidated into seven:

| Destination | Absorbed |
|---|---|
| **Overview** | four role dashboards, now one screen composing blocks by role |
| **Queue** | Entries + Approvals, one list with a status filter and inline review |
| **Partners** | + Leaderboard, as a ranked view of the same records |
| **Goals** | — |
| **Configuration** | Arms + Periods |
| **People** | Users + Invitations |
| **Activity** | — |

Every old path is kept as a router redirect, pre-filtered where the old path
implied one (`/approvals` → `/queue?filter=pending`).

## Components

`lib/design/components/`

| Component | Notes |
|---|---|
| `SelButton` | `cyan` `ghost` `quiet` `edge`. **One cyan per viewport.** |
| `SelCard` / `SelPanel` / `SelInverseCard` | `SelLift.flat / card / floating` |
| `SelLedger` | Replaces every data table. `SelColumn`, `SelRow`, `SelCell` |
| `SelStatusMark` / `SelStatusChip` | Monochrome state |
| `SelHighlight` | The sky-wash span. **One per screen.** |
| `SelStat` / `SelStatRow` / `SelGoalLine` | Figures |
| `SelField` / `SelSelect` / `SelPillGroup` | Inputs |
| `SelPageBody` / `SelPageTitle` / `SelSectionLabel` | Page scaffolding |
| `SelEmpty` / `SelError` / `SelSkeleton` | States |
| `SelDialog` / `selConfirm` | Modals |

## State

| State | Icon | Colour | Weight |
|---|---|---|---|
| Approved / Accepted / Active | `check` / `circleDot` | Moss | 500 |
| Pending | `clock` | Ochre | 400 |
| Declined / Expired | `x` | Clay | 400 |
| Blocked | `alertTriangle` | Clay | 500 |
| Inactive | `minus` | Ash | 400 |
| Info | `info` | Cyan edge | 400 |

The glyph still carries the meaning and the set stays legible in greyscale —
the palette is deliberately low-chroma — so this remains colourblind-safe. The
colour is there to make a column scannable, not to be the only signal.

Destructive confirmations still put the cyan on the *safe* choice and make the
destructive one a ghost.

## Do / Don't

**Do**
- Page is `Sel.canvas`; content lives in white `SelCard`s
- One `SelButton.cyan` per viewport; everything else ghost or quiet
- One `SelHighlight` per screen, on the value word
- Body at 14/400/1.64 — do not break the rhythm without reason
- Ledger captions in 10px caps; everything else sentence case

**Don't**
- No colours outside the tokens above — stone, one cyan, four semantic, the arm palette
- No semantic colour on an action, and no cyan on a state
- No display type above weight 500 — only 400/500 are bundled
- No `SelShadow.floating` on more than one element per screen
- No white page background
- No headline set in Inter — display is Inter Tight

## Tenant branding

Churches set `primaryColorHex`. It appears on the **identity mark only** — the
church avatar in the rail and on auth. It does not seed the `ColorScheme`.

```dart
final accent = SelTheme.tenantMark(parseHexColor(settings?.primaryColorHex));
```
