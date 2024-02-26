-- Shadow Tables

-- Setup Table 1
CREATE TABLE public.table1 (
	key SERIAL,
	value INTEGER,
	value_type VARCHAR,
	PRIMARY KEY (key)
);

-- Setup Table 2
CREATE TABLE public.table2 (
	key SERIAL,
	value INTEGER,
	value_type VARCHAR,
	user_name NAME,
	action VARCHAR,
	action_time TIMESTAMP
);

-- Basic Shadow Table Function
CREATE FUNCTION public.shadow_table1 ( )
RETURNS trigger AS
$body$
BEGIN
   IF TG_OP = 'INSERT' THEN
      INSERT INTO public.table2
      VALUES(NEW.key, NEW.value, NEW.value_type, current_user, TG_OP, now());
      RETURN NEW;
   END IF;
   IF TG_OP = 'UPDATE' THEN
      INSERT INTO public.table2
      VALUES(NEW.key, NEW.value, NEW.value_type, current_user, TG_OP, now());
      RETURN NEW;
   END IF;
   IF TG_OP = 'DELETE' THEN
      INSERT INTO public.table2
      VALUES(OLD.key, OLD.value, OLD.value_type, current_user, TG_OP, now());
      RETURN OLD;
   END IF;
END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;

CREATE TRIGGER table1_tr  
 BEFORE INSERT OR UPDATE OR DELETE  
 ON public.table1 FOR EACH ROW  
 EXECUTE PROCEDURE public.shadow_table1();

-- Insert Test Data
INSERT INTO public.table1 (value, value_type) VALUES ('30', 'meters');
INSERT INTO public.table1 (value, value_type) VALUES ('10', 'inches');
UPDATE public.table1 SET value = '20' WHERE value_type = 'inches';
DELETE FROM public.table1 WHERE value_type = 'inches';
INSERT INTO public.table1 (value, value_type) VALUES ('50', 'inches');

-- Look at contents of Table1
SELECT * FROM public.table2;
/*
key | value | value_type
1   | 30    | meters
3   | 50    | inches
*/


-- Look at contents of Table2
SELECT * FROM public.table2;
/*
key | value | value_type | user_name | action | action_time
1   | 30    | meters     | postgres  | INSERT | 12/3/2013 4:58:04 PM
2   | 10    | inches     | postgres  | INSERT | 12/3/2013 4:58:05 PM
2   | 20    | inches     | postgres  | UPDATE | 12/3/2013 4:58:06 PM
2   | 20    | inches     | postgres  | DELETE | 12/3/2013 4:58:07 PM
3   | 50    | inches     | postgres  | INSERT | 12/3/2013 4:58:08 PM
*/

-- Updated to support Row Expansion
CREATE FUNCTION public.shadow_table1 ()
RETURNS trigger AS
$body$
BEGIN
   IF TG_OP = 'INSERT' THEN
      INSERT INTO public.table2
         VALUES((NEW).*, current_user, TG_OP, now());
      RETURN NEW;
   END IF;
   IF TG_OP = 'UPDATE' THEN
      INSERT INTO public.table2
         VALUES((NEW).*, current_user, TG_OP, now());
      RETURN NEW;
   END IF;
   IF TG_OP = 'DELETE' THEN
      INSERT INTO public.table2
         VALUES((OLD).*, current_user, TG_OP, now());
      RETURN OLD;
   END IF;
END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;

-- New and improved Shadow Function - Version 1
CREATE OR REPLACE FUNCTION public.shadow ()
RETURNS trigger AS
$body$
DECLARE
   shadow_schema TEXT;
   shadow_table TEXT;
BEGIN
   IF (TG_NARGS <> 2) THEN
      RAISE EXCEPTION 'Incorrect number of arguments for shadow_function(schema, table): %', TG_NARGS;
   END IF;

   shadow_schema = TG_ARGV[0];
   shadow_table = TG_ARGV[1];
   IF TG_OP = 'INSERT' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING NEW, TG_OP;
      RETURN NEW;
   ELSIF TG_OP = 'UPDATE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING NEW, TG_OP;
      RETURN NEW;
   ELSIF TG_OP = 'DELETE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING OLD, TG_OP;
      RETURN OLD;
   ELSIF TG_OP = 'TRUNCATE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT a.*, current_user, $1, now() FROM ' || quote_ident(TG_TABLE_SCHEMA) || '.' || quote_ident(TG_TABLE_NAME) || ' a' USING TG_OP;
      RETURN NULL;
   END IF;
END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;

-- New and improved Shadow Function - Version 2
CREATE OR REPLACE FUNCTION public.shadow ()
RETURNS trigger AS
$body$
DECLARE
   shadow_schema TEXT;
   shadow_table TEXT;
BEGIN
   IF (TG_NARGS <> 2) THEN
      RAISE EXCEPTION 'Incorrect number of arguments for shadow_function(schema, table): %', TG_NARGS;
   END IF;

   shadow_schema = TG_ARGV[0];
   shadow_table = TG_ARGV[1];
   IF TG_OP = 'INSERT' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING NEW, TG_OP;
      RETURN NEW;
   ELSIF TG_OP = 'UPDATE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING NEW, TG_OP;
      RETURN NEW;
   ELSIF TG_OP = 'DELETE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING OLD, TG_OP;
      RETURN OLD;
   ELSIF TG_OP = 'TRUNCATE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' (user_name, action, action_time) VALUES (current_user, $1 , now())';
      RETURN NULL;
   END IF;
