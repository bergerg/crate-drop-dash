# Crate Drop Dash

2-player pixel-art party game (one keyboard). One player runs a parkour course, the other drops boxes from a crane, then they swap.

Open `index.html` in a browser to play.

## Security notes

- Strict Content-Security-Policy: only this site's own scripts, styles and fonts load; network access only to the game's Supabase project.
- No third-party CDNs: `vendor/supabase.js` (supabase-js 2.45.4, MIT) and the pixel fonts in `fonts/` (SIL OFL) are self-hosted.
- Leaderboard writes go through `start_run` / `submit_score` (see `supabase/migrations/`), which check run time, allow one score per run, and rate-limit.
- Online rooms use 6-letter random codes, pair the two players by random ids, and validate every incoming message.
