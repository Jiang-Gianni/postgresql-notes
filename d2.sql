with d as (
    select
        c.relname,
        format('%s: %s', a.attname, t.typname) as column,
        case
        when con.contype = 'p' then '{constraint: primary_key}'
        when con.contype = 'f' then '{constraint: foreign_key}'
        else null
        end as constraint,
        case
        when ref_a.attname is not null then format('%s.%s -> %s.%s',c.relname,a.attname,ref_c.relname,ref_a.attname)
        else null
        end as ref
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
    where
        c.relkind = 'r'
        and n.nspname not in ('pg_catalog', 'information_schema')
        and not a.attisdropped
        and a.attnum > 0
    order by c.relname, a.attnum
)
select
    d.relname || ' :{ ' || chr(10)
    || '  shape: sql_table' || chr(10) || '  '
    || coalesce(string_agg(format('%s %s', d.column, d.constraint), chr(10)||'  '), '')
    || chr(10) || '}' || chr(10) || chr(10)
    || coalesce(string_agg(d.ref,chr(10)), '') || chr(10)
from d
group by d.relname;