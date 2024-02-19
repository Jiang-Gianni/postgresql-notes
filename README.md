- [postgresql-notes](#postgresql-notes)
  - [PostgreSQL Docker](#postgresql-docker)
  - [Info about function or trigger](#info-about-function-or-trigger)
  - [Listen JSON](#listen-json)

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

Cons: only pub-sub (no queue)


<!-- ## Unnest

```sql

``` -->