# Privacy notice

*Last updated: 27 September 2026*

YNAB Sankey is a macOS app that reads your YNAB budget and draws it as a chart. It runs entirely on
your Mac. There is no YNAB Sankey server, account, analytics, crash reporting or advertising.

## What the app reads

Using the YNAB Personal Access Token you give it, the app reads from YNAB:

- your list of budgets
- the chosen budget's accounts, categories and transactions

It only ever reads. It never creates, changes or deletes anything in YNAB.

## Where your data goes

Only between your Mac and YNAB. The app connects to `https://api.ynab.com` over HTTPS and nowhere
else. Nothing is sent to the app's author or to any third party. YNAB's own
[privacy policy](https://www.ynab.com/privacy-policy) covers the data they hold.

## What is kept on your Mac

| What | Where | Why |
|---|---|---|
| Your YNAB access token | macOS login Keychain (`com.markrwatts.YNABSankey`) | So you don't have to paste it every launch |
| Your default budget's ID (if you set one) | `~/Library/Preferences/com.markrwatts.YNABSankey.plist` | To open the right budget |
| Window size and position | Same preferences file | Standard macOS window restoration |

Your budget, account, category and transaction data is held in memory only while the app is open and
is gone when you quit. The app turns off macOS's network cache, so none of it is written to disk.

## Deleting your data

1. In the app, **YNAB Sankey → Settings… → Disconnect** removes the token from the Keychain and clears
   the default budget.
2. To remove the preferences file too:
   ```bash
   defaults delete com.markrwatts.YNABSankey
   ```
3. Delete `YNAB Sankey.app` from Applications.

To cut off the app's access from YNAB's side, revoke the token in YNAB under Account Settings →
Developer Settings.

## Changes and questions

Changes to this notice are tracked in this repository's history. Questions or concerns:
[open an issue](https://github.com/MarkRWatts/YNAB-Sankey/issues).