END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;

-- Drop previous test trigger
DROP TRIGGER public.table1_tr;

-- Add new triggers to table 1
CREATE TRIGGER table1_tr
  BEFORE INSERT OR UPDATE OR DELETE
  ON public.table1 FOR EACH ROW
  EXECUTE PROCEDURE public.shadow ('public', 'table2');

CREATE TRIGGER table1_tr1
  BEFORE TRUNCATE
  ON public.table1 FOR EACH STATEMENT
  EXECUTE PROCEDURE public.shadow ('public', 'table2');

-- Remove previous test data
TRUNCATE table1, table2;

-- New Test Data
INSERT INTO public.table1 (value, value_type) VALUES ('30', 'meters');
INSERT INTO public.table1 (value, value_type) VALUES ('10', 'inches');
UPDATE public.table1 SET value = '20' WHERE value_type = 'inches';
DELETE FROM public.table1 WHERE value_type = 'inches';
INSERT INTO public.table1 (value, value_type) VALUES ('50', 'inches');
TRUNCATE public.table1;
INSERT INTO public.table1 (value, value_type) VALUES ('50', 'inches');
DELETE FROM public.table1 WHERE value_type = 'inches';
INSERT INTO public.table1 (value, value_type) VALUES ('30', 'meters');

-- Look at contents of Table1
SELECT * FROM public.table2;
/*
Version 1 & 2
key | value | value_type
52   | 30    | meters
*/


-- Look at contents of Table2
SELECT * FROM public.table2;
/*
Version 1
key | value | value_type | user_name | action   | action_time
45  | 30    | meters     | postgres  | INSERT   | 12/4/2015 11:46:19 AM
46  | 10    | inches     | postgres  | INSERT   | 12/4/2015 11:46:23 AM
46  | 20    | inches     | postgres  | UPDATE   | 12/4/2015 11:46:27 AM
46  | 20    | inches     | postgres  | DELETE   | 12/4/2015 11:46:31 AM
47  | 50    | inches     | postgres  | INSERT   | 12/4/2015 11:46:35 AM
45  | 30    | meters     | postgres  | TRUNCATE | 12/4/2015 2:11:31 PM
47  | 50    | inches     | postgres  | TRUNCATE | 12/4/2015 2:11:31 PM
51  | 50    | inches     | postgres  | INSERT   | 12/4/2015 2:11:42 PM
51  | 50    | inches     | postgres  | DELETE   | 12/4/2015 2:11:50 PM
52  | 30    | meters     | postgres  | INSERT   | 12/4/2015 2:11:57 PM

Version 2
key | value | value_type | user_name | action   | action_time
45  | 30    | meters     | postgres  | INSERT   | 12/4/2015 11:46:19 AM
46  | 10    | inches     | postgres  | INSERT   | 12/4/2015 11:46:23 AM
46  | 20    | inches     | postgres  | UPDATE   | 12/4/2015 11:46:27 AM
46  | 20    | inches     | postgres  | DELETE   | 12/4/2015 11:46:31 AM
47  | 50    | inches     | postgres  | INSERT   | 12/4/2015 11:46:35 AM
    |       |            | postgres  | TRUNCATE | 12/4/2015 2:11:31 PM
51  | 50    | inches     | postgres  | INSERT   | 12/4/2015 2:11:42 PM
51  | 50    | inches     | postgres  | DELETE   | 12/4/2015 2:11:50 PM
52  | 30    | meters     | postgres  | INSERT   | 12/4/2015 2:11:57 PM
*/

-- Time Travel - Version 1 Shadow Table
SELECT * FROM (
   SELECT DISTINCT ON (key) *
   FROM table2
   WHERE action_time <= '12/4/2015 11:46:36 AM'
   ORDER BY key, action_time DESC
) a
WHERE action IN ('UPDATE', 'INSERT');
/*
Version 1
key | value | value_type | user_name | action   | action_time
45  | 30    | meters     | postgres  | INSERT   | 12/4/2015 11:46:19 AM
47  | 50    | inches     | postgres  | INSERT   | 12/4/2015 11:46:35 AM
*/

-- Time Travel - Version 2 Shadow Table
SELECT a.* FROM
(
   SELECT DISTINCT ON (key) *
   FROM table2
   WHERE action_time <= '12/4/2015 2:11:43 PM'
   ORDER BY key, action_time DESC
) a
LEFT JOIN
(
   SELECT DISTINCT ON (action) action_time
   FROM table2
   WHERE action_time <= '12/4/2015 2:11:43 PM'
   AND action = 'TRUNCATE'
   ORDER BY action, action_time DESC ) b ON (TRUE)
WHERE
   (
      a.action_time > b.action_time
      OR b.action_time IS NULL
   )
   AND action IN ('UPDATE', 'INSERT');
