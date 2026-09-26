# YNAB Sankey

A macOS app that draws a month's or a year's spending from a YNAB budget as a Sankey diagram:

**income sources → Budget → category groups (+ Saved) → categories**

## Build & run

```bash
scripts/build-app.sh            # builds build/YNAB Sankey.app
scripts/build-app.sh --install  # …and copies it to /Applications
swift test                      # unit tests
```

On first launch, paste a YNAB Personal Access Token (YNAB → Account Settings → Developer Settings).
It's stored in the login Keychain under `com.markrwatts.YNABSankey`; disconnect via **YNAB Sankey → Settings…**.

## How the numbers are worked out

- Only on-budget accounts count. Split transactions use their subtransactions.
- Income = anything categorised to *Inflow: Ready to Assign*, grouped by payee (top 6 + "Other income").
- Spending = net activity per category, so refunds reduce the category they're filed against.
- Transfers between your own on-budget accounts are ignored; categorised transfers to tracking
  accounts (e.g. pension, investments) count as spending.
- If income exceeds spending the difference flows to **Saved / unspent**; if spending exceeds
  income a **From savings / buffer** source makes up the difference.
- Categories under 0.6% of the period's spending fold into "Other <group>".

Hover a node or ribbon for its amount and share. ⌘← / ⌘→ step between periods, ⌘R reloads from YNAB.
Zoom with a trackpad pinch, the toolbar magnifiers, or ⌘= / ⌘- / ⌘0 (up to 400%); zoomed in, the chart scrolls and
crowded labels get room to breathe.

To eyeball layout changes without a token, render synthetic snapshots:

```bash
SANKEY_SNAPSHOT_DIR=/tmp swift test --filter renderSnapshot
```
