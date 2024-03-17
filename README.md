- [postgresql-notes](#postgresql-notes)
  - [PostgreSQL Docker](#postgresql-docker)
  - [Info about function or trigger](#info-about-function-or-trigger)
  - [Explain Analyze Buffers Verbose](#explain-analyze-buffers-verbose)
  - [Listen JSON](#listen-json)
  - [Json with CTE](#json-with-cte)
  - [Constraints (citusdata)](#constraints-citusdata)
  - [Generate Series](#generate-series)
  - [Returning](#returning)
  - [Time Zone](#time-zone)
  - [Advanced Postgres Schema Design](#advanced-postgres-schema-design)
  - [Check item dependencies](#check-item-dependencies)
  - [Identifying Slow Queries and Fixing Them](#identifying-slow-queries-and-fixing-them)
  - [Window Functions](#window-functions)
  - [Index](#index)
  - [Constraints](#constraints)
  - [PL/pgSQL](#plpgsql)
    - [Function:](#function)
    - [Procedures:](#procedures)
    - [Records](#records)
    - [Cursors](#cursors)
    - [Table](#table)
    - [FOR](#for)
    - [ARRAY](#array)
    - [EXCEPTION](#exception)
  - [JSON](#json)
  - [Shadow table](#shadow-table)
  - [UPSERT](#upsert)
  - [Monitoring](#monitoring)
  - [pgexercises](#pgexercises)
  - [pg\_stat\_statements](#pg_stat_statements)
  - [Postgres basic types](#postgres-basic-types)
  - [Lateral Join](#lateral-join)
  - [Generated Columns](#generated-columns)
  - [Trigger](#trigger)
  - [Transaction](#transaction)
  - [CTE](#cte)
  - [Custom Operator](#custom-operator)
  - [Custom Cast](#custom-cast)
  - [Custom Aggregate](#custom-aggregate)
  - [Temporary Functions](#temporary-functions)
  - [Dynamic SQL](#dynamic-sql)
  - [Performance](#performance)
    - [OR clause](#or-clause)
    - [COUNT(\*)](#count)
    - [JOINS](#joins)
    - [GROUPING SETS, CUBE, ROLLUP](#grouping-sets-cube-rollup)
    - [GROUP BY](#group-by)
    - [SET OPERATIONS](#set-operations)
    - [FILTER](#filter)
    - [OFFSET](#offset)
    - [PARTITIONING](#partitioning)
    - [Flowchart](#flowchart)
  - [Extensions:](#extensions)
  - [Comments](#comments)
  - [Crypto](#crypto)
  - [Full Text Search](#full-text-search)
  - [Other](#other)

# postgresql-notes
Notes about PostgreSQL and Go

## PostgreSQL Docker

```bash
# make sd
systemctl start docker
# make pg
docker run --rm -it --name local-postgres -p 5432:5432 -e POSTGRES_PASSWORD=my-secret-pw -e POSTGRES_USER=root -e POSTGRES_DB=mydb -d postgres
```

Connection string:

**postgresql://root:my-secret-pw@localhost:5432/mydb?sslmode=disable**

```bash
# https://www.postgresql.org/docs/current/app-psql.html
psql -d postgresql://root:my-secret-pw@localhost:5432/mydb?sslmode=disable
```

Using [**dbmate**](https://github.com/amacneil/dbmate) for migrations:

```bash
# make up
dbmate up && docker exec local-postgres pg_dump mydb > ./db/schema.sql
# make down
dbmate down && docker exec local-postgres pg_dump mydb > ./db/schema.sql
```

```bash
# get info about the applied migration files status
dbmate status
```


## Info about function or trigger

```sql
SELECT proname, prosrc
FROM pg_proc
WHERE proname = 'notify_event';
```

```sql
SELECT tgname, pg_get_triggerdef(oid) AS trigger_definition
FROM pg_trigger
WHERE tgname = 'products_notify_event';
```

## Explain Analyze Buffers Verbose

For performance tuning:

```sql
start transaction;
explain (analyze, buffers, verbose)
-- insert your SQL query here
rollback;
```

explain analyze actually executes the query, so any update/delete/create will persist

Other tools with explain:

* https://explain.depesz.com/
* https://github.com/mgartner/pg_flame


## Listen JSON

Using PostgreSQL's LISTEN/NOTIFY feature with Go:

https://tapoueh.org/blog/2018/07/postgresql-listen/notify/

https://coussej.github.io/2015/09/15/Listening-to-generic-JSON-notifications-from-PostgreSQL-in-Go/

See [**SQL file**](./db/migrations/20240219182555_listenJSON.sql)

```bash
go run cmd/listenJSON/main.go
```

The trigger will notify the listeners on the 'events' channel on any insert, update and delete of the products table: the content of the message is a json payload.


```sql
insert into products values (1, 'my product name', 123);
insert into products values (2, 'your product name', 321);
update products set name = 'my new name';
delete from products;
```

Pro: doesn't require too much configuration if you are already using PostgreSQL. The triggered SQL function can also be handy to perform some other database operations like inserting in a events/log table.

Cons: only pub-sub (no queue) and might be harder to debug.


Postgres queue has a default size of 8GB and is where all NOTIFY command messages are stored, along with the PID of the sender.
Use `pg_listening_channels()` to get a list of listeners, `pg_notification_queue_usage()` to get a percentage of unprocessed messages.

Use **SELECT FOR UPDATE SKIP LOCKED** to lock the row of the task and to allow other transactions to skip the lock check.


## Json with CTE

https://tapoueh.org/blog/2018/01/exporting-a-hierarchy-in-json-with-recursive-queries/

See [**SQL file**](./db/migrations/20240221212444_jsonWithCTE.sql)

```bash
go run cmd/jsonWithCTE/!(*_test).go
```

Table:

```sql
create table dndclasses
 (
   id         int generated by default as identity primary key,
   parent_id  int references dndclasses(id),
   name       text
 );
```

CTE:

```sql
with recursive dndclasses_from_parents as
(
         -- Classes with no parent, our starting point
      select id, name, '{}'::int[] as parents, 0 as level
        from dndclasses
       where parent_id is NULL

   union all

         -- Recursively find sub-classes and append them to the result-set
      select c.id, c.name, parents || c.parent_id, level+1
        from      dndclasses_from_parents p
             join dndclasses c
               on c.parent_id = p.id
       where not c.id = any(parents)
),
    dndclasses_from_children as
(
         -- Now start from the leaf nodes and recurse to the top-level
         -- Leaf nodes are not parents (level > 0) and have no other row
         -- pointing to them as their parents, directly or indirectly
         -- (not id = any(parents))
     select c.parent_id,
            json_agg(jsonb_build_object('Name', c.name))::jsonb as js
       from dndclasses_from_parents tree
            join dndclasses c using(id)
      where level > 0 and not id = any(parents)
   group by c.parent_id

  union all

         -- build our JSON document, one piece at a time
         -- as we're traversing our graph from the leaf nodes,
         -- the bottom-up traversal makes it possible to accumulate
         -- sub-classes as JSON document parts that we glue together
     select c.parent_id,

               jsonb_build_object('Name', c.name)
            || jsonb_build_object('Sub Classes', js) as js

       from dndclasses_from_children tree
            join dndclasses c on c.id = tree.parent_id
)
-- Finally, the traversal being done, we can aggregate
-- the top-level classes all into the same JSON document,
-- an array.
-- select jsonb_pretty(jsonb_agg(js))
select jsonb_agg(js)
  from dndclasses_from_children
 where parent_id IS NULL;
```

Output:

```json
[{"Name": "Priest", "Sub Classes": [{"Name": "Cleric"}, {"Name": "Druid"}, {"Name": "Priest of specific mythos"}]}, {"Name": "Rogue", "Sub Classes": [{"Name": "Thief"}, {"Name": "Bard"}]}, {"Name": "Wizard", "Sub Classes": [{"Name": "Mage"}, {"Name": "Specialist wizard"}]}, {"Name": "Warrior", "Sub Classes": [{"Name": "Fighter"}, {"Name": "Paladin"}, {"Name": "Ranger"}]}, {"Name": "Rogue", "Sub Classes": {"Name": "Thief", "Sub Classes": [{"Name": "Assassin"}]}}]
```

Depending on the conditions, using SQL to process and filter the data can be more performant than fetching all the data and processing from the application side as it can avoid transfering too much data over the network.

In this case there are only 15 rows in the table and (at least compared to executing the previous query on a Docker contained PostgreSQL instance) processing everything from the go server ([**see code here**](./cmd/jsonWithCTE/server.go#L52)) seems faster (although more memory is used).

```bash
╰─ go test -bench=. ./cmd/jsonWithCTE -benchmem
goos: linux
goarch: amd64
pkg: github.com/Jiang-Gianni/postgresql-notes/cmd/jsonWithCTE
cpu: AMD Ryzen 5 5600G with Radeon Graphics
BenchmarkDatabase-12                1656            680454 ns/op           22450 B/op        185 allocs/op
BenchmarkApplication-12             2667            415754 ns/op           24268 B/op        262 allocs/op
PASS
ok      github.com/Jiang-Gianni/postgresql-notes/cmd/jsonWithCTE        2.365s
```


## Constraints (citusdata)

https://www.citusdata.com/blog/2018/03/19/postgres-database-constraints/

Check constraints can be set with refererence to other columns:

```sql
CREATE TABLE products (
    product_no integer,
    name text,
    price numeric CHECK (price > 0),
    sale_price numeric CHECK (sale_price > 0),
    CHECK (price > sale_price)
);
```

or even functions:

```sql
CREATE OR REPLACE FUNCTION is_fib(i int) RETURNS boolean AS $$
DECLARE
 a integer := 5*i*i+4;
 b integer := 5*i*i-4;
 asq integer;
 bsq integer;
BEGIN
IF i <= 0 THEN RETURN false; END IF;
 asq = sqrt(a)::int;
 bsq = sqrt(b)::int;
 RETURN asq*asq=a OR bsq*bsq=b;
end
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE TABLE onlyfib( i int CHECK (is_fib(i)) );
```

Exclusion:

```sql
CREATE TABLE billings_citus (
 id uuid NOT NULL,
 period tstzrange NOT NULL,
 price_per_month integer NOT NULL
);

ALTER TABLE billings_citus
ADD CONSTRAINT billings_excl
EXCLUDE USING gist (
 id WITH =,
 period WITH &&
);
```


## Generate Series

The Art of PostgreSQL (Chapter 13)

```sql
select date::date,
    extract('isodow' from date) as dow,
    to_char(date, 'dy') as day,
    extract('isoyear' from date) as "iso year",
    extract('week' from date) as week,
    extract('day' from
        (date + interval '2 month - 1 day')
    ) as feb,
    extract('year' from date) as year,
    extract('day' from
        (date + interval '2 month - 1 day')
    ) = 29 as leap
from generate_series(
    date '2000-01-01',
    date '2010-01-01',
    interval '1 year'
    ) as t(date);
```

https://www.postgresql.org/docs/current/sql-expressions.html

```sql
select
    count(*) as unfiltered,
    count(*) filter (where i < 5) as filtered
from generate_series(1,10) as s(i);

select array_agg(seq) filter (where mod(seq,2) = 0) from generate_series(0,10) t(seq);

select string_agg(seq::text, '-' order by seq) from generate_series(0,10) t(seq);

select percentile_cont(0.37) within group (order by seq*1.2) from generate_series(0,123) t(seq);

select seq from generate_series(3.2, 0.7, -0.3) t(seq);

select seq from generate_series(timestamp '2000-01-01 00:00', timestamp '2000-01-01 23:00', interval '1 hour') as t(seq);
select seq from generate_series(timestamp '2000-01-01 00:00', timestamp '2000-01-01 01:00', interval '1 minute') as t(seq);

select * from generate_series(1, 3) as a, generate_series(5, 7) as b; -- cross joins
select generate_series(1, 3) as a, generate_series(5, 7) as b; -- zips
```


## Returning

https://di.nmfay.com/postgres-vs-mysql

`returning` allows to use the inserted, updated and deleted data inside a single CTE, making it easier to reference the values

```sql
start transaction;
with
deleted_rows as (
    delete from dndclasses where id in (14,15) returning *
),
updated_rows as (
    update dndclasses a
    set name = concat(deleted_rows.name, ' has been deleted')
    from deleted_rows
    where a.id = deleted_rows.parent_id
    returning a.*
),
inserted_rows as(
    insert into dndclasses
    select updated_rows.id + 1234, updated_rows.id, 'Inserted Name' from updated_rows
    returning *
)
select * from deleted_rows
union all
select * from updated_rows
union all
select * from inserted_rows
;
rollback;
```

## Time Zone

https://tapoueh.org/blog/2018/04/postgresql-data-types-date-timestamp-and-time-zones/

Use timestamps WITH time zones (column type **timestamptz**): there no additional memory cost since PostgreSQL defaults to using bigint internally to store timestamps.

```sql
select pg_column_size(timestamp without time zone 'now'), pg_column_size(timestamp with time zone 'now');

select (now() at time zone 'asia/shanghai');

select name, abbrev, utc_offset, is_dst from pg_timezone_names;
```

## Advanced Postgres Schema Design

https://www.youtube.com/watch?v=lkWiyEe2RUQ

* use column type `uuid` instead of `text` since it requires less memory and it has some default checks
* order columns from largest to smallest in size to improve data aligment memory usage (like in C or in Go structs)

```sql
-- first byte is a boolean and is followed by 7 empty bytes because big int (next column) requires 8 bytes
-- (the memory location for datatype can't be random)
create table bad_aligment( a boolean, b bigint, c boolean, d bigint, e boolean, f bigint );

-- here it is even possible to add 5 trailing boolean columns without adding any extra disk space
create table good_aligment( b bigint, d bigint, e bigint, a boolean, c boolean, f boolean );

insert into bad_aligment select true, 1, false, 2, true, 1 from generate_series(1, 1000000);
insert into good_aligment select 2, 1, 1, true, false, true from generate_series(1, 1000000);

select
-- bad_aligment: [(1+7 {empty bytes} ) + 8] * 3 = 48
pg_size_pretty( pg_total_relation_size('bad_aligment') ),
-- good_aligment: [8 * 3] + 8 {because all 3 booleans are inside the same memory slice of 8 bytes } = 32
pg_size_pretty( pg_total_relation_size('good_aligment') )
;
-- 73 MB	57 MB: difference is 16 MB -> 1000000 bytes
```

* check constraints
```sql
create table person(
  name text not null,
  firstId bigint,
  secondId bigint
  -- Regexp
  constraint name_regexp check (name ~* '^[a-z][a-z0-9_]+[a-z0-9]$'),
  constraint exactly_one_id check ((firstId is null) != (secondId is null))
);
-- Error: pq: new row for relation "person" violates check constraint "name_regexp"
insert into person values ('1myName', 1, null);
-- Error: pq: new row for relation "person" violates check constraint "exactly_one_id"
insert into person values ('myName', null, null);
```

* array checks
```sql
create or replace function array_sort(anyarray)
  returns anyarray as
  $body$
    select array_agg(elem order by elem) from unnest($1) as elem;
  $body$
language sql immutable;

create table foo(
  some_array text[] not null,
  constraint only_one_dim
    check(array_ndims(some_array) = 1),
  constraint ordered
    check(some_array = array_sort(some_array))
);
-- Error: pq: new row for relation "foo" violates check constraint "only_one_dim"
insert into foo values  ('{{foo, bar}, {bar, bam}}'::text[]);
-- Error: pq: new row for relation "foo" violates check constraint "ordered"
insert into foo values  ('{foo, bar}'::text[]);
```
* partial index and include index (also called covering index)
```sql
-- Useful when selecting active rows
create index foo_idx_active on foo(bar_id) where active;
-- Useful when selecting only a, b and c where the condition is checked on a
create index foo_idx_include on foo(a) include (b, c);

create unique index foo_idx_lower on foo(lower(name)) where active;
```

## Check item dependencies

pg_class, pg_attribute, pg_constraint, pg_depend, pg_rewrite, pg_index, pg_trigger

[Information Schema](https://www.postgresql.org/docs/current/information-schema.html)


```sql
-- All the views that depend on the column columnName of the table tableName
SELECT v.oid::regclass AS view
FROM pg_attribute AS a   -- columns for the table
   JOIN pg_depend AS d   -- objects that depend on the column
      ON d.refobjsubid = a.attnum AND d.refobjid = a.attrelid
   JOIN pg_rewrite AS r  -- rules depending on the column
      ON r.oid = d.objid
   JOIN pg_class AS v    -- views for the rules
      ON v.oid = r.ev_class
WHERE v.relkind = 'v'    -- only interested in views
  -- dependency must be a rule depending on a relation
  AND d.classid = 'pg_rewrite'::regclass
  AND d.refclassid = 'pg_class'::regclass
  AND d.deptype = 'n'    -- normal dependency
  AND a.attrelid = 'tableName'::regclass
  AND a.attname = 'columnName';
```


## Identifying Slow Queries and Fixing Them

https://www.youtube.com/watch?v=_waM0GsH4HY

https://www.postgresql.org/docs/current/sql-prepare.html

* **DELETE with FOREIGN KEY**: a delete on the parent table will cause a scan on the child table to check the constraint, so an index on the referring side is recommended

* **prepare statement**

*A prepared statement is a server-side object that can be used to optimize performance.*

*Prepared statements only last for the duration of the current database session*

*Prepared statements potentially have the largest performance advantage when a single session is being used to execute a large number of similar statements.*

```sql
prepare stmt(int) as select * from dndclasses where id = $1;
execute stmt(2);
explain (analyze, verbose, buffers, format json) execute stmt(13);
deallocate stmt;
```

* **select * from table**: large values over 2K are stored out of line in a side table and requires more time to pull back

* **select distinct * from a, b, c where a.x = b.x**: check if an extra join would yield the same result because distinct implies sort and unique operations (and prefer using join syntax over comma join)

* **select * from x where myid in (select myid from bigtable)**: a join can be more performant and allow for more options (large value set for a in list is parsed slower than an array)

* **select * from x where myid not in (select myid from bigtable)**: better to use a left join or NOT EXISTS

* **index**: check the explain analysis that the query uses the (partial) index. Drop any unused index.

```sql
UPDATE pg_index SET indisvalid = false WHERE indexrelid::regclass::text IN ( < Unused indexes > )
```


## Window Functions

https://www.youtube.com/watch?v=D8Q4n6YXdpk

https://www.youtube.com/watch?v=blHEnrYwySE

https://gist.github.com/IllusiveMilkman/70c319d60756b78dc11366ffdb5127b3

https://www.postgresql.org/docs/current/functions-window.html

https://learnsql.com/blog/sql-window-functions-cheat-sheet/

```sql
select
*,
count(*) over() as total,
count(*) over(partition by dept_name) as dept_total,
max(salary_amt) over(partition by dept_name) as max_dept_salary,
avg(salary_amt) over(partition by dept_name)::decimal(8,2) as avg_dept_salary,
sum(salary_amt) over(partition by dept_name)::decimal(8,2) as tot_dept_salary,
sum(case when mod(emp_no, 2) = 0 then 1 else 0 end) over(partition by dept_name) as custom
from Payroll
-- where dept_name = 'IT'
;

select
*,
count(*) over() as total,
count(*) over(partition by dept_name) as dept_total,
max(salary_amt) over(partition by dept_name) as max_dept_salary,
-- use alias window w
avg(salary_amt) over w ::decimal(8,2) as avg_dept_salary,
sum(salary_amt) over w ::decimal(8,2)  as tot_dept_salary,
sum(case when mod(emp_no, 2) = 0 then 1 else 0 end) over(partition by dept_name) as custom
from Payroll
-- define w window here
window w as (partition by dept_name)
-- where dept_name = 'IT'
;
```

```sql
SELECT
	*,
	(salary_amt / (SUM(salary_amt) OVER (PARTITION BY dept_name)) * 100)::DECIMAL(18,2) AS Dept_Percentage,
	(salary_amt / (SUM(salary_amt) OVER () ) * 100)::DECIMAL(18,2) AS Company_Percentage
FROM Payroll
ORDER BY dept_name, dept_percentage;
```


```sql
SELECT
	*,
	-- Note the difference between row_number and the emp_no in terms of when it was captured.
	ROW_NUMBER() OVER () AS "Base Row No",
	-- No Partition, just an ORDER BY, thus the whole base resultset is used.
	ROW_NUMBER() OVER (ORDER BY salary_amt) AS "Salary Row No",
	-- Order each partition first, then assign row numbers.
	ROW_NUMBER() OVER (PARTITION BY dept_name ORDER BY salary_amt) AS "Dept,Salary Row No"
FROM Payroll
ORDER BY emp_no;
```

**ROW_NUMBER**: one distinct number for each row

**RANK**: duplicates number if same rank, skipping the next number(s) in line

**DENSE_RANK**: duplicates number if same rank, no skipping

```sql
SELECT 	*,
	-- Row_Number assigns a unique integer to each row within your partition within your window.
	ROW_NUMBER() OVER (),							-- Note the difference between row_number and the emp_no in terms of when it was captured.
	ROW_NUMBER() OVER (ORDER BY salary_amt),				-- No Partition, just an ORDER BY, thus the whole base resultset is used.
	ROW_NUMBER() OVER (PARTITION BY dept_name),
	ROW_NUMBER() OVER (PARTITION BY dept_name ORDER BY salary_amt),

	-- Ranks --> Equal values are ranked the same, creating gaps in numbering
	RANK() OVER (),								-- Ranks are useless without an ORDER BY
	RANK() OVER (PARTITION BY dept_name),
	RANK() OVER (ORDER BY salary_amt),
	RANK() OVER (PARTITION BY dept_name ORDER BY salary_amt),

	-- Dense_Ranks --> Equal values are ranked the same, without gaps in numbering
	DENSE_RANK() OVER (),
	DENSE_RANK() OVER (PARTITION BY dept_name),
	DENSE_RANK() OVER (ORDER BY salary_amt),
	DENSE_RANK() OVER (PARTITION BY dept_name ORDER BY salary_amt)
FROM  	Payroll
ORDER BY emp_no
;
```

```sql
-- Top 2 earners by department
-- ROW_NUMBER only takes 2 excluding other earners with same salary
-- RANK skip dept_rank = 2 if there are 2 ore more earners in first spot
WITH 	ctePayroll AS (
	SELECT 	*,
		DENSE_RANK() OVER (PARTITION BY dept_name ORDER BY salary_amt DESC) AS dept_rank
	FROM 	Payroll
	)
-- Window function wrapped in a CTE to apply WHERE dept_rank <= 2
SELECT 	*
FROM 	ctePayroll
WHERE 	dept_rank <= 2
--ORDER BY dept_rank		--> Note how we can order based on CTE name, cannot do this without CTE
;
```

**LAG**: previous row

**LEAD**: next row

FIRST_VALUE (column) OVER (...)

LAST_VALUE (column) OVER (...)

```sql
SELECT 	emp_no,
		dept_name,
		emp_name,
		LEAD(emp_name) 	OVER (PARTITION BY dept_name ORDER BY emp_no) AS "Next Employee",
		LAG(emp_name) 	OVER (PARTITION BY dept_name ORDER BY emp_no) AS "Previous Employee",
	  LAG(emp_name, 2) OVER (PARTITION BY dept_name ORDER BY emp_no) AS "Previous Offset 2",
	  LAG(emp_name, 2, 'nada...') OVER (PARTITION BY dept_name ORDER BY emp_no) AS "Previous Offset 2 with Defaults"
FROM 	Payroll
ORDER BY emp_no;
```

```sql
SELECT 	*,
	FIRST_VALUE(emp_name) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC) AS "Higest Earner",
	MAX(salary_amt) 			OVER (PARTITION BY dept_name ORDER BY salary_amt DESC) AS "Highest Salary",

	LAST_VALUE(emp_name) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC) AS "Lowest Earner",  --> Notice how LAST and MIN move with Window Frame
	MIN(salary_amt) 			OVER (PARTITION BY dept_name ORDER BY salary_amt DESC) AS "Lowest Salary",

	LAST_VALUE(emp_name) 	OVER (PARTITION BY dept_name) AS "Lowest Earner for real",
	MIN(salary_amt)			OVER (PARTITION BY dept_name) "Lowest Salary for real"
FROM 	Payroll
ORDER BY dept_name, salary_amt DESC
;
```

**(ROWS / RANGE) BETWEEN (UNBOUNDED PRECEDING / CURRENT ROW / N PRECEDING) AND (CURRENT ROW / UNBOUNDED FOLLOWING / N FOLLOWING) EXCLUDE (CURRENT ROW / GROUP / TIES NO OTHERS)**

ROWS is default for PARTITION BY

RANGE is default for ORDER BY (within the Partition): **if there is no ORDER BY then RANGE considers the entire group**

**if in RANGE mode and with ORDER BY then the CURRENT ROW also contain all the other previous/next rows that share the same value of the ORDER BY column**


**PRECEDING** and **FOLLOWING** can also use intervals (if same data type as ORDER BY column):

```sql
SELECT *, array_agg(points) OVER (ORDER BY d RANGE BETWEEN '6 months' PRECEDING AND CURRENT ROW);
```

```sql
SELECT 	*,
	LAST_VALUE(emp_name) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC) AS "Default lv",
	LAST_VALUE(emp_name) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC
							RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "lv range up cr",  --> So ORDER BY default is RANGE

	LAST_VALUE(emp_name) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC
							ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "lv rows up cr", --> Overriding default behaviour here

	LAST_VALUE(emp_name) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC
							ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS "lv cr uf",

	LAST_VALUE(emp_name) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC
							ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS "lv up uf",

	FIRST_VALUE(emp_name) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC
							ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS "fv up uf"
FROM 	Payroll
;
```

```sql
SELECT *,
	SUM(salary_amt) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC
							RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "sum range up cr",
	SUM(salary_amt) 	OVER (PARTITION BY dept_name ORDER BY salary_amt DESC
							ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "sum rows up cr"
FROM Payroll
;
```

Checklist:

* Split the set? **PARTITION BY**
* Order inside the partition? **ORDER BY**
* Same ORDER BY values? (RANGE vs ROW) and (RANK vs DENSE_RANK)
* Check window default

| Scope     | Type        | Function                                     | Description                                    |
| --------- | ----------- | -------------------------------------------- | ---------------------------------------------- |
| frame     | computation | generic aggs                                 | ex: SUM, AVG                                   |
| frame     | row access  | FIRST/LAST/NTH _VALUE                        | (first/last/nth) frame value                   |
| partition | row access  | LAG/LEAD/ROW_NUMBER                          | row (before/after) current, current row number |
| partition | ranking     | CUME_DIST/DENSE_RANK/NTILE/PERCENT_RANK/RANK | ...                                            |

If no PARTITION BY is defined then the partition is the entire set


## Index

https://www.youtube.com/watch?v=HAn1xu6_SW0

https://www.youtube.com/watch?v=Mni_1yTaNbE

https://www.postgresql.org/docs/current/sql-alterindex.html

* B-tree (Balanced Tree, the most used):
  * Supports <, <=, =, >=, >, IN, BETWEEN, IS NULL, IS NOT NULL.
  * LIKE and ~ only if regexp is constant with an anchored start (LIKE 'foo%').
  * ILIKE and ~* (case insensiteve) only if the first letter is not a letter (case sensitivity doesn't matter).

* GIN (Generalized Inverted Index)
  * good for columns with multiple values (array, jsonb, tsvector, range types)
  * contains an inde entry for each value and test the presence for specific value
  * useful for text search (pg_trgm extension), slower to build (and more memory) but faster to use
  * Supports <@, @>, =, &&, ?, ?&, ?|, @>, @@, @@@

* GiST (Generalized Search Tree)
  * for rows with overlapping values
  * best for geometry

* SP-GiST (Spaced Partitioned GiST)
  * for larger data wih natural clustering (telephone number, IP addresses)

* BRIN (Blocked range index)
  * for orded data (it fetches the blocks that may potentially contain the searched value)

* Hash
  * only if you use = operator


```sql
-- Sigle column index
-- will default to btree
create index name on myTable (col1);
create index name on myTable using hash (col1);

-- Multi column index: the db will concatenate the values
-- still used if the first specified columns (in order) are used:
-- "select * from myTable where col1 = 'A'"
-- not used in case if only col2
-- "select * from myTable where col2 = 'A'"
create index name on myTable (col1, col2);
-- Compound for sorting to match the order by
create index name on myTable (col1 asc, col2 desc);
-- In general, an index on (X,Y,Z) will be used for searches on X, (X,Y), and (X,Y,Z) and even (X,Z) but not on Y alone and not on YZ
-- Index only scan (no table access) if only columns X, Y, Z are retrieved from the select statement. The first column X is mandatory
-- Index order matters, declare column used for equality first, then the others used for ranges to prevent multiple index scans
-- Compound indexes can be used to also be able to index NULL like any value by adding the constant as the second index column
create index name on myTable (nullableColumn, 1);

-- Partial index and index on expression (must be IMMUTABLE)
-- great if the where clause matches the select query
create index name on myTable (col1) where col2 > 100;
create index name on myTable (lower(col1));

-- Only btree
create unique index name on myTable (col1);

-- Doesn't lock the table. Marks the index as invalid until completion
create index concurrently name on myTable (col1);

-- To add an index that helps with 'like' conditions
create index frequent_fl_last_name_lower_pattern on frequent_flyer (lower(last_name) text_pattern_ops);
```

Index can also be applied to [Generated Columns](#generated-columns)

After altering a table and adding an expression based index, launch:

```sql
analyze yourTableName;
```

so that Postgres collects statistics about the contents of the table to make a better evaluations (with the new index) of the query plans.


A Unique constraints will create a unique index. The difference is that unique index can have where clause. Use unique index only in case of partial index with where clause (**don't create both**).

```sql
-- Add constraint concurrently without locking the table
create index concurrently ix_name on myTable (col1);
alter table myTable add unique constraint un_name using index ix_name;
```

Foreign key constraints do not create any index automatically: consider adding an index to improve DELETE and UPDATE performance (avoid sequentially scan of the related table).

Single column index is used when retrieving only that column or when sorting by that column.

Careful when adding an index for sorting (see https://www.cybertec-postgresql.com/en/index-decreases-select-performance/)

```sql
create index name on myTable (col1);
-- Scan the index without reading other columns
select col1 from myTable;
-- order by only works with btree
select * from myTable order by col1 asc;
```

Check the where clause:

```sql
-- does not use index on sale_date
select * from sales where now() > sale_date + INTERVAL 30 DAY;
-- uses index on sale_date because right side is constant
select * from sales where sale_date < now() - INTERVAL 30 DAY;
```

```sql
-- idx_tup_read, idx_tup_fetch: if zero then the index is unused
select * from pg_stat_user_indexes;
select * from pg_stat_user_tables;
```

PostgreSQL decide to execute a specific plan based on cost. Some of the affected parameter can be found in :
```sql
-- most_common_vals, histogram_bounds
select * from pg_stats;
```

For materialized views it can be beneficial to break a long view select into chunks of smaller views and add an index to each of them in order to speed up all the joins.

https://gajus.medium.com/lessons-learned-scaling-postgresql-database-to-1-2bn-records-month-edc5449b3067



Cluster:

```sql
CLUSTER table_name USING index_name;
ANALYZE table_name;
```


If there is an index on a timestamp column and there is a need to extract values for a single date then it can be more performant to use a range comparison instead of casting the timestamp to a date:

```sql
-- may not use the index
where my_tmstmp::date = '2024-03-10'
-- will use the index
where my_tmstmp >= '2024-03-10' and my_tmstmp < '2024-03-11'
```


## Constraints

https://www.youtube.com/watch?v=s1MYgLFhs-o

* primary key:
  * **it generates a unique index**
  * limited to one (single or multiple composite columns), cannot be NULL
  * create table products (id serial primary key, name varchar(20), price numeric(7,2));
  * create table products (id int, name varchar(20), price numeric(7,2), primary key(id, name));

* NOT NULL:
  * alter table products alter price set not null;

* check:
  * alter table products add constraint positive_price check (price > 0);

* unique:
  * **it generates a unique index**
  * alter table products add constraint unique_name unique (name);
  * duplicate NULL values are accepted

* foreign key:
  * add constraint constraint_name foreign key(col_name) references parent_table(col_name);

* exclusion:
  * **it generates an index**
  * ensures that if any two rows are compared on the specified columns/expressions/operators then at least one of the comparisons will return false or null
  * create table b (p period);
  * alter table b add exclude using gist (p with &&);
  * insert into b values ('[2009-01-05, 2009-01-10]');
  * insert into b values ('[2009-01-07, 2009-01-12]'); -> causes error

* constraint on jsonb field:
  * create table jsontable (j json not null);
  * create unique index j_uuid_idx on jsontable(((j->>'uuid')::uuid));
  * alter table jsontable add constraint uuid_must_exists check(j?'uuid');

* constraint triggers (see https://www.postgresql.org/docs/9.0/sql-createconstraint.html)


## PL/pgSQL

https://www.youtube.com/watch?v=7nCCN6OE9iA

https://www.youtube.com/watch?v=VqW_l5JNbpQ

https://www.postgresql.org/docs/current/plpgsql.html

https://www.postgresql.org/docs/current/plpgsql-control-structures.html

https://www.postgresql.org/docs/current/errcodes-appendix.html

https://www.postgresql.org/docs/current/plpgsql-statements.html

### Function:
* VOLATILE: can return different output given the same inputs within the same transaction (can't be optimized by Postgres)
* STABLE: will return the same output given the same inputs within the same transaction
* IMMUTABLE: will return the same output given the same inputs
* (usually) have return values (scalar like int, text, varchar or composite like row {fixed structure}, record {not fixed structure} or void return or declared as function parameters)
* single transaction
* can be executed with select
* RETURNS TABLE (column_name column_type, ...) can be used to define the output structure

```sql
create or replace function <function_name>
returns table (col1 type, col2...) as $$
begin
 return query <your select query>;
end;
$$ language plpgsql;
```

* RETURNS SETOF to return multiple rows. Each of which can have different columns.

```sql
create or replace function <function_name>
returns setof <table> as $$
begin
 return query <your select query>;
end;
$$ language plpgsql;
```

* OUT (and INOUT for input+output) can be used to define the output. Use SELECT INTO to set the value. Cannot return multiple rows.

```sql
create or replace function <function_name>(out <parameter> integer)
as $$
begin
 select <col> into <parameter> from <table>;
end;
$$ language plpgsql;
```
```sql
-- A list of out parameters can also be defined
create or replace function public.testout(out p_output1 integer, out p_output2 text)
returns setof record language plpgsql as $function$
declare
 v_rec record;
begin
 for v_rec in (select generate_series(1, 10) i, 'abcd' a ) loop
    p_output1 := v_rec.i;
    p_output2 := v_rec.a;
    return next;
 end loop;
 return;
end;
$function$;
```

* can be executed with named notation (parameters order can be changed) or mixed but cannot be used with aggregate functions:
  * select concat_lower_or_upper(a => 'Hello', b => 'World', uppercase => true);
  * select concat_lower_or_upper(a := 'Hello', b := 'World', uppercase := true);
* [RETURN NEXT and RETURN QUERY](https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-STATEMENTS-RETURNING-RETURN-NEXT) (only if declared RETURNS SETOF sometype)
  * they both append the value to the result
  * still must call RETURN to exit the function
  * RETURN NEXT is used to build up the return value by adding the next row of a set. This way a single row is returned at a time instead of the entire set at once. Example: FOR r IN (SELECT ...) LOOP RETURN NEXT r; END LOOP; RETURN;
  * RETURN QUERY example: RETURN QUERY SELECT ...; RETURN;

```sql
-- Can also return the results of multiple queries
-- Output: 1,2,3,4,5,2
create or replace function public.test_multiple()
returns setof integer
language plpgsql
as $function$
begin
 return query select generate_series(1,5);
 return query select 2;
 return;
end;
$function$;
```

* function overloading: you can define multiple function with the same name and different in-out signature (can be ambigous with variadic inputs)


```sql
-- amorphous type return record
create or replace function testfoo (in int, inout int, out int) returns record as
$$ values ($2, $1 * $2) $$ language sql;

-- column1 :3     column2:42
select * from testfoo(14,3);

-- testfoo: (3,42)
select testfoo(14,3);
```

```sql
create or replace function testfoo (in a int, inout mult int = 2, out a int) returns record as
$$ values (mult, a * mult) $$ language sql;

-- Same result as before
select * from testfoo(mult:= 3, a:= 14);
select * from testfoo(mult=> 3, a=> 14);

-- testfoo: (2,28) -> mult has default 2
select testfoo(a:= 14);
```

```sql
-- argtype can reference a table column with: table_name.column_name%TYPE
-- polymorphic pseudotypes: anyelement, anyarray, anynonarray, anyenum, anyrange
create or replace function testfoo (inout a anyelement, inout mult anyelement) returns record as
$$ values (a * mult,mult) $$ language sql;

-- testfoo: (8.5353992,3.14)
select testfoo(mult:= 3.14, a:= 2.71828);
```

```sql
-- no returns clause -> can't return multiple rows
create or replace function testbar1(out f1 int, out f2 text) as
$$ values (42, 'hello'), (64, 'world') $$ language sql;
-- testbar1: (42,hello)
select testbar1();

-- With returns setof record
create or replace function testbar2(out f1 int, out f2 text) returns setof record as
$$ values (42, 'hello'), (64, 'world') $$ language sql;
-- testbar2: (42,hello), (64,world)
select testbar2();

-- With custom type
create type testbar3_type as (f1 int, f2 text);
create or replace function testbar3() returns setof testbar3_type as
$$ values (42, 'hello'), (64, 'world') $$ language sql;
-- testbar3: (42,hello), (64,world)
select testbar3();

-- With table
create or replace function testbar4() returns table (f1 int, f2 text) as
$$ values (42, 'hello'), (64, 'world') $$ language sql;
-- testbar4: (42,hello), (64,world)
select testbar4();

-- No specification
create or replace function testbar5() returns setof record as
$$ values (42, 'hello'), (64, 'world') $$ language sql;
-- testbar5: (42,hello), (64,world)
select testbar5();
-- you need to specify the columns type and names in a select *
select * from testbar5() as t(f1 int, f2 text);
select * from testbar5() t(f1 int, f2 text);
```

* RETURNS NULL ON NULL INPUT: more efficient since it skips the function call

```sql
create or replace function sum1 (int, int) returns int as
$$ select $1 + $2 $$ language sql returns null on null input;

create or replace function sum2 (int, int) returns int as
$$ select coalesce($1, 0) + coalesce($2, 0) $$ language sql called on null input;
```

* To alter Postgres Query Planning:
```sql
alter function your_function(int) cost 9001;
```

* Functions can worsen performance because they can't be optimized by the query planner

### Procedures:
* no return value (but technically if it has an INOUT parameter it can modify that input variable)
* **can manage multiple transactions**
* executed with CALL


### Records

```sql
-- ///
declare
  my_record my_table%ROWTYPE;
begin
  select * into my_record from myT_table where id = 1;
  my_record.my_column := 'my_value';
  update my_table set my_column = my_record.my_column where id = 2;
end;
```


### Cursors

https://www.postgresql.org/docs/current/plpgsql-cursors.html

Great for fetching only a small set of rows at each time, process them and fetch the next set.

```sql
-- ///
declare
  my_cursor refcursor;
  my_record my_table%ROWTYPE;
  my_scroll_cursor scroll cursor;
begin
  open my_cursor for select * from my_table;
  -- my_record -> first row
  fetch my_cursor into my_record;
  -- my_record -> second row (= next row)
  fetch my_cursor into my_record;
  if found then
    raise notice 'row found.';
  else
    raise notice 'no rows found.';
  end if;
  -- move forward all to hold all the row
  move forward all from my_cursor;
  get diagnostics num_rows = row_count;
  close my_cursor;
end;
```

Cursor attributes:

* ISOPEN
* FOUND: true if the last operation on the cursor found a row
* NOTFOUND
* ROWCOUNT: processed row count by the last FETCH or MOVE statement

Cursors are automatically closed after the transaction end or an exception is raised.

```sql
-- open cursors
select * from pg_cursors;
```

FOR LOOP creates an implicit cursor

SCROLL CURSOR allows to both MOVE BACKWARD and FETCH NEXT and should only be used only to read. NO SCRULL CURSOR to block the backward move

WITH HOLD cursors will persist the data and the pointer even after the transaction end. Great for dashboard/table data.

```sql
DECLARE cur CURSOR WITH HOLD FOR select * from scroll_test;
fetch forward 10 from cur;
fetch forward 10 from cur;
fetch backward 10 from cur;
```

REFCURSOR can be passed around the function calls


```sql
CREATE FUNCTION myfunc(refcursor, refcursor) RETURNS SETOF refcursor AS $$
BEGIN
OPEN $1 FOR SELECT * FROM table_1;
RETURN NEXT $1;
OPEN $2 FOR SELECT * FROM table_2;
RETURN NEXT $2;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION myfunc2(cur1 refcursor, cur2 refcursor)
RETURNS VOID AS $$
BEGIN
OPEN cur1 FOR SELECT * FROM table_1;
OPEN cur2 FOR SELECT * FROM table_2;
END;
$$ LANGUAGE plpgsql;
```


### Table

```sql
CREATE OR REPLACE FUNCTION get_top_selling_products(p_month INTEGER)
RETURNS TABLE (product_id INTEGER, total_sales NUMERIC) AS $$
DECLARE
 product_ids INTEGER[] := (SELECT ARRAY_AGG(DISTINCT sales.product_id)
FROM sales WHERE EXTRACT(MONTH FROM sale_date) = p_month);
BEGIN
 RETURN QUERY SELECT s.product_id, SUM(s.price * s.quantity) AS total_
sales FROM sales s WHERE s.product_id = ANY(product_ids) GROUP BY
s.product_id ORDER BY total_sales DESC LIMIT 10;
END;
$$ LANGUAGE plpgsql;
```


**IF/ELSEIF/CASE WHEN statement conditions do not short circuit**

EXECUTE INTO:

```sql
EXECUTE 'SELECT count(*) FROM mytable WHERE inserted_by = $1 AND inserted <= $2'
   INTO c
   USING checked_user, checked_date;
```

CASE without an ELSE branch will throw a CASE_NOT_FOUND if there is no match

### FOR
* FOR i IN 1..10 LOOP (...) END LOOP; -> 1,2,3...10
* FOR i IN REVERSE 10...1 LOOP (...) END LOOP; -> 10,9,8...1
* FOR i IN REVERSE 10...1 BY 2 LOOP (...) END LOOP; -> 10,8,6,4,2
* FOR r IN query LOOP (...) END LOOP; -> query must return rows
* FOR r IN EXECUTE textExpression LOOP (...) END LOOP; -> textExpression is a prepared statement
* FOREACH x SLICE 1 IN ARRAY $1 LOOP (...) END LOOP; -> SLICE indicates the dimension of the loop in which array is traversed. If not defined then the elements are traversed in storage order. **IMPORTANT**: if the ARRAY of the FOREACH statement is NULL then an exception will be thrown


### ARRAY

First element is index 1 but it is possible to explicity assign a value to the index 0 and to negative indices.

Useful functions:
* array_length(your_array, n): length of your_array at depth n (n=1 for the length of the entire array). The array is calculated based on the upper and lower bound of the array which means that if a value is explicitly assigned at an index greater than the size of the original array then the upper bound will grow (and so will the length): the gaps are filled with NULLs
* unnest(ARRAY['ONE', 'TWO', 'THREE'])
```sql
SELECT * FROM unnest(ARRAY['ONE', 'TWO', 'THREE']) AS arr_element;
```
* ||: used to append values. Example: v_dup:= v_dup||v_arr[idx];
* v_arr:= array_append(v_arr, 'FOUR'); // works like ||
* array_cat(v_arr1, v_arr2); // merge two arrays


### EXCEPTION

```sql
-- rows impacted by last statement
GET DIAGNOSTICS <variable> = ROW_COUNT;
-- last statement's context. Gives the call stack where GET DIAGNOSTICS was executed from
GET DIAGNOSTICS <variable> = PG_CONTEXT;
-- true if last statement returned any row
FOUND
```

EXCEPTION handling block: only use them when needed because they are expensive to enter and exit

```sql
BEGIN
  -- statements
EXCEPTION
-- SQLSTATE SQLERR
-- GET STACKED DIAGNOSTICS
-- https://www.postgresql.org/docs/current/plpgsql-statements.html
  -- WHEN condition THEN handler_statements
END
```

```sql
BEGIN
 -- code block
  IF condition THEN
    RAISE EXCEPTION USING MESSAGE='This is error message', DETAIL='These are the details about this error', HINT='Hint message which may fix this error',ERRCODE='P1234';
    RETURN FALSE;
  END IF;
 RETURN TRUE;
EXCEPTION
-- https://www.postgresql.org/docs/current/errcodes-appendix.html
 WHEN SQLSTATE '<error_number>' THEN
 -- handle the unique constraint violation error
 WHEN SQLSTATE '23502' THEN
    RAISE NOTICE 'customer error: not-null violation error';
    RETURN FALSE;
 WHEN OTHERS THEN
    err_num := SQLSTATE;
    err_msg := SUBSTR(SQLERRM, 100);
    -- to retrieve info about the latest exception
    -- GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
    RAISE NOTICE 'other error is: %:%', err_num, err_msg;
    RETURN FALSE;
END;
```

```sql
DO
$$
BEGIN
 ASSERT 1=1, 'this assertion should not raise';
 ASSERT 1=0, 'assertion failed, as 1 is not equal to 0';
END;
$$;
-- ERROR: assertion failed, as 1 is not equal to 0
-- CONTEXT: PL/pgSQL function inline_code_block line 4 at ASSERT
```



## JSON

https://www.postgresql.org/docs/9.4/functions-json.html

```sql
CREATE TABLE test_table (
 id SERIAL PRIMARY KEY,
 data JSON
);
INSERT INTO test_table (data) VALUES ('{"name": "my_name", "age": 30}');

-- "my_name"	30
SELECT data->'name' as name, data->'age' as age FROM test_table
--  -> access the value and return a json type
SELECT pg_typeof(data->'name') as name, pg_typeof(data->'age') as age FROM test_table;
-- ->> to get the field in text format
SELECT (data->>'name')::varchar as name, (data->>'age')::int as age FROM test_table;

INSERT INTO test_table(data) VALUES ('{"name":["foo","bar"], "age":[40,50]}');
-- #> to get a specific value
-- "foo" 40
SELECT data#>'{name,0}' as name, data#>'{age,1}' as age FROM test_table WHERE id=2;
SELECT data#>>'{name,0}' as name, data#>>'{age,1}' as age FROM test_table WHERE id=2;

SELECT data FROM test_table WHERE data->'name' ? 'foo';

SELECT jsonb_pretty(data::jsonb) FROM test_table
```

Use index GIN (Generalized Inverted Index) for simple lookups. Use Index GIST (Generalized Search Tree) to index the entire JSON (complex query for specific values).


## Shadow table

https://www.youtube.com/watch?v=Ew_P1Mk6VlQ

https://lloyd.thealbins.com/ShadowTablesVersPGAudit

By using a trigger it is possible to create an audit table with the entire history of the values, the users who performed any operations on the data.

See [SQL Files](./db/migrations/20240225152915_shadowTable.sql)

On any insert, update, delete, truncate a trigger will execute a function that will write the operation into the shadow table

```sql
-- Version 1 (TRUNCATE will copy all the rows to the shadow table)
-- distinct + order by key, action_time will return only the last action for each key
SELECT * FROM (
   SELECT DISTINCT ON (key) *
   FROM table2
   WHERE action_time <= '01/01/2030'
   ORDER BY key, action_time DESC
) a
WHERE action IN ('UPDATE', 'INSERT');
```


```sql
-- Version 1 (TRUNCATE will copy all the rows to the shadow table)
-- Reset the table up to a timestamp
BEGIN;
ALTER TABLE table1 DISABLE TRIGGER ALL;
TRUNCATE table1;
INSERT INTO table1 SELECT key, value, value_type FROM (
  -- get the most recent values before the timestamp
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
```

In case of massive insert/update/delete with PostgreSQL 10+ use [this version of the trigger](./db/2019-03-22%20Shadow%20Tables%20vers%20pgAudit.sql#L577) (577 - 678) which create a temporary table with all the modified rows


## UPSERT

https://www.youtube.com/watch?v=wgLf_ucdFbY

**EXCLUDED** references the failed inserted row

```sql
-- With update
insert into distributors (did, dname)
values (1, 'Distributor 1'), (2, 'Distributor 2')
on conflict (did) do update set dname = EXCLUDED.name;

-- ignore
insert into distributors (did, dname)
values (1, 'Distributor 1'), (2, 'Distributor 2')
on conflict (did) do nothing;


insert into distributors (did, dname) as d
values (1, 'Distributor 1'), (2, 'Distributor 2')
on conflict (did) do update set dname = EXCLUDED.name;
where d.zipcode != '1234';
```

**on conflict (did)** -> **did** is the unique index

**RETURNING** * is also supported, so it can be used inside a **WITH** block.




## Monitoring

https://www.youtube.com/watch?v=JqG0xtaHqCg

https://www.slideshare.net/denishpatel/advanced-postgres-monitoring

https://www.citusdata.com/blog/2019/03/29/health-checks-for-your-postgres-database/

```sql
-- Client connections
-- check current query and query_start
select * from pg_stat_activity;

-- If a query is stuck then get the pid from the above query and run
select pg_terminate_backend(your_pid);

-- Transactions
select * from pg_stat_database;

-- Tables
select * from pg_stat_user_tables;

-- Indexes
select * from pg_stat_user_indexes order by idx_scan;

-- Disk IO
select * from pg_statio_user_tables;

-- Database size
select pg_size_pretty(pg_database_size('mydb')) as size;

-- Locks
select * from pg_locks;

-- Archiving
select * from pg_stat_archiver;

-- Scans
select * from pg_stat_all_tables;

-- Settings
select * from pg_settings;

-- Table size
select pg_relation_size('bookings');

-- returns the size for each table
SELECT schemaname || '.' || relname,
       pg_size_pretty(pg_table_size(schemaname || '.' || relname)) as size
  FROM pg_stat_user_tables
order by pg_table_size(schemaname || '.' || relname) desc
;

-- Table + Index size
SELECT    CONCAT(n.nspname,'.', c.relname) AS table,
          i.relname AS index_name, pg_size_pretty(pg_relation_size(x.indrelid)) AS table_size,
          pg_size_pretty(pg_relation_size(x.indexrelid)) AS index_size,
          pg_size_pretty(pg_total_relation_size(x.indrelid)) AS total_size
FROM pg_class c
JOIN      pg_index x ON c.oid = x.indrelid
JOIN      pg_class i ON i.oid = x.indexrelid
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE     c.relkind = ANY (ARRAY['r', 't'])
AND       n.oid NOT IN (99, 11, 12375);

-- Index Definitions for a table
SELECT pg_get_indexdef(indexrelid) AS index_query
FROM   pg_index WHERE  indrelid = 'bookings'::regclass;

select quote_ident(table_schema)||'.'||quote_ident(table_name) as name
,pg_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name)) as size
from information_schema.tables where table_schema not in ('information_schema', 'pg_catalog')
order by size desc limit 10;

-- Constraints of a table
select * from pg_constraint where confrelid = 'members'::regclass;

-- Highest average execution time
SELECT query, total_exec_time/calls AS avg, calls FROM pg_stat_statements ORDER BY 2 DESC;

-- HOT -> Heap Only Tuples
CREATE OR REPLACE VIEW av_needed AS
SELECT N.nspname, C.relname
, pg_stat_get_tuples_inserted(C.oid) AS n_tup_ins
, pg_stat_get_tuples_updated(C.oid) AS n_tup_upd
, pg_stat_get_tuples_deleted(C.oid) AS n_tup_del
, CASE WHEN pg_stat_get_tuples_updated(C.oid) > 0
 THEN pg_stat_get_tuples_hot_updated(C.oid)::real
 / pg_stat_get_tuples_updated(C.oid)
 END AS HOT_update_ratio
, pg_stat_get_live_tuples(C.oid) AS n_live_tup
, pg_stat_get_dead_tuples(C.oid) AS n_dead_tup
, C.reltuples AS reltuples
, round(COALESCE(threshold.custom, current_setting('autovacuum_vacuum_threshold'))::integer
 + COALESCE(scale_factor.custom, current_setting('autovacuum_vacuum_scale_factor'))::numeric
 * C.reltuples)
 AS av_threshold
, date_trunc('minute',
 greatest(pg_stat_get_last_vacuum_time(C.oid),
 pg_stat_get_last_autovacuum_time(C.oid)))
 AS last_vacuum
, date_trunc('minute',
 greatest(pg_stat_get_last_analyze_time(C.oid),
 pg_stat_get_last_analyze_time(C.oid)))
 AS last_analyze
, pg_stat_get_dead_tuples(C.oid) >
 round( current_setting('autovacuum_vacuum_threshold')::integer
 + current_setting('autovacuum_vacuum_scale_factor')::numeric
 * C.reltuples)
 AS av_needed
, CASE WHEN reltuples > 0
 THEN round(100.0 * pg_stat_get_dead_tuples(C.oid) / reltuples)
 ELSE 0 END
 AS pct_dead
FROM pg_class C
LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
NATURAL LEFT JOIN LATERAL (
 SELECT (regexp_match(unnest,'^[^=]+=(.+)$'))[1]
 FROM unnest(reloptions)
 WHERE unnest ~ '^autovacuum_vacuum_threshold='
) AS threshold(custom)
NATURAL LEFT JOIN LATERAL (
 SELECT (regexp_match(unnest,'^[^=]+=(.+)$'))[1]
 FROM unnest(reloptions)
 WHERE unnest ~ '^autovacuum_vacuum_scale_factor='
) AS scale_factor(custom)
WHERE C.relkind IN ('r', 't', 'm')
 AND N.nspname NOT IN ('pg_catalog', 'information_schema')
 AND N.nspname NOT LIKE 'pg_toast%'
ORDER BY av_needed DESC, n_dead_tup DESC;

-- Index Size
SELECT schemaname || '.' || indexrelname,
       pg_size_pretty(pg_total_relation_size(indexrelid))
  FROM pg_stat_user_indexes
  order by pg_total_relation_size(indexrelid) desc
  ;

-- Index usage
SELECT s.relname AS table_name,
       indexrelname AS index_name,
       i.indisunique,
       idx_scan AS index_scans
FROM   pg_catalog.pg_stat_user_indexes s,
       pg_index i
WHERE  i.indexrelid = s.indexrelid;

-- Bloated index:
SELECT
 nspname,relname,
 round(100 * pg_relation_size(indexrelid) / pg_relation_size(indrelid))
/ 100
 AS index_ratio,
 pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
 pg_size_pretty(pg_relation_size(indrelid)) AS table_size
FROM pg_index I
LEFT JOIN pg_class C ON (C.oid = I.indexrelid)
LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
WHERE
 nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') AND
 C.relkind='i' AND
 pg_relation_size(indrelid) > 0;

-- Index usage:
CREATE OR REPLACE VIEW table_stats AS
SELECT
 stat.relname AS relname,
seq_scan, seq_tup_read, idx_scan, idx_tup_fetch,
heap_blks_read, heap_blks_hit, idx_blks_read, idx_blks_hit
FROM
 pg_stat_user_tables stat
RIGHT JOIN pg_statio_user_tables statio
ON stat.relid=statio.relid;

-- Also index usage:
SELECT
    t.schemaname,
    t.tablename,
    c.reltuples::bigint                            AS num_rows,
    pg_size_pretty(pg_relation_size(c.oid))        AS table_size,
    psai.indexrelname                              AS index_name,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
    CASE WHEN i.indisunique THEN 'Y' ELSE 'N' END  AS "unique",
    psai.idx_scan                                  AS number_of_scans,
    psai.idx_tup_read                              AS tuples_read,
    psai.idx_tup_fetch                             AS tuples_fetched
FROM
    pg_tables t
    LEFT JOIN pg_class c ON t.tablename = c.relname
    LEFT JOIN pg_index i ON c.oid = i.indrelid
    LEFT JOIN pg_stat_all_indexes psai ON i.indexrelid = psai.indexrelid
WHERE
    t.schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY 1, 2;

-- Duplicate Indexes:
SELECT pg_size_pretty(sum(pg_relation_size(idx))::bigint) as size,
       (array_agg(idx))[1] as idx1, (array_agg(idx))[2] as idx2,
       (array_agg(idx))[3] as idx3, (array_agg(idx))[4] as idx4
FROM (
    SELECT indexrelid::regclass as idx, (indrelid::text ||E'\n'|| indclass::text ||E'\n'|| indkey::text ||E'\n'||
                                         coalesce(indexprs::text,'')||E'\n' || coalesce(indpred::text,'')) as key
    FROM pg_index) sub
GROUP BY key HAVING count(*)>1
ORDER BY sum(pg_relation_size(idx)) DESC;

-- Invalid Indexes
SELECT ir.relname AS indexname
, it.relname AS tablename
, n.nspname AS schemaname
FROM pg_index i
JOIN pg_class ir ON ir.oid = i.indexrelid
JOIN pg_class it ON it.oid = i.indrelid
JOIN pg_namespace n ON n.oid = it.relnamespace
WHERE NOT i.indisvalid;

-- Index per table
SELECT
    pg_class.relname,
    pg_size_pretty(pg_class.reltuples::bigint)            AS rows_in_bytes,
    pg_class.reltuples                                    AS num_rows,
    COUNT(*)                                              AS total_indexes,
    COUNT(*) FILTER ( WHERE indisunique)                  AS unique_indexes,
    COUNT(*) FILTER ( WHERE indnatts = 1 )                AS single_column_indexes,
    COUNT(*) FILTER ( WHERE indnatts IS DISTINCT FROM 1 ) AS multi_column_indexes
FROM
    pg_namespace
    LEFT JOIN pg_class ON pg_namespace.oid = pg_class.relnamespace
    LEFT JOIN pg_index ON pg_class.oid = pg_index.indrelid
WHERE
    pg_namespace.nspname = 'public' AND
    pg_class.relkind = 'r'
GROUP BY pg_class.relname, pg_class.reltuples
ORDER BY pg_class.reltuples DESC;

-- Reset statistics
select pg_stat_reset();

-- reltuples -> n of rows, relpages -> n of pages (8K size each)
SELECT relname,relpages,reltuples, round(reltuples / relpages) AS rows_per_page FROM pg_class WHERE relname='table_name';
SELECT relname,relpages,reltuples, round(reltuples / relpages) AS rows_per_page FROM pg_class WHERE relname='index_name';

-- Foreign key levels
WITH RECURSIVE fkeys AS (
   /* source and target tables for all foreign keys */
   SELECT conrelid AS source,
          confrelid AS target
   FROM pg_constraint
   WHERE contype = 'f'
),
tables AS (
      (   /* all tables ... */
          SELECT oid AS table_name,
                 1 AS level,
                 ARRAY[oid] AS trail,
                 FALSE AS circular
          FROM pg_class
          WHERE relkind = 'r'
            AND NOT relnamespace::regnamespace::text LIKE ANY
                    (ARRAY['pg_catalog', 'information_schema', 'pg_temp_%'])
       EXCEPT
          /* ... except the ones that have a foreign key */
          SELECT source,
                 1,
                 ARRAY[ source ],
                 FALSE
          FROM fkeys
      )
   UNION ALL
      /* all tables with a foreign key pointing a table in the working set */
      SELECT fkeys.source,
             tables.level + 1,
             tables.trail || fkeys.source,
             tables.trail @> ARRAY[fkeys.source]
      FROM fkeys
         JOIN tables ON tables.table_name = fkeys.target
      /*
       * Stop when a table appears in the trail the third time.
       * This way, we get the table once with "circular = TRUE".
       */
      WHERE cardinality(array_positions(tables.trail, fkeys.source)) < 2
),
ordered_tables AS (
   /* get the highest level per table */
   SELECT DISTINCT ON (table_name)
          table_name,
          level,
          circular
   FROM tables
   ORDER BY table_name, level DESC
)
SELECT table_name::regclass,
       level
FROM ordered_tables
WHERE NOT circular
ORDER BY level, table_name;
```

## pgexercises

https://pgexercises.com/gettingstarted.html



## pg_stat_statements

Enabling with Docker:

https://gist.github.com/lfittl/1b0671ac07b33521ea35fcd22b0120f5

```sql
CREATE EXTENSION pg_stat_statements;

SELECT *
FROM pg_available_extensions
WHERE
name = 'pg_stat_statements' and
installed_version is not null;
```

```sql
select * from pg_stat_statements;
```

```sql
select pg_stat_statements_reset();
```

## Postgres basic types

```sql
select nspname, typname
from pg_type t join pg_namespace n on n.oid = t.typnamespace
where nspname = 'pg_catalog' and typname !~ '(^_|^pg_|^reg|_handler$)'
order by nspname, typname;
```


## Lateral Join

https://www.crunchydata.com/developers/playground/lateral-join

https://stackoverflow.com/a/52671180

https://www.cybertec-postgresql.com/en/understanding-lateral-joins-in-postgresql/

https://www.depesz.com/2022/09/18/what-is-lateral-what-is-it-for-and-how-can-one-use-it/

https://www.softwareandbooz.com/what-i-wish-i-had-known-about-postgresql/

```sql
SELECT * FROM (
    SELECT id, name, created_at FROM companies WHERE created_at < '2018-01-01'
) c, LATERAL delete_company(c.id);
```

## Generated Columns

https://www.postgresql.org/docs/current/ddl-generated-columns.html#:~:text=A%20virtual%20generated%20column%20occupies,implements%20only%20stored%20generated%20columns.

```sql
CREATE TABLE people (
    ...,
    height_cm numeric,
    height_in numeric GENERATED ALWAYS AS (height_cm / 2.54) STORED
);
```


## Trigger

https://www.postgresql.org/docs/current/plpgsql-trigger.html#PLPGSQL-DML-TRIGGER

https://www.youtube.com/watch?v=gV5W4AhWBzo

https://tapoueh.org/blog/2018/07/postgresql-event-based-processing/

https://severalnines.com/blog/postgresql-triggers-and-stored-function-basics

https://www.postgresql.org/docs/current/sql-createtrigger.html

https://www.postgresql.org/docs/current/event-trigger-matrix.html

https://www.postgresql.org/docs/current/functions-event-triggers.html

Trigger execution order:
timing AFTER / BEFORE
ordered alphabetically by trigger_name (later trigger will received the updated data from the previous triggers)

```sql
select * from information_schema.triggers
order by action_timing desc, trigger_name
;
```

**NOTE**: If the function returns NEW, the row will be inserted as expected. However, if you return NULL, the operation will be silently ignored. In case of a BEFORE trigger the row will not be inserted.

To avoid a stack overflow use `pg_trigger_depth`

```sql
CREATE OR REPLACE FUNCTION trigger_function()
RETURNS TRIGGER AS $$
DECLARE
  nested_trigger_depth INTEGER;
BEGIN
  nested_trigger_depth := pg_trigger_depth();
-- Perform different actions based on the trigger depth
  CASE nested_trigger_depth
  WHEN 1 THEN
    RAISE NOTICE 'This is the outermost trigger';
  WHEN 2 THEN
    RAISE NOTICE 'This is the first nested trigger, and stop further nested calls';
    RETURN NEW;
  ELSE
    RAISE NOTICE 'This is a nested trigger at depth %', nested_trigger_depth;
  END CASE;
  INSERT INTO test(name) VALUES ('Test2');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Or

CREATE TRIGGER trg_taxonomic_positions
AFTER INSERT OR UPDATE OF taxonomic_position
ON taxon_concepts
FOR EACH ROW
WHEN (pg_trigger_depth() = 0)
EXECUTE PROCEDURE trg_taxonomic_positions()
```

[INSTEAD OF](https://www.postgresql.org/docs/current/sql-createtrigger.html) for triggers on views

The parameters available in the trigger function body are:

* OLD/NEW: old/new record
* TG_OP: string (INSERT, UPDATE, DELETE or TRUNCATE)
* TG_NAME: variable holding the name of the trigger. Useful when there are multiple triggers on the same table
* TG_WHEN: string (BEFORE, AFTER, INSTEAD OF)
* TG_LEVEL: string (ROW, STATEMENT)
* TG_TABLE_NAME: string
* TG_RELNAME: like TG_TABLE_NAME
* TG_RELID: table ID
* TG_TABLE_SCHEMA: string
* TG_NARGS: count of arguments
* TG_ARGV[]: arguments array

**Event Triggers** are trigger not related to a specific table

See https://www.postgresql.org/docs/current/event-trigger-matrix.html

`current_query()` returns the executed query

The function must return **event_trigger**

```sql
CREATE OR REPLACE FUNCTION log_ddl_event() RETURNS event_trigger AS $$
DECLARE
  rec RECORD;
BEGIN
-- See https://www.postgresql.org/docs/current/functions-event-triggers.html
 rec := pg_event_trigger_ddl_commands();
 INSERT INTO ddl_log (event_type, event_time, object_name, statement)
 VALUES (tg_tag, current_timestamp, rec.object_identity, current_query());
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER ddl_event_trigger ON ddl_command_end EXECUTE PROCEDURE log_ddl_event();

CREATE EVENT TRIGGER track_ddl_event ON ddl_command_start
WHEN TAG IN ('CREATE TABLE', 'DROP TABLE', 'ALTER TABLE')
EXECUTE PROCEDURE track_ddl_function();
```

To drop a trigger:

```sql
DROP TRIGGER insert_customer_report ON customers;
DROP EVENT TRIGGER ddl_event_trigger;
```


## Transaction

```sql
begin;
select txid_current();
rollback;
```

COMMIT and EXCEPTION blocks should not be in a single BEGIN END block in that order. The reason is the way transactions are handled inside the PL/pgSQL blocks. Each BEGIN END block creates an implicit subtransaction with the help of SAVEPOINT.

```sql
BEGIN
 --- Statements
<<COMMIT/ROLLBACK>>
EXCEPTION WHEN others THEN
 --- Handle exception
END
```

is converted to

```sql
BEGIN
 SAVEPOINT one;
 --- Statements
<<COMMIT/ROLLBACK>>
 RELEASE SAVEPOINT one;
 EXCEPTION WHEN others THEN
 ROLLBACK TO SAVEPOINT one;
 --- Handle exception
END
```

If there is an exception then the exception ROLLBACK can't be executed because the COMMIT command has already be executed.

COMMIT/ROLLBACK should be put as the last executable statement of the procedure.

## CTE

https://hakibenita.medium.com/be-careful-with-cte-in-postgresql-fca5e24d2119

https://www.crunchydata.com/blog/with-queries-present-future-common-table-expressions

https://habr.com/en/companies/postgrespro/articles/490228/



## Custom Operator

```sql
SELECT * FROM pg_operator;
```

https://www.timescale.com/blog/function-pipelines-building-functional-programming-into-postgresql-using-custom-operators/

https://www.postgresql.org/docs/current/sql-createoperator.html

https://www.postgresql.org/docs/current/xoper.html

https://www.postgresql.org/docs/current/xoper-optimization.html

https://www.postgresql.org/docs/current/xindex.html

```sql
create or replace function add_string(varchar, varchar)
returns varchar as $$
begin
    return $1 || $2;
end;
$$ language plpgsql immutable;
grant execute on function add_string(varchar, varchar) to public;

create operator + (
    leftarg = varchar,
    rightarg = varchar,
    procedure = add_string
);
-- drop operator +(varchar, varchar);
-- drop function add_string;
```

```sql
-- ?column?: hello world
select 'hello ' + 'world';
```

To help the planner optimize the query:

* define a commuter A of the operator B such that: x A y = y B x
```sql
CREATE OPERATOR > (LEFTARG=integer, RIGHTARG=integer, PROCEDURE=comp, COMMUTATOR = <)
```
* define a negator of the operator
CREATE OPERATOR = (LEFTARG=integer, RIGHTARG=integer, PROCEDURE=comp, COMMUTATOR = <>)


## Custom Cast

https://www.postgresql.org/docs/current/sql-createcast.html

```sql
create type fahrenheit as (value numeric(10,2));

create or replace function celsius_to_fahrenheit(celsius numeric)
returns fahrenheit as $$
begin
    return row(Celsius * 9/5 + 32)::fahrenheit;
end;
$$ language plpgsql;

create cast(numeric as fahrenheit) with function celsius_to_fahrenheit(numeric ) as implicit;
```

```sql
select cast(t::numeric as fahrenheit) from generate_series(1,10) as seq(t);
select t::numeric::fahrenheit from generate_series(1,10) as seq(t);
select (t::numeric::fahrenheit).value from generate_series(1,10) as seq(t);
```


## Custom Aggregate

https://www.postgresql.org/docs/current/functions-aggregate.html

https://www.postgresql.org/docs/current/xaggr.html


## Temporary Functions

Temporary functions should be defined in the `pg_temp` schema.

```sql
create  function pg_temp.add_string(varchar, varchar)
returns varchar as $$
begin
    return $1 || $2;
end;
$$ language plpgsql immutable;
```


## Dynamic SQL

Postgres can save the execution plan of a prepared staement (or function) when it is called for the first time.

By executing dynamic SQL we are guaranteed that the execution plan will be evaluated and optimized for the specific values it's called with (crucial in some cases for function calls). There are cases where different parameters can lead to different execution plans based on the statistics and distribution of the values. In some other cases (when the executions would always be the same) it is beneficial to only plan once saving CPU computations.

```sql
CREATE OR REPLACE FUNCTION select_booking_leg_country_dynamic(
 p_country text,
 p_updated timestamptz)
RETURNS setof booking_leg_part AS
$body$
BEGIN
RETURN QUERY
EXECUTE $$
SELECT
 departure_airport,
 booking_id,
 is_returning
FROM booking_leg bl
JOIN flight f USING (flight_id)
WHERE departure_airport IN
 (SELECT
 airport_code
 FROM airport
--  quote_literal is to guard against SQL injection
 WHERE iso_country=$$|| quote_literal(p_country) || $$ )
 AND bl.booking_id IN
 (SELECT
 booking_id
 FROM booking
 WHERE update_ts>$$|| quote_literal(p_updated)||$$)$$;
END;
$body$ LANGUAGE plpgsql;
```





## Performance

https://postgrespro.com/blog/pgsql/5968054

https://hakibenita.com/sql-tricks-application-dba

https://www.cybertec-postgresql.com/en/join-strategies-and-performance-in-postgresql/

https://www.crunchydata.com/blog/postgres-query-optimization-left-join-vs-union-all

https://wiki.postgresql.org/wiki/Don%27t_Do_This#Don.27t_use_NOT_IN

https://www.cybertec-postgresql.com/en/subqueries-and-performance-in-postgresql/

### OR clause

https://www.cybertec-postgresql.com/en/avoid-or-for-better-performance/

https://www.cybertec-postgresql.com/en/rewrite-or-to-union-in-postgresql-queries/

OR in WHERE clause often requires a Bitmap index scan, consuming more RAM. A multi index doesn't help.

* (single table) `... WHERE id = value_1 OR id = value_2` (Bitmap Heap scan) might be better rewritten as `... WHERE id IN (value_1, value_2)` (Index Only Scan)
* (join tables) `... FROM a JOIN b ... WHERE a.id = value_1 OR b.id = value_2` (Merge Join) might be better rewritten as ` ... FROM a JOIN b ...WHERE a.id = value_1 UNION ALL ...  FROM a JOIN b  ...WHERE b.id = value_2` (Unique) (careful about duplicates)


### COUNT(*)

https://www.youtube.com/watch?v=GtQueJe6xRQ

https://www.postgresql.org/docs/current/sql-vacuum.html

COUNT(*) can be slow because every transaction can see a different set of rows. Each row have a transacion min and max: Postgres determines the visibility based on this range. Use `VACUUM` to clear dead rows that are not visible anymore.

https://www.peterbe.com/plog/best-way-to-count-distinct-indexed-things-in-postgresql

```sql
SELECT COUNT(*) FROM (SELECT DISTINCT my_not_unique_indexed_column FROM my_table) t;
```

https://www.cybertec-postgresql.com/en/postgresql-count-made-fast/

Count estimation (between -10% and +10%):

```sql
SELECT reltuples FROM pg_catalog.pg_class WHERE relname = 'mytable';
```

https://pganalyze.com/blog/5mins-postgres-limited-count

Add **LIMIT 101** to speed up the count query if you are ok displaying either 0-100 or 100+ in your frontend.

```sql
SELECT count(*) AS count FROM (
  SELECT 1
    FROM my_table
    WHERE -- ....
  LIMIT 101
) limited_count
```

### JOINS

Main point: reduce the size of the intermediate dataset

The most restrictive joins (i.e., joins that reduce the result set size the most) should be executed first.

Semi-joins and Anti-joins (select ... where [not] exists (...) / where .. [not] in (...)) never increase the size of the result set; check whether it is beneficial to apply them first.

Force a specific join order by setting the join_collapse_limit parameter to 1.

To reduce the size of hash table size (used in Hash Joins), only select the columns that are needed.


|                  | Nested Loop Join           | Hash Join                    | Merge Join        |
| ---------------- | -------------------------- | ---------------------------- | ----------------- |
| Algorithm        | For each outer, scan inner | Hash inner, probe with outer | Sort, then merge  |
| Helping Indexes  | Join keys of inner         | None                         | Both join keys    |
| Good strategy if | Outer is small             | Hash fits in work_mem        | Both large tables |



### GROUPING SETS, CUBE, ROLLUP

https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-GROUPING-SETS


### GROUP BY

For all columns used in the GROUP BY clause, filtering should be pushed inside the grouping.

Group First, Select Last

```sql
SELECT
 city,
 date_trunc('month', scheduled_departure) AS month,
 count(*) passengers
FROM airport a
JOIN flight f ON airport_code = departure_airport
JOIN booking_leg l ON f.flight_id =l.flight_id
JOIN boarding_pass b ON b.booking_leg_id = l.booking_leg_id
GROUP BY 1,2
ORDER BY 3 DESC

-- More performant version
SELECT
 city,
 date_trunc('month', scheduled_departure),
 sum(passengers) passengers
FROM airport a
JOIN flight f ON airport_code = departure_airport
JOIN (
 SELECT flight_id, count(*) passengers
 FROM booking_leg l
 JOIN boarding_pass b USING (booking_leg_id)
 GROUP BY flight_id
 ) cnt USING (flight_id)
GROUP BY 1,2
ORDER BY 3 DESC
```

### SET OPERATIONS

Use set operations to (sometimes) prompt an alternative execution plan and improve readability.

* Use EXCEPT instead of NOT EXISTS and NOT IN.
* Use INTERSECT instead of EXISTS and IN.
* Use UNION instead of complex selection criteria with OR.

If the query aren't correlated with each other then thy can run in parallel.

If you have two different queries you're UNIONing, you have to make sure to not have any data type coercions in order for subquery pull-up to work!

### FILTER

When retrieving multiple attributes from an entity-attribute-value table, join to the table only once and use FILTER in the aggregate function MAX() in SELECT list to return the appropriate values in each column.


```sql
-- 3 Scans on table custom_field
SELECT
 first_name,
 last_name,
 pn.custom_field_value AS passport_num,
 pe.custom_field_value AS passport_exp_date,
 pc.custom_field_value AS passport_country
FROM passenger p
JOIN custom_field pn ON pn.passenger_id=p.passenger_id AND pn.custom_field_name='passport_num'
JOIN custom_field pe ON pe.passenger_id=p.passenger_id AND pe.custom_field_name='passport_exp_date'
JOIN custom_field pc ON pc.passenger_id=p.passenger_id AND pc.custom_field_name='passport_country'
WHERE p.passenger_id<5000000

-- Single Scan on table custom_field
SELECT
 last_name,
 first_name,
 passport_num,
 passport_exp_date,
 passport_country
FROM passenger p
JOIN (
SELECT
 cf.passenger_id,
 coalesce(max (custom_field_value ) FILTER (WHERE custom_field_name ='passport_num' ),'') AS passport_num,
 coalesce(max (custom_field_value ) FILTER (WHERE custom_field_name ='passport_exp_date' ),'') AS passport_exp_date,
 coalesce(max (custom_field_value ) FILTER (WHERE custom_field_name ='passport_country' ),'') AS passport_country
FROM custom_field cf
WHERE cf.passenger_id<5000000
GROUP BY 1
 ) info USING (passenger_id)
WHERE p.passenger_id<5000000
```


### OFFSET

Avoid offset if it has to discard too many values.

Offset can be used to force join order.

```sql
-- join a and b first, then the result with c
SELECT b.b_id, a.value
FROM a
   JOIN b USING (a_id)
   JOIN c USING (a_id)
WHERE c.c_id < 300;

-- join c and b first, then the result with a
SELECT subq.b_id, a.value
FROM a JOIN
   (SELECT a_id, b.b_id, c.c_id
    FROM b
       JOIN c USING (a_id)
    WHERE c.c_id < 300
    OFFSET 0
   ) AS subq
      USING (a_id);
```

### PARTITIONING

*  the partitioning key should be used in (almost) all queries that run on this table, or at least in critical queries,
*  these values should be known prior to the SQL statement execution
*  an index on a partition, most likely, will eliminate only one level of the B-tree, while the choice of needed partition also requires some amount of resources

```sql
CREATE TABLE boarding_pass_part (
 boarding_pass_id SERIAL,
 passenger_id BIGINT NOT NULL,
 booking_leg_id BIGINT NOT NULL,
 seat TEXT,
 boarding_time TIMESTAMPTZ,
 precheck BOOLEAN,
 update_ts TIMESTAMPTZ
)
PARTITION BY RANGE (boarding_time);

CREATE TABLE boarding_pass_may
PARTITION OF boarding_pass_part
FOR VALUES
FROM ('2023-05-01'::timestamptz)
TO ('2023-06-01'::timestamptz) ;
--
CREATE TABLE boarding_pass_june
PARTITION OF boarding_pass_part
FOR VALUES
FROM ('2023-06-01'::timestamptz)
TO ('2023-07-01'::timestamptz);

INSERT INTO boarding_pass_part SELECT * from boarding_pass;
```


### Flowchart

<picture style="margin-left: auto;margin-right: auto; display: block; width: 50%">
  <img src="./img/optimizationFlowchart.svg"/>
</picture>


* short? if the numbe of returned rows is small. See if it is possible with the business to restrict the returned set (example only rows for a certain period)
* short:
  * the most restrictive criteria: query the tables and find out the least frequent values
  * check the indexes: are the attribute of the above step being indexed? is it possible to index-only scan? compound index?
  * exessive selection criterion: only when no index can be applied
  * build the query: build the select query bottom (most restrictive) up and check with explain analyze each of the steps. Consider CTEs or dynamic SQL
* incremental? (meaning only pull the data since the previous pull, example daily reports)
* long:
  * most restrictive join: try also semi-join or anti-join. Build the joins steps by steps and check the execution planning
  * don't perform multiple sequential scan on the same table
  * group first, select last





## Extensions:

```sql
-- https://www.postgresql.org/docs/current/pgstatstatements.html
SELECT * FROM pg_extension;
-- https://www.postgresql.org/docs/current/auto-explain.html
LOAD 'auto_explain';
```

* [plprofiler](https://github.com/bigsql/plprofiler?tab=readme-ov-file)
* [plpgsql_check](https://github.com/okbob/plpgsql_check?tab=readme-ov-file)
* https://postgrespro.com/blog/company/5968040
* https://postgrespro.com/blog/pgsql/5968054


## Comments

```sql
-- Table and columns
comment on table bookings is 'Bookings table';
comment on column bookings.memid is 'Member ID associated with the bookings';
select
st.schemaname,
st.relname as table_name,
c.column_name,
 pgd.*
from pg_catalog.pg_statio_all_tables as st
inner join pg_catalog.pg_description pgd on pgd.objoid = st.relid
left join information_schema.columns c on (
    pgd.objsubid   = c.ordinal_position and
    c.table_schema = st.schemaname and
    c.table_name   = st.relname
);

-- Trigger
comment on trigger products_notify_event on products is 'Notify Trigger on Products';
select
st.tgname,
 pgd.*
from pg_catalog.pg_trigger as st
inner join pg_catalog.pg_description pgd on pgd.objoid = st.oid
;

-- Function
comment on function "assert" is 'Assert a condition. Raise Exception if false.';
select
st.proname,
 pgd.*
from pg_catalog.pg_proc as st
inner join pg_catalog.pg_description pgd on pgd.objoid = st.oid
;
```


## Crypto

https://www.postgresql.org/docs/current/pgcrypto.html#AEN178870

```sql
create extension if not exists "pgcrypto";
select crypt('my-super-secret-pw', gen_salt('bf'));
-- $2a$06$kvVAUdwQj53a8oi1zZBWx.iVG3ywc7T54lm7.yttWkHKzI/sHIeVq
select crypt('my-super-secret-pw', '$2a$06$kvVAUdwQj53a8oi1zZBWx.iVG3ywc7T54lm7.yttWkHKzI/sHIeVq') = '$2a$06$kvVAUdwQj53a8oi1zZBWx.iVG3ywc7T54lm7.yttWkHKzI/sHIeVq';
```


## Full Text Search

https://www.crunchydata.com/blog/postgres-full-text-search-a-search-engine-in-a-database


## Other

* Use `IDENTITY` (Postgres 10 or later) as primary key instead of `SERIAL`

```sql
CREATE TABLE people (
   people_id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
   first_name varchar,
   last_name varchar
)
```

* pg_sleep(n) to stop the execution for n seconds

* https://wiki.postgresql.org/wiki/Don't_Do_This
* https://www.citusdata.com/blog/2019/07/17/postgres-tips-for-average-and-power-user/
* gitlab.com/microo8/plgo
* https://medium.com/avitotech/how-to-work-with-postgres-in-go-bad2dabd13e4
* https://hakibenita.com/sql-dos-and-donts
* https://www.cybertec-postgresql.com/en/abusing-postgresql-as-an-sql-beautifier/

* Generate SQL commands to rename tables and columns

```sql
-- create table "MY_TABLE"("ID" serial primary key, "MY_COLUMN" integer);
SELECT 'ALTER TABLE public.' || quote_ident(tablename) || ' RENAME TO ' || lower(quote_ident(tablename))
FROM    pg_tables
WHERE   schemaname = 'public' AND   tablename <> lower(tablename);

SELECT   'ALTER TABLE ' || a.oid::regclass || ' RENAME COLUMN ' || quote_ident(attname)
|| ' TO ' || lower(quote_ident(attname))
FROM    pg_attribute AS b, pg_class AS a, pg_namespace AS c
WHERE
  relkind = 'r'
  AND     c.oid = a.relnamespace
  AND     a.oid = b.attrelid
  AND     b.attname NOT IN ('xmin', 'xmax', 'oid', 'cmin', 'cmax', 'tableoid', 'ctid')
  AND     a.oid > 16384
  AND     nspname = 'public'
  AND     lower(attname) != attname;
```

* https://www.depesz.com/2020/01/28/dont-do-these-things-in-postgresql/
* https://www.cybertec-postgresql.com/en/postgresql-network-latency-does-make-a-big-difference/
* https://www.graphile.org/postgraphile/postgresql-schema-design/
* https://abdulyadi.wordpress.com/2020/04/07/parallel-query-inside-function/
* https://www.2ndquadrant.com/en/blog/7-best-practice-tips-for-postgresql-bulk-data-loading/
* https://www.2ndquadrant.com/en/blog/how-to-get-the-best-out-of-postgresql-logs/
* https://pganalyze.com/blog/5mins-postgres-performance-in-lists-vs-any-operator-bind-parameters
* https://www.softwareandbooz.com/advent-of-code-2022-with-postgresql-part1/
* https://psql-tips.org/psql_tips_all.html

* Consider Unlogged table for testing
* https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-UNLOGGED
* https://www.crunchydata.com/developers/playground


<img src="./d2.svg"/>