/*
Version 2
key | value | value_type | user_name | action   | action_time
51  | 50    | inches     | postgres  | INSERT   | 12/4/2015 2:11:42 PM
*/

-- Comparisons over time - Version 1
SELECT key, value, value_type FROM (
   SELECT DISTINCT ON (key) *
   FROM table2
   WHERE action_time <= '12/4/2015 11:46:36 AM'
   --HAVING action IN ('SELECT', 'INSERT')
   ORDER BY key, action_time DESC
) a
WHERE action IN ('UPDATE', 'INSERT')
EXCEPT
SELECT * FROM table1;

-- Comparisons over time - Version 2
SELECT * FROM table1
EXCEPT
SELECT key, value, value_type FROM (
   SELECT DISTINCT ON (key) *
   FROM table2
   WHERE action_time <= '12/4/2015 11:46:36 AM'
   --HAVING action IN ('SELECT', 'INSERT')
   ORDER BY key, action_time DESC
) a
WHERE action IN ('UPDATE', 'INSERT');

-- Restoring Data from Shadow Table to Source Table - Version 1
BEGIN;
ALTER TABLE table1 DISABLE TRIGGER ALL;
TRUNCATE table1;
INSERT INTO table1 SELECT key, value, value_type FROM (
   SELECT DISTINCT ON (key) *
   FROM table2
   WHERE action_time <= '12/4/2015 11:46:36 AM'
   --HAVING action IN ('SELECT', 'INSERT')
   ORDER BY key, action_time DESC
) a
WHERE action IN ('UPDATE', 'INSERT');
ALTER TABLE table1 ENABLE TRIGGER ALL;
-- Optional trim of the shadow table for anything after the time
DELETE FROM table2 WHERE action_time > '12/4/2015 11:46:36 AM';
END;

-- Restoring Data from Shadow Table to Source Table - Version 2
BEGIN;
ALTER TABLE table1 DISABLE TRIGGER ALL;
TRUNCATE table1;
INSERT INTO table1 SELECT key, value, value_type FROM (
   SELECT DISTINCT ON (key) *
   FROM table2
   WHERE action_time <= '12/4/2015 2:11:43 PM'
   ORDER BY key, action_time DESC
) a LEFT JOIN (
   SELECT DISTINCT ON (action) action_time
   FROM table2
   WHERE action_time <= '12/4/2015 2:11:43 PM'
   AND action = 'TRUNCATE'
   ORDER BY action, action_time DESC
) b ON (TRUE)
WHERE
   (
      a.action_time > b.action_time
      OR b.action_time IS NULL
   )
   AND action IN ('UPDATE', 'INSERT');
ALTER TABLE table1 ENABLE TRIGGER ALL;
-- Optional trim of the shadow table for anything after the time
DELETE FROM table2 WHERE action_time > '12/4/2015 2:11:43 PM';
END;

-- Add Shadow Function - Version 1
CREATE OR REPLACE FUNCTION public.add_shadow (
   source_schema name,
   source_table name,
   shadow_schema name = NULL::name,
   shadow_table name = NULL::name
)
RETURNS void AS
$body$
DECLARE
   r RECORD;
   version RECORD;
   trigger_def RECORD;
