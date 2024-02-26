-- migrate:up
create table foo(fooid int, foosubid int, fooname text);
insert into foo values (1,2,'three');
insert into foo values (4,5,'six');

create or replace function getFooNext() returns setof foo as
$BODY$
declare
    r foo%rowtype;
    stack text;
begin
    GET DIAGNOSTICS stack = PG_CONTEXT;
    RAISE NOTICE E'--- CALL STACK ---\n%', stack;
    for r in select * from foo where fooid > 0
    loop
        return next r;
    end loop;
    return;
end
$BODY$
language plpgsql;

create or replace function getFooQuery() returns setof foo as
$BODY$
declare r foo%rowtype;
begin
    return query select * from foo where fooid > 0;
    return;
end
$BODY$
language plpgsql;

-- migrate:down
drop function getFooNext;
drop function getFooQuery;
drop table foo;