# Settings rework (SON-23)

## Intent

Settings is one long scroll of 11 sections. Make it readable by grouping
the items into categories, each on its own page.

## Approaches

- **A. A category list, each category on its own page (picked).** The
  first screen fits without scrolling, and categories have room to grow.
  It costs one extra tap.
- **B. One page with grouped cards.** Everything stays one scroll away,
  but the page is still long.

How A is built: each category gets its own route (`/settings/<category>`).
A navigator nested inside Settings was rejected, because it breaks Back
and links can't point at a category.

## Design

- **Categories, in this order:**

  | Category   | Address                | What's on it |
  |------------|------------------------|--------------|
  | Library    | `/settings/library`    | music folders, storage |
  | Playback   | `/settings/playback`   | equalizer, downloads |
  | YouTube    | `/settings/youtube`    | sign-in, yt-dlp, helper, reset recommendations |
  | Appearance | `/settings/appearance` | themes, reduce animations |
  | Privacy    | `/settings/privacy`    | listening, top 10, crash reports |
  | Discord    | `/settings/discord`    | Discord status |
  | About      | `/settings/about`      | version, device ID, report a bug, check for updates, export log |

- **Phone (narrower than 720 px):**
  - `/settings` lists the categories, each with an icon and a short line
    of what's inside.
  - Tapping a category pushes its page, which has a Back arrow.
- **Wide (720 px or more):**
  - The list sits on the left, 280 px wide, and the chosen category shows
    on the right.
  - Picking a category swaps the right side, so pages don't stack.
  - Plain `/settings` shows Library, highlighted in the list.
- **Category pages** reuse the existing section widgets unchanged. Their
  section titles stay as subheadings, for example "Music folders" and
  "Storage" on Library.
- **Unchanged:**
  - `/settings/themes` and the theme editor.
  - Every setting's behavior.
  - The importer's link to `/settings`, which shows Library on wide
    windows and the list on phones.
- **An unknown category** in the address shows Library.

## Non-goals

No new settings, no search, and no changes to what any setting does.

## Left to the builder

The icons, the one-line descriptions, and the list's styling.