BEGIN
   IF source_schema IS NULL THEN
      RAISE EXCEPTION 'Must specify source schema: add_shadow(source_schema, source_table, shadow_schema, shadow_table)';
   END IF;
   IF source_table IS NULL THEN
      RAISE EXCEPTION 'Must specify source table: add_shadow(source_schema, source_table, shadow_schema, shadow_table)';
   END IF;
   IF shadow_schema IS NULL THEN
      shadow_schema := source_schema;
   END IF;
   IF shadow_table IS NULL THEN
      shadow_table := source_table || '_s';
   END IF;

   -- Check to see if source table already exists
   SELECT table_schema, table_name INTO r FROM information_schema.tables WHERE table_schema = source_schema AND table_name = source_table;
   IF NOT FOUND THEN
      RAISE EXCEPTION 'Source Table must exist (%.%)', source_schema, source_table;
   END IF;
   -- Check to see if shadow table already exists
   SELECT table_schema, table_name INTO r FROM information_schema.tables WHERE table_schema = shadow_schema AND table_name = shadow_table;
   IF FOUND THEN
      RAISE EXCEPTION 'Shadow Table already exist (%.%)', shadow_schema, shadow_table;
   END IF;

   -- Check to see if triggers already exist
   -- Need to check the object source because the same trigger name may exist more than once in a schema if applied to different tables.
   SELECT trigger_schema, trigger_name
      INTO r
      FROM information_schema.triggers
      WHERE trigger_schema = source_schema
         AND trigger_name = lower(source_table) || '_tsr'
         AND event_object_schema = source_schema
         AND event_object_table = source_table;
   IF FOUND THEN
      RAISE EXCEPTION 'Trigger already exist (%.%)', source_schema, (lower(source_table) || '_tsr');
   END IF;

   SELECT trigger_schema, trigger_name
      INTO r
      FROM information_schema.triggers
      WHERE trigger_schema = source_schema
         AND trigger_name = lower(source_table) || '_tss'
         AND event_object_schema = source_schema
         AND event_object_table = source_table;
   IF FOUND THEN
      -- BUG: Postgres 9.1 through 10 does not support TRUNCATE triggers in this view.
      RAISE EXCEPTION 'Trigger already exist (%.%)', source_schema, (lower(source_table) || '_tss');
   END IF;

   SELECT substr(setting,1,length(setting)-strpos(reverse(setting), '.')) AS version INTO version FROM pg_settings WHERE "name" = 'server_version';
   IF NOT FOUND THEN
      RAISE EXCEPTION 'Could not figure out the PostgreSQL version';
   ELSE
      IF version.version IN ('9.1', '9.2', '9.4', '9.5', '9.6', '10') THEN
         SELECT replace(replace(definition, '(16,''UPDATE''::text)', '(16,''UPDATE''::text), (32,''TRUNCATE''::text)'), '(16, ''UPDATE''::text)', '(16, ''UPDATE''::text), (32, ''TRUNCATE''::text)') AS definition
         INTO trigger_def
         FROM pg_catalog.pg_views WHERE schemaname = 'information_schema' AND viewname = 'triggers';
         FOR r IN EXECUTE left(trigger_def.definition, -1) || ' AND t.tgname = (lower(' || quote_literal(source_table) || ') || ''_tss'')' LOOP
            -- BUG: Postgres 9.1 through 10 does not support TRUNCATE triggers in the triggers view.
            RAISE EXCEPTION 'Trigger already exist (%.%)', source_schema, (lower(source_table) || '_tss');
         END LOOP;
      ELSE
         -- Postgres 9.3's pg_views is broken and not compatible.
	     -- Let Postgres throw an error when trying to create this trigger.
      END IF;
   END IF;

   -- Create Shadow Table
   EXECUTE 'CREATE TABLE ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' AS SELECT *, current_user::name AS user_name, ''INSERT''::varchar AS action, now()::timestamp AS action_time FROM ' || quote_ident(source_schema) || '.' || quote_ident(source_table);

   -- Add Triggers     
   EXECUTE 'CREATE TRIGGER ' || lower(source_table) || '_tsr BEFORE INSERT OR UPDATE OR DELETE ON ' || quote_ident(source_schema) || '.' || quote_ident(source_table) || ' FOR EACH ROW EXECUTE PROCEDURE public.shadow(' || quote_literal(shadow_schema) || ', ' || quote_literal(shadow_table) || ')';

   EXECUTE 'CREATE TRIGGER ' || lower(source_table) || '_tss BEFORE TRUNCATE ON ' || quote_ident(source_schema) || '.' || quote_ident(source_table) || ' FOR EACH STATEMENT EXECUTE PROCEDURE public.shadow(' || quote_literal(shadow_schema) || ', ' || quote_literal(shadow_table) || ')';

   EXECUTE 'CREATE INDEX ON ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' USING btree (key, action_time DESC);';

   -- Only needed for Version 2 of the Shadow Tables
   EXECUTE 'CREATE INDEX ON ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' USING btree (action_time DESC) WHERE action = ''TRUNCATE'';';

END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;


-- Add Shadow Function - Version 2
CREATE OR REPLACE FUNCTION public.add_shadow (
   source_schema name,
   source_table name,
   shadow_schema name = NULL::name,
   shadow_table name = NULL::name
)
RETURNS void AS
$body$
DECLARE
   r RECORD;
   version RECORD;
   trigger_def RECORD;
BEGIN
IF source_schema IS NULL THEN
   RAISE EXCEPTION 'Must specify source schema: add_shadow(source_schema, source_table, shadow_schema, shadow_table)';
END IF;
IF source_table IS NULL THEN
   RAISE EXCEPTION 'Must specify source table: add_shadow(source_schema, source_table, shadow_schema, shadow_table)';
END IF;
IF shadow_schema IS NULL THEN
   shadow_schema := source_schema;
END IF;
IF shadow_table IS NULL THEN
   shadow_table := source_table || '_s';
END IF;
-- Check to see if source table already exists
SELECT table_schema, table_name INTO r FROM information_schema.tables WHERE table_schema = source_schema AND table_name = source_table;
IF NOT FOUND THEN
   RAISE EXCEPTION 'Source Table must exist (%.%)', source_schema, source_table;
END IF;
-- Check to see if shadow table already exists
SELECT table_schema, table_name INTO r FROM information_schema.tables WHERE table_schema = shadow_schema AND table_name = shadow_table;
IF FOUND THEN
   RAISE EXCEPTION 'Shadow Table already exist (%.%)', shadow_schema, shadow_table;
END IF;

-- Check to see if triggers already exist
-- Need to check the object source because the same trigger name may exist more than once in a schema if applied to different tables.
SELECT trigger_schema, trigger_name
   INTO r
   FROM information_schema.triggers
   WHERE trigger_schema = source_schema
      AND trigger_name = lower(source_table) || '_tsr'
      AND event_object_schema = source_schema
      AND event_object_table = source_table;
