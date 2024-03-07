-- migrate:up
create type fahrenheit as (value numeric(10,2));

create or replace function celsius_to_fahrenheit(celsius numeric)
returns fahrenheit as $$
begin
    return row(Celsius * 9/5 + 32)::fahrenheit;
end;
$$ language plpgsql;

create cast(numeric as fahrenheit) with function celsius_to_fahrenheit(numeric ) as implicit;

-- migrate:down
drop cast(numeric as fahrenheit);
drop function celsius_to_fahrenheit;
drop type fahrenheit;