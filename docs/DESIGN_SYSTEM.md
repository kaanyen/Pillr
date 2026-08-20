# Pillr Design System — Hellotime

> Monochrome editorial command center

Applied on branch `ui/hellotime-overhaul`. This is the reference for anyone
adding UI to Pillr.

## The one-paragraph version

White canvas, near-black type, hairline borders, no shadows. Hierarchy comes
from **type weight and size**, not from color. There is exactly one filled
button per section (Charcoal), exactly one gradient (Electric Blue, on
headline keywords only), and state is communicated through fill/border/weight
plus an icon — never through hue.

## Tokens

All tokens live in `lib/core/theme/`. Never hardcode a color, size or radius.

### Color — `app_colors.dart`

| Token | Hex | Use |
|---|---|---|
| `AppColors.ink` | `#151619` | Primary text, icons, strong hairlines |
| `AppColors.smoke` | `#7F8491` | Secondary text, metadata, placeholders |
| `AppColors.fog` | `#C8CAD0` | **The default hairline** — card borders, dividers |
| `AppColors.ash` | `#E1E2E5` | Input borders at rest, section dividers |
| `AppColors.mist` | `#F3F3F5` | Card surfaces, hover wash, active nav rows |
| `AppColors.paper` | `#FFFFFF` | Page canvas, nav background |
| `AppColors.charcoal` | `#25272D` | **The only dark surface** — primary actions |
| `AppColors.graphite` | `#363940` | Nav link text |
| `AppColors.pewter` | `#B0B3BB` | Ghost button borders, disabled fills |
| `AppColors.signalGreen` | `#059669` | Identity marks only (logo, tenant avatar) |
| `AppColors.electricBlue` | gradient | Headline keyword highlight **only** |

### Type — `app_typography.dart`

Two optical sizes of Inter, **bundled locally** in `assets/fonts/` (subset to
Latin + currency, incl. ₵). There is no runtime font fetch.

- `InterDisplay` → headlines, 24px and up (`AppTypography.displayFamily`)
- `Inter` → body, labels, buttons, table cells (`AppTypography.textFamily`)

| Style | Size / weight | Use |
|---|---|---|
| `displayLg` | 80 / 700 / -1.6 | Hero. One per screen at most |
| `display` | 64 / 700 / -1.2 | Primary screen headline |
| `headingXl` | 48 / 600 / -0.8 | Section title |
| `headingLg` | 40 / 600 / -0.4 | Subsection, dense-screen hero |
| `heading` | 24 / 600 | **Ceiling for dense screens** |
| `headingSm` | 20 / 600 | Card and dialog titles |
| `subheading` | 18 / 400 | Hero subtext (Smoke) |
| `body` | 16 / 400 / 1.5 | The default rhythm |
| `caption` | 14 / 400 | Helper text |
| `label` | 14 / 500 | Metadata, nav links, buttons |
| `tableCell` | 14 / 400 / 1.2 | Table rows — the one tightened leading |
| `pill` | 12 / 500 | Tags, badges, eyebrows |

**Responsive display type.** The 64–80px scale is a desktop instrument. Use the
`…For(width)` helpers so it steps down on phones:

```dart
final width = MediaQuery.sizeOf(context).width;
Text(title, style: AppTypography.displayFor(width));  // 64 → 40 → 30
```

### Spacing & radius — `app_spacing.dart`

8px base. `xs:4 · sm:8 · md:16 · lg:24 · xl:32 · xxl:40 · xxxl:48 · section:64 · sectionLg:80`

Radii — **16px is the ceiling**:
`bar:4` (progress) · `button:8` · `input:12` · `card:16` · `full:9999` (pills)

## Density: two registers

This is the one place Pillr deliberately adapts the reference. Hellotime is a
marketing language; Pillr is a data app. So:

**Editorial** — dashboards, auth, onboarding, empty/error states, success
screens. Full display scale (40–80px), gradient keyword, 64–80px section gaps.

```dart
PillrPageHeader.editorial(
  title: 'Welcome back, ',
  highlight: firstName,      // the gradient word
  subtitle: 'Live counts from partnership entries.',
)
```

**Dense** — entries, partners, users, arms, periods, goals, logs, search, bulk
import. Titles capped at 24–40px with a hairline rule beneath, table text at
14/400/1.2 so rows stay above the fold.

```dart
PillrPageHeader.dense(title: 'Entries', actions: [PillrButton(...)])
```

## Rules

### Do

- Use `AppColors.fog` hairlines and `AppColors.mist` surface contrast for separation
- One `PillrButtonVariant.primary` (Charcoal) per section; everything else `secondary`
- Gradient on **1–2 words** inside a headline, via `PillrGradientHeadline`
- Table headers in sentence case at 14/500 Smoke
- 32px card padding, 64–80px between sections

### Don't

- **No shadows.** `AppTheme.cardShadow` is deprecated and returns an empty list
- **No blue fills.** The gradient is text-only — never a button, card or surface
- **No color for state.** Use `PillrBadge` / `PillrStatusStyle`
- **No radius above 16px**
- **No weight above 700** — only 400/500/600/700 are bundled; anything else synthesizes
- **No centered body paragraphs** — center headlines, CTAs and short labels only
- **No uppercase letterspaced labels** — this system is weight-driven

## State without color

`PillrStatusStyle` replaces the old amber/green/red badges. Also better for
colorblind users, since the icon carries what hue used to.

| State | Fill | Border | Text | Icon | Reads as |
|---|---|---|---|---|---|
| Approved | Charcoal | — | Paper | `check` | Settled, final |
| Pending | Mist | Fog | Ink | `clock` | In progress |
| Declined | — | Pewter | Smoke | `x` | Closed |
| Inactive | — | Ash | Smoke | `circleDashed` | Ambient |

```dart
PillrBadge.fromStatus(status: entry.status, label: 'Pending')
```

Errors follow the same logic: Ink text at weight 500, not red.

## Tenant branding

Churches set `primaryColorHex`. It is confined to **identity marks** — the
church avatar and logo lockup — and never touches actions, state, borders or
surfaces. It no longer seeds the `ColorScheme`.

```dart
final accent = AppTheme.tenantAccent(parseHexColor(settings?.primaryColorHex));
```

Falls back to Signal Green, the reference's own brand-mark accent.

## Where saturation is still allowed

Exactly one place: `AppColors.timelineBar(index)` for product-timeline and
multi-series chart bars, mirroring the reference's Gantt bars. Everything else
on the page stays neutral. Note that **status breakdowns are not this** — those
use a tonal ramp (Ink → Smoke → Ash).

## Components

`lib/common/widgets/`

| Widget | Notes |
|---|---|
| `PillrCard` / `PillrSurfaceCard` / `PillrInverseCard` | Paper / clipped / Charcoal |
| `PillrButton` | `primary` `secondary` `danger` `ghost` — danger is also Ink |
| `PillrPillLink` | The eyebrow pill above hero headlines |
| `PillrGradientHeadline` | The keyword highlight |
| `PillrBadge` / `PillrCountBadge` | Monochrome state |
| `PillrPageHeader` | `.editorial()` and `.dense()` |
| `PillrSectionHeader` | Block divider inside a screen |
| `PillrStatCard` | `emphasized: true` inverts one tile per row |
| `PillrDataTable` | Mist header band, hairline rows |
| `PillrEmptyState` / `PillrErrorState` | Editorial treatment |