IF FOUND THEN
   RAISE EXCEPTION 'Trigger already exist (%.%)', source_schema, (lower(source_table) || '_tsr');
END IF;
SELECT trigger_schema, trigger_name
   INTO r
   FROM information_schema.triggers
   WHERE trigger_schema = source_schema
      AND trigger_name = lower(source_table) || '_tss'
      AND event_object_schema = source_schema
      AND event_object_table = source_table;
IF FOUND THEN
   -- BUG: Postgres 9.1 through 10 does not support TRUNCATE triggers in this view.
   RAISE EXCEPTION 'Trigger already exist (%.%)', source_schema, (lower(source_table) || '_tss');
END IF;

SELECT
   n.nspname::information_schema.sql_identifier AS trigger_schema,
   t.tgname::information_schema.sql_identifier AS trigger_name,
   n.nspname::information_schema.sql_identifier AS event_object_schema,
   c.relname::information_schema.sql_identifier AS event_object_table
INTO r
FROM
   pg_namespace n,
   pg_class c,
   pg_trigger t
WHERE
   n.oid = c.relnamespace
   AND c.oid = t.tgrelid
   AND NOT t.tgisinternal
   AND n.nspname = source_schema
   AND t.tgname = lower(source_table) || '_tss'
   AND n.nspname = source_schema
   AND c.relname = source_table;
IF FOUND THEN
   RAISE EXCEPTION 'Trigger already exist (%.%)', source_schema, (lower(source_table) || '_tss');
END IF;

-- Create Shadow Table
EXECUTE 'CREATE TABLE ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' AS SELECT *, current_user::name AS user_name, ''INSERT''::varchar AS action, now()::timestamp AS action_time FROM ' || quote_ident(source_schema) || '.' || quote_ident(source_table);
    
-- Add Triggers     
EXECUTE 'CREATE TRIGGER ' || lower(source_table) || '_tsr BEFORE INSERT OR UPDATE OR DELETE ON ' || quote_ident(source_schema) || '.' || quote_ident(source_table) || ' FOR EACH ROW EXECUTE PROCEDURE public.shadow(' || quote_literal(shadow_schema) || ', ' || quote_literal(shadow_table) || ')';

EXECUTE 'CREATE TRIGGER ' || lower(source_table) || '_tss BEFORE TRUNCATE ON ' || quote_ident(source_schema) || '.' || quote_ident(source_table) || ' FOR EACH STATEMENT EXECUTE PROCEDURE public.shadow(' || quote_literal(shadow_schema) || ', ' || quote_literal(shadow_table) || ')';

EXECUTE 'CREATE INDEX ON ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' USING btree (key, action_time DESC);';

EXECUTE 'CREATE INDEX ON ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' USING btree (action_time DESC) WHERE action = ''TRUNCATE'';';

END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;

-- Source Table public.table1
-- Shadow Table public.table2
SELECT add_shadow('public','table1','public','table2');

-- Source Table public.table1
-- Shadow Table public.table1_s
SELECT add_shadow('public','table1','public',null);
SELECT add_shadow('public','table1','public');

-- Source Table public.table1
-- Shadow Table public.table1_s
SELECT add_shadow('public','table1',null,null);
SELECT add_shadow('public','table1',null);
SELECT add_shadow('public','table1');

-- Drop previous triggers
DROP TRIGGER public.table1_tr;
DROP TRIGGER public.table1_tr1;

-- Remove previous test data
TRUNCATE table1, table2;

-- Triggers for Windows 10+
CREATE TRIGGER table2_tr
  AFTER INSERT
  ON public.table1
  REFERENCING NEW TABLE AS new_table
  FOR EACH STATEMENT
  EXECUTE PROCEDURE public.shadow();

CREATE TRIGGER table3_tr
  AFTER UPDATE
  ON public.table1
  REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
  FOR EACH STATEMENT
  EXECUTE PROCEDURE public.shadow();

CREATE TRIGGER table4_tr
  AFTER DELETE
  ON public.table1
  REFERENCING OLD TABLE AS old_table
  FOR EACH STATEMENT
  EXECUTE PROCEDURE public.shadow();

CREATE TRIGGER table1_tr
  BEFORE TRUNCATE
  ON public.table1
  FOR EACH STATEMENT
  EXECUTE PROCEDURE public.shadow();

-- New and improved Shadow Function - Version 1
CREATE OR REPLACE FUNCTION public.shadow ()
RETURNS trigger AS
$body$
DECLARE
   shadow_schema TEXT;
   shadow_table TEXT;
BEGIN
   IF (TG_NARGS <> 2) THEN
      RAISE EXCEPTION 'Incorrect number of arguments for shadow_function(schema, table): %', TG_NARGS;
   END IF;

   shadow_schema = TG_ARGV[0];
   shadow_table = TG_ARGV[1];
   IF TG_OP IN ('INSERT', 'UPDATE') AND TG_LEVEL = 'ROW' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING NEW, TG_OP;
      RETURN NEW;
   ELSIF TG_OP IN ('INSERT', 'UPDATE') AND TG_LEVEL = 'STATEMENT' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT n.*, current_user, $1 , now() FROM new_table n' USING TG_OP;
      RETURN NEW;
   ELSIF TG_OP = 'DELETE' AND TG_LEVEL = 'ROW' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING OLD, TG_OP;
      RETURN OLD;
   ELSIF TG_OP = 'DELETE' AND TG_LEVEL = 'STATEMENT' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT o.*, current_user, $1 , now() FROM old_table o' USING TG_OP;
      RETURN OLD;
   ELSIF TG_OP = 'TRUNCATE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT a.*, current_user, $1, now() FROM ' || quote_ident(TG_TABLE_SCHEMA) || '.' || quote_ident(TG_TABLE_NAME) || ' a' USING TG_OP;
      RETURN NULL;
   END IF;

