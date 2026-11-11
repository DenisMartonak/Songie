# The Songies website

The site lives in `website/` and is published to
<https://denismartonak.github.io/Songie/> by `.github/workflows/pages.yml`
whenever `main` changes anything under `website/` (or by hand: Actions →
Website → Run workflow). Plain HTML, CSS and JavaScript; nothing to build.

Design: `docs/superpowers/specs/2026-11-11-website-design.md`.

## One-time setup

GitHub repo → Settings → Pages → Source: **GitHub Actions**.

## Pages

| Address | File | What it is |
| --- | --- | --- |
| `/Songie/` | `website/index.html` | Home: the S animation, download for the visitor's device, showcase clips |
| `/Songie/features/` | `website/features/index.html` | Every feature |
| `/Songie/r/<CODE>` | `website/404.html` | Listen together invite: opens `songies://room/<CODE>` |

GitHub Pages has no server, so room links work through `404.html`, which
Pages serves for any unknown address. It reads the code from the address.
Room links still open the app through the `songies://` scheme. The app
shares the https address from the first release after 1.4.0 (`kRoomSiteBase`
in `lib/room/room_links.dart`).

The Download button asks the GitHub API for the latest release and picks
the `.apk`, `-windows-setup.exe` or `-x86_64.AppImage`, so keep those asset
names. If the API can't be reached, or the device is an iPhone or a Mac, the
button reads "All downloads" and links to the releases page.

## Preview locally

    tool/website_preview.sh

That serves the site at <http://localhost:8123/Songie/>. The room page:
<http://localhost:8123/Songie/404.html?preview=/Songie/r/ABCD2345>.

The site's scripts have tests: `node --test test/website/`.

## Re-recording the showcase clips

    tool/showcase.sh                    # every scene, about 3 minutes
    SCENES=themes,search tool/showcase.sh

It runs the real Linux app under `integration_test/showcase/` with a
throwaway data folder (`XDG_DATA_HOME`). It stays signed out of everything,
and the test refuses to start without that folder, so your own library and
accounts are never opened. A window opens on your desktop and clicks
through the scenes. Leave it alone until it closes. It needs internet:
the songs are real YouTube Music tracks (pinned in `demo_library.dart`).

Results go to `website/media/showcase/` (a WebM and an MP4 per scene, a
poster, and `showcase.json`, which the home page reads). Commit them.

## Not yet

Passkeys (SON-6) need `/.well-known/assetlinks.json` at the root of a
domain. A project site under `/Songie/` can't serve that. It needs a custom
domain or a `DenisMartonak.github.io` repository.
