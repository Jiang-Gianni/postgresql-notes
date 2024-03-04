-- migrate:up
CREATE EXTENSION pg_stat_statements;


-- migrate:down
DROP EXTENSION pg_stat_statements;