END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;

-- New and improved Shadow Function - Version 2
CREATE OR REPLACE FUNCTION public.shadow ()
RETURNS trigger AS
$body$
DECLARE
   shadow_schema TEXT;
   shadow_table TEXT;
BEGIN
   IF (TG_NARGS <> 2) THEN
      RAISE EXCEPTION 'Incorrect number of arguments for shadow_function(schema, table): %', TG_NARGS;
   END IF;

   shadow_schema = TG_ARGV[0];
   shadow_table = TG_ARGV[1];
   IF TG_OP IN ('INSERT', 'UPDATE') AND TG_LEVEL = 'ROW' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING NEW, TG_OP;
      RETURN NEW;
   ELSIF TG_OP IN ('INSERT', 'UPDATE') AND TG_LEVEL = 'STATEMENT' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT n.*, current_user, $1 , now() FROM new_table n' USING TG_OP;
      RETURN NEW;
   ELSIF TG_OP = 'DELETE' AND TG_LEVEL = 'ROW' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING OLD, TG_OP;
      RETURN OLD;
   ELSIF TG_OP = 'DELETE' AND TG_LEVEL = 'STATEMENT' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' SELECT o.*, current_user, $1 , now() FROM old_table o' USING TG_OP;
      RETURN OLD;
   ELSIF TG_OP = 'TRUNCATE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' (user_name, action, action_time) VALUES (current_user, $1 , now())';
      RETURN NULL;
   END IF;
END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;

-- Find previously created row triggers and update them to statement.
DO
$$
DECLARE
	r RECORD;
BEGIN
	FOR r IN SELECT
		'DROP TRIGGER ' || quote_ident(pg_trigger.tgname) || ' ON ' || quote_ident(pg_namespace.nspname) || '.' || quote_ident(pg_class.relname) || ';' AS drop_trigger,
		'CREATE TRIGGER ' || quote_ident(pg_class.relname) || '_tsi AFTER INSERT ON ' || quote_ident(pg_namespace.nspname) || '.' || quote_ident(pg_class.relname) || ' REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE PROCEDURE ' || quote_ident(b.nspname) || '.' || quote_ident(pg_proc.proname) || '(' || quote_literal((string_to_array(encode(pg_trigger.tgargs, 'escape'),'\000'))[1]) || ',' || quote_literal((string_to_array(encode(pg_trigger.tgargs, 'escape'),'\000'))[2]) || ');' AS create_insert,
		'CREATE TRIGGER ' || quote_ident(pg_class.relname) || '_tsu AFTER UPDATE ON ' || quote_ident(pg_namespace.nspname) || '.' || quote_ident(pg_class.relname) || ' REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE PROCEDURE ' || quote_ident(b.nspname) || '.' || quote_ident(pg_proc.proname) || '(' || quote_literal((string_to_array(encode(pg_trigger.tgargs, 'escape'),'\000'))[1]) || ',' || quote_literal((string_to_array(encode(pg_trigger.tgargs, 'escape'),'\000'))[2]) || ');' AS create_update,
		'CREATE TRIGGER ' || quote_ident(pg_class.relname) || '_tsd AFTER DELETE ON ' || quote_ident(pg_namespace.nspname) || '.' || quote_ident(pg_class.relname) || ' REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE PROCEDURE ' || quote_ident(b.nspname) || '.' || quote_ident(pg_proc.proname) || '(' || quote_literal((string_to_array(encode(pg_trigger.tgargs, 'escape'),'\000'))[1]) || ',' || quote_literal((string_to_array(encode(pg_trigger.tgargs, 'escape'),'\000'))[2]) || ');' AS create_delete,
	    pg_namespace.nspname AS table_schema,
	    pg_class.relname AS table_name,
	    b.nspname AS function_schema,
	    pg_proc.proname AS function_name
	FROM pg_catalog.pg_trigger
	LEFT JOIN pg_catalog.pg_class ON pg_trigger.tgrelid = pg_class.oid
	LEFT JOIN pg_catalog.pg_namespace ON pg_class.relnamespace = pg_namespace.oid
	LEFT JOIN pg_catalog.pg_proc ON pg_trigger.tgfoid = pg_proc.oid
	LEFT JOIN pg_catalog.pg_namespace b ON pg_proc.pronamespace = b.oid
	WHERE tgisinternal = false
		AND b.nspname = 'public'
		AND pg_proc.proname = 'shadow'
		AND pg_trigger.tgname LIKE '%_tsr' LOOP
        EXECUTE r.drop_trigger;
        EXECUTE r.create_insert;
        EXECUTE r.create_update;
        EXECUTE r.create_delete;
    END LOOP;
