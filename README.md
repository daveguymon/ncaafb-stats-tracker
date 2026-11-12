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

Run tests with `bin/rails test`.
