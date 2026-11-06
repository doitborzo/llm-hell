# Letting a friend search a shared Google Drive folder

Goal: you have a Drive folder (**"On-prem AI"**) with test data, and you want
your friend's local copy of the app to answer questions from it.

## How search actually works (read this first)

The Google connector searches Drive with `fullText contains` across names,
content and metadata, and **"Shared with me" is included** — so once you share
"On-prem AI" with your friend's account, its files become searchable.

**To search ONLY that folder, set `GOOGLE_DRIVE_FOLDER`** in `.env` to the
folder name (or its Drive id):

```bash
GOOGLE_DRIVE_FOLDER=On-prem AI
```

When set, the app resolves that folder for the signed-in account, walks its
subfolders, and constrains every Drive query to that folder tree. It
**fails closed**: if the folder can't be found for the account, Drive search
returns nothing rather than quietly searching the whole account. This is
already preset in the `.env` you're sharing, so your friend can use their
everyday Google account and still only ever see "On-prem AI".

> Matching is by exact folder name. If the account can see two folders both
> named "On-prem AI", use the folder's Drive id instead (open the folder in a
> browser; the id is the last path segment of the URL).

---

## Part A — what you do (you share nothing but the folder)

By design, each person's deployment uses **its own** Google OAuth client and
**its own** account consent. You never hand over credentials or tokens — the
only thing that leaves your side is the folder share itself.

1. **Ask your friend for the email address** of the Google account they'll use
   with the app.

2. **Share the folder with that email.** In Google Drive: right-click
   **On-prem AI → Share**, add your friend's email, give **Viewer** access,
   send. It will appear under **Shared with me** in their Drive.

That's your entire part. Everything else happens on your friend's machine with
his own Google project — see Part B.

---

## Part B — what your friend does on their machine

Prerequisites: the app already set up and running (see `FRIEND_SETUP.md`), and
**Node.js ≥ 22.12** installed (the consent tool needs it).

1. **Create his own Google OAuth client.** In the Google Cloud console: a new
   project → enable the **Google Drive API** → **OAuth consent screen** (User
   type *External*, add his own email under **Test users**) → **Credentials →
   Create OAuth client ID → Desktop app**. Copy the client id and secret. Full
   walkthrough: [`google-workspace-setup.md`](google-workspace-setup.md), §1.
   Nothing here comes from you.

2. **Put the Google settings in `.env`** (these are blank in the shared `.env`
   by default):

   ```bash
   GOOGLE_CLIENT_ID=<his own, from step 1>
   GOOGLE_CLIENT_SECRET=<his own, from step 1>
   GOOGLE_ACCOUNT_EMAIL=<his own email - the account the folder was shared with>
   GOOGLE_DRIVE_FOLDER=On-prem AI     # already preset; limits search to this folder
   ```

3. **Run the one-time browser consent** (produces his personal tokens):

   ```powershell
   cd <repo>; .\setup-google-consent.ps1
   ```

   This opens the MCP Inspector. In it: **Connect → Tools → `manage_accounts`**,
   run with `operation = authenticate`, `category = work`. A Google sign-in
   window opens — he signs in with **his own** account and approves. Full
   mechanics (and verifying with `manage_drive`) are in
   [`google-workspace-setup.md`](google-workspace-setup.md), §3.

4. **Copy the tokens into the repo** so the container can use them:

   ```powershell
   mkdir -Force secrets\google-workspace\config, secrets\google-workspace\share
   Copy-Item -Recurse "$env:USERPROFILE\.config\google-workspace-mcp\*"      secrets\google-workspace\config\
   Copy-Item -Recurse "$env:USERPROFILE\.local\share\google-workspace-mcp\*" secrets\google-workspace\share\
   ```

   (The server stores tokens under `~/.config` and `~/.local/share` — XDG
   paths — on every OS, including Windows.)

   `secrets/` is gitignored — these are live credentials, treat them like a
   password.

5. **Start the Google sidecar and enable the sources:**

   ```bash
   docker compose --profile google up -d --build google-mcp
   docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
     -c "UPDATE sources SET enabled=true WHERE key IN ('google_drive','google_mail');"
   docker compose restart api
   ```

   (Enable only `google_drive` if he doesn't need Gmail.)

6. **Verify.** On the **Sources** page, press **Check** on Google Drive — it
   should report reachable with `manage_drive` in its tool list. Then ask the
   app something answerable from a file in "On-prem AI"; the answer should cite
   that file.

---

## Troubleshooting

- **`access_blocked` during consent:** his own email isn't added as a **Test
  user** on his OAuth consent screen (step 1).
- **`Errno -2` / "Name or service not known" on Check:** the `google-mcp`
  container isn't running — run the `--profile google` command in step 5.
- **Search returns their own files too:** `GOOGLE_DRIVE_FOLDER` isn't set, or
  is set to a name the account can't see. Set it to `On-prem AI` (or the
  folder's Drive id) and `docker compose restart api`.
- **Drive search suddenly returns nothing:** `GOOGLE_DRIVE_FOLDER` is set to a
  folder the account can't find (wrong name, or not shared yet). Confirm the
  share landed in the friend's "Shared with me", then restart api.
- **A shared file isn't found:** make sure the folder (not just individual
  files) was shared, and that it's under **My Drive** sharing, not a separate
  Shared Drive — Shared Drives need different API flags the connector doesn't
  set.