END
$$;

-- Update add_shadow() function - Version 1 for Postgres 10+
CREATE OR REPLACE FUNCTION public.add_shadow (
   source_schema name,
   source_table name,
   shadow_schema name = NULL::name,
   shadow_table name = NULL::name
)
RETURNS void AS
$body$
DECLARE
   r RECORD;
   version RECORD;
   trigger_def RECORD;
BEGIN
   IF source_schema IS NULL THEN
      RAISE EXCEPTION 'Must specify source schema: add_shadow(source_schema, source_table, shadow_schema, shadow_table)';
   END IF;
   IF source_table IS NULL THEN
      RAISE EXCEPTION 'Must specify source table: add_shadow(source_schema, source_table, shadow_schema, shadow_table)';
   END IF;
   IF shadow_schema IS NULL THEN
      shadow_schema := source_schema;
   END IF;
   IF shadow_table IS NULL THEN
      shadow_table := source_table || '_s';
   END IF;

   -- Check to see if source table already exists
   SELECT table_schema, table_name INTO r FROM information_schema.tables WHERE table_schema = source_schema AND table_name = source_table;
   IF NOT FOUND THEN
      RAISE EXCEPTION 'Source Table must exist (%.%)', source_schema, source_table;
   END IF;
   -- Check to see if shadow table already exists
   SELECT table_schema, table_name INTO r FROM information_schema.tables WHERE table_schema = shadow_schema AND table_name = shadow_table;
   IF FOUND THEN
      RAISE EXCEPTION 'Shadow Table already exist (%.%)', shadow_schema, shadow_table;
   END IF;

   -- Check to see if triggers already exist
   -- Need to check the object source because the same trigger name may exist more than once in a schema if applied to different tables.
   SELECT trigger_schema, trigger_name
      INTO r
      FROM information_schema.triggers
      WHERE trigger_schema = source_schema
         AND trigger_name IN (lower(source_table) || '_tsr', lower(source_table) || '_tsr', lower(source_table) || '_tsr', lower(source_table) || '_tsr')
         AND event_object_schema = source_schema
         AND event_object_table = source_table;
   IF FOUND THEN
      RAISE EXCEPTION 'Trigger already exist (%.%)', r.trigger_schema, r.trigger_name;
   END IF;

   SELECT trigger_schema, trigger_name
      INTO r
      FROM information_schema.triggers
      WHERE trigger_schema = source_schema
         AND trigger_name = lower(source_table) || '_tss'
         AND event_object_schema = source_schema
         AND event_object_table = source_table;
   IF FOUND THEN
      -- BUG: Postgres 9.1 through 10 does not support TRUNCATE triggers in this view.
      RAISE EXCEPTION 'Trigger already exist (%.%)', source_schema, (lower(source_table) || '_tss');
   END IF;

   SELECT substr(setting,1,length(setting)-strpos(reverse(setting), '.')) AS version INTO version FROM pg_settings WHERE "name" = 'server_version';
   IF NOT FOUND THEN
      RAISE EXCEPTION 'Could not figure out the PostgreSQL version';
   ELSE
      IF version.version IN ('9.1', '9.2', '9.4', '9.5', '9.6', '10') THEN
         SELECT replace(replace(definition, '(16,''UPDATE''::text)', '(16,''UPDATE''::text), (32,''TRUNCATE''::text)'), '(16, ''UPDATE''::text)', '(16, ''UPDATE''::text), (32, ''TRUNCATE''::text)') AS definition
         INTO trigger_def
         FROM pg_catalog.pg_views WHERE schemaname = 'information_schema' AND viewname = 'triggers';
         FOR r IN EXECUTE left(trigger_def.definition, -1) || ' AND t.tgname = (lower(' || quote_literal(source_table) || ') || ''_tss'')' LOOP
            -- BUG: Postgres 9.1 through 10 does not support TRUNCATE triggers in the triggers view.
            RAISE EXCEPTION 'Trigger already exist (%.%)', source_schema, (lower(source_table) || '_tss');
         END LOOP;
      ELSE
         -- Postgres 9.3's pg_views is broken and not compatible.
	     -- Let Postgres throw an error when trying to create this trigger.
      END IF;
   END IF;

   -- Create Shadow Table
   EXECUTE 'CREATE TABLE ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' AS SELECT *, current_user::name AS user_name, ''INSERT''::varchar AS action, now()::timestamp AS action_time FROM ' || quote_ident(source_schema) || '.' || quote_ident(source_table);

   -- Add Triggers     
   EXECUTE 'CREATE TRIGGER ' || lower(source_table) || '_tsi AFTER INSERT ON ' || quote_ident(source_schema) || '.' || quote_ident(source_table) || ' REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE PROCEDURE public.shadow(' || quote_literal(shadow_schema) || ', ' || quote_literal(shadow_table) || ')';
   EXECUTE 'CREATE TRIGGER ' || lower(source_table) || '_tsu AFTER UPDATE ON ' || quote_ident(source_schema) || '.' || quote_ident(source_table) || ' REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE PROCEDURE public.shadow(' || quote_literal(shadow_schema) || ', ' || quote_literal(shadow_table) || ')';
   EXECUTE 'CREATE TRIGGER ' || lower(source_table) || '_tsd AFTER DELETE ON ' || quote_ident(source_schema) || '.' || quote_ident(source_table) || ' REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE PROCEDURE public.shadow(' || quote_literal(shadow_schema) || ', ' || quote_literal(shadow_table) || ')';

   EXECUTE 'CREATE TRIGGER ' || lower(source_table) || '_tss BEFORE TRUNCATE ON ' || quote_ident(source_schema) || '.' || quote_ident(source_table) || ' FOR EACH STATEMENT EXECUTE PROCEDURE public.shadow(' || quote_literal(shadow_schema) || ', ' || quote_literal(shadow_table) || ')';

   EXECUTE 'CREATE INDEX ON ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' USING btree (key, action_time DESC);';

   -- Only needed for Version 2 of the Shadow Tables
   EXECUTE 'CREATE INDEX ON ' || quote_ident(shadow_schema) || '.' || quote_ident(shadow_table) || ' USING btree (action_time DESC) WHERE action = ''TRUNCATE'';';

