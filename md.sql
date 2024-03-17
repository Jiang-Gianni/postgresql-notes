with d as (
    select
        c.relname,
        case
        when tb.objsubid = 0 then chr(10) || '<i>' || des.description || '</i>' || chr(10) || chr(10)
        else ''
        end as table_description,
        format(
            '| %s | %s | %s | %s | %s |',
            a.attname,
            t.typname,
            con.contype,
            case
            when ref_a.attname is not null then format('[%s.%s](#%s)', ref_c.relname, ref_a.attname, ref_c.relname)
            else ''
            end,
            case
            when des.objsubid = a.attnum then '<i>' || des.description || '</i>'
            else ''
            end
            ) as column
    from
        pg_class c
        join pg_namespace n on c.relnamespace = n.oid
        join pg_attribute a on a.attrelid = c.oid
        join pg_type t on a.atttypid = t.oid
        left join pg_constraint con on
            c.oid = con.conrelid
            and a.attnum = any(con.conkey)
            and con.contype in ('p', 'f')
        left join pg_class ref_c on ref_c.oid = con.confrelid
        left join pg_attribute ref_a on
            ref_a.attrelid = con.confrelid
            and ref_a.attnum = con.confkey[1]
        left join pg_description des on des.objoid = c.oid and des.objsubid = a.attnum
        left join pg_description tb on tb.objoid = c.oid and tb.objsubid = 0
    where
        c.relkind = 'r'
        and n.nspname not in ('pg_catalog', 'information_schema')
        and not a.attisdropped
        and a.attnum > 0
    order by c.relname, a.attnum
)
select
    '## ' || d.relname || chr(10) ||
    max(d.table_description) ||
    '| column_name | column_type | key | reference        | comment |' || chr(10) ||
    '| ----------- | ----------- | ---------- | ---------------- | ------- |' || chr(10) ||
    string_agg(d.column,chr(10)) || chr(10) || chr(10)
from d
group by d.relname;