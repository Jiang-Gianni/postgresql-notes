-- migrate:up
CREATE TABLE products_citus (
    product_no integer,
    name text,
    price numeric CHECK (price > 0),
    sale_price numeric CHECK (sale_price > 0),
    CHECK (price > sale_price)
);

insert into products_citus values (1, 'product name', 10, 5);

-- Invalid:
-- insert into products_citus values (1, 'product name', 10, 11);
-- insert into products_citus values (1, 'product name', 10, -11);
-- insert into products_citus values (1, 'product name', -10, 11);

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
insert into onlyfib values (5), (8);

-- Invalid:
-- insert into onlyfib values (6);

-- migrate:down
DROP TABLE products_citus;
DROP TABLE onlyfib;
DROP FUNCTION is_fib;