END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;


log_destination = 'csvlog'
log_directory = '/pgdata_local/pg_log'
log_min_duration_statement = '0'
log_hostname = 'true'
shared_preload_libraries = 'pgaudit,pg_stat_statements'          #pgaudit (change requires restart)
pgaudit.role = 'auditor'
pgaudit.log_catalog = 'false'
pgaudit.log_parameter = 'true'
pgaudit.log_relation = 'true'
pgaudit.log_statement_once = 'false'

CREATE EXTENSION pgaudit;

CREATE ROLE auditor NOINHERIT NOREPLICATION;

ALTER SYSTEM SET pgaudit.role TO 'auditor'; -- Log specific user role -- no default
ALTER SYSTEM SET pgaudit.log_catalog = false; -- Log system catalog -- default true
ALTER SYSTEM SET pgaudit.log_parameter = true; -- Log prepared statement parameters -- default false
ALTER SYSTEM SET pgaudit.log_relation = true; -- Log sub items, when looking at views/functions -- default false
ALTER SYSTEM SET pgaudit.log_statement_once = false; -- Hide sql on secondary rows -- default false

ALTER ROLE xapps SET pgaudit.log = 'none';
ALTER ROLE xapps SET pgaudit.role = '';

ALTER ROLE postgres SET pgaudit.log = 'none';
ALTER ROLE postgres SET pgaudit.role = '';

SET ROLE xapps;

CREATE TABLE account
(
    id INT,
    name TEXT,
    password TEXT,
    description TEXT
);

GRANT SELECT
   ON public.account
   TO auditor;

GRANT SELECT
   ON public.account
   TO delphi_hptn;

CREATE TABLE login
(
    id INT,
    account_id INT,
    login "timestamp",
    logout timestamp
);

CREATE VIEW user_login AS
SELECT a.id AS user_id, a.name, b.login, b.logout FROM public.account a LEFT JOIN public."login" b ON a.id = b.account_id;

GRANT SELECT
   ON public.user_login
   TO delphi_hptn;

CREATE FUNCTION public.function ()
RETURNS SETOF public.user_login AS
$body$
SELECT * FROM user_login;
$body$
LANGUAGE 'sql'
VOLATILE
CALLED ON NULL INPUT
SECURITY INVOKER;

GRANT EXECUTE
   ON FUNCTION public.function()
   TO delphi_hptn;

INSERT INTO account (id, name, password, description)
             VALUES (1, 'user1', 'HASH1', 'blah, blah');

INSERT INTO public."login" (id, account_id, login, logout)
             VALUES (1, 1, '2018-05-25 16:30', NULL);


SELECT * FROM account;
-- 2018-06-26 15:57:45 PDT [7188]: [20-1] user=postgres,db=sandbox LOG:  AUDIT: OBJECT,5,1,READ,SELECT,TABLE,public.account,SELECT * FROM account;,<none>

SELECT * FROM account;
-- 2018-06-26 15:58:03 PDT [7188]: [21-1] user=postgres,db=sandbox LOG:  AUDIT: OBJECT,6,1,READ,SELECT,TABLE,public.account,SELECT * FROM account;,<none>

-- Disconnect / Reconnect
SELECT * FROM account;
-- No pgaudit log



RESET ROLE;


/usr/local/apps/perl/perl-current/bin/perl \
/pgdata_local/pgaudit_analyze/bin/pgaudit_analyze_lloyd \
--port=5432 \
--log-file=/pgdata_local/pgaudit_analyze/log/pgaudit_analyze.log \
--user=postgres \
--socket-path=127.0.0.1 \
--log-server=sqltest-alt \
--log-database=pgaudit \
--log-port=5432 \
--log-from-server=sqltest-alt \
--daemon \
/pgdata_local/pg_log


SELECT * FROM sqltest-alt_sandbox.vw_audit_event;
