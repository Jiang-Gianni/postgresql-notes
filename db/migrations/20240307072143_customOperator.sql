-- migrate:up
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

-- set search_path to pg_catalog;

-- migrate:down
drop operator +(varchar, varchar);
drop function add_string;