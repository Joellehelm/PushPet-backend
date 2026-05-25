# PushPet Backend

Rails API-only backend for PushPet. It fetches public GitHub data server-side, computes individual Pushpets, and updates one shared Community Pushpet. No login is required, but the app now uses Postgres for hatched pets, leaderboard entries, and shared community state.

## Setup

```powershell
cd C:\Users\Joelle\Desktop\PushPet\PushPet-backend
bundle install
.\bin\local-postgres.ps1
```

Set these environment variables as needed:

```powershell
$env:FRONTEND_URL="http://localhost:5177"
$env:GITHUB_TOKEN="optional_github_token_for_higher_rate_limits"
```

## Run Locally

```powershell
bundle exec rails server -p 3004
```

API routes:

```text
GET   /api/v1/status
GET   /api/v1/pets/:username
GET   /api/v1/community_pet
PATCH /api/v1/community_pet/customization
```

## Tests

Run the request suite after starting the local database:

```powershell
.\bin\local-postgres.ps1
bundle exec ruby -Itest test/requests/pushpet_api_test.rb
```

The tests stub GitHub responses, so they run fast and do not need network access, but they do need Postgres.

## Deployment

Render can use `render.yaml` from this folder.

Build command:

```bash
bash ./bin/render-build.sh
```

Start command:

```bash
bundle exec rails server -b 0.0.0.0 -p $PORT
```

Required production environment variables:

```text
FRONTEND_URL=https://your-production-frontend-origin
RAILS_ENV=production
DATABASE_URL=postgresql://...
SECRET_KEY_BASE=generate_on_render_or_use_rails_secret
```

When deploying with `render.yaml`, Render provisions `pushpet-db` and injects `DATABASE_URL` from that database automatically.

Optional:

```text
GITHUB_TOKEN=github_token_for_higher_public_api_limits
```

`FRONTEND_ORIGIN` is still accepted as a backwards-compatible alias for `FRONTEND_URL`.
