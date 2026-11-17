# Blacklist 1.1.0

Your own list of players to avoid, with a note, the date and the zone you were in.

## Adding players
- Right-click a player (target, party frame, chat name) and choose **Add to Blacklist**.
- Or `/bl add` with a player targeted, or `/bl add <name> <note>`.
- `/bl` opens the window. Click a row to edit its note; X removes it (Shift-click skips the question).

## Warnings (only in your own chat, never party chat)
- **Group Finder:** hovering a listing or applicant adds a red line to the tooltip with your note.
- **Applicants:** when someone on your list applies to your group.
- **Invites:** when you invite them, apply to a group they lead, or they invite you.
- **Groups:** when they join your group.
- `/bl alerts off` turns warnings off.

## Nameplate icon
A red X appears after the name on the nameplate of anyone on your list. Nameplates have to be on for that player (V for enemies, Shift-V for friendly players). Inside dungeons the game blocks addons from changing friendly nameplates, so there it only shows on enemies.
`/bl icons off` turns it off.

## Sharing
Lists are swapped automatically with friends who run Blacklist (character or Battle.net friends, same faction). They appear in the **Shared** tab; press **Import** to copy a player to your own list. Nothing is added to your list automatically.
`/bl share` shows status, `/bl share now` syncs, `/bl share off` stops sharing.

## Other commands
`/bl check [name]`, `/bl remove <name>`, `/bl debug` (shows which warnings are hooked into your client).
