# AGB 1.1: notice to existing users (§ 15 Abs. 2 AGB)

Draft of the notice that has to reach existing users before version 1.1 of the AGB / Terms of Service can bind them. Version 1.1 went live on the website with PR #5 (merged 2026-10-14 09:51 UTC); people who signed up since then accepted it at onboarding (§ 1 Abs. 4 AGB). Everyone who accepted version 1.0 stays on 1.0 until this notice has run its course.

**Nothing has been sent.** The wording is a draft: have a lawyer who knows consumer and platform terms read it before the first e-mail goes out.

| File | What it is |
| --- | --- |
| `notice.de.txt` | E-mail text in German. The legally binding version. |
| `notice.en.txt` | English translation for convenience. |
| `in-app.de.txt`, `in-app.en.txt` | Short in-app notice (title, text, three button labels) with the same legal content. |
| `render_notice.py` | Checks the quoted provisions against `agb.html` / `terms.html`, fills in the dates, writes `rendered/` (git-ignored). |

## Use

```sh
cd legal-notices/agb-1-1
python3 render_notice.py --check                  # do the quotes still match the live pages?
python3 render_notice.py --send-date 2026-10-19   # check, then fill in the dates -> rendered/
```

`rendered/notice.combined.txt` is the German text followed by the English one, for a single bilingual mail.

The dates follow from the send date. Receipt is assumed on the next day, the objection period is six weeks from receipt (a weekend deadline moves to Monday, § 193 BGB), and the changes take effect the day after. Sending on Mon 2026-10-19 gives: objection until Tue 2026-12-01, effective Wed 2026-12-02. Public holidays are not considered, check them by hand.

`--check` fails if a quoted provision no longer matches the pages, if a provision that changed between 1.0 and the live version is missing from the notice, or if the live pages are no longer version 1.1. Run it again whenever `agb.html` or `terms.html` change before the notice goes out. The old wording is read from commit `acab1b0`, the last one with version 1.0, so it needs the full git history.

## Before sending

- **Recipients:** accounts created before 2026-10-14 09:51 UTC, at the address each person signed up with. Check that the onboarding screen links to the live AGB, so that later sign-ups are covered.
- **Make sure the text is true.** The notice repeats § 8 Abs. 3: all AI processing on servers inside the EU. Confirm that for every AI route the backend uses (chat, plans, meal/food estimation, photo analysis), or fix the route or the wording. The privacy policy linked in the mail still lists the data-processing agreements with Eden AI and Mistral AI as pending.
- **One e-mail per person**, never a shared CC/BCC list, with the full text in the body (a link alone is not text form) and Reply-To `robin.juengerich@icloud.com`. Keep the rendered text and a send log (user, time).
- **Show the in-app notice from the same day**, with a way to read the full wording and to send the objection (`mailto:robin.juengerich@icloud.com?subject=Widerspruch%20AGB%201.1`). Mail can bounce or land in spam.
- Put the objection deadline and the effective date into your calendar.

## After sending

- Record objections (who, when). Under § 15 Abs. 3 such users stay on version 1.0 and either side may terminate (provider: 14 days to the end of a month, § 13 Abs. 3). Decide beforehand how you want to handle them.
- Users who did not object need nothing further. Keep the send log together with the rendered text.

## Legal notes (not legal advice)

- **Deemed consent is fragile.** § 15 Abs. 2 lets silence count as acceptance. The BGH declared a comparable clause in bank terms invalid (XI ZR 26/20, 27 April 2021, § 307 BGB), and courts have applied that reasoning to other consumer contracts. § 15 Abs. 3 already keeps changes to core services and fees out of the mechanism, but a court could still reject it. The safer route is **active acceptance in the app** (version and timestamp stored per user) in addition to this notice. That needs an app and database change and is not part of this folder.
- **Changes to the digital service itself** are also governed by § 327r BGB: a valid reason named in the contract, no extra cost, clear information, and for changes that impair use more than minimally advance notice on a durable medium plus a free termination right for consumers. It matters again for every later model or provider switch under § 8 Abs. 4.
- The mail names the reason for the change (§ 15 Abs. 1) and has a separate, highlighted section on the objection right and its consequences. Keep both when editing.
