# PushPet Backend

Rails API-only backend for PushPet. It fetches public GitHub data server-side, computes individual Pushpets, and updates one shared Community Pushpet. No login and no database are required for the MVP.

## Setup

```powershell
cd C:\Users\Joelle\Desktop\PushPet\PushPet-backend
bundle install
Copy-Item .env.example .env
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
GET   /api/v1/pets/:username
GET   /api/v1/community_pet
PATCH /api/v1/community_pet/customization
```

## Tests

The app intentionally skips Rails' database-backed test setup. Run the lightweight request suite directly:

```powershell
bundle exec ruby -Itest test/requests/pushpet_api_test.rb
```

The tests stub GitHub responses, so they run fast and do not need network access.

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
SECRET_KEY_BASE=generate_on_render_or_use_rails_secret
```

Optional:

```text
GITHUB_TOKEN=github_token_for_higher_public_api_limits
COMMUNITY_PET_STORE_PATH=tmp/community_pet.production.json
```

Community state is currently JSON-backed in `tmp/community_pet.json`, which is suitable for the competition MVP but ephemeral on many hosting platforms.

`FRONTEND_ORIGIN` is still accepted as a backwards-compatible alias for `FRONTEND_URL`.
