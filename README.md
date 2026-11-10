# Utah Football Stats Tracker

Set `SPORTRADAR_API_KEY` in `.env` for development (see `.env.example`), install
dependencies with `bundle install`, and start the app with `bin/rails server`.
Visit `http://localhost:3000` to view Utah's schedule. Enter a four-digit year
to load a different season; games are ordered by scheduled time (UTC), with
games without a known time last. Expand a game to inspect its response data.
Select **View play-by-play** for a game to see its periods, drives, and events
in Sportradar's order. Expand an event for its underlying details and player
statistics. The refresh link reloads the feed subject to the client cache.

The schedule combines regular-season and postseason feeds. A missing
postseason feed is skipped; other API errors are displayed. Responses are
cached in-app according to the existing Sportradar client cache policy.
Availability of historical seasons depends on your Sportradar subscription.

Run tests with `bin/rails test`.
