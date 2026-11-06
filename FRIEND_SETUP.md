# Running this project on your machine

A practical, start-to-finish guide to getting the app running locally. It
covers the two things the README's Quick Start doesn't: the Docker network
fix Windows/WSL2 users hit, and how the model gets wired up.

> **Fastest path:** install Docker Desktop, drop in the `.env` you were
> given, then run `./setup.ps1` (Windows) — it does everything below for you.
> Read on if you'd rather do it by hand or hit a snag.

---

## 1. Prerequisites

- **Docker Desktop** (with Compose v2). Start it and wait until the whale
  icon is steady — the daemon must be running.
- ~6 GB free disk for images, and a working internet connection for the
  first build.
- That's it. No Python, Node, or database to install — everything runs in
  containers.

---

## 2. The one gotcha: Docker MTU on Windows/WSL2

**Symptom:** the first `docker compose ... --build` crawls or stalls during
`npm`/`pip` downloads, with errors like `error (23)` or `below 50 KiB/s`,
even though your internet is fine.

**Cause:** Docker Desktop defaults its network MTU to 1500, which is too
large for the WSL2 virtual network underneath. Large downloads fragment and
stall *inside* containers (they're fine on the host).

**Fix:** add an MTU of 1442 to Docker's daemon config and restart it.

1. Open (or create) `C:\Users\<you>\.docker\daemon.json` and add `"mtu": 1442`:

   ```json
   {
     "mtu": 1442
   }
   ```

   If the file already has settings, just add the `"mtu": 1442` line (mind
   the commas).

2. Restart Docker Desktop (tray icon → Restart, or quit and relaunch). Wait
   for the daemon to come back.

3. Verify (optional):

   ```bash
   docker run --rm alpine cat /sys/class/net/eth0/mtu
   ```

   It should print `1442`.

`setup.ps1` applies this automatically if it's missing.

---

## 3. The `.env` file

The app reads its configuration from a `.env` file in the repo root. It is
**gitignored**, so it never comes with the repo — you received one
separately. Drop it in the project root as `.env`.

It already contains a working **model API key** (OpenRouter), so answers work
out of the box — see the next section. The only thing you might change is
`POSTGRES_PASSWORD`.

If you *didn't* get an `.env`, copy the template and fill in a model key:

```bash
cp .env.example .env
# then set MODEL_API_KEY=sk-or-v1-...   (from https://openrouter.ai/)
```

---

## 4. The model (already wired up)

The app answers using a real model through an OpenAI-compatible provider
(OpenRouter). The relevant `.env` settings are:

```bash
MODEL_API_BASE_URL=https://openrouter.ai/api/v1
MODEL_API_KEY=sk-or-v1-...      # already set in the .env you were given
ANSWER_MODEL_ID=...             # the model that writes answers
AGENT_MODEL_ID=...              # the model behind @coder
```

On first boot, the app **auto-registers** these as model endpoints in its
database — there's no manual setup step. If you ever see **"no model endpoint
is registered"**, it means `MODEL_API_KEY` is empty in your `.env`; set it and
restart (`docker compose up -d`).

> Usage runs against the key in the `.env`. If that key is shared with you,
> be mindful that what you spend is billed to its owner.

---

## 5. Start the stack

```bash
docker compose up -d --build
```

The first build takes several minutes (it compiles the frontend). Later
starts are seconds. Then create your login — there is no default account:

```bash
docker compose exec api python manage.py create-user demo --password 'choose-something' --role admin
```

Open **http://localhost:3001** and sign in.

| service | URL |
| --- | --- |
| Web app | http://localhost:3001 |
| API | http://localhost:8000 |

Both are bound to `127.0.0.1` (this machine only), not your LAN.

To stop: `docker compose stop`. To start again: `docker compose up -d`.

---

## 6. Data sources

The app can search several sources. By default only the two that need no
external accounts are active:

- **Semantic index** — built from documents you add; no external account.
- **Postgres KB** — a bundled demo corpus; works out of the box.

Three more are **off by default** and you don't need them to try the app:

- **GitLab** and **Grafana/Prometheus (monitoring)** live behind an opt-in
  Compose profile and are **not started**. If you ever want them:
  `docker compose --profile optional up -d` (GitLab also needs your own
  `GITLAB_PERSONAL_ACCESS_TOKEN` in `.env`).
- **Google Drive / Gmail** need a **per-person** Google OAuth consent done in
  *your own* browser (see `docs/google-workspace-setup.md`). The `.env` you
  were given has the Google fields blank on purpose, so these sources stay
  disabled and no one else's Google account is ever touched. Set them up only
  if you want to search your own Google data.
  - **Searching a folder someone shared with you** (e.g. a "test data" folder):
    see [`docs/share-google-drive-folder.md`](docs/share-google-drive-folder.md)
    for the exact steps on both ends.

---

## Troubleshooting

- **Build stalls / slow downloads (Windows):** see §2 (MTU fix).
- **"no model endpoint is registered":** `MODEL_API_KEY` is empty in `.env` —
  set it and `docker compose up -d`.
- **Can't sign in:** there's no default user; create one (see §5).
- **Port already in use:** change the host-side port in `docker-compose.yml`
  (e.g. `127.0.0.1:3001:3000` → `127.0.0.1:3005:3000`).
