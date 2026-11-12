# Utah Football Stats Tracker

Set `SPORTRADAR_API_KEY` in `.env` for development (see `.env.example`), install
dependencies with `bundle install`, and start the app with `bin/rails server`.
Visit `http://localhost:3000` to view Utah's schedule. Enter a four-digit year
to load a different season; games are ordered by scheduled time (UTC), with
games without a known time last. Expand a game to inspect its response data.
Matchup records show completed regular-season and postseason results before
each game, based on the available schedule feed. Future games show only
results available so far. Where a record cannot be determined it is marked
unavailable; ties are included when present.
Select **View play-by-play** for a game to see its periods, drives, and events
in Sportradar's order. Expand an event for its underlying details and player
statistics. The reload link checks the cache; it does not force a new API request.
When a drive's result is missing, the game view labels results inferred from
its plays; if the feed does not provide enough evidence, the result is
displayed as unavailable.

The schedule combines regular-season and postseason feeds. A missing
postseason feed is skipped; other API errors are displayed. Responses are
cached in-app according to the existing Sportradar client cache policy.
Availability of historical seasons depends on your Sportradar subscription.
The schedule shows freshness separately for regular-season and postseason feeds;
the game page shows it for play-by-play. The displayed time is when this app
received the response, not the age of Sportradar's underlying data. Existing
cache entries created before freshness tracking are displayed with an unknown
fetch time until they expire. Missing postseason feeds are identified explicitly.
Closed game responses are cached for 30 days, current schedules for 10 minutes,
and older schedules for 30 days; upstream corrections may not appear until
the cached response expires.

Cache misses are coordinated between app processes sharing the same
`storage/sportradar_locks` directory and cache. Trial requests are spaced at
one per second. A 429 is retried once when its `Retry-After` delay is at most
two seconds (or after one second if the header is absent); longer delays and
repeated 429s are reported to the user. This does not coordinate separate
hosts or other clients using the same API key. Check your account's actual
QPS and rolling quota before deploying multiple instances.

## Quota protection

Set `SPORTRADAR_QUOTA_LIMIT` to a positive integer to cap upstream attempts in
a rolling window, and optionally set `SPORTRADAR_QUOTA_WINDOW_SECONDS`
(default `86400`). Production requires a limit; development and test are
unlimited unless one is configured. The supplied Kamal configuration starts
at 25 attempts per 24 hours, **not** a statement of your provider's quota.
Choose a lower budget if necessary for your plan, including other clients and
any monthly or other limits. This cap is local to this application and cannot
read or guarantee the provider's remaining quota.

Each network attempt reserves a slot before the request, including retries,
404s and failures; cached responses consume none. When exhausted, cached data
remains available and new requests receive the existing rate-limit message
(HTTP 429 on JSON endpoints). Slots expire on a rolling basis. The budget and
cooldown are persisted alongside the coordinator lock and shared between
processes and rolling deploys of quota-aware versions on **one host using the
same storage volume**.
Never delete or replace that state to obtain more requests. If its data becomes
corrupt, requests fail closed and the server logs a coordination error; inspect
the state and your provider's actual usage before recovery.
For the first deployment of quota protection, stop older application processes
before starting the new version: older versions do not enforce the budget and
use an incompatible coordinator-state format. Allow for their previous usage.
All concurrently running versions must use the same budget and window.

The limit cannot coordinate other machines, installations, access levels or
clients sharing the key. It is not a per-visitor throttle: one visitor can
exhaust the app's budget. Use an edge rate limiter or restrict access before
making this app public. Changing the key or access level creates a separate
budget. When increasing the window or enabling the limit for an existing app,
prior usage outside the recorded window is not known; account for it manually.
Keep the server clock synchronized. Deleting the storage volume loses both
cache and quota history.

## Production deployment

The included Dockerfile and Kamal configuration are a **single-host template**,
not a ready-to-run public deployment. Configure a real host, registry, DNS and
TLS proxy in `config/deploy.yml`; do not use the example IP or registry.
Configure a persistent volume at `/rails/storage`, writable by container UID
1000, and ensure the old and new containers share it during deploys.
Multi-host deployments require a shared, atomic cache and distributed
coordination before using this integration safely.

Provide `RAILS_MASTER_KEY` and `SPORTRADAR_API_KEY` through the deployment
platform's secret manager or environment; never put the key in the image or
commit it. For Kamal, export `SPORTRADAR_API_KEY` in the deployment shell and
provide `config/master.key` locally (or replace the corresponding lookup in
`.kamal/secrets` with your secret manager). `.env` is not shipped in the
image. Configure `SPORTRADAR_ACCESS_LEVEL`, the budget and window in
`config/deploy.yml` for your account. The template's quota settings must be
reviewed before deploying.

Terminate HTTPS at a trusted reverse proxy, set `APP_HOST` to the exact public
hostname for Rails host authorization, and set `FORCE_SSL=true` when the app
is reachable only through that TLS-terminating proxy. Do not expose the app
directly when using `FORCE_SSL`: it trusts the proxy for HTTPS. Configure the
proxy's own host filtering, request limits and monitoring. `/up` checks Rails
boot only; it does not check the API key, storage, or available quota. Monitor
application logs and provider usage, and verify a cached and uncached request
after deployment while accounting for quota.

For a local container smoke test after building the image, provide the secrets
as exported environment variables (not literal command-line values):

```sh
docker build -t ncaafb-stats-tracker .
docker run --rm -p 127.0.0.1:8080:80 \
  -v ncaafb_stats_tracker_storage:/rails/storage \
  -e RAILS_MASTER_KEY -e SPORTRADAR_API_KEY \
  -e SPORTRADAR_ACCESS_LEVEL=trial -e SPORTRADAR_QUOTA_LIMIT=25 \
  ncaafb-stats-tracker
```

Visit `http://localhost:8080/up` to check boot. This local-only example does
not configure TLS or host authorization. Stop the container when finished;
the named volume persists quota and cache state.

Run tests with `bin/rails test`.
