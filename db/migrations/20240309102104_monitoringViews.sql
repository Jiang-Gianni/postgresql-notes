-- migrate:up
-- CREATE OR REPLACE VIEW av_needed AS
-- SELECT N.nspname, C.relname
-- , pg_stat_get_tuples_inserted(C.oid) AS n_tup_ins
-- , pg_stat_get_tuples_updated(C.oid) AS n_tup_upd
-- , pg_stat_get_tuples_deleted(C.oid) AS n_tup_del
-- , CASE WHEN pg_stat_get_tuples_updated(C.oid) > 0
--  THEN pg_stat_get_tuples_hot_updated(C.oid)::real
--  / pg_stat_get_tuples_updated(C.oid)
--  END AS HOT_update_ratio
-- , pg_stat_get_live_tuples(C.oid) AS n_live_tup
-- , pg_stat_get_dead_tuples(C.oid) AS n_dead_tup
-- , C.reltuples AS reltuples
-- , round(COALESCE(threshold.custom, current_setting('autovacuum_vacuum_threshold'))::integer
--  + COALESCE(scale_factor.custom, current_setting('autovacuum_vacuum_scale_factor'))::numeric
--  * C.reltuples)
--  AS av_threshold
-- , date_trunc('minute',
--  greatest(pg_stat_get_last_vacuum_time(C.oid),
--  pg_stat_get_last_autovacuum_time(C.oid)))
--  AS last_vacuum
-- , date_trunc('minute',
--  greatest(pg_stat_get_last_analyze_time(C.oid),
--  pg_stat_get_last_analyze_time(C.oid)))
--  AS last_analyze
-- , pg_stat_get_dead_tuples(C.oid) >
--  round( current_setting('autovacuum_vacuum_threshold')::integer
--  + current_setting('autovacuum_vacuum_scale_factor')::numeric
--  * C.reltuples)
--  AS av_needed
-- , CASE WHEN reltuples > 0
--  THEN round(100.0 * pg_stat_get_dead_tuples(C.oid) / reltuples)
--  ELSE 0 END
--  AS pct_dead
-- FROM pg_class C
-- LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
-- NATURAL LEFT JOIN LATERAL (
--  SELECT (regexp_match(unnest,'^[^=]+=(.+)$'))[1]
--  FROM unnest(reloptions)
--  WHERE unnest ~ '^autovacuum_vacuum_threshold='
-- ) AS threshold(custom)
-- NATURAL LEFT JOIN LATERAL (
--  SELECT (regexp_match(unnest,'^[^=]+=(.+)$'))[1]
--  FROM unnest(reloptions)
--  WHERE unnest ~ '^autovacuum_vacuum_scale_factor='
-- ) AS scale_factor(custom)
-- WHERE C.relkind IN ('r', 't', 'm')
--  AND N.nspname NOT IN ('pg_catalog', 'information_schema')
--  AND N.nspname NOT LIKE 'pg_toast%'
-- ORDER BY av_needed DESC, n_dead_tup DESC;

-- create or replace view index_info as
-- SELECT
--  nspname,relname,
--  round(100 * pg_relation_size(indexrelid) / pg_relation_size(indrelid))
-- / 100
--  AS index_ratio,
--  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
--  pg_size_pretty(pg_relation_size(indrelid)) AS table_size
-- FROM pg_index I
-- LEFT JOIN pg_class C ON (C.oid = I.indexrelid)
-- LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
-- WHERE
--  nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') AND
--  C.relkind='i' AND
--  pg_relation_size(indrelid) > 0;

-- CREATE OR REPLACE VIEW table_stats AS
-- SELECT
--  stat.relname AS relname,
-- seq_scan, seq_tup_read, idx_scan, idx_tup_fetch,
-- heap_blks_read, heap_blks_hit, idx_blks_read, idx_blks_hit
-- FROM
--  pg_stat_user_tables stat
-- RIGHT JOIN pg_statio_user_tables statio
-- ON stat.relid=statio.relid;

-- create or replace view invalid_indexes as
-- SELECT ir.relname AS indexname
-- , it.relname AS tablename
-- , n.nspname AS schemaname
-- FROM pg_index i
-- JOIN pg_class ir ON ir.oid = i.indexrelid
-- JOIN pg_class it ON it.oid = i.indrelid
-- JOIN pg_namespace n ON n.oid = it.relnamespace
-- WHERE NOT i.indisvalid;

-- create view stats_by_total_time as
-- select
-- 	(total_exec_time + total_plan_time)::int as total_time,
-- 	total_exec_time::int,
-- 	total_plan_time::int,
-- 	mean_exec_time::int,
-- 	calls,
-- 	query
-- from
-- 	pg_stat_statements
-- order by
-- 	total_time desc
-- limit 50;

-- create view stats_by_slowest_query as
-- select
-- 	(mean_exec_time + mean_plan_time)::int as mean_time,
-- 	mean_exec_time::int,
-- 	mean_plan_time::int,
-- 	calls,
-- 	query
-- from
-- 	pg_stat_statements
-- --where
-- --	calls > 1
-- --	and userid = 99999
-- order by
-- 	mean_time desc
-- limit 50;


-- create view stats_by_buffers as
-- select
-- 	shared_blks_hit + shared_blks_read + shared_blks_dirtied + shared_blks_written + local_blks_hit + local_blks_read + local_blks_dirtied + local_blks_written + temp_blks_read + temp_blks_written as total_buffers,
-- 	(total_exec_time + total_plan_time)::int as total_time,
-- 	calls,
-- 	shared_blks_hit as sbh,
-- 	shared_blks_read as sbr,
-- 	shared_blks_dirtied as sbd,
-- 	shared_blks_written as sbw,
-- 	local_blks_hit as lbh,
-- 	local_blks_read as lbr,
-- 	local_blks_dirtied as lbd,
-- 	local_blks_written as lbw,
-- 	temp_blks_read as tbr,
-- 	temp_blks_written as tbr,
-- 	query
-- from
-- 	pg_stat_statements
-- order by
-- 	total_buffers desc
-- limit 50;

-- create view stats_by_jit as
-- select
-- 	((jit_generation_time + jit_inlining_time + jit_optimization_time + jit_emission_time)/(total_exec_time + total_plan_time)) as jit_total_time_percent,
-- 	calls,
-- 	jit_functions,
-- 	jit_generation_time,
-- 	jit_inlining_count,
-- 	jit_inlining_time,
-- 	jit_optimization_count,
-- 	jit_optimization_time,
-- 	jit_emission_count,
-- 	jit_emission_time,
-- 	query
-- from
-- 	pg_stat_statements
-- order by
-- 	jit_total_time_percent desc
-- limit 50;

-- migrate:down
-- drop view av_needed;
-- drop view index_info;
-- drop view table_stats;
-- drop view invalid_indexes;
-- drop view stats_by_total_time;
-- drop view stats_by_slowest_query;
-- drop view stats_by_buffers;
-- drop view stats_by_jit;