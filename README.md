- [postgresql-notes](#postgresql-notes)
  - [PostgreSQL Docker](#postgresql-docker)
  - [Info about function or trigger](#info-about-function-or-trigger)
  - [Explain Analyze Buffers Verbose](#explain-analyze-buffers-verbose)
  - [Listen JSON](#listen-json)
  - [Json with CTE](#json-with-cte)

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

explain analyze actually executes the query, so any update/delete/create will persists


## Listen JSON

Using PostgreSQL's LISTEN/NOTIFY feature with Go:

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


## Json with CTE

https://tapoueh.org/blog/2018/01/exporting-a-hierarchy-in-json-with-recursive-queries/

See [**SQL file**](./db/migrations/20240221212444_jsonWithCTE.sql)

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
select jsonb_pretty(jsonb_agg(js))
  from dndclasses_from_children
 where parent_id IS NULL;
```

Output:

```json
[ { "Name": "Priest", "Sub Classes": [ { "Name": "Cleric" }, { "Name": "Druid" }, { "Name": "Priest of specific mythos" } ] }, { "Name": "Rogue", "Sub Classes": [ { "Name": "Thief" }, { "Name": "Bard" } ] }, { "Name": "Wizard", "Sub Classes": [ { "Name": "Mage" }, { "Name": "Specialist wizard" } ] }, { "Name": "Warrior", "Sub Classes": [ { "Name": "Fighter" }, { "Name": "Paladin" }, { "Name": "Ranger" }, { "Name": "Assassin" } ] } ]
```