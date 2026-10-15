-- Token rollups from llama-swap's activity store.
--   input_tokens  = prompt tokens actually prefilled
--   cache_tokens  = prompt tokens served from the prompt cache (not recomputed)
--   output_tokens = tokens generated
--   draft_acc_tokens / draft_tokens = MTP/speculative drafts accepted / proposed
-- ts_created is unix epoch seconds; every bucket is in local time.
--
-- run:  nix-shell -p sqlite --run 'sqlite3 /var/lib/llama-swap/activity.sqlite < ~/.config/llama-swap/rollups.sql'

.headers on
.mode column

.print == per hour (last 48) ==============================================
SELECT strftime('%Y-%m-%d %H:00', ts_created, 'unixepoch', 'localtime') AS hour,
       count(*)                    AS reqs,
       sum(input_tokens)           AS prefilled,
       sum(cache_tokens)           AS cached,
       sum(input_tokens + cache_tokens) AS total_in,
       sum(output_tokens)          AS generated,
       round(100.0 * sum(draft_acc_tokens) / NULLIF(sum(draft_tokens), 0), 1) AS mtp_pct
FROM activity
GROUP BY hour
ORDER BY hour DESC
LIMIT 48;

.print
.print == per day =========================================================
SELECT strftime('%Y-%m-%d', ts_created, 'unixepoch', 'localtime') AS day,
       count(*)           AS reqs,
       sum(input_tokens)  AS prefilled,
       sum(cache_tokens)  AS cached,
       sum(input_tokens + cache_tokens) AS total_in,
       sum(output_tokens) AS generated,
       round(sum(duration_ms) / 1000.0, 0) AS busy_s
FROM activity
GROUP BY day
ORDER BY day DESC;

.print
.print == per month =======================================================
SELECT strftime('%Y-%m', ts_created, 'unixepoch', 'localtime') AS month,
       count(*)           AS reqs,
       sum(input_tokens)  AS prefilled,
       sum(cache_tokens)  AS cached,
       sum(output_tokens) AS generated
FROM activity
GROUP BY month
ORDER BY month DESC;

.print
.print == rolling windows =================================================
WITH bounds(name, since) AS (
  VALUES ('last 1 hour',  strftime('%s','now','-1 hour')),
         ('last 24 hours',strftime('%s','now','-1 day')),
         ('last 7 days',  strftime('%s','now','-7 days')),
         ('last 30 days', strftime('%s','now','-30 days'))
)
SELECT b.name,
       count(a.id)                AS reqs,
       sum(a.input_tokens)        AS prefilled,
       sum(a.cache_tokens)        AS cached,
       sum(a.input_tokens + a.cache_tokens) AS total_in,
       sum(a.output_tokens)       AS generated
FROM bounds b
LEFT JOIN activity a ON a.ts_created >= b.since
GROUP BY b.name
ORDER BY b.since;

.print
.print == busiest models in the last 7 days ===============================
SELECT model_id,
       count(*)           AS reqs,
       sum(input_tokens)  AS prefilled,
       sum(cache_tokens)  AS cached,
       sum(output_tokens) AS generated
FROM activity
WHERE ts_created >= strftime('%s','now','-7 days')
GROUP BY model_id
ORDER BY generated DESC;
