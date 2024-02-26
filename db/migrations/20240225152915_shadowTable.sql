-- migrate:up
-- Table 1
CREATE TABLE table1 (
	key SERIAL,
	value INTEGER,
	value_type VARCHAR,
	PRIMARY KEY (key)
);

-- Table 2
CREATE TABLE table2 (
	key SERIAL,
	value INTEGER,
	value_type VARCHAR,
	user_name NAME,
	action VARCHAR,
	action_time TIMESTAMP
);

-- CREATE FUNCTION shadow_table1 ()
-- RETURNS trigger AS
-- $body$
-- BEGIN
--    IF TG_OP = 'INSERT' THEN
--       INSERT INTO table2
--         VALUES((NEW).*, current_user, TG_OP, now());
--       RETURN NEW;
--     END IF;
--     IF TG_OP = 'UPDATE' THEN
--       INSERT INTO table2
--          VALUES((NEW).*, current_user, TG_OP, now());
--       RETURN NEW;
--     END IF;
--     IF TG_OP = 'DELETE' THEN
--       INSERT INTO table2
--          VALUES((OLD).*, current_user, TG_OP, now());
--       RETURN OLD;
--    END IF;
-- END;
-- $body$
-- LANGUAGE plpgsql
-- VOLATILE
-- CALLED ON NULL INPUT
-- SECURITY DEFINER;
-- SECURITY DEFINER specifies that the function is to be executed with the privileges of the user that owns it

-- CREATE TRIGGER table1_tr
-- BEFORE INSERT OR UPDATE OR DELETE
-- ON table1 FOR EACH ROW
-- EXECUTE PROCEDURE shadow_table1();


CREATE OR REPLACE FUNCTION shadow ()
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
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING NEW, TG_OP;
      RETURN NEW;
   ELSIF TG_OP = 'UPDATE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING NEW, TG_OP;
      RETURN NEW;
   ELSIF TG_OP = 'DELETE' THEN
      EXECUTE 'INSERT INTO ' || quote_ident(shadow_table) || ' SELECT $1.*, current_user, $2 , now()' USING OLD, TG_OP;
      RETURN OLD;
   ELSIF TG_OP = 'TRUNCATE' THEN
-- insert every row that was present
        -- EXECUTE 'INSERT INTO ' || quote_ident(shadow_table) || ' SELECT a.*, current_user, $1, now() FROM ' || quote_ident(TG_TABLE_NAME) || ' a' USING TG_OP;
-- insert just one row
        EXECUTE 'INSERT INTO ' || quote_ident(shadow_table) || ' (user_name, action, action_time) VALUES (current_user, $1 , now())' USING TG_OP;
      RETURN NULL;
   END IF;
END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY DEFINER;




CREATE TRIGGER table1_tr
BEFORE INSERT OR UPDATE OR DELETE
ON table1 FOR EACH ROW
EXECUTE PROCEDURE shadow('mydb', 'table2');

CREATE TRIGGER table1_tr1
BEFORE TRUNCATE
ON table1 FOR EACH STATEMENT
EXECUTE PROCEDURE shadow('mydb', 'table2');


INSERT INTO table1 (value, value_type) VALUES ('30', 'meters');
INSERT INTO table1 (value, value_type) VALUES ('10', 'inches');
UPDATE table1 SET value = '20' WHERE value_type = 'inches';
DELETE FROM table1 WHERE value_type = 'inches';
INSERT INTO table1 (value, value_type) VALUES ('50', 'inches');
TRUNCATE table1;
INSERT INTO table1 (value, value_type) VALUES ('50', 'inches');
DELETE FROM table1 WHERE value_type = 'inches';
INSERT INTO table1 (value, value_type) VALUES ('30', 'meters');



-- migrate:down
drop trigger table1_tr on table1;
drop trigger table1_tr1 on table1;
-- drop function shadow_table1;
drop function shadow;
drop table table1;
drop table table2;