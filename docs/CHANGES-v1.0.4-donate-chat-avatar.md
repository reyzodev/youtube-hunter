# v1.0.4: Donate window + Hunter chat mark (UI pass)

## Donate window (components/DonateOverlay.qml)
- Wider: 1120 -> 1360 max (window margin 88 -> 64), height 920 -> 940.
- Wide layout (card >= 1100 px): a 300 px brand rail on the left (glossy accent
  tile with the beating heart, title, three perks, a "Secure checkout" card,
  version), and the page on the right. Under 1100 px the old single-column
  layout comes back automatically.
- Header becomes a browser bar in wide mode: full-width Safari-style address
  pill (lock + Secure + live host), nav pill, close.
- The page viewport now looks rounded (radiusLg): four static corner caps in
  the card colour + a rounded hairline. No mask, no layer, no extra cost.
- Lit top edge: accent -> white -> accent instead of plain white.
- The top accent wash now ends above the page frame so the corner caps match.
- Footer in wide mode: just the keycaps (security text moved to the rail).
- Weight: nothing new animates. The only motion added is the heart, and the
  header heart stops when the rail one runs.

## Hunter chat mark (components/HunterAvatar.qml, pages/AIChatPage.qml)
- New HunterAvatar (drop-in API: size / mode / breathe) replaces HunterSigil
  in the message header, the live answer, the empty-state hero and the drop zone.
  HunterSigil.qml is kept (unused) for easy rollback.
- Accent squircle tile (follows the user's accent, both themes), white crest
  with the play notch punched in accent, glass sheen, inner light edge.
- thinking: a comet of light orbits the rim + crest breathes.
  streaming: rim stays lit + a glint sweeps the glass. idle: zero animation.
- Header row: "Hunter" + a mono model chip (route prefix dimmed, status dot,
  pulses while live) + time. Avatar 28 -> 30 px; shared idle texture kept.

---

# v1.0.4 round 2

## AI Chat: Persian answers (pages/AIChatPage.qml)
- The header row of an answer follows the answer's language: a Persian answer
  puts it on the right, in the order mark -> "Hunter" -> model chip -> time.
  Decided by the first strong letter of the text (same rule Text uses for its
  alignment). The Copy / Regenerate row follows too. A live answer follows the
  question's language until its first token arrives.

## Donate window: the page's language switch (components/DonateOverlay.qml)
- The page's own ENG/FA circle (pinned against its "recent donations" box) is
  found by its label, hidden, and replaced by a language control in the card's
  header (translate icon + current label, next to Reload). Clicking it clicks
  the page's own button. If the page has no such button, nothing is hidden and
  nothing shows, so the worst case is the old behaviour.

## Cookie warning (components/CookieRiskDialog.qml)
- Aurora: two radial gradients filled into the card's own rounded shape. Fixes
  the sharp square corner top-right and the visible seam where the old blurred
  layer ended. No MultiEffect layers left in this dialog.
- Rim lit at the top, neutral below (no more red outline around the card).
- Hold key rebuilt: a tinted key that floods with the danger gradient from the
  left while held, white label under the fill, bright leading edge, glow
  underneath. The emblem's ring charges in step. Done = green check, 420 ms beat,
  then commit.

## AI Ideas (pages/AIIdeasPage.qml, vm/ideas_vm.py, core/ai/content_lab.py)
- NEW "My channel" card: niche, audience, constraints (Faceless, Solo creator,
  Phone only, Quick edits, No voiceover, Clip channel) and output language
  (Auto / English / Persian). Saved in config.json under "ideas_creator", sent
  with every run AND every single-greenlight rebuild, shown as tokens in the
  launch bar.
- Output language: "Auto" keeps the old rule; English/Persian force it.
- Removed: the hero's three-node pipeline card (duplicated the step badges).
- CSV panel: one explanation instead of two, an "Optional" tag, no empty row.
