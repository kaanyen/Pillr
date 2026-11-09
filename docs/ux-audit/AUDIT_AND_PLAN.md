# Pillr × Laws of UX — full audit and implementation plan

This document maps every law on [Laws of UX](https://lawsofux.com/) (Jon Yablonski) onto Pillr as it stands today: a Flutter web app for church partnership giving. The audience is a pastor or staff member who records gifts, reviews a queue, and reads totals. They are not designers. They are mid-task, often on a laptop, sometimes on a phone after service.

**Method.** Each law gets: what it says, how Pillr already uses it, where it fails, and a concrete fix. Findings come from the Seline design system (`lib/design/`) and the screens that spend the most time on screen — Overview, Queue, Records, Goals, Sign-in, and the rail / mobile bar.

**What we implement in this pass** is marked **P0**. Later work is **P1** / **P2**. Screenshots live in `docs/ux-audit/screenshots/before/` and `…/after/`. The side-by-side of what changed is `docs/ux-audit/WHAT_CHANGED.md`.

---

## Product facts that shape every recommendation

- One chromatic voice: cyan `#3BA6F1` for actions only. State is moss / ochre / clay.
- Controls were designed *compact on purpose*: default buttons are **34px**, dense **28px**, icon buttons **32px**, filter pills ~**28px**, rail rows ~**32px**.
- Custom buttons are `GestureDetector`s. They have hover. They do **not** have a keyboard focus ring.
- Caption / helper chrome uses `Sel.ash` `#A8A29E` on canvas `#FAFAF9` — about **2.4:1**. WCAG AA needs **4.5:1** for text and **3:1** for UI icons.
- Information architecture already did a lot of Hick’s / Tesler work: twelve destinations became seven; Entries and Approvals are one Queue; Records filters cap at two.

---

## The laws, one by one

### 1. Aesthetic-Usability Effect

Users judge a good-looking interface as more usable.

**Already good.** Warm paper canvas, one accent, whisper-weight display type, cards that float. The system reads as considered.

**Gap.** Beauty is carrying some of the usability. Ash captions, 28px pills, and invisible keyboard focus look refined and fail people with low vision or a keyboard. Aesthetic-usability does not excuse a 2.4:1 caption.

**Fix (P0).** Keep the language. Raise contrast and targets until the pretty version is also the usable one.

---

### 2. Choice Overload

Too many options freeze people.

**Already good.** Record filters: two at a time, options drawn from live data. Queue is one list with a status pill, not two apps. Tools never mutate on arrival.

**Gap.** Pastor mobile bar is **six** destinations (Overview, Queue, Records, Partners, Fellowships, Settings) even though the code says it “caps at five.” Settings is already on the account chip. Entry form asks for partner, arm, period, amount, date, notes, and sometimes currency in one column — fine for experts, heavy for a first Sunday.

**Fix (P0).** Drop Settings from the mobile bar (it lives under the account menu). **P1:** progressive disclosure on the entry form — required fields first, notes / FX behind “More.”

---

### 3. Chunking

Group bits into meaningful wholes.

**Already good.** Nav is titled clusters (Partnership / Church). Overview is greeting → stats → “Waiting on you” → goals → activity. Ledgers have a caption row, not a spreadsheet header band.

**Gap.** Queue toolbar can put title, status pills, New entry, Import, and export on one row. On a 1280px laptop that is one undifferentiated strip.

**Fix (P1).** Put status pills in their own labelled region (“Show”) so they are a chunk, not siblings of the primary CTA.

---

### 4. Cognitive Bias

Systematic errors in judgment.

**Already good.** Tools are scan → show → ask. Void/restore is explicit. Approval has a confirm. Empty queue says the queue is clear, not “no results.”

**Gap.** Compact money on Overview (`₵12.4k`) without a hover exact on every tile can bias a pastor toward the rounded story. Status colour on pending (ochre) is right; declined and voided must stay visually distinct so “set aside” is not read as “rejected.”

**Fix (P1).** Exact value tooltip on every abbreviated stat (already on some). Keep voided warm-gray, never clay.

---

### 5. Cognitive Load

Mental work required to use the UI.

**Already good.** Role-adaptive Overview. Cmd/Ctrl+K search. Queue keyboard cursor. Filters that cannot return empty option sets.

**Gap.** Working memory is spent on chrome: tiny targets, low-contrast captions, and controls that do not look focused. That is load that does not help the gift get recorded.

**Fix (P0).** 44px targets, 4.5:1 secondary text, visible focus. Those three remove load on every screen at once.

---

### 6. Doherty Threshold

Keep the loop under ~400ms or show that the system is working.

**Already good.** Button loading spinner. Ledger skeletons. Records infinite scroll. Offline strip.

**Gap.** Some pastor actions (approve, import commit) are network-bound and go quiet. A 34px spinner is easy to miss.

**Fix (P1).** Keep the row in a deciding state; do not blank the list. **P0** only ensures the loading control itself is a 44px target you can still see.

---

### 7. Fitts’s Law — **P0, primary**

Time to a target = f(distance, size).

**Measured today**

| Control | Height | Notes |
|---|---|---|
| `SelButton` | 34px (dense 28) | Primary “New entry”, Approve, Import |
| `SelIconButton` | 32px | Search, notifications |
| Status pills | ~28px | Queue All / Pending / Approved / Declined |
| Filter chips | ~32px | Records “Add filter” |
| Rail link | ~32px | Entire left nav |
| Text / popup items | 32–38px | Account menu, filter menus |
| Field (dense) | ~36px | Sign-in, entry form |
| Account chip | ~30px | Top-right, includes a 13px ash chevron |

Apple HIG and WCAG 2.5.5 point at **44×44**. These are the worst targets in the app, and several live in a horizontal rail — the same pattern Wave called out.

**Fix (P0).** Default tap target **44px**. Dense toolbar **36px** (never 28). Icon buttons 44. Pills 44. Fields 44. Rail rows 44. Popup items 44. Account chip 44.

---

### 8. Flow

Immersion when challenge and skill match.

**Already good.** Queue is a review flow with a cursor and inline approve. Import is a grid, not a wizard that dumps you out.

**Gap.** Breaking flow to hunt a 28px “Approve” or an unfocused field is how you fall out of flow.

**Fix (P0).** Fitts + focus. **P1:** keep bulk-approve playback on the same surface.

---

### 9. Goal-Gradient Effect — **P0**

People accelerate as they near a goal.

**Already good.** `SelGoalLine` shows a bar and a percent. Overview has a “Goal progress” stat.

**Gap.** The bar is **4px** — easy to miss. Copy is “₵12,400 of ₵20,000” with no “how much is left,” which is the number that makes the last stretch feel close.

**Fix (P0).** 8px track. Add “X% to go” under the figures when the goal is open.

---

### 10. Hick’s Law — **P0**

Decision time grows with number and complexity of choices.

**Already good.** One Overview. One Queue. Two filters max. One cyan button per viewport.

**Gap.** Six-item mobile bar. Pastor rail still offers Overview + Queue + Records (with three children) + Partners + Fellowships + Goals + People + Configuration + Help + Settings. That is a lot, but it is grouped. The mobile bar is not.

**Fix (P0).** Five mobile destinations. Settings stays in the account menu (Jakob — that is where people look).

---

### 11. Jakob’s Law

People expect your product to work like the others they already use.

**Already good.** Cmd+K. Sign-in with email/password and a footer link. Account chip top-right. Bottom bar on small screens. Pull-to-refresh.

**Gap.** Custom pills that are not focusable violate “buttons behave like buttons.” A 13px ash chevron on the account chip is a common pattern executed below the contrast other sites use.

**Fix (P0).** Real focus, 44px account chip, chevron at ≥3:1. Do not invent a new nav model.

---

### 12. Law of Common Region

Things that share a boundary are a group.

**Already good.** Cards vs canvas. Active rail item lifts onto a white card. Auth form is one card.

**Gap.** Queue status pills sit in the page header with the primary CTA — no shared boundary — so “Pending” can read as an action, not a filter.

**Fix (P1).** A hairline region around the pill group. Not this pass; pills themselves getting to 44px already helps.

---

### 13. Law of Proximity

Near things group.

**Already good.** Label 8px above the field (never floating). Stat label / number / footnote stacked. Goal name next to its bar.

**Gap.** Header actions and filters share the same 8px gap, so proximity cannot tell them apart.

**Fix (P1).** More space between “New entry” and the filter row than between the pills themselves.

---

### 14. Law of Prägnanz

People see the simplest shape.

**Already good.** Pills vs 10px cards. No illustration clutter. Empty state is a ringed glyph + one sentence.

**Gap.** None urgent. Do not add decorative charts to Overview.

---

### 15. Law of Similarity

Same look = same kind.

**Already good.** All primary actions are cyan pills. Ghost for secondary. Status chips share one vocabulary.

**Gap.** Quiet buttons, links, and filter chips can look like three kinds of the same thing. After 44px, keep quiet buttons text-only so they do not compete with pills.

---

### 16. Law of Uniform Connectedness

A visible connection beats proximity.

**Already good.** Ledger rows. Goal bar attached to its label. Records sub-nav indented under Records.

**Gap.** Pending preview rows on Overview do not show approve — you leave for the queue. Connection between “Waiting on you” and the work is a quiet text button.

**Fix (P1).** Keep “Open queue” but make the panel visually the ochre/waiting region (Von Restorff), not another white card identical to Activity.

---

### 17. Mental Model

People use a compressed story of how the system works.

**Already good.** Queue = things that need a decision. Records = the archive. Partners = people. Goals = targets for this period. Import draft persists (“An import is waiting”).

**Gap.** “Partnership entry” is product language. Staff think “I wrote down what was given.” The form title should keep saying that.

**Fix (P2).** Copy pass: “New entry” can stay; helper text should say “Record a gift,” not “Create a partnership entry.”

---

### 18. Miller’s Law

Working memory holds about 7±2 items.

**Already good.** Overview stats are four. Activity preview is six. Pending preview is four. Mobile bar *should* be five.

**Gap.** Six mobile items. Tools page lists several repairs in one column — acceptable because each card is a chunk.

**Fix (P0).** Five mobile items.

---

### 19. Occam’s Razor

Prefer the explanation / UI with fewer assumptions.

**Already good.** One shell, one queue, one design system.

**Gap.** Do not add a second button style to “solve” Fitts. Make the existing pill 44px.

---

### 20. Paradox of the Active User

Nobody reads the manual.

**Already good.** Help exists but the product tries to be usable without it. Empty states carry the next action.

**Fix (P2).** Do not add onboarding tours. Put the one sentence that matters on the empty queue and the first goal.

---

### 21. Pareto Principle

~80% of use comes from ~20% of the surface.

**The 20% in Pillr:** New entry, Approve (single and all), Queue filter, Records by month, partner search.

**Fix (P0).** Those controls get 44px, 4.5:1, and a focus ring first. Tools and Configuration can wait.

---

### 22. Parkinson’s Law

Work expands to fill the time.

**Already good.** Queue is “what still needs a decision,” not an endless archive. Decided rows leave after 24 hours.

**Gap.** None for this pass.

---

### 23. Peak-End Rule

People remember the peak and the end.

**Already good.** Entry success screen. Approval playback. Empty queue as good news.

**Gap.** A tiny, low-contrast “Approved” chip is a weak peak. After P0 targets, **P1** can give the success end a calmer, larger confirmation without a second accent colour.

---

### 24. Postel’s Law

Be liberal in what you accept, conservative in what you send.

**Already good.** Import resolver, title-case utilities, pesewa-aware money, void/restore rather than delete.

**Gap.** Sign-in email should trim and not fail on trailing space (it already trims). Amount fields should accept `1,200` and `1200`.

**Fix (P1).** Liberal amount parse on the entry form.

---

### 25. Selective Attention

People only see what matches their goal.

**Already good.** One cyan CTA. Pending badge on Queue. Unfinished import banner only when there is a draft.

**Gap.** Ash captions and 4px goal bars lose the race for attention. The thing you need to see (progress, “optional,” a chevron) disappears.

**Fix (P0).** Contrast and thicker progress.

---

### 26. Serial Position Effect

First and last items are remembered.

**Already good.** Overview is first. Help/Settings are last (footer). Queue is second for pastors — correct.

**Gap.** On mobile, Settings in the last slot is memorable but low-value compared with Queue. After dropping it, Fellowships is last; Queue stays second.

---

### 27. Tesler’s Law

Complexity cannot be destroyed, only moved.

**Already good.** Import complexity lives in the grid, not the pastor’s Sunday loop. Currency rates live in Configuration. Totals repair is scan-then-ask.

**Gap.** Do not “simplify” the queue by hiding Approve behind a menu. Keep the complexity on the row; make the target large enough to hit.

---

### 28. Von Restorff Effect (Isolation)

The different thing is the one you remember.

**Already good.** Cyan is the only fill. Active rail item is the only white card in the margin. Unfinished import is a banner.

**Gap.** “Waiting on you” is the same card as “Recent activity.” The isolation is only in the title.

**Fix (P0).** A quiet ochre edge or “needs you” mark on the pending panel — still stone, not a second brand colour.

---

### 29. Working Memory

Hold only what the task needs.

**Already good.** Partner snapshot on the row so you do not open the profile to approve. Amount + arm on one line.

**Gap.** Low-contrast metadata forces people to re-read. That is working-memory tax.

**Fix (P0).** Caption and chevron contrast.

---

### 30. Zeigarnik Effect — **P0**

Unfinished tasks stay in mind.

**Already good.** “An import is waiting.” Queue badge. Overview “Awaiting review” stat and pending preview. Goal bars.

**Gap.** The pending panel does not isolate. Goal bars do not say what is left. Together they under-use the effect: the open loop is there, but it does not *look* open.

**Fix (P0).** Isolate the pending panel. Spell out remaining goal progress.

---

## Contrast notes (measured)

Approximate WCAG contrast on `#FAFAF9` canvas / `#FFFFFF` card:

| Token | Hex | Role | Ratio (canvas) | AA text | AA UI (3:1) |
|---|---|---|---|---|---|
| `Sel.ink` | `#0C0A09` | Headings | ~19:1 | Pass | Pass |
| `Sel.warm` | `#78716C` | Body muted | ~4.6:1 | Pass | Pass |
| `Sel.ash` | `#A8A29E` | Captions, chevrons, unused nav icons | **~2.4:1** | **Fail** | **Fail** |
| `Sel.cyan` | `#3BA6F1` | Links / focus | ~2.6:1 on white | Fail as *text* | Border OK if 2px |

Wave’s write-up moved helper text from **2.38:1 → 4.5:1**. Pillr’s captions are the same class of bug.

**P0 rule.** Captions, chevrons, prefix icons, and inactive rail children use `Sel.warm` (4.6:1). `Sel.ash` stays for disabled and purely decorative strokes. Keyboard focus uses a **2px `Sel.ink` ring with a 2px offset**, not a 1px cyan tint — ink clears 3:1 as a UI component; a thin cyan tint does not.

---

## Implementation plan

### Phase 0 — this pass (system-wide, screenshottable)

Touch the design system so every screen inherits the fix. Do not restyle marketing. Do not add a new accent.

1. **Tokens** — `SelLayout.tapTarget = 44`, `tapTargetDense = 36`. Document the contrast rule on `Sel.ash`.
2. **Focus** — `FocusableActionDetector` on pills, icon buttons, links, tappable cards, rail links. 2px ink offset ring.
3. **Fitts** — buttons, pills, fields, icon buttons, rail, account chip, filter chips, popup items → 44 / 36.
4. **Contrast** — captions, chevrons, field icons, inactive subnav → `Sel.warm`.
5. **Hick / Miller** — mobile bar max 5; Settings via account menu.
6. **Goal-gradient** — 8px bar + “X% to go.”
7. **Zeigarnik / Von Restorff** — pending preview marked as the open loop.

### Phase 1 — next (screen-level)

- Entry form: required first, notes/FX behind More (Choice Overload, Hick).
- Queue: pill group in its own region (Common Region, Proximity).
- Liberal amount parse (Postel).
- Stronger approve / success end (Peak-End) without a second fill colour.
- Exact-value tooltips on every compact stat (Cognitive Bias).

### Phase 2 — later

- Copy: “Record a gift” mental model.
- No tours (Paradox of the Active User).
- Doherty: deciding-state on rows during approve.
- Help stays optional; empty states keep the one next action.

### Out of scope (on purpose)

- Dark mode.
- A second brand colour.
- Changing the editorial type (Inter Tight 400).
- Production data, Airport City, or any write outside the emulator.
- Redesigning Tools / Configuration in this pass.

### Verification

- Widget gallery screenshots: `docs/ux-audit/screenshots/before|after/`.
- `WHAT_CHANGED.md` in the Wave format: metric, law, before / after.
- `flutter analyze` clean, `flutter test` green.
- Semantics tests still pass (buttons remain named buttons).

### Risk

Raising 34 → 44 will make toolbars wrap earlier. That is acceptable: Fitts beats a single-line chrome. Dense 36px is the escape hatch for a row that already has a 44px primary.

---

## Priority matrix (P0 only)

| Change | Laws | Files |
|---|---|---|
| 44px targets | Fitts, Cognitive Load, Pareto | `sel_button.dart`, `sel_field.dart`, `seline_theme.dart`, `sel_rail.dart`, `sel_shell.dart`, `record_filter_bar.dart` |
| Ink focus ring | Jakob, Visibility / Selective Attention | `sel_button.dart`, `sel_field.dart`, `sel_card.dart`, `sel_rail.dart` |
| Caption / chevron 4.5:1 | Aesthetic-Usability, Working Memory | `seline_type.dart`, `seline_theme.dart`, `sel_field.dart`, `sel_rail.dart`, `record_filter_bar.dart` |
| 5-item mobile bar | Hick, Miller, Serial Position | `nav_model.dart` |
| Goal remaining + 8px bar | Goal-Gradient, Zeigarnik | `sel_stat.dart` |
| Pending panel isolation | Von Restorff, Zeigarnik, Uniform Connectedness | `overview_screen.dart` |

---

## Sources

- [Laws of UX](https://lawsofux.com/) and [llms.txt](https://lawsofux.com/llms.txt)
- [Fitts’s Law](https://lawsofux.com/fittss-law/), [Hick’s Law](https://lawsofux.com/hicks-law/), [Goal-Gradient Effect](https://lawsofux.com/goal-gradient-effect/)
- WCAG 2.2 — 1.4.3 Contrast (Minimum), 1.4.11 Non-text Contrast, 2.4.7 Focus Visible, 2.5.5 Target Size (Enhanced)
- Pillr design reference: `docs/DESIGN_SYSTEM.md`
