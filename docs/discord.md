# Discord status setup (once)

Songies shows "Listening to Songies" with the song, artist and a progress bar on your Discord profile (Settings → Discord, Windows and Linux only). Discord needs an "application" for that: its name is the "Songies" in "Listening to Songies".

1. Open https://discord.com/developers/applications and sign in. Click **New Application**, name it `Songies`, accept the terms.
2. On **General Information**, set the **App Icon** to `linux/packaging/songies.png` (the 512 px app icon).
3. Open **Rich Presence → Art Assets**, click **Add Image(s)**, choose the same `songies.png` and name it exactly `songies`. Local songs (no public cover) show this picture; YouTube songs show their cover with it as a small badge. Discord can take a few minutes to show a new asset.
4. Back on **General Information**, copy the **Application ID** (a long number). It is public, not a secret.
5. Paste it as `defaultValue` of `kDiscordClientId` in `lib/discord/discord_presence.dart`, then build or release as usual. (Done: the Songies app's id is `1566284629118296066`.)

Without an id the switch in Settings says "Not set up in this version of Songies yet".

## Checking it

- [ ] Discord desktop app open (on Linux the Flatpak and Snap versions work too). Settings → Discord → "Show what I'm listening to" on, then play a song: within a second or two your profile shows Listening to Songies, the title, the artist and a moving progress bar.
- [ ] A YouTube song shows its cover and a "Listen on YouTube Music" button (other people see the button; Discord hides your own).
- [ ] Pause: the status disappears. Play: it comes back. Seek: the bar jumps to match.
- [ ] Turn the switch off: the status disappears at once.
- [ ] Start Discord after Songies is already playing: the status appears with the next song change, pause/play or seek (Songies doesn't poll for Discord).
