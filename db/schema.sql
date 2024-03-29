--
-- PostgreSQL database dump
--

-- Dumped from database version 16.0 (Debian 16.0-1.pgdg120+1)
-- Dumped by pg_dump version 16.0 (Debian 16.0-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: fahrenheit; Type: TYPE; Schema: public; Owner: root
--

CREATE TYPE public.fahrenheit AS (
	value numeric(10,2)
);


ALTER TYPE public.fahrenheit OWNER TO root;

--
-- Name: celsius_to_fahrenheit(numeric); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.celsius_to_fahrenheit(celsius numeric) RETURNS public.fahrenheit
    LANGUAGE plpgsql
    AS $$
begin
    return row(Celsius * 9/5 + 32)::fahrenheit;
end;
$$;


ALTER FUNCTION public.celsius_to_fahrenheit(celsius numeric) OWNER TO root;

--
-- Name: CAST (numeric AS public.fahrenheit); Type: CAST; Schema: -; Owner: -
--

CREATE CAST (numeric AS public.fahrenheit) WITH FUNCTION public.celsius_to_fahrenheit(numeric) AS IMPLICIT;


--
-- Name: add_string(character varying, character varying); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.add_string(character varying, character varying) RETURNS character varying
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
begin
    return $1 || $2;
end;
$_$;


ALTER FUNCTION public.add_string(character varying, character varying) OWNER TO root;

--
-- Name: assert(boolean, text); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.assert(in_assertion boolean, in_errormessage text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
  begin
    if not in_assertion
    then raise exception '%', in_errormessage;
    end if;
    return in_assertion;
  end;
$$;


ALTER FUNCTION public.assert(in_assertion boolean, in_errormessage text) OWNER TO root;

--
-- Name: format_sql(text); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.format_sql(text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
   DECLARE
      v_ugly_string       ALIAS FOR $1;
      v_beauty            text;
      v_tmp_name          text;
   BEGIN
      -- let us create a unique view name
      v_tmp_name := 'temp_' || md5(v_ugly_string);
      EXECUTE 'CREATE TEMPORARY VIEW ' ||
      v_tmp_name || ' AS ' || v_ugly_string;

      -- the magic happens here
      SELECT pg_get_viewdef(v_tmp_name) INTO v_beauty;

      -- cleanup the temporary object
      EXECUTE 'DROP VIEW ' || v_tmp_name;
      RETURN v_beauty;
   EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'you have provided an invalid string: % / %',
            sqlstate, sqlerrm;
   END;
$_$;


ALTER FUNCTION public.format_sql(text) OWNER TO root;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: foo; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.foo (
    fooid integer,
    foosubid integer,
    fooname text
);


ALTER TABLE public.foo OWNER TO root;

--
-- Name: getfoonext(); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.getfoonext() RETURNS SETOF public.foo
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.getfoonext() OWNER TO root;

--
-- Name: getfooquery(); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.getfooquery() RETURNS SETOF public.foo
    LANGUAGE plpgsql
    AS $$
declare r foo%rowtype;
begin
    return query select * from foo where fooid > 0;
    return;
end
$$;


ALTER FUNCTION public.getfooquery() OWNER TO root;

--
-- Name: is_fib(integer); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.is_fib(i integer) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
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
$$;


ALTER FUNCTION public.is_fib(i integer) OWNER TO root;

--
-- Name: notify_event(); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.notify_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

    DECLARE
        data json;
        notification json;

    BEGIN

        -- Convert the old or new row to JSON, based on the kind of action.
        -- Action = DELETE?             -> OLD row
        -- Action = INSERT or UPDATE?   -> NEW row
        IF (TG_OP = 'DELETE') THEN
            data = row_to_json(OLD);
        ELSE
            data = row_to_json(NEW);
        END IF;

        -- Contruct the notification as a JSON string.
        notification = json_build_object(
                          'table',TG_TABLE_NAME,
                          'action', TG_OP,
                          'data', data);


        -- Execute pg_notify(channel, notification)
        PERFORM pg_notify('events',notification::text);

        -- Result is ignored since this is an AFTER trigger
        RETURN NULL;
    END;

$$;


ALTER FUNCTION public.notify_event() OWNER TO root;

--
-- Name: shadow(); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.shadow() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
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
$_$;


ALTER FUNCTION public.shadow() OWNER TO root;

--
-- Name: transfermoney(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: root
--

CREATE FUNCTION public.transfermoney(in_acc_from integer, in_acc_to integer, amount integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
    declare
        discard record;
    begin
        with updated_rows as (
            update accounts
            set balance =
                case
                    when account_id = in_acc_from then balance - amount
                    when account_id = in_acc_to then balance + amount
                    else balance
                end
            where account_id in (in_acc_from, in_acc_to)
            returning *
        )
        select
            assert( bool_and(balance > 0), 'negative balance') as balance_check,
            assert( count(*) = 2, 'account not found') as account_found
        from updated_rows into discard;
        return;
    end;
$$;


ALTER FUNCTION public.transfermoney(in_acc_from integer, in_acc_to integer, amount integer) OWNER TO root;

--
-- Name: +; Type: OPERATOR; Schema: public; Owner: root
--

CREATE OPERATOR public.+ (
    FUNCTION = public.add_string,
    LEFTARG = character varying,
    RIGHTARG = character varying
);


ALTER OPERATOR public.+ (character varying, character varying) OWNER TO root;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.accounts (
    account_id integer NOT NULL,
    balance integer NOT NULL
);


ALTER TABLE public.accounts OWNER TO root;

--
-- Name: accounts_account_id_seq; Type: SEQUENCE; Schema: public; Owner: root
--

CREATE SEQUENCE public.accounts_account_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.accounts_account_id_seq OWNER TO root;

--
-- Name: accounts_account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: root
--

ALTER SEQUENCE public.accounts_account_id_seq OWNED BY public.accounts.account_id;


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.bookings (
    bookid integer NOT NULL,
    facid integer NOT NULL,
    memid integer NOT NULL,
    starttime timestamp without time zone NOT NULL,
    slots integer NOT NULL
);


ALTER TABLE public.bookings OWNER TO root;

--
-- Name: dndclasses; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.dndclasses (
    id integer NOT NULL,
    parent_id integer,
    name text
);


ALTER TABLE public.dndclasses OWNER TO root;

--
-- Name: dndclasses_id_seq; Type: SEQUENCE; Schema: public; Owner: root
--

ALTER TABLE public.dndclasses ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.dndclasses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: facilities; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.facilities (
    facid integer NOT NULL,
    name character varying(100) NOT NULL,
    membercost numeric NOT NULL,
    guestcost numeric NOT NULL,
    initialoutlay numeric NOT NULL,
    monthlymaintenance numeric NOT NULL
);


ALTER TABLE public.facilities OWNER TO root;

--
-- Name: members; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.members (
    memid integer NOT NULL,
    surname character varying(200) NOT NULL,
    firstname character varying(200) NOT NULL,
    address character varying(300) NOT NULL,
    zipcode integer NOT NULL,
    telephone character varying(20) NOT NULL,
    recommendedby integer,
    joindate timestamp without time zone NOT NULL
);


ALTER TABLE public.members OWNER TO root;

--
-- Name: onlyfib; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.onlyfib (
    i integer,
    CONSTRAINT onlyfib_i_check CHECK (public.is_fib(i))
);


ALTER TABLE public.onlyfib OWNER TO root;

--
-- Name: payroll; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.payroll (
    emp_no integer,
    emp_name character varying(20) NOT NULL,
    dept_name character varying(15) NOT NULL,
    salary_amt numeric(8,2) NOT NULL,
    CONSTRAINT payroll_salary_amt_check CHECK ((salary_amt > 0.00))
);


ALTER TABLE public.payroll OWNER TO root;

--
-- Name: products; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.products (
    id integer NOT NULL,
    name text,
    quantity double precision
);


ALTER TABLE public.products OWNER TO root;

--
-- Name: products_citus; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.products_citus (
    product_no integer,
    name text,
    price numeric,
    sale_price numeric,
    CONSTRAINT products_citus_check CHECK ((price > sale_price)),
    CONSTRAINT products_citus_price_check CHECK ((price > (0)::numeric)),
    CONSTRAINT products_citus_sale_price_check CHECK ((sale_price > (0)::numeric))
);


ALTER TABLE public.products_citus OWNER TO root;

--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: root
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.products_id_seq OWNER TO root;

--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: root
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.schema_migrations (
    version character varying(128) NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO root;

--
-- Name: table1; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.table1 (
    key integer NOT NULL,
    value integer,
    value_type character varying
);


ALTER TABLE public.table1 OWNER TO root;

--
-- Name: table1_key_seq; Type: SEQUENCE; Schema: public; Owner: root
--

CREATE SEQUENCE public.table1_key_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.table1_key_seq OWNER TO root;

--
-- Name: table1_key_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: root
--

ALTER SEQUENCE public.table1_key_seq OWNED BY public.table1.key;


--
-- Name: table2; Type: TABLE; Schema: public; Owner: root
--

CREATE TABLE public.table2 (
    key integer NOT NULL,
    value integer,
    value_type character varying,
    user_name name,
    action character varying,
    action_time timestamp without time zone
);


ALTER TABLE public.table2 OWNER TO root;

--
-- Name: table2_key_seq; Type: SEQUENCE; Schema: public; Owner: root
--

CREATE SEQUENCE public.table2_key_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.table2_key_seq OWNER TO root;

--
-- Name: table2_key_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: root
--

ALTER SEQUENCE public.table2_key_seq OWNED BY public.table2.key;


--
-- Name: accounts account_id; Type: DEFAULT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.accounts ALTER COLUMN account_id SET DEFAULT nextval('public.accounts_account_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: table1 key; Type: DEFAULT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.table1 ALTER COLUMN key SET DEFAULT nextval('public.table1_key_seq'::regclass);


--
-- Name: table2 key; Type: DEFAULT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.table2 ALTER COLUMN key SET DEFAULT nextval('public.table2_key_seq'::regclass);


--
-- Data for Name: accounts; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.accounts VALUES (1, 100);
INSERT INTO public.accounts VALUES (2, 100);


--
-- Data for Name: bookings; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.bookings VALUES (0, 3, 1, '2012-07-03 11:00:00', 2);
INSERT INTO public.bookings VALUES (1, 4, 1, '2012-07-03 08:00:00', 2);
INSERT INTO public.bookings VALUES (2, 6, 0, '2012-07-03 18:00:00', 2);
INSERT INTO public.bookings VALUES (3, 7, 1, '2012-07-03 19:00:00', 2);
INSERT INTO public.bookings VALUES (4, 8, 1, '2012-07-03 10:00:00', 1);
INSERT INTO public.bookings VALUES (5, 8, 1, '2012-07-03 15:00:00', 1);
INSERT INTO public.bookings VALUES (6, 0, 2, '2012-07-04 09:00:00', 3);
INSERT INTO public.bookings VALUES (7, 0, 2, '2012-07-04 15:00:00', 3);
INSERT INTO public.bookings VALUES (8, 4, 3, '2012-07-04 13:30:00', 2);
INSERT INTO public.bookings VALUES (9, 4, 0, '2012-07-04 15:00:00', 2);
INSERT INTO public.bookings VALUES (10, 4, 0, '2012-07-04 17:30:00', 2);
INSERT INTO public.bookings VALUES (11, 6, 0, '2012-07-04 12:30:00', 2);
INSERT INTO public.bookings VALUES (12, 6, 0, '2012-07-04 14:00:00', 2);
INSERT INTO public.bookings VALUES (13, 6, 1, '2012-07-04 15:30:00', 2);
INSERT INTO public.bookings VALUES (14, 7, 2, '2012-07-04 14:00:00', 2);
INSERT INTO public.bookings VALUES (15, 8, 2, '2012-07-04 12:00:00', 1);
INSERT INTO public.bookings VALUES (16, 8, 3, '2012-07-04 18:00:00', 1);
INSERT INTO public.bookings VALUES (17, 1, 0, '2012-07-05 17:30:00', 3);
INSERT INTO public.bookings VALUES (18, 2, 1, '2012-07-05 09:30:00', 3);
INSERT INTO public.bookings VALUES (19, 3, 3, '2012-07-05 09:00:00', 2);
INSERT INTO public.bookings VALUES (20, 3, 1, '2012-07-05 19:00:00', 2);
INSERT INTO public.bookings VALUES (21, 4, 3, '2012-07-05 18:30:00', 2);
INSERT INTO public.bookings VALUES (22, 6, 0, '2012-07-05 13:00:00', 2);
INSERT INTO public.bookings VALUES (23, 6, 1, '2012-07-05 14:30:00', 2);
INSERT INTO public.bookings VALUES (24, 7, 2, '2012-07-05 18:30:00', 2);
INSERT INTO public.bookings VALUES (25, 8, 3, '2012-07-05 12:30:00', 1);
INSERT INTO public.bookings VALUES (26, 0, 0, '2012-07-06 08:00:00', 3);
INSERT INTO public.bookings VALUES (27, 0, 0, '2012-07-06 14:00:00', 3);
INSERT INTO public.bookings VALUES (28, 0, 2, '2012-07-06 15:30:00', 3);
INSERT INTO public.bookings VALUES (29, 2, 1, '2012-07-06 17:00:00', 3);
INSERT INTO public.bookings VALUES (30, 3, 1, '2012-07-06 11:00:00', 2);
INSERT INTO public.bookings VALUES (31, 4, 3, '2012-07-06 12:00:00', 2);
INSERT INTO public.bookings VALUES (32, 6, 1, '2012-07-06 14:00:00', 2);
INSERT INTO public.bookings VALUES (33, 7, 2, '2012-07-06 08:30:00', 2);
INSERT INTO public.bookings VALUES (34, 7, 2, '2012-07-06 13:30:00', 2);
INSERT INTO public.bookings VALUES (35, 8, 3, '2012-07-06 15:30:00', 1);
INSERT INTO public.bookings VALUES (36, 0, 2, '2012-07-07 08:30:00', 3);
INSERT INTO public.bookings VALUES (37, 0, 0, '2012-07-07 12:30:00', 3);
INSERT INTO public.bookings VALUES (38, 0, 2, '2012-07-07 14:30:00', 3);
INSERT INTO public.bookings VALUES (39, 1, 3, '2012-07-07 08:30:00', 3);
INSERT INTO public.bookings VALUES (40, 2, 1, '2012-07-07 09:00:00', 3);
INSERT INTO public.bookings VALUES (41, 2, 1, '2012-07-07 11:30:00', 3);
INSERT INTO public.bookings VALUES (42, 2, 1, '2012-07-07 16:00:00', 3);
INSERT INTO public.bookings VALUES (43, 3, 2, '2012-07-07 12:30:00', 2);
INSERT INTO public.bookings VALUES (44, 4, 3, '2012-07-07 11:30:00', 2);
INSERT INTO public.bookings VALUES (45, 4, 3, '2012-07-07 14:00:00', 2);
INSERT INTO public.bookings VALUES (46, 4, 0, '2012-07-07 17:30:00', 2);
INSERT INTO public.bookings VALUES (47, 6, 0, '2012-07-07 08:30:00', 2);
INSERT INTO public.bookings VALUES (48, 6, 1, '2012-07-07 10:30:00', 2);
INSERT INTO public.bookings VALUES (49, 6, 1, '2012-07-07 14:30:00', 2);
INSERT INTO public.bookings VALUES (50, 6, 0, '2012-07-07 16:00:00', 2);
INSERT INTO public.bookings VALUES (51, 7, 2, '2012-07-07 11:30:00', 2);
INSERT INTO public.bookings VALUES (52, 8, 3, '2012-07-07 16:00:00', 1);
INSERT INTO public.bookings VALUES (53, 8, 3, '2012-07-07 17:30:00', 2);
INSERT INTO public.bookings VALUES (54, 0, 3, '2012-07-08 13:00:00', 3);
INSERT INTO public.bookings VALUES (55, 0, 2, '2012-07-08 17:30:00', 3);
INSERT INTO public.bookings VALUES (56, 1, 1, '2012-07-08 15:00:00', 3);
INSERT INTO public.bookings VALUES (57, 1, 1, '2012-07-08 17:30:00', 3);
INSERT INTO public.bookings VALUES (58, 3, 1, '2012-07-08 11:30:00', 2);
INSERT INTO public.bookings VALUES (59, 3, 3, '2012-07-08 18:30:00', 2);
INSERT INTO public.bookings VALUES (60, 3, 1, '2012-07-08 19:30:00', 2);
INSERT INTO public.bookings VALUES (61, 4, 0, '2012-07-08 11:00:00', 2);
INSERT INTO public.bookings VALUES (62, 4, 2, '2012-07-08 16:30:00', 2);
INSERT INTO public.bookings VALUES (63, 4, 0, '2012-07-08 18:00:00', 2);
INSERT INTO public.bookings VALUES (64, 4, 0, '2012-07-08 19:30:00', 2);
INSERT INTO public.bookings VALUES (65, 6, 0, '2012-07-08 14:00:00', 2);
INSERT INTO public.bookings VALUES (66, 6, 0, '2012-07-08 18:30:00', 2);
INSERT INTO public.bookings VALUES (67, 7, 2, '2012-07-08 11:00:00', 2);
INSERT INTO public.bookings VALUES (68, 7, 1, '2012-07-08 16:30:00', 2);
INSERT INTO public.bookings VALUES (69, 8, 3, '2012-07-08 10:00:00', 1);
INSERT INTO public.bookings VALUES (70, 8, 3, '2012-07-08 16:30:00', 1);
INSERT INTO public.bookings VALUES (71, 0, 2, '2012-07-09 12:30:00', 3);
INSERT INTO public.bookings VALUES (72, 0, 2, '2012-07-09 15:30:00', 3);
INSERT INTO public.bookings VALUES (73, 0, 2, '2012-07-09 19:00:00', 3);
INSERT INTO public.bookings VALUES (74, 1, 0, '2012-07-09 13:00:00', 3);
INSERT INTO public.bookings VALUES (75, 1, 1, '2012-07-09 19:00:00', 3);
INSERT INTO public.bookings VALUES (76, 2, 1, '2012-07-09 09:00:00', 6);
INSERT INTO public.bookings VALUES (77, 2, 0, '2012-07-09 19:00:00', 3);
INSERT INTO public.bookings VALUES (78, 3, 3, '2012-07-09 17:00:00', 2);
INSERT INTO public.bookings VALUES (79, 3, 3, '2012-07-09 18:30:00', 2);
INSERT INTO public.bookings VALUES (80, 4, 2, '2012-07-09 11:00:00', 2);
INSERT INTO public.bookings VALUES (81, 4, 3, '2012-07-09 14:30:00', 2);
INSERT INTO public.bookings VALUES (82, 6, 0, '2012-07-09 14:30:00', 2);
INSERT INTO public.bookings VALUES (83, 7, 1, '2012-07-09 15:30:00', 2);
INSERT INTO public.bookings VALUES (84, 7, 0, '2012-07-09 18:30:00', 4);
INSERT INTO public.bookings VALUES (85, 8, 3, '2012-07-09 09:30:00', 1);
INSERT INTO public.bookings VALUES (86, 8, 3, '2012-07-09 16:30:00', 1);
INSERT INTO public.bookings VALUES (87, 8, 3, '2012-07-09 20:00:00', 1);
INSERT INTO public.bookings VALUES (88, 0, 0, '2012-07-10 11:30:00', 3);
INSERT INTO public.bookings VALUES (89, 0, 0, '2012-07-10 16:00:00', 3);
INSERT INTO public.bookings VALUES (90, 3, 2, '2012-07-10 08:00:00', 2);
INSERT INTO public.bookings VALUES (91, 3, 1, '2012-07-10 11:00:00', 2);
INSERT INTO public.bookings VALUES (92, 3, 3, '2012-07-10 15:30:00', 2);
INSERT INTO public.bookings VALUES (93, 3, 2, '2012-07-10 16:30:00', 2);
INSERT INTO public.bookings VALUES (94, 3, 1, '2012-07-10 18:00:00', 2);
INSERT INTO public.bookings VALUES (95, 4, 0, '2012-07-10 10:00:00', 2);
INSERT INTO public.bookings VALUES (96, 4, 4, '2012-07-10 11:30:00', 2);
INSERT INTO public.bookings VALUES (97, 4, 0, '2012-07-10 15:00:00', 2);
INSERT INTO public.bookings VALUES (98, 4, 3, '2012-07-10 17:00:00', 4);
INSERT INTO public.bookings VALUES (99, 5, 0, '2012-07-10 08:30:00', 2);
INSERT INTO public.bookings VALUES (100, 6, 0, '2012-07-10 14:30:00', 2);
INSERT INTO public.bookings VALUES (101, 6, 0, '2012-07-10 19:00:00', 2);
INSERT INTO public.bookings VALUES (102, 7, 4, '2012-07-10 08:30:00', 2);
INSERT INTO public.bookings VALUES (103, 7, 2, '2012-07-10 17:30:00', 2);
INSERT INTO public.bookings VALUES (104, 8, 0, '2012-07-10 11:30:00', 1);
INSERT INTO public.bookings VALUES (105, 8, 3, '2012-07-10 12:00:00', 1);
INSERT INTO public.bookings VALUES (106, 8, 3, '2012-07-10 19:30:00', 1);
INSERT INTO public.bookings VALUES (107, 0, 4, '2012-07-11 08:00:00', 3);
INSERT INTO public.bookings VALUES (108, 0, 2, '2012-07-11 10:00:00', 3);
INSERT INTO public.bookings VALUES (109, 0, 0, '2012-07-11 12:00:00', 3);
INSERT INTO public.bookings VALUES (110, 0, 0, '2012-07-11 14:00:00', 3);
INSERT INTO public.bookings VALUES (111, 0, 2, '2012-07-11 15:30:00', 3);
INSERT INTO public.bookings VALUES (112, 0, 2, '2012-07-11 18:30:00', 3);
INSERT INTO public.bookings VALUES (113, 1, 0, '2012-07-11 12:30:00', 3);
INSERT INTO public.bookings VALUES (114, 1, 0, '2012-07-11 16:00:00', 3);
INSERT INTO public.bookings VALUES (115, 4, 1, '2012-07-11 08:00:00', 2);
INSERT INTO public.bookings VALUES (116, 4, 0, '2012-07-11 09:00:00', 2);
INSERT INTO public.bookings VALUES (117, 4, 3, '2012-07-11 11:00:00', 2);
INSERT INTO public.bookings VALUES (118, 4, 0, '2012-07-11 15:00:00', 2);
INSERT INTO public.bookings VALUES (119, 5, 4, '2012-07-11 17:00:00', 2);
INSERT INTO public.bookings VALUES (120, 6, 0, '2012-07-11 14:00:00', 2);
INSERT INTO public.bookings VALUES (121, 6, 0, '2012-07-11 19:30:00', 2);
INSERT INTO public.bookings VALUES (122, 7, 0, '2012-07-11 08:00:00', 2);
INSERT INTO public.bookings VALUES (123, 7, 0, '2012-07-11 14:00:00', 2);
INSERT INTO public.bookings VALUES (124, 7, 0, '2012-07-11 16:30:00', 2);
INSERT INTO public.bookings VALUES (125, 8, 4, '2012-07-11 11:00:00', 1);
INSERT INTO public.bookings VALUES (126, 8, 3, '2012-07-11 13:00:00', 1);
INSERT INTO public.bookings VALUES (127, 0, 0, '2012-07-12 13:30:00', 3);
INSERT INTO public.bookings VALUES (128, 0, 2, '2012-07-12 16:30:00', 3);
INSERT INTO public.bookings VALUES (129, 1, 1, '2012-07-12 11:30:00', 3);
INSERT INTO public.bookings VALUES (130, 2, 1, '2012-07-12 09:00:00', 3);
INSERT INTO public.bookings VALUES (131, 2, 1, '2012-07-12 18:30:00', 3);
INSERT INTO public.bookings VALUES (132, 3, 3, '2012-07-12 18:00:00', 2);
INSERT INTO public.bookings VALUES (133, 4, 1, '2012-07-12 16:00:00', 2);
INSERT INTO public.bookings VALUES (134, 6, 0, '2012-07-12 12:00:00', 4);
INSERT INTO public.bookings VALUES (135, 7, 2, '2012-07-12 08:00:00', 2);
INSERT INTO public.bookings VALUES (136, 7, 4, '2012-07-12 13:30:00', 2);
INSERT INTO public.bookings VALUES (137, 7, 4, '2012-07-12 16:00:00', 2);
INSERT INTO public.bookings VALUES (138, 8, 3, '2012-07-12 16:30:00', 1);
INSERT INTO public.bookings VALUES (139, 0, 2, '2012-07-13 10:30:00', 3);
INSERT INTO public.bookings VALUES (140, 0, 4, '2012-07-13 14:00:00', 3);
INSERT INTO public.bookings VALUES (141, 0, 3, '2012-07-13 17:00:00', 3);
INSERT INTO public.bookings VALUES (142, 1, 1, '2012-07-13 15:00:00', 3);
INSERT INTO public.bookings VALUES (143, 2, 1, '2012-07-13 09:00:00', 3);
INSERT INTO public.bookings VALUES (144, 2, 0, '2012-07-13 15:00:00', 3);
INSERT INTO public.bookings VALUES (145, 2, 1, '2012-07-13 16:30:00', 3);
INSERT INTO public.bookings VALUES (146, 4, 0, '2012-07-13 11:00:00', 2);
INSERT INTO public.bookings VALUES (147, 4, 0, '2012-07-13 13:30:00', 2);
INSERT INTO public.bookings VALUES (148, 4, 0, '2012-07-13 15:00:00', 2);
INSERT INTO public.bookings VALUES (149, 4, 3, '2012-07-13 16:00:00', 2);
INSERT INTO public.bookings VALUES (150, 4, 4, '2012-07-13 17:30:00', 2);
INSERT INTO public.bookings VALUES (151, 6, 0, '2012-07-13 09:30:00', 2);
INSERT INTO public.bookings VALUES (152, 7, 0, '2012-07-13 08:00:00', 2);
INSERT INTO public.bookings VALUES (153, 7, 1, '2012-07-13 11:00:00', 2);
INSERT INTO public.bookings VALUES (154, 7, 4, '2012-07-13 12:30:00', 2);
INSERT INTO public.bookings VALUES (155, 8, 0, '2012-07-13 15:30:00', 1);
INSERT INTO public.bookings VALUES (156, 8, 2, '2012-07-13 18:30:00', 1);
INSERT INTO public.bookings VALUES (157, 0, 2, '2012-07-14 08:30:00', 3);
INSERT INTO public.bookings VALUES (158, 0, 4, '2012-07-14 11:30:00', 3);
INSERT INTO public.bookings VALUES (159, 0, 3, '2012-07-14 15:00:00', 3);
INSERT INTO public.bookings VALUES (160, 1, 3, '2012-07-14 10:30:00', 3);
INSERT INTO public.bookings VALUES (161, 1, 3, '2012-07-14 12:30:00', 3);
INSERT INTO public.bookings VALUES (162, 1, 0, '2012-07-14 14:30:00', 3);
INSERT INTO public.bookings VALUES (163, 2, 1, '2012-07-14 08:30:00', 3);
INSERT INTO public.bookings VALUES (164, 3, 2, '2012-07-14 16:00:00', 2);
INSERT INTO public.bookings VALUES (165, 4, 3, '2012-07-14 08:00:00', 2);
INSERT INTO public.bookings VALUES (166, 4, 1, '2012-07-14 14:30:00', 2);
INSERT INTO public.bookings VALUES (167, 6, 0, '2012-07-14 09:30:00', 2);
INSERT INTO public.bookings VALUES (168, 6, 1, '2012-07-14 12:30:00', 2);
INSERT INTO public.bookings VALUES (169, 6, 0, '2012-07-14 15:00:00', 2);
INSERT INTO public.bookings VALUES (170, 7, 2, '2012-07-14 12:30:00', 2);
INSERT INTO public.bookings VALUES (171, 7, 2, '2012-07-14 15:00:00', 2);
INSERT INTO public.bookings VALUES (172, 7, 4, '2012-07-14 16:30:00', 2);
INSERT INTO public.bookings VALUES (173, 7, 1, '2012-07-14 19:00:00', 2);
INSERT INTO public.bookings VALUES (174, 8, 3, '2012-07-14 09:00:00', 1);
INSERT INTO public.bookings VALUES (175, 8, 1, '2012-07-14 17:00:00', 1);
INSERT INTO public.bookings VALUES (176, 0, 2, '2012-07-15 08:00:00', 3);
INSERT INTO public.bookings VALUES (177, 0, 0, '2012-07-15 16:00:00', 3);
INSERT INTO public.bookings VALUES (178, 0, 2, '2012-07-15 19:00:00', 3);
INSERT INTO public.bookings VALUES (179, 1, 0, '2012-07-15 10:00:00', 3);
INSERT INTO public.bookings VALUES (180, 1, 0, '2012-07-15 12:00:00', 3);
INSERT INTO public.bookings VALUES (181, 1, 3, '2012-07-15 15:30:00', 3);
INSERT INTO public.bookings VALUES (182, 2, 1, '2012-07-15 13:00:00', 3);
INSERT INTO public.bookings VALUES (183, 3, 1, '2012-07-15 17:30:00', 2);
INSERT INTO public.bookings VALUES (184, 4, 3, '2012-07-15 11:30:00', 2);
INSERT INTO public.bookings VALUES (185, 4, 0, '2012-07-15 15:00:00', 2);
INSERT INTO public.bookings VALUES (186, 4, 3, '2012-07-15 17:30:00', 2);
INSERT INTO public.bookings VALUES (187, 7, 4, '2012-07-15 14:30:00', 2);
INSERT INTO public.bookings VALUES (188, 7, 4, '2012-07-15 17:00:00', 2);
INSERT INTO public.bookings VALUES (189, 8, 4, '2012-07-15 10:00:00', 1);
INSERT INTO public.bookings VALUES (190, 8, 2, '2012-07-15 12:00:00', 1);
INSERT INTO public.bookings VALUES (191, 8, 3, '2012-07-15 12:30:00', 1);
INSERT INTO public.bookings VALUES (192, 8, 3, '2012-07-15 13:30:00', 1);
INSERT INTO public.bookings VALUES (193, 0, 5, '2012-07-16 11:00:00', 3);
INSERT INTO public.bookings VALUES (194, 0, 5, '2012-07-16 19:00:00', 3);
INSERT INTO public.bookings VALUES (195, 1, 1, '2012-07-16 08:00:00', 3);
INSERT INTO public.bookings VALUES (196, 1, 0, '2012-07-16 12:30:00', 3);
INSERT INTO public.bookings VALUES (197, 2, 1, '2012-07-16 16:30:00', 3);
INSERT INTO public.bookings VALUES (198, 4, 3, '2012-07-16 09:00:00', 2);
INSERT INTO public.bookings VALUES (199, 4, 1, '2012-07-16 11:00:00', 2);
INSERT INTO public.bookings VALUES (200, 4, 3, '2012-07-16 12:00:00', 2);
INSERT INTO public.bookings VALUES (201, 4, 3, '2012-07-16 17:30:00', 2);
INSERT INTO public.bookings VALUES (202, 6, 0, '2012-07-16 18:30:00', 2);
INSERT INTO public.bookings VALUES (203, 7, 4, '2012-07-16 08:00:00', 2);
INSERT INTO public.bookings VALUES (204, 7, 2, '2012-07-16 11:30:00', 2);
INSERT INTO public.bookings VALUES (205, 7, 4, '2012-07-16 12:30:00', 2);
INSERT INTO public.bookings VALUES (206, 7, 5, '2012-07-16 14:00:00', 2);
INSERT INTO public.bookings VALUES (207, 8, 4, '2012-07-16 12:00:00', 1);
INSERT INTO public.bookings VALUES (208, 8, 1, '2012-07-16 15:00:00', 1);
INSERT INTO public.bookings VALUES (209, 8, 4, '2012-07-16 18:00:00', 1);
INSERT INTO public.bookings VALUES (210, 8, 3, '2012-07-16 19:30:00', 1);
INSERT INTO public.bookings VALUES (211, 0, 5, '2012-07-17 12:30:00', 3);
INSERT INTO public.bookings VALUES (212, 0, 5, '2012-07-17 18:00:00', 3);
INSERT INTO public.bookings VALUES (213, 1, 1, '2012-07-17 10:00:00', 3);
INSERT INTO public.bookings VALUES (214, 1, 4, '2012-07-17 14:30:00', 3);
INSERT INTO public.bookings VALUES (215, 2, 5, '2012-07-17 10:30:00', 3);
INSERT INTO public.bookings VALUES (216, 2, 1, '2012-07-17 12:30:00', 3);
INSERT INTO public.bookings VALUES (217, 2, 1, '2012-07-17 15:30:00', 3);
INSERT INTO public.bookings VALUES (218, 2, 2, '2012-07-17 19:00:00', 3);
INSERT INTO public.bookings VALUES (219, 3, 1, '2012-07-17 14:00:00', 2);
INSERT INTO public.bookings VALUES (220, 3, 2, '2012-07-17 15:00:00', 2);
INSERT INTO public.bookings VALUES (221, 4, 0, '2012-07-17 09:00:00', 2);
INSERT INTO public.bookings VALUES (222, 4, 3, '2012-07-17 10:30:00', 2);
INSERT INTO public.bookings VALUES (223, 4, 3, '2012-07-17 12:00:00', 2);
INSERT INTO public.bookings VALUES (224, 4, 5, '2012-07-17 16:00:00', 2);
INSERT INTO public.bookings VALUES (225, 4, 3, '2012-07-17 18:30:00', 2);
INSERT INTO public.bookings VALUES (226, 5, 0, '2012-07-17 13:30:00', 2);
INSERT INTO public.bookings VALUES (227, 6, 4, '2012-07-17 12:00:00', 2);
INSERT INTO public.bookings VALUES (228, 6, 0, '2012-07-17 14:00:00', 2);
INSERT INTO public.bookings VALUES (229, 7, 4, '2012-07-17 08:00:00', 2);
INSERT INTO public.bookings VALUES (230, 7, 5, '2012-07-17 14:00:00', 2);
INSERT INTO public.bookings VALUES (231, 7, 4, '2012-07-17 16:00:00', 2);
INSERT INTO public.bookings VALUES (232, 8, 3, '2012-07-17 08:30:00', 1);
INSERT INTO public.bookings VALUES (233, 8, 2, '2012-07-17 11:00:00', 1);
INSERT INTO public.bookings VALUES (234, 8, 3, '2012-07-17 11:30:00', 1);
INSERT INTO public.bookings VALUES (235, 8, 3, '2012-07-17 14:30:00', 1);
INSERT INTO public.bookings VALUES (236, 8, 0, '2012-07-17 15:00:00', 1);
INSERT INTO public.bookings VALUES (237, 8, 3, '2012-07-17 15:30:00', 1);
INSERT INTO public.bookings VALUES (238, 8, 3, '2012-07-17 18:00:00', 1);
INSERT INTO public.bookings VALUES (239, 8, 3, '2012-07-17 20:00:00', 1);
INSERT INTO public.bookings VALUES (240, 0, 5, '2012-07-18 13:00:00', 3);
INSERT INTO public.bookings VALUES (241, 0, 5, '2012-07-18 17:30:00', 3);
INSERT INTO public.bookings VALUES (242, 1, 0, '2012-07-18 14:00:00', 3);
INSERT INTO public.bookings VALUES (243, 1, 0, '2012-07-18 16:30:00', 3);
INSERT INTO public.bookings VALUES (244, 2, 1, '2012-07-18 14:00:00', 3);
INSERT INTO public.bookings VALUES (245, 3, 2, '2012-07-18 11:30:00', 2);
INSERT INTO public.bookings VALUES (246, 3, 3, '2012-07-18 19:00:00', 2);
INSERT INTO public.bookings VALUES (247, 4, 1, '2012-07-18 08:30:00', 2);
INSERT INTO public.bookings VALUES (248, 4, 4, '2012-07-18 10:00:00', 2);
INSERT INTO public.bookings VALUES (249, 4, 5, '2012-07-18 19:00:00', 2);
INSERT INTO public.bookings VALUES (250, 5, 0, '2012-07-18 14:30:00', 2);
INSERT INTO public.bookings VALUES (251, 6, 0, '2012-07-18 10:30:00', 2);
INSERT INTO public.bookings VALUES (252, 6, 0, '2012-07-18 13:00:00', 2);
INSERT INTO public.bookings VALUES (253, 6, 0, '2012-07-18 15:00:00', 2);
INSERT INTO public.bookings VALUES (254, 6, 1, '2012-07-18 19:30:00', 2);
INSERT INTO public.bookings VALUES (255, 7, 4, '2012-07-18 08:30:00', 2);
INSERT INTO public.bookings VALUES (256, 7, 4, '2012-07-18 11:00:00', 2);
INSERT INTO public.bookings VALUES (257, 8, 3, '2012-07-18 11:00:00', 1);
INSERT INTO public.bookings VALUES (258, 8, 0, '2012-07-18 13:00:00', 1);
INSERT INTO public.bookings VALUES (259, 8, 3, '2012-07-18 14:30:00', 1);
INSERT INTO public.bookings VALUES (260, 8, 4, '2012-07-18 16:00:00', 1);
INSERT INTO public.bookings VALUES (261, 8, 3, '2012-07-18 16:30:00', 1);
INSERT INTO public.bookings VALUES (262, 8, 4, '2012-07-18 20:00:00', 1);
INSERT INTO public.bookings VALUES (263, 0, 2, '2012-07-19 08:30:00', 3);
INSERT INTO public.bookings VALUES (264, 0, 4, '2012-07-19 10:30:00', 3);
INSERT INTO public.bookings VALUES (265, 0, 5, '2012-07-19 12:00:00', 3);
INSERT INTO public.bookings VALUES (266, 0, 0, '2012-07-19 13:30:00', 3);
INSERT INTO public.bookings VALUES (267, 0, 5, '2012-07-19 16:30:00', 3);
INSERT INTO public.bookings VALUES (268, 1, 1, '2012-07-19 11:30:00', 3);
INSERT INTO public.bookings VALUES (269, 1, 0, '2012-07-19 15:00:00', 3);
INSERT INTO public.bookings VALUES (270, 1, 0, '2012-07-19 18:30:00', 3);
INSERT INTO public.bookings VALUES (271, 2, 1, '2012-07-19 09:30:00', 3);
INSERT INTO public.bookings VALUES (272, 2, 0, '2012-07-19 11:30:00', 3);
INSERT INTO public.bookings VALUES (273, 2, 1, '2012-07-19 14:30:00', 3);
INSERT INTO public.bookings VALUES (274, 2, 2, '2012-07-19 16:00:00', 3);
INSERT INTO public.bookings VALUES (275, 3, 3, '2012-07-19 08:30:00', 2);
INSERT INTO public.bookings VALUES (276, 3, 3, '2012-07-19 17:00:00', 2);
INSERT INTO public.bookings VALUES (277, 3, 3, '2012-07-19 18:30:00', 2);
INSERT INTO public.bookings VALUES (278, 4, 3, '2012-07-19 12:00:00', 2);
INSERT INTO public.bookings VALUES (279, 4, 5, '2012-07-19 14:30:00', 2);
INSERT INTO public.bookings VALUES (280, 4, 0, '2012-07-19 16:30:00', 2);
INSERT INTO public.bookings VALUES (281, 4, 1, '2012-07-19 18:30:00', 2);
INSERT INTO public.bookings VALUES (282, 4, 0, '2012-07-19 19:30:00', 2);
INSERT INTO public.bookings VALUES (283, 5, 0, '2012-07-19 08:30:00', 2);
INSERT INTO public.bookings VALUES (284, 6, 4, '2012-07-19 12:30:00', 2);
INSERT INTO public.bookings VALUES (285, 6, 2, '2012-07-19 14:00:00', 2);
INSERT INTO public.bookings VALUES (286, 6, 0, '2012-07-19 15:00:00', 2);
INSERT INTO public.bookings VALUES (287, 6, 0, '2012-07-19 16:30:00', 2);
INSERT INTO public.bookings VALUES (288, 7, 2, '2012-07-19 13:00:00', 2);
INSERT INTO public.bookings VALUES (289, 7, 0, '2012-07-19 14:00:00', 2);
INSERT INTO public.bookings VALUES (290, 7, 0, '2012-07-19 16:30:00', 2);
INSERT INTO public.bookings VALUES (291, 7, 4, '2012-07-19 17:30:00', 4);
INSERT INTO public.bookings VALUES (292, 8, 3, '2012-07-19 11:00:00', 1);
INSERT INTO public.bookings VALUES (293, 8, 1, '2012-07-19 13:30:00', 1);
INSERT INTO public.bookings VALUES (294, 8, 3, '2012-07-19 14:30:00', 1);
INSERT INTO public.bookings VALUES (295, 8, 3, '2012-07-19 18:00:00', 1);
INSERT INTO public.bookings VALUES (296, 8, 3, '2012-07-19 20:00:00', 1);
INSERT INTO public.bookings VALUES (297, 0, 3, '2012-07-20 08:00:00', 3);
INSERT INTO public.bookings VALUES (298, 0, 5, '2012-07-20 12:00:00', 3);
INSERT INTO public.bookings VALUES (299, 0, 5, '2012-07-20 14:00:00', 3);
INSERT INTO public.bookings VALUES (300, 0, 5, '2012-07-20 17:30:00', 3);
INSERT INTO public.bookings VALUES (301, 0, 0, '2012-07-20 19:00:00', 3);
INSERT INTO public.bookings VALUES (302, 1, 2, '2012-07-20 08:30:00', 3);
INSERT INTO public.bookings VALUES (303, 1, 3, '2012-07-20 12:00:00', 3);
INSERT INTO public.bookings VALUES (304, 1, 4, '2012-07-20 13:30:00', 3);
INSERT INTO public.bookings VALUES (305, 2, 1, '2012-07-20 14:30:00', 3);
INSERT INTO public.bookings VALUES (306, 3, 3, '2012-07-20 15:00:00', 2);
INSERT INTO public.bookings VALUES (307, 3, 1, '2012-07-20 17:30:00', 2);
INSERT INTO public.bookings VALUES (308, 4, 5, '2012-07-20 08:00:00', 2);
INSERT INTO public.bookings VALUES (309, 4, 0, '2012-07-20 13:00:00', 2);
INSERT INTO public.bookings VALUES (310, 4, 1, '2012-07-20 16:30:00', 2);
INSERT INTO public.bookings VALUES (311, 4, 0, '2012-07-20 17:30:00', 2);
INSERT INTO public.bookings VALUES (312, 4, 3, '2012-07-20 18:30:00', 2);
INSERT INTO public.bookings VALUES (313, 6, 0, '2012-07-20 11:00:00', 2);
INSERT INTO public.bookings VALUES (314, 6, 4, '2012-07-20 12:30:00', 2);
INSERT INTO public.bookings VALUES (315, 6, 2, '2012-07-20 15:00:00', 2);
INSERT INTO public.bookings VALUES (316, 6, 0, '2012-07-20 16:00:00', 4);
INSERT INTO public.bookings VALUES (317, 7, 2, '2012-07-20 12:30:00', 2);
INSERT INTO public.bookings VALUES (318, 7, 2, '2012-07-20 16:00:00', 2);
INSERT INTO public.bookings VALUES (319, 7, 4, '2012-07-20 19:30:00', 2);
INSERT INTO public.bookings VALUES (320, 8, 1, '2012-07-20 09:00:00', 1);
INSERT INTO public.bookings VALUES (321, 8, 2, '2012-07-20 12:00:00', 1);
INSERT INTO public.bookings VALUES (322, 8, 3, '2012-07-20 19:30:00', 1);
INSERT INTO public.bookings VALUES (323, 0, 0, '2012-07-21 08:00:00', 3);
INSERT INTO public.bookings VALUES (324, 0, 5, '2012-07-21 11:00:00', 3);
INSERT INTO public.bookings VALUES (325, 0, 5, '2012-07-21 13:30:00', 3);
INSERT INTO public.bookings VALUES (326, 0, 4, '2012-07-21 15:30:00', 3);
INSERT INTO public.bookings VALUES (327, 1, 1, '2012-07-21 09:30:00', 3);
INSERT INTO public.bookings VALUES (328, 1, 0, '2012-07-21 11:00:00', 3);
INSERT INTO public.bookings VALUES (329, 2, 0, '2012-07-21 10:30:00', 3);
INSERT INTO public.bookings VALUES (330, 2, 1, '2012-07-21 13:30:00', 3);
INSERT INTO public.bookings VALUES (331, 3, 2, '2012-07-21 08:00:00', 2);
INSERT INTO public.bookings VALUES (332, 4, 0, '2012-07-21 09:00:00', 2);
INSERT INTO public.bookings VALUES (333, 4, 3, '2012-07-21 10:30:00', 2);
INSERT INTO public.bookings VALUES (334, 4, 0, '2012-07-21 14:00:00', 4);
INSERT INTO public.bookings VALUES (335, 4, 3, '2012-07-21 16:00:00', 2);
INSERT INTO public.bookings VALUES (336, 4, 1, '2012-07-21 17:00:00', 2);
INSERT INTO public.bookings VALUES (337, 4, 0, '2012-07-21 19:00:00', 2);
INSERT INTO public.bookings VALUES (338, 6, 4, '2012-07-21 08:00:00', 2);
INSERT INTO public.bookings VALUES (339, 6, 0, '2012-07-21 09:30:00', 2);
INSERT INTO public.bookings VALUES (340, 6, 0, '2012-07-21 12:00:00', 2);
INSERT INTO public.bookings VALUES (341, 8, 3, '2012-07-21 09:30:00', 1);
INSERT INTO public.bookings VALUES (342, 8, 3, '2012-07-21 11:30:00', 1);
INSERT INTO public.bookings VALUES (343, 8, 3, '2012-07-21 18:00:00', 2);
INSERT INTO public.bookings VALUES (344, 8, 3, '2012-07-21 19:30:00', 1);
INSERT INTO public.bookings VALUES (345, 0, 5, '2012-07-22 10:00:00', 3);
INSERT INTO public.bookings VALUES (346, 0, 0, '2012-07-22 16:00:00', 3);
INSERT INTO public.bookings VALUES (347, 0, 2, '2012-07-22 18:00:00', 3);
INSERT INTO public.bookings VALUES (348, 1, 0, '2012-07-22 08:30:00', 3);
INSERT INTO public.bookings VALUES (349, 1, 0, '2012-07-22 10:30:00', 3);
INSERT INTO public.bookings VALUES (350, 1, 5, '2012-07-22 18:30:00', 3);
INSERT INTO public.bookings VALUES (351, 2, 1, '2012-07-22 08:30:00', 3);
INSERT INTO public.bookings VALUES (352, 2, 1, '2012-07-22 13:30:00', 3);
INSERT INTO public.bookings VALUES (353, 2, 1, '2012-07-22 16:30:00', 3);
INSERT INTO public.bookings VALUES (354, 3, 3, '2012-07-22 11:30:00', 2);
INSERT INTO public.bookings VALUES (355, 3, 2, '2012-07-22 14:00:00', 2);
INSERT INTO public.bookings VALUES (356, 4, 4, '2012-07-22 08:00:00', 2);
INSERT INTO public.bookings VALUES (357, 4, 3, '2012-07-22 10:30:00', 2);
INSERT INTO public.bookings VALUES (358, 4, 0, '2012-07-22 12:00:00', 2);
INSERT INTO public.bookings VALUES (359, 4, 5, '2012-07-22 13:00:00', 2);
INSERT INTO public.bookings VALUES (360, 4, 0, '2012-07-22 16:30:00', 2);
INSERT INTO public.bookings VALUES (361, 4, 1, '2012-07-22 18:00:00', 2);
INSERT INTO public.bookings VALUES (362, 4, 3, '2012-07-22 19:30:00', 2);
INSERT INTO public.bookings VALUES (363, 6, 4, '2012-07-22 10:30:00', 4);
INSERT INTO public.bookings VALUES (364, 6, 0, '2012-07-22 14:30:00', 2);
INSERT INTO public.bookings VALUES (365, 6, 0, '2012-07-22 16:30:00', 2);
INSERT INTO public.bookings VALUES (366, 7, 2, '2012-07-22 10:30:00', 2);
INSERT INTO public.bookings VALUES (367, 7, 2, '2012-07-22 12:00:00', 2);
INSERT INTO public.bookings VALUES (368, 8, 3, '2012-07-22 16:00:00', 1);
INSERT INTO public.bookings VALUES (369, 8, 3, '2012-07-22 17:00:00', 1);
INSERT INTO public.bookings VALUES (370, 8, 2, '2012-07-22 17:30:00', 1);
INSERT INTO public.bookings VALUES (371, 0, 0, '2012-07-23 09:30:00', 3);
INSERT INTO public.bookings VALUES (372, 0, 0, '2012-07-23 12:00:00', 3);
INSERT INTO public.bookings VALUES (373, 0, 5, '2012-07-23 17:00:00', 3);
INSERT INTO public.bookings VALUES (374, 1, 1, '2012-07-23 10:00:00', 3);
INSERT INTO public.bookings VALUES (375, 1, 4, '2012-07-23 12:30:00', 3);
INSERT INTO public.bookings VALUES (376, 1, 4, '2012-07-23 15:30:00', 3);
INSERT INTO public.bookings VALUES (377, 1, 0, '2012-07-23 17:00:00', 3);
INSERT INTO public.bookings VALUES (378, 1, 4, '2012-07-23 19:00:00', 3);
INSERT INTO public.bookings VALUES (379, 2, 1, '2012-07-23 08:00:00', 3);
INSERT INTO public.bookings VALUES (380, 2, 5, '2012-07-23 11:30:00', 3);
INSERT INTO public.bookings VALUES (381, 2, 1, '2012-07-23 13:00:00', 3);
INSERT INTO public.bookings VALUES (382, 2, 1, '2012-07-23 15:00:00', 3);
INSERT INTO public.bookings VALUES (383, 3, 2, '2012-07-23 09:30:00', 2);
INSERT INTO public.bookings VALUES (384, 3, 2, '2012-07-23 19:00:00', 2);
INSERT INTO public.bookings VALUES (385, 4, 4, '2012-07-23 10:00:00', 2);
INSERT INTO public.bookings VALUES (386, 4, 0, '2012-07-23 16:30:00', 2);
INSERT INTO public.bookings VALUES (387, 4, 3, '2012-07-23 19:00:00', 2);
INSERT INTO public.bookings VALUES (388, 5, 3, '2012-07-23 13:00:00', 2);
INSERT INTO public.bookings VALUES (389, 6, 0, '2012-07-23 13:30:00', 2);
INSERT INTO public.bookings VALUES (390, 6, 0, '2012-07-23 15:00:00', 4);
INSERT INTO public.bookings VALUES (391, 6, 0, '2012-07-23 19:00:00', 2);
INSERT INTO public.bookings VALUES (392, 7, 5, '2012-07-23 16:00:00', 2);
INSERT INTO public.bookings VALUES (393, 7, 4, '2012-07-23 18:00:00', 2);
INSERT INTO public.bookings VALUES (394, 8, 3, '2012-07-23 08:30:00', 3);
INSERT INTO public.bookings VALUES (395, 8, 3, '2012-07-23 11:00:00', 1);
INSERT INTO public.bookings VALUES (396, 8, 3, '2012-07-23 14:00:00', 2);
INSERT INTO public.bookings VALUES (397, 8, 2, '2012-07-23 15:00:00', 1);
INSERT INTO public.bookings VALUES (398, 0, 0, '2012-07-24 11:00:00', 3);
INSERT INTO public.bookings VALUES (399, 0, 4, '2012-07-24 13:00:00', 3);
INSERT INTO public.bookings VALUES (400, 0, 5, '2012-07-24 14:30:00', 3);
INSERT INTO public.bookings VALUES (401, 1, 4, '2012-07-24 11:00:00', 3);
INSERT INTO public.bookings VALUES (402, 1, 0, '2012-07-24 16:00:00', 6);
INSERT INTO public.bookings VALUES (403, 1, 1, '2012-07-24 19:00:00', 3);
INSERT INTO public.bookings VALUES (404, 2, 1, '2012-07-24 09:00:00', 3);
INSERT INTO public.bookings VALUES (405, 2, 2, '2012-07-24 12:30:00', 3);
INSERT INTO public.bookings VALUES (406, 3, 3, '2012-07-24 09:00:00', 2);
INSERT INTO public.bookings VALUES (407, 3, 3, '2012-07-24 17:30:00', 2);
INSERT INTO public.bookings VALUES (408, 4, 0, '2012-07-24 08:30:00', 2);
INSERT INTO public.bookings VALUES (409, 4, 5, '2012-07-24 09:30:00', 2);
INSERT INTO public.bookings VALUES (410, 4, 0, '2012-07-24 11:30:00', 2);
INSERT INTO public.bookings VALUES (411, 4, 1, '2012-07-24 14:30:00', 2);
INSERT INTO public.bookings VALUES (412, 4, 0, '2012-07-24 15:30:00', 2);
INSERT INTO public.bookings VALUES (413, 4, 0, '2012-07-24 17:30:00', 2);
INSERT INTO public.bookings VALUES (414, 4, 0, '2012-07-24 19:30:00', 2);
INSERT INTO public.bookings VALUES (415, 5, 5, '2012-07-24 16:30:00', 2);
INSERT INTO public.bookings VALUES (416, 6, 0, '2012-07-24 09:30:00', 2);
INSERT INTO public.bookings VALUES (417, 6, 0, '2012-07-24 14:30:00', 2);
INSERT INTO public.bookings VALUES (418, 7, 4, '2012-07-24 09:30:00', 2);
INSERT INTO public.bookings VALUES (419, 7, 5, '2012-07-24 11:30:00', 2);
INSERT INTO public.bookings VALUES (420, 7, 2, '2012-07-24 16:30:00', 2);
INSERT INTO public.bookings VALUES (421, 7, 4, '2012-07-24 18:00:00', 2);
INSERT INTO public.bookings VALUES (422, 7, 2, '2012-07-24 19:30:00', 2);
INSERT INTO public.bookings VALUES (423, 8, 3, '2012-07-24 08:30:00', 1);
INSERT INTO public.bookings VALUES (424, 8, 3, '2012-07-24 10:30:00', 2);
INSERT INTO public.bookings VALUES (425, 8, 3, '2012-07-24 12:00:00', 1);
INSERT INTO public.bookings VALUES (426, 8, 3, '2012-07-24 14:00:00', 1);
INSERT INTO public.bookings VALUES (427, 8, 0, '2012-07-24 15:00:00', 1);
INSERT INTO public.bookings VALUES (428, 8, 4, '2012-07-24 16:30:00', 1);
INSERT INTO public.bookings VALUES (429, 8, 0, '2012-07-24 20:00:00', 1);
INSERT INTO public.bookings VALUES (430, 0, 5, '2012-07-25 08:00:00', 3);
INSERT INTO public.bookings VALUES (431, 0, 0, '2012-07-25 12:30:00', 3);
INSERT INTO public.bookings VALUES (432, 0, 0, '2012-07-25 16:30:00', 3);
INSERT INTO public.bookings VALUES (433, 1, 1, '2012-07-25 08:00:00', 3);
INSERT INTO public.bookings VALUES (434, 1, 0, '2012-07-25 10:30:00', 3);
INSERT INTO public.bookings VALUES (435, 1, 4, '2012-07-25 15:00:00', 3);
INSERT INTO public.bookings VALUES (436, 2, 1, '2012-07-25 13:30:00', 3);
INSERT INTO public.bookings VALUES (437, 2, 1, '2012-07-25 17:30:00', 3);
INSERT INTO public.bookings VALUES (438, 3, 2, '2012-07-25 10:00:00', 2);
INSERT INTO public.bookings VALUES (439, 3, 3, '2012-07-25 14:00:00', 4);
INSERT INTO public.bookings VALUES (440, 3, 3, '2012-07-25 17:00:00', 2);
INSERT INTO public.bookings VALUES (441, 3, 2, '2012-07-25 18:30:00', 2);
INSERT INTO public.bookings VALUES (442, 4, 3, '2012-07-25 08:30:00', 2);
INSERT INTO public.bookings VALUES (443, 4, 0, '2012-07-25 09:30:00', 4);
INSERT INTO public.bookings VALUES (444, 4, 3, '2012-07-25 11:30:00', 4);
INSERT INTO public.bookings VALUES (445, 4, 5, '2012-07-25 13:30:00', 4);
INSERT INTO public.bookings VALUES (446, 4, 3, '2012-07-25 16:00:00', 2);
INSERT INTO public.bookings VALUES (447, 4, 3, '2012-07-25 18:00:00', 2);
INSERT INTO public.bookings VALUES (448, 4, 3, '2012-07-25 19:30:00', 2);
INSERT INTO public.bookings VALUES (449, 5, 0, '2012-07-25 18:30:00', 2);
INSERT INTO public.bookings VALUES (450, 6, 4, '2012-07-25 08:30:00', 2);
INSERT INTO public.bookings VALUES (451, 6, 1, '2012-07-25 09:30:00', 2);
INSERT INTO public.bookings VALUES (452, 6, 0, '2012-07-25 12:00:00', 2);
INSERT INTO public.bookings VALUES (453, 6, 0, '2012-07-25 13:30:00', 2);
INSERT INTO public.bookings VALUES (454, 6, 0, '2012-07-25 16:30:00', 4);
INSERT INTO public.bookings VALUES (455, 6, 5, '2012-07-25 19:00:00', 2);
INSERT INTO public.bookings VALUES (456, 7, 5, '2012-07-25 10:30:00', 2);
INSERT INTO public.bookings VALUES (457, 7, 2, '2012-07-25 14:00:00', 2);
INSERT INTO public.bookings VALUES (458, 7, 2, '2012-07-25 16:00:00', 2);
INSERT INTO public.bookings VALUES (459, 8, 3, '2012-07-25 08:00:00', 1);
INSERT INTO public.bookings VALUES (460, 8, 3, '2012-07-25 10:00:00', 1);
INSERT INTO public.bookings VALUES (461, 8, 4, '2012-07-25 14:30:00', 1);
INSERT INTO public.bookings VALUES (462, 8, 1, '2012-07-25 16:00:00', 1);
INSERT INTO public.bookings VALUES (463, 8, 2, '2012-07-25 20:00:00', 1);
INSERT INTO public.bookings VALUES (464, 0, 4, '2012-07-26 09:00:00', 3);
INSERT INTO public.bookings VALUES (465, 0, 0, '2012-07-26 11:30:00', 3);
INSERT INTO public.bookings VALUES (466, 0, 4, '2012-07-26 18:00:00', 3);
INSERT INTO public.bookings VALUES (467, 1, 8, '2012-07-26 08:00:00', 3);
INSERT INTO public.bookings VALUES (468, 1, 8, '2012-07-26 11:30:00', 3);
INSERT INTO public.bookings VALUES (469, 1, 8, '2012-07-26 13:30:00', 3);
INSERT INTO public.bookings VALUES (470, 1, 1, '2012-07-26 15:00:00', 3);
INSERT INTO public.bookings VALUES (471, 1, 0, '2012-07-26 16:30:00', 3);
INSERT INTO public.bookings VALUES (472, 1, 6, '2012-07-26 19:00:00', 3);
INSERT INTO public.bookings VALUES (473, 2, 1, '2012-07-26 08:30:00', 3);
INSERT INTO public.bookings VALUES (474, 2, 2, '2012-07-26 11:00:00', 6);
INSERT INTO public.bookings VALUES (475, 2, 7, '2012-07-26 14:00:00', 3);
INSERT INTO public.bookings VALUES (476, 2, 2, '2012-07-26 17:00:00', 3);
INSERT INTO public.bookings VALUES (477, 2, 3, '2012-07-26 19:00:00', 3);
INSERT INTO public.bookings VALUES (478, 3, 0, '2012-07-26 09:00:00', 2);
INSERT INTO public.bookings VALUES (479, 3, 0, '2012-07-26 13:30:00', 2);
INSERT INTO public.bookings VALUES (480, 3, 3, '2012-07-26 16:00:00', 2);
INSERT INTO public.bookings VALUES (481, 4, 3, '2012-07-26 08:00:00', 2);
INSERT INTO public.bookings VALUES (482, 4, 6, '2012-07-26 09:00:00', 2);
INSERT INTO public.bookings VALUES (483, 4, 0, '2012-07-26 12:00:00', 2);
INSERT INTO public.bookings VALUES (484, 4, 5, '2012-07-26 13:30:00', 2);
INSERT INTO public.bookings VALUES (485, 4, 6, '2012-07-26 16:00:00', 2);
INSERT INTO public.bookings VALUES (486, 4, 7, '2012-07-26 17:30:00', 2);
INSERT INTO public.bookings VALUES (487, 6, 0, '2012-07-26 10:00:00', 4);
INSERT INTO public.bookings VALUES (488, 6, 0, '2012-07-26 13:00:00', 2);
INSERT INTO public.bookings VALUES (489, 6, 0, '2012-07-26 19:00:00', 2);
INSERT INTO public.bookings VALUES (490, 7, 7, '2012-07-26 09:30:00', 2);
INSERT INTO public.bookings VALUES (491, 7, 6, '2012-07-26 11:00:00', 2);
INSERT INTO public.bookings VALUES (492, 7, 5, '2012-07-26 12:30:00', 2);
INSERT INTO public.bookings VALUES (493, 7, 4, '2012-07-26 13:30:00', 2);
INSERT INTO public.bookings VALUES (494, 7, 5, '2012-07-26 17:00:00', 2);
INSERT INTO public.bookings VALUES (495, 8, 3, '2012-07-26 12:00:00', 1);
INSERT INTO public.bookings VALUES (496, 8, 3, '2012-07-26 13:30:00', 1);
INSERT INTO public.bookings VALUES (497, 8, 2, '2012-07-26 15:00:00', 1);
INSERT INTO public.bookings VALUES (498, 8, 1, '2012-07-26 16:30:00', 1);
INSERT INTO public.bookings VALUES (499, 8, 3, '2012-07-26 17:00:00', 1);
INSERT INTO public.bookings VALUES (500, 0, 4, '2012-07-27 08:00:00', 3);
INSERT INTO public.bookings VALUES (501, 0, 5, '2012-07-27 11:00:00', 3);
INSERT INTO public.bookings VALUES (502, 0, 6, '2012-07-27 14:00:00', 3);
INSERT INTO public.bookings VALUES (503, 0, 6, '2012-07-27 17:30:00', 3);
INSERT INTO public.bookings VALUES (504, 1, 0, '2012-07-27 10:00:00', 3);
INSERT INTO public.bookings VALUES (505, 1, 7, '2012-07-27 11:30:00', 3);
INSERT INTO public.bookings VALUES (506, 1, 0, '2012-07-27 13:00:00', 3);
INSERT INTO public.bookings VALUES (507, 1, 0, '2012-07-27 15:00:00', 3);
INSERT INTO public.bookings VALUES (508, 1, 0, '2012-07-27 18:00:00', 3);
INSERT INTO public.bookings VALUES (509, 2, 1, '2012-07-27 12:00:00', 6);
INSERT INTO public.bookings VALUES (510, 3, 0, '2012-07-27 10:30:00', 2);
INSERT INTO public.bookings VALUES (511, 3, 2, '2012-07-27 14:00:00', 2);
INSERT INTO public.bookings VALUES (512, 3, 3, '2012-07-27 19:00:00', 2);
INSERT INTO public.bookings VALUES (513, 4, 1, '2012-07-27 10:00:00', 4);
INSERT INTO public.bookings VALUES (514, 4, 6, '2012-07-27 12:30:00', 2);
INSERT INTO public.bookings VALUES (515, 4, 0, '2012-07-27 14:00:00', 4);
INSERT INTO public.bookings VALUES (516, 4, 0, '2012-07-27 16:30:00', 2);
INSERT INTO public.bookings VALUES (517, 4, 1, '2012-07-27 17:30:00', 2);
INSERT INTO public.bookings VALUES (518, 4, 0, '2012-07-27 18:30:00', 2);
INSERT INTO public.bookings VALUES (519, 5, 7, '2012-07-27 18:00:00', 2);
INSERT INTO public.bookings VALUES (520, 6, 0, '2012-07-27 09:00:00', 2);
INSERT INTO public.bookings VALUES (521, 6, 5, '2012-07-27 14:00:00', 2);
INSERT INTO public.bookings VALUES (522, 6, 8, '2012-07-27 16:30:00', 2);
INSERT INTO public.bookings VALUES (523, 7, 2, '2012-07-27 18:00:00', 2);
INSERT INTO public.bookings VALUES (524, 7, 4, '2012-07-27 19:00:00', 2);
INSERT INTO public.bookings VALUES (525, 8, 3, '2012-07-27 09:00:00', 1);
INSERT INTO public.bookings VALUES (526, 8, 3, '2012-07-27 12:30:00', 1);
INSERT INTO public.bookings VALUES (527, 8, 3, '2012-07-27 16:00:00', 1);
INSERT INTO public.bookings VALUES (528, 8, 6, '2012-07-27 16:30:00', 1);
INSERT INTO public.bookings VALUES (529, 8, 0, '2012-07-27 18:30:00', 1);
INSERT INTO public.bookings VALUES (530, 0, 7, '2012-07-28 08:00:00', 9);
INSERT INTO public.bookings VALUES (531, 0, 4, '2012-07-28 13:00:00', 3);
INSERT INTO public.bookings VALUES (532, 0, 5, '2012-07-28 15:00:00', 3);
INSERT INTO public.bookings VALUES (533, 0, 2, '2012-07-28 19:00:00', 3);
INSERT INTO public.bookings VALUES (534, 1, 1, '2012-07-28 08:00:00', 3);
INSERT INTO public.bookings VALUES (535, 1, 0, '2012-07-28 10:00:00', 3);
INSERT INTO public.bookings VALUES (536, 1, 0, '2012-07-28 16:00:00', 3);
INSERT INTO public.bookings VALUES (537, 1, 7, '2012-07-28 17:30:00', 3);
INSERT INTO public.bookings VALUES (538, 2, 1, '2012-07-28 10:00:00', 3);
INSERT INTO public.bookings VALUES (539, 2, 1, '2012-07-28 14:00:00', 3);
INSERT INTO public.bookings VALUES (540, 2, 1, '2012-07-28 17:00:00', 3);
INSERT INTO public.bookings VALUES (541, 2, 5, '2012-07-28 18:30:00', 3);
INSERT INTO public.bookings VALUES (542, 3, 3, '2012-07-28 08:30:00', 2);
INSERT INTO public.bookings VALUES (543, 3, 3, '2012-07-28 15:30:00', 2);
INSERT INTO public.bookings VALUES (544, 4, 0, '2012-07-28 09:00:00', 2);
INSERT INTO public.bookings VALUES (545, 4, 3, '2012-07-28 10:30:00', 4);
INSERT INTO public.bookings VALUES (546, 4, 0, '2012-07-28 12:30:00', 2);
INSERT INTO public.bookings VALUES (547, 4, 8, '2012-07-28 16:00:00', 2);
INSERT INTO public.bookings VALUES (548, 4, 0, '2012-07-28 19:00:00', 2);
INSERT INTO public.bookings VALUES (549, 5, 0, '2012-07-28 18:00:00', 2);
INSERT INTO public.bookings VALUES (550, 6, 0, '2012-07-28 17:00:00', 2);
INSERT INTO public.bookings VALUES (551, 6, 0, '2012-07-28 18:30:00', 2);
INSERT INTO public.bookings VALUES (552, 7, 2, '2012-07-28 09:00:00', 2);
INSERT INTO public.bookings VALUES (553, 7, 5, '2012-07-28 10:00:00', 2);
INSERT INTO public.bookings VALUES (554, 7, 6, '2012-07-28 12:30:00', 2);
INSERT INTO public.bookings VALUES (555, 7, 8, '2012-07-28 17:00:00', 4);
INSERT INTO public.bookings VALUES (556, 8, 2, '2012-07-28 16:00:00', 1);
INSERT INTO public.bookings VALUES (557, 8, 3, '2012-07-28 16:30:00', 1);
INSERT INTO public.bookings VALUES (558, 8, 4, '2012-07-28 19:00:00', 1);
INSERT INTO public.bookings VALUES (559, 0, 7, '2012-07-29 09:30:00', 3);
INSERT INTO public.bookings VALUES (560, 0, 2, '2012-07-29 11:00:00', 3);
INSERT INTO public.bookings VALUES (561, 0, 6, '2012-07-29 13:00:00', 3);
INSERT INTO public.bookings VALUES (562, 0, 5, '2012-07-29 15:00:00', 3);
INSERT INTO public.bookings VALUES (563, 0, 0, '2012-07-29 17:00:00', 3);
INSERT INTO public.bookings VALUES (564, 1, 8, '2012-07-29 09:30:00', 3);
INSERT INTO public.bookings VALUES (565, 1, 0, '2012-07-29 15:00:00', 3);
INSERT INTO public.bookings VALUES (566, 1, 8, '2012-07-29 16:30:00', 3);
INSERT INTO public.bookings VALUES (567, 2, 1, '2012-07-29 08:30:00', 3);
INSERT INTO public.bookings VALUES (568, 2, 1, '2012-07-29 12:00:00', 6);
INSERT INTO public.bookings VALUES (569, 2, 1, '2012-07-29 15:30:00', 3);
INSERT INTO public.bookings VALUES (570, 4, 3, '2012-07-29 08:00:00', 2);
INSERT INTO public.bookings VALUES (571, 4, 0, '2012-07-29 09:00:00', 2);
INSERT INTO public.bookings VALUES (572, 4, 3, '2012-07-29 10:30:00', 2);
INSERT INTO public.bookings VALUES (573, 4, 8, '2012-07-29 11:30:00', 4);
INSERT INTO public.bookings VALUES (574, 4, 8, '2012-07-29 15:00:00', 2);
INSERT INTO public.bookings VALUES (575, 4, 0, '2012-07-29 18:30:00', 2);
INSERT INTO public.bookings VALUES (576, 6, 0, '2012-07-29 09:00:00', 2);
INSERT INTO public.bookings VALUES (577, 6, 0, '2012-07-29 10:30:00', 2);
INSERT INTO public.bookings VALUES (578, 6, 6, '2012-07-29 17:30:00', 4);
INSERT INTO public.bookings VALUES (579, 7, 4, '2012-07-29 16:00:00', 2);
INSERT INTO public.bookings VALUES (580, 7, 8, '2012-07-29 18:30:00', 2);
INSERT INTO public.bookings VALUES (581, 8, 3, '2012-07-29 12:30:00', 1);
INSERT INTO public.bookings VALUES (582, 8, 7, '2012-07-29 13:00:00', 1);
INSERT INTO public.bookings VALUES (583, 8, 3, '2012-07-29 15:30:00', 1);
INSERT INTO public.bookings VALUES (584, 8, 3, '2012-07-29 18:00:00', 1);
INSERT INTO public.bookings VALUES (585, 0, 5, '2012-07-30 14:00:00', 3);
INSERT INTO public.bookings VALUES (586, 0, 6, '2012-07-30 15:30:00', 3);
INSERT INTO public.bookings VALUES (587, 0, 7, '2012-07-30 19:00:00', 3);
INSERT INTO public.bookings VALUES (588, 1, 8, '2012-07-30 08:30:00', 3);
INSERT INTO public.bookings VALUES (589, 1, 7, '2012-07-30 11:00:00', 3);
INSERT INTO public.bookings VALUES (590, 1, 2, '2012-07-30 13:30:00', 3);
INSERT INTO public.bookings VALUES (591, 1, 1, '2012-07-30 15:30:00', 3);
INSERT INTO public.bookings VALUES (592, 2, 5, '2012-07-30 10:00:00', 3);
INSERT INTO public.bookings VALUES (593, 2, 8, '2012-07-30 11:30:00', 3);
INSERT INTO public.bookings VALUES (594, 2, 7, '2012-07-30 15:00:00', 3);
INSERT INTO public.bookings VALUES (595, 2, 0, '2012-07-30 17:30:00', 3);
INSERT INTO public.bookings VALUES (596, 3, 3, '2012-07-30 11:30:00', 2);
INSERT INTO public.bookings VALUES (597, 3, 4, '2012-07-30 16:30:00', 2);
INSERT INTO public.bookings VALUES (598, 4, 0, '2012-07-30 08:00:00', 2);
INSERT INTO public.bookings VALUES (599, 4, 0, '2012-07-30 10:30:00', 2);
INSERT INTO public.bookings VALUES (600, 4, 0, '2012-07-30 12:00:00', 2);
INSERT INTO public.bookings VALUES (601, 4, 7, '2012-07-30 18:00:00', 2);
INSERT INTO public.bookings VALUES (602, 4, 3, '2012-07-30 19:30:00', 2);
INSERT INTO public.bookings VALUES (603, 5, 0, '2012-07-30 12:30:00', 2);
INSERT INTO public.bookings VALUES (604, 5, 0, '2012-07-30 14:00:00', 2);
INSERT INTO public.bookings VALUES (605, 6, 0, '2012-07-30 08:30:00', 2);
INSERT INTO public.bookings VALUES (606, 6, 0, '2012-07-30 12:00:00', 2);
INSERT INTO public.bookings VALUES (607, 6, 0, '2012-07-30 14:30:00', 2);
INSERT INTO public.bookings VALUES (608, 6, 0, '2012-07-30 17:30:00', 2);
INSERT INTO public.bookings VALUES (609, 7, 7, '2012-07-30 08:00:00', 2);
INSERT INTO public.bookings VALUES (610, 7, 6, '2012-07-30 09:30:00', 2);
INSERT INTO public.bookings VALUES (611, 7, 8, '2012-07-30 14:30:00', 2);
INSERT INTO public.bookings VALUES (612, 7, 5, '2012-07-30 16:30:00', 2);
INSERT INTO public.bookings VALUES (613, 7, 4, '2012-07-30 18:00:00', 2);
INSERT INTO public.bookings VALUES (614, 7, 6, '2012-07-30 19:00:00', 2);
INSERT INTO public.bookings VALUES (615, 8, 3, '2012-07-30 08:30:00', 1);
INSERT INTO public.bookings VALUES (616, 8, 2, '2012-07-30 09:00:00', 1);
INSERT INTO public.bookings VALUES (617, 8, 2, '2012-07-30 11:00:00', 1);
INSERT INTO public.bookings VALUES (618, 8, 2, '2012-07-30 12:30:00', 1);
INSERT INTO public.bookings VALUES (619, 8, 3, '2012-07-30 15:00:00', 2);
INSERT INTO public.bookings VALUES (620, 8, 5, '2012-07-30 16:00:00', 1);
INSERT INTO public.bookings VALUES (621, 8, 2, '2012-07-30 16:30:00', 1);
INSERT INTO public.bookings VALUES (622, 8, 3, '2012-07-30 18:30:00', 1);
INSERT INTO public.bookings VALUES (623, 8, 1, '2012-07-30 19:30:00', 1);
INSERT INTO public.bookings VALUES (624, 0, 7, '2012-07-31 09:30:00', 3);
INSERT INTO public.bookings VALUES (625, 0, 0, '2012-07-31 11:00:00', 3);
INSERT INTO public.bookings VALUES (626, 0, 0, '2012-07-31 15:00:00', 3);
INSERT INTO public.bookings VALUES (627, 0, 5, '2012-07-31 17:00:00', 3);
INSERT INTO public.bookings VALUES (628, 0, 0, '2012-07-31 18:30:00', 3);
INSERT INTO public.bookings VALUES (629, 1, 0, '2012-07-31 08:00:00', 3);
INSERT INTO public.bookings VALUES (630, 1, 7, '2012-07-31 13:00:00', 3);
INSERT INTO public.bookings VALUES (631, 2, 1, '2012-07-31 16:30:00', 3);
INSERT INTO public.bookings VALUES (632, 3, 3, '2012-07-31 08:30:00', 2);
INSERT INTO public.bookings VALUES (633, 3, 1, '2012-07-31 13:00:00', 2);
INSERT INTO public.bookings VALUES (634, 3, 1, '2012-07-31 15:30:00', 2);
INSERT INTO public.bookings VALUES (635, 4, 8, '2012-07-31 09:30:00', 2);
INSERT INTO public.bookings VALUES (636, 4, 0, '2012-07-31 11:00:00', 2);
INSERT INTO public.bookings VALUES (637, 4, 3, '2012-07-31 12:00:00', 2);
INSERT INTO public.bookings VALUES (638, 4, 2, '2012-07-31 13:00:00', 2);
INSERT INTO public.bookings VALUES (639, 4, 3, '2012-07-31 14:00:00', 2);
INSERT INTO public.bookings VALUES (640, 4, 0, '2012-07-31 15:00:00', 2);
INSERT INTO public.bookings VALUES (641, 4, 6, '2012-07-31 17:00:00', 2);
INSERT INTO public.bookings VALUES (642, 4, 7, '2012-07-31 18:30:00', 2);
INSERT INTO public.bookings VALUES (643, 4, 0, '2012-07-31 19:30:00', 2);
INSERT INTO public.bookings VALUES (644, 6, 0, '2012-07-31 09:00:00', 2);
INSERT INTO public.bookings VALUES (645, 6, 5, '2012-07-31 10:00:00', 2);
INSERT INTO public.bookings VALUES (646, 6, 6, '2012-07-31 11:00:00', 2);
INSERT INTO public.bookings VALUES (647, 6, 0, '2012-07-31 14:30:00', 2);
INSERT INTO public.bookings VALUES (648, 6, 6, '2012-07-31 16:00:00', 2);
INSERT INTO public.bookings VALUES (649, 7, 4, '2012-07-31 18:30:00', 2);
INSERT INTO public.bookings VALUES (650, 8, 3, '2012-07-31 10:00:00', 1);
INSERT INTO public.bookings VALUES (651, 8, 3, '2012-07-31 11:30:00', 1);
INSERT INTO public.bookings VALUES (652, 8, 5, '2012-07-31 12:00:00', 1);
INSERT INTO public.bookings VALUES (653, 8, 7, '2012-07-31 12:30:00', 1);
INSERT INTO public.bookings VALUES (654, 8, 8, '2012-07-31 13:30:00', 1);
INSERT INTO public.bookings VALUES (655, 8, 6, '2012-07-31 14:00:00', 1);
INSERT INTO public.bookings VALUES (656, 8, 4, '2012-07-31 17:00:00', 1);
INSERT INTO public.bookings VALUES (657, 8, 2, '2012-07-31 17:30:00', 1);
INSERT INTO public.bookings VALUES (658, 0, 5, '2012-08-01 15:30:00', 3);
INSERT INTO public.bookings VALUES (659, 0, 5, '2012-08-01 18:00:00', 3);
INSERT INTO public.bookings VALUES (660, 1, 8, '2012-08-01 09:00:00', 9);
INSERT INTO public.bookings VALUES (661, 1, 8, '2012-08-01 17:30:00', 3);
INSERT INTO public.bookings VALUES (662, 2, 1, '2012-08-01 09:30:00', 6);
INSERT INTO public.bookings VALUES (663, 2, 1, '2012-08-01 14:30:00', 3);
INSERT INTO public.bookings VALUES (664, 2, 1, '2012-08-01 16:30:00', 3);
INSERT INTO public.bookings VALUES (665, 3, 7, '2012-08-01 13:00:00', 2);
INSERT INTO public.bookings VALUES (666, 4, 5, '2012-08-01 08:00:00', 2);
INSERT INTO public.bookings VALUES (667, 4, 6, '2012-08-01 09:00:00', 2);
INSERT INTO public.bookings VALUES (668, 4, 0, '2012-08-01 10:30:00', 6);
INSERT INTO public.bookings VALUES (669, 4, 3, '2012-08-01 13:30:00', 4);
INSERT INTO public.bookings VALUES (670, 4, 3, '2012-08-01 19:30:00', 2);
INSERT INTO public.bookings VALUES (671, 5, 7, '2012-08-01 08:30:00', 2);
INSERT INTO public.bookings VALUES (672, 5, 0, '2012-08-01 14:30:00', 2);
INSERT INTO public.bookings VALUES (673, 6, 0, '2012-08-01 09:30:00', 2);
INSERT INTO public.bookings VALUES (674, 6, 0, '2012-08-01 11:00:00', 4);
INSERT INTO public.bookings VALUES (675, 6, 6, '2012-08-01 14:30:00', 2);
INSERT INTO public.bookings VALUES (676, 6, 0, '2012-08-01 18:00:00', 2);
INSERT INTO public.bookings VALUES (677, 7, 4, '2012-08-01 12:30:00', 2);
INSERT INTO public.bookings VALUES (678, 7, 2, '2012-08-01 16:00:00', 2);
INSERT INTO public.bookings VALUES (679, 7, 5, '2012-08-01 17:00:00', 2);
INSERT INTO public.bookings VALUES (680, 8, 3, '2012-08-01 08:30:00', 2);
INSERT INTO public.bookings VALUES (681, 8, 2, '2012-08-01 09:30:00', 1);
INSERT INTO public.bookings VALUES (682, 8, 3, '2012-08-01 10:30:00', 1);
INSERT INTO public.bookings VALUES (683, 8, 3, '2012-08-01 11:30:00', 1);
INSERT INTO public.bookings VALUES (684, 8, 8, '2012-08-01 13:30:00', 1);
INSERT INTO public.bookings VALUES (685, 8, 8, '2012-08-01 15:00:00', 1);
INSERT INTO public.bookings VALUES (686, 8, 3, '2012-08-01 17:00:00', 1);
INSERT INTO public.bookings VALUES (687, 0, 8, '2012-08-02 08:00:00', 3);
INSERT INTO public.bookings VALUES (688, 0, 5, '2012-08-02 13:00:00', 3);
INSERT INTO public.bookings VALUES (689, 0, 7, '2012-08-02 15:30:00', 3);
INSERT INTO public.bookings VALUES (690, 0, 5, '2012-08-02 18:30:00', 3);
INSERT INTO public.bookings VALUES (691, 1, 8, '2012-08-02 09:30:00', 3);
INSERT INTO public.bookings VALUES (692, 1, 8, '2012-08-02 12:00:00', 3);
INSERT INTO public.bookings VALUES (693, 1, 0, '2012-08-02 13:30:00', 3);
INSERT INTO public.bookings VALUES (694, 1, 5, '2012-08-02 15:30:00', 3);
INSERT INTO public.bookings VALUES (695, 1, 0, '2012-08-02 18:00:00', 3);
INSERT INTO public.bookings VALUES (696, 2, 1, '2012-08-02 09:30:00', 3);
INSERT INTO public.bookings VALUES (697, 2, 0, '2012-08-02 11:30:00', 3);
INSERT INTO public.bookings VALUES (698, 2, 3, '2012-08-02 14:00:00', 3);
INSERT INTO public.bookings VALUES (699, 2, 1, '2012-08-02 19:00:00', 3);
INSERT INTO public.bookings VALUES (700, 3, 3, '2012-08-02 10:00:00', 2);
INSERT INTO public.bookings VALUES (701, 3, 2, '2012-08-02 15:00:00', 2);
INSERT INTO public.bookings VALUES (702, 3, 3, '2012-08-02 17:00:00', 2);
INSERT INTO public.bookings VALUES (703, 3, 6, '2012-08-02 18:00:00', 2);
INSERT INTO public.bookings VALUES (704, 3, 4, '2012-08-02 19:30:00', 2);
INSERT INTO public.bookings VALUES (705, 4, 4, '2012-08-02 10:00:00', 2);
INSERT INTO public.bookings VALUES (706, 4, 7, '2012-08-02 11:30:00', 2);
INSERT INTO public.bookings VALUES (707, 4, 5, '2012-08-02 14:30:00', 2);
INSERT INTO public.bookings VALUES (708, 4, 8, '2012-08-02 15:30:00', 2);
INSERT INTO public.bookings VALUES (709, 4, 8, '2012-08-02 17:00:00', 2);
INSERT INTO public.bookings VALUES (710, 4, 3, '2012-08-02 18:30:00', 2);
INSERT INTO public.bookings VALUES (711, 4, 0, '2012-08-02 19:30:00', 2);
INSERT INTO public.bookings VALUES (712, 6, 4, '2012-08-02 09:00:00', 2);
INSERT INTO public.bookings VALUES (713, 6, 0, '2012-08-02 10:00:00', 2);
INSERT INTO public.bookings VALUES (714, 6, 0, '2012-08-02 11:30:00', 2);
INSERT INTO public.bookings VALUES (715, 6, 6, '2012-08-02 12:30:00', 2);
INSERT INTO public.bookings VALUES (716, 6, 8, '2012-08-02 14:00:00', 2);
INSERT INTO public.bookings VALUES (717, 6, 0, '2012-08-02 17:00:00', 4);
INSERT INTO public.bookings VALUES (718, 6, 2, '2012-08-02 19:30:00', 2);
INSERT INTO public.bookings VALUES (719, 7, 7, '2012-08-02 08:00:00', 2);
INSERT INTO public.bookings VALUES (720, 7, 5, '2012-08-02 11:00:00', 2);
INSERT INTO public.bookings VALUES (721, 7, 6, '2012-08-02 14:00:00', 2);
INSERT INTO public.bookings VALUES (722, 7, 4, '2012-08-02 16:00:00', 2);
INSERT INTO public.bookings VALUES (723, 7, 0, '2012-08-02 18:00:00', 2);
INSERT INTO public.bookings VALUES (724, 8, 3, '2012-08-02 08:30:00', 1);
INSERT INTO public.bookings VALUES (725, 8, 3, '2012-08-02 13:00:00', 1);
INSERT INTO public.bookings VALUES (726, 8, 7, '2012-08-02 15:00:00', 1);
INSERT INTO public.bookings VALUES (727, 8, 3, '2012-08-02 16:30:00', 1);
INSERT INTO public.bookings VALUES (728, 8, 7, '2012-08-02 17:00:00', 1);
INSERT INTO public.bookings VALUES (729, 8, 3, '2012-08-02 19:30:00', 1);
INSERT INTO public.bookings VALUES (730, 0, 5, '2012-08-03 11:30:00', 3);
INSERT INTO public.bookings VALUES (731, 0, 0, '2012-08-03 16:00:00', 3);
INSERT INTO public.bookings VALUES (732, 0, 6, '2012-08-03 18:30:00', 3);
INSERT INTO public.bookings VALUES (733, 1, 8, '2012-08-03 10:30:00', 3);
INSERT INTO public.bookings VALUES (734, 1, 0, '2012-08-03 13:00:00', 6);
INSERT INTO public.bookings VALUES (735, 1, 7, '2012-08-03 16:30:00', 3);
INSERT INTO public.bookings VALUES (736, 1, 8, '2012-08-03 19:00:00', 3);
INSERT INTO public.bookings VALUES (737, 2, 8, '2012-08-03 08:30:00', 3);
INSERT INTO public.bookings VALUES (738, 2, 1, '2012-08-03 11:00:00', 3);
INSERT INTO public.bookings VALUES (739, 3, 6, '2012-08-03 08:00:00', 2);
INSERT INTO public.bookings VALUES (740, 3, 2, '2012-08-03 10:00:00', 2);
INSERT INTO public.bookings VALUES (741, 3, 6, '2012-08-03 12:00:00', 2);
INSERT INTO public.bookings VALUES (742, 3, 6, '2012-08-03 16:30:00', 2);
INSERT INTO public.bookings VALUES (743, 3, 2, '2012-08-03 18:30:00', 2);
INSERT INTO public.bookings VALUES (744, 4, 0, '2012-08-03 09:30:00', 2);
INSERT INTO public.bookings VALUES (745, 4, 7, '2012-08-03 10:30:00', 2);
INSERT INTO public.bookings VALUES (746, 4, 0, '2012-08-03 11:30:00', 2);
INSERT INTO public.bookings VALUES (747, 4, 0, '2012-08-03 13:00:00', 2);
INSERT INTO public.bookings VALUES (748, 4, 1, '2012-08-03 14:30:00', 2);
INSERT INTO public.bookings VALUES (749, 4, 3, '2012-08-03 15:30:00', 4);
INSERT INTO public.bookings VALUES (750, 4, 3, '2012-08-03 18:30:00', 2);
INSERT INTO public.bookings VALUES (751, 6, 0, '2012-08-03 09:00:00', 2);
INSERT INTO public.bookings VALUES (752, 6, 0, '2012-08-03 10:30:00', 2);
INSERT INTO public.bookings VALUES (753, 6, 4, '2012-08-03 12:00:00', 2);
INSERT INTO public.bookings VALUES (754, 6, 0, '2012-08-03 15:30:00', 2);
INSERT INTO public.bookings VALUES (755, 6, 1, '2012-08-03 16:30:00', 2);
INSERT INTO public.bookings VALUES (756, 6, 0, '2012-08-03 19:00:00', 2);
INSERT INTO public.bookings VALUES (757, 7, 6, '2012-08-03 09:00:00', 2);
INSERT INTO public.bookings VALUES (758, 7, 6, '2012-08-03 10:30:00', 2);
INSERT INTO public.bookings VALUES (759, 7, 2, '2012-08-03 13:30:00', 2);
INSERT INTO public.bookings VALUES (760, 7, 5, '2012-08-03 17:30:00', 2);
INSERT INTO public.bookings VALUES (761, 8, 8, '2012-08-03 12:00:00', 1);
INSERT INTO public.bookings VALUES (762, 8, 3, '2012-08-03 12:30:00', 1);
INSERT INTO public.bookings VALUES (763, 8, 6, '2012-08-03 14:00:00', 1);
INSERT INTO public.bookings VALUES (764, 8, 3, '2012-08-03 15:00:00', 1);
INSERT INTO public.bookings VALUES (765, 8, 6, '2012-08-03 15:30:00', 1);
INSERT INTO public.bookings VALUES (766, 8, 8, '2012-08-03 16:00:00', 1);
INSERT INTO public.bookings VALUES (767, 8, 0, '2012-08-03 19:00:00', 1);
INSERT INTO public.bookings VALUES (768, 8, 3, '2012-08-03 19:30:00', 1);
INSERT INTO public.bookings VALUES (769, 0, 6, '2012-08-04 15:00:00', 3);
INSERT INTO public.bookings VALUES (770, 1, 9, '2012-08-04 09:30:00', 3);
INSERT INTO public.bookings VALUES (771, 1, 0, '2012-08-04 11:30:00', 3);
INSERT INTO public.bookings VALUES (772, 1, 8, '2012-08-04 16:00:00', 3);
INSERT INTO public.bookings VALUES (773, 1, 0, '2012-08-04 18:30:00', 3);
INSERT INTO public.bookings VALUES (774, 2, 1, '2012-08-04 08:00:00', 3);
INSERT INTO public.bookings VALUES (775, 2, 2, '2012-08-04 09:30:00', 3);
INSERT INTO public.bookings VALUES (776, 2, 1, '2012-08-04 11:00:00', 3);
INSERT INTO public.bookings VALUES (777, 2, 2, '2012-08-04 16:30:00', 3);
INSERT INTO public.bookings VALUES (778, 2, 9, '2012-08-04 18:30:00', 3);
INSERT INTO public.bookings VALUES (779, 3, 6, '2012-08-04 11:30:00', 2);
INSERT INTO public.bookings VALUES (780, 3, 1, '2012-08-04 15:00:00', 2);
INSERT INTO public.bookings VALUES (781, 3, 3, '2012-08-04 18:00:00', 2);
INSERT INTO public.bookings VALUES (782, 3, 4, '2012-08-04 19:00:00', 2);
INSERT INTO public.bookings VALUES (783, 4, 8, '2012-08-04 08:30:00', 2);
INSERT INTO public.bookings VALUES (784, 4, 7, '2012-08-04 10:00:00', 2);
INSERT INTO public.bookings VALUES (785, 4, 0, '2012-08-04 13:30:00', 2);
INSERT INTO public.bookings VALUES (786, 4, 5, '2012-08-04 14:30:00', 2);
INSERT INTO public.bookings VALUES (787, 4, 0, '2012-08-04 17:00:00', 2);
INSERT INTO public.bookings VALUES (788, 4, 5, '2012-08-04 19:30:00', 2);
INSERT INTO public.bookings VALUES (789, 5, 0, '2012-08-04 12:30:00', 2);
INSERT INTO public.bookings VALUES (790, 6, 6, '2012-08-04 08:30:00', 2);
INSERT INTO public.bookings VALUES (791, 6, 5, '2012-08-04 09:30:00', 2);
INSERT INTO public.bookings VALUES (792, 6, 6, '2012-08-04 12:30:00', 2);
INSERT INTO public.bookings VALUES (793, 6, 0, '2012-08-04 16:00:00', 2);
INSERT INTO public.bookings VALUES (794, 6, 0, '2012-08-04 17:30:00', 2);
INSERT INTO public.bookings VALUES (795, 7, 5, '2012-08-04 08:00:00', 2);
INSERT INTO public.bookings VALUES (796, 7, 9, '2012-08-04 11:00:00', 2);
INSERT INTO public.bookings VALUES (797, 7, 7, '2012-08-04 15:00:00', 2);
INSERT INTO public.bookings VALUES (798, 7, 5, '2012-08-04 18:30:00', 2);
INSERT INTO public.bookings VALUES (799, 8, 3, '2012-08-04 08:00:00', 1);
INSERT INTO public.bookings VALUES (800, 8, 3, '2012-08-04 11:00:00', 2);
INSERT INTO public.bookings VALUES (801, 8, 3, '2012-08-04 13:00:00', 1);
INSERT INTO public.bookings VALUES (802, 8, 3, '2012-08-04 16:30:00', 1);
INSERT INTO public.bookings VALUES (803, 8, 6, '2012-08-04 18:00:00', 1);
INSERT INTO public.bookings VALUES (804, 8, 7, '2012-08-04 18:30:00', 1);
INSERT INTO public.bookings VALUES (805, 8, 3, '2012-08-04 19:00:00', 1);
INSERT INTO public.bookings VALUES (806, 0, 2, '2012-08-05 08:00:00', 3);
INSERT INTO public.bookings VALUES (807, 0, 5, '2012-08-05 09:30:00', 3);
INSERT INTO public.bookings VALUES (808, 0, 7, '2012-08-05 15:00:00', 3);
INSERT INTO public.bookings VALUES (809, 0, 7, '2012-08-05 17:30:00', 3);
INSERT INTO public.bookings VALUES (810, 1, 0, '2012-08-05 08:00:00', 3);
INSERT INTO public.bookings VALUES (811, 1, 7, '2012-08-05 09:30:00', 3);
INSERT INTO public.bookings VALUES (812, 1, 9, '2012-08-05 11:00:00', 3);
INSERT INTO public.bookings VALUES (813, 1, 9, '2012-08-05 15:30:00', 3);
INSERT INTO public.bookings VALUES (814, 1, 1, '2012-08-05 18:00:00', 3);
INSERT INTO public.bookings VALUES (815, 2, 1, '2012-08-05 10:00:00', 3);
INSERT INTO public.bookings VALUES (816, 2, 5, '2012-08-05 11:30:00', 3);
INSERT INTO public.bookings VALUES (817, 2, 2, '2012-08-05 15:00:00', 3);
INSERT INTO public.bookings VALUES (818, 2, 8, '2012-08-05 17:00:00', 3);
INSERT INTO public.bookings VALUES (819, 3, 3, '2012-08-05 09:30:00', 2);
INSERT INTO public.bookings VALUES (820, 3, 4, '2012-08-05 14:30:00', 2);
INSERT INTO public.bookings VALUES (821, 3, 3, '2012-08-05 15:30:00', 2);
INSERT INTO public.bookings VALUES (822, 4, 0, '2012-08-05 08:30:00', 2);
INSERT INTO public.bookings VALUES (823, 4, 0, '2012-08-05 10:00:00', 2);
INSERT INTO public.bookings VALUES (824, 4, 0, '2012-08-05 11:30:00', 2);
INSERT INTO public.bookings VALUES (825, 4, 4, '2012-08-05 16:00:00', 2);
INSERT INTO public.bookings VALUES (826, 4, 8, '2012-08-05 19:00:00', 2);
INSERT INTO public.bookings VALUES (827, 6, 0, '2012-08-05 10:00:00', 4);
INSERT INTO public.bookings VALUES (828, 6, 6, '2012-08-05 13:00:00', 2);
INSERT INTO public.bookings VALUES (829, 6, 0, '2012-08-05 15:30:00', 2);
INSERT INTO public.bookings VALUES (830, 7, 2, '2012-08-05 10:30:00', 2);
INSERT INTO public.bookings VALUES (831, 7, 8, '2012-08-05 15:30:00', 2);
INSERT INTO public.bookings VALUES (832, 7, 2, '2012-08-05 19:30:00', 2);
INSERT INTO public.bookings VALUES (833, 8, 0, '2012-08-05 08:30:00', 1);
INSERT INTO public.bookings VALUES (834, 8, 3, '2012-08-05 13:00:00', 1);
INSERT INTO public.bookings VALUES (835, 8, 0, '2012-08-05 14:00:00', 1);
INSERT INTO public.bookings VALUES (836, 8, 3, '2012-08-05 16:30:00', 1);
INSERT INTO public.bookings VALUES (837, 8, 3, '2012-08-05 17:30:00', 1);
INSERT INTO public.bookings VALUES (838, 8, 3, '2012-08-05 19:30:00', 2);
INSERT INTO public.bookings VALUES (839, 0, 7, '2012-08-06 09:00:00', 3);
INSERT INTO public.bookings VALUES (840, 0, 0, '2012-08-06 10:30:00', 3);
INSERT INTO public.bookings VALUES (841, 0, 2, '2012-08-06 12:00:00', 3);
INSERT INTO public.bookings VALUES (842, 0, 0, '2012-08-06 13:30:00', 3);
INSERT INTO public.bookings VALUES (843, 0, 7, '2012-08-06 15:00:00', 3);
INSERT INTO public.bookings VALUES (844, 0, 5, '2012-08-06 16:30:00', 3);
INSERT INTO public.bookings VALUES (845, 0, 7, '2012-08-06 18:00:00', 3);
INSERT INTO public.bookings VALUES (846, 1, 8, '2012-08-06 08:00:00', 3);
INSERT INTO public.bookings VALUES (847, 1, 3, '2012-08-06 10:00:00', 3);
INSERT INTO public.bookings VALUES (848, 1, 0, '2012-08-06 11:30:00', 3);
INSERT INTO public.bookings VALUES (849, 1, 9, '2012-08-06 14:30:00', 3);
INSERT INTO public.bookings VALUES (850, 1, 9, '2012-08-06 17:30:00', 3);
INSERT INTO public.bookings VALUES (851, 2, 1, '2012-08-06 08:30:00', 3);
INSERT INTO public.bookings VALUES (852, 2, 5, '2012-08-06 10:30:00', 3);
INSERT INTO public.bookings VALUES (853, 2, 8, '2012-08-06 12:00:00', 3);
INSERT INTO public.bookings VALUES (854, 2, 8, '2012-08-06 14:00:00', 3);
INSERT INTO public.bookings VALUES (855, 3, 3, '2012-08-06 08:30:00', 2);
INSERT INTO public.bookings VALUES (856, 3, 6, '2012-08-06 15:00:00', 2);
INSERT INTO public.bookings VALUES (857, 3, 6, '2012-08-06 17:00:00', 2);
INSERT INTO public.bookings VALUES (858, 4, 0, '2012-08-06 08:00:00', 4);
INSERT INTO public.bookings VALUES (859, 4, 0, '2012-08-06 12:00:00', 2);
INSERT INTO public.bookings VALUES (860, 4, 7, '2012-08-06 13:30:00', 2);
INSERT INTO public.bookings VALUES (861, 4, 0, '2012-08-06 16:30:00', 2);
INSERT INTO public.bookings VALUES (862, 4, 6, '2012-08-06 18:30:00', 2);
INSERT INTO public.bookings VALUES (863, 5, 0, '2012-08-06 11:00:00', 2);
INSERT INTO public.bookings VALUES (864, 6, 6, '2012-08-06 09:00:00', 2);
INSERT INTO public.bookings VALUES (865, 6, 0, '2012-08-06 10:00:00', 2);
INSERT INTO public.bookings VALUES (866, 6, 6, '2012-08-06 13:00:00', 2);
INSERT INTO public.bookings VALUES (867, 6, 0, '2012-08-06 14:00:00', 2);
INSERT INTO public.bookings VALUES (868, 6, 5, '2012-08-06 15:00:00', 2);
INSERT INTO public.bookings VALUES (869, 7, 8, '2012-08-06 09:30:00', 2);
INSERT INTO public.bookings VALUES (870, 7, 2, '2012-08-06 11:00:00', 2);
INSERT INTO public.bookings VALUES (871, 7, 5, '2012-08-06 12:00:00', 4);
INSERT INTO public.bookings VALUES (872, 7, 4, '2012-08-06 17:30:00', 2);
INSERT INTO public.bookings VALUES (873, 7, 2, '2012-08-06 19:00:00', 2);
INSERT INTO public.bookings VALUES (874, 8, 3, '2012-08-06 08:00:00', 1);
INSERT INTO public.bookings VALUES (875, 8, 4, '2012-08-06 09:00:00', 1);
INSERT INTO public.bookings VALUES (876, 8, 3, '2012-08-06 09:30:00', 1);
INSERT INTO public.bookings VALUES (877, 8, 6, '2012-08-06 12:00:00', 1);
INSERT INTO public.bookings VALUES (878, 8, 1, '2012-08-06 18:00:00', 1);
INSERT INTO public.bookings VALUES (879, 8, 8, '2012-08-06 18:30:00', 1);
INSERT INTO public.bookings VALUES (880, 8, 3, '2012-08-06 19:00:00', 1);
INSERT INTO public.bookings VALUES (881, 0, 10, '2012-08-07 09:00:00', 3);
INSERT INTO public.bookings VALUES (882, 1, 0, '2012-08-07 08:00:00', 3);
INSERT INTO public.bookings VALUES (883, 1, 8, '2012-08-07 09:30:00', 3);
INSERT INTO public.bookings VALUES (884, 1, 7, '2012-08-07 17:00:00', 3);
INSERT INTO public.bookings VALUES (885, 2, 1, '2012-08-07 09:00:00', 6);
INSERT INTO public.bookings VALUES (886, 2, 1, '2012-08-07 13:00:00', 3);
INSERT INTO public.bookings VALUES (887, 2, 10, '2012-08-07 15:00:00', 3);
INSERT INTO public.bookings VALUES (888, 2, 2, '2012-08-07 18:00:00', 3);
INSERT INTO public.bookings VALUES (889, 3, 6, '2012-08-07 08:30:00', 2);
INSERT INTO public.bookings VALUES (890, 3, 6, '2012-08-07 10:00:00', 2);
INSERT INTO public.bookings VALUES (891, 3, 3, '2012-08-07 11:00:00', 2);
INSERT INTO public.bookings VALUES (892, 3, 3, '2012-08-07 12:30:00', 2);
INSERT INTO public.bookings VALUES (893, 3, 3, '2012-08-07 14:30:00', 2);
INSERT INTO public.bookings VALUES (894, 4, 0, '2012-08-07 08:30:00', 2);
INSERT INTO public.bookings VALUES (895, 4, 8, '2012-08-07 12:00:00', 2);
INSERT INTO public.bookings VALUES (896, 4, 8, '2012-08-07 13:30:00', 2);
INSERT INTO public.bookings VALUES (897, 4, 0, '2012-08-07 15:30:00', 2);
INSERT INTO public.bookings VALUES (898, 4, 6, '2012-08-07 18:30:00', 2);
INSERT INTO public.bookings VALUES (899, 6, 1, '2012-08-07 08:00:00', 2);
INSERT INTO public.bookings VALUES (900, 6, 0, '2012-08-07 14:00:00', 2);
INSERT INTO public.bookings VALUES (901, 6, 0, '2012-08-07 15:30:00', 2);
INSERT INTO public.bookings VALUES (902, 6, 0, '2012-08-07 18:00:00', 2);
INSERT INTO public.bookings VALUES (903, 7, 10, '2012-08-07 12:30:00', 2);
INSERT INTO public.bookings VALUES (904, 7, 4, '2012-08-07 15:00:00', 2);
INSERT INTO public.bookings VALUES (905, 7, 9, '2012-08-07 18:30:00', 2);
INSERT INTO public.bookings VALUES (906, 8, 3, '2012-08-07 08:30:00', 2);
INSERT INTO public.bookings VALUES (907, 8, 2, '2012-08-07 10:00:00', 1);
INSERT INTO public.bookings VALUES (908, 8, 3, '2012-08-07 10:30:00', 1);
INSERT INTO public.bookings VALUES (909, 8, 0, '2012-08-07 11:00:00', 1);
INSERT INTO public.bookings VALUES (910, 8, 3, '2012-08-07 12:00:00', 1);
INSERT INTO public.bookings VALUES (911, 8, 2, '2012-08-07 12:30:00', 1);
INSERT INTO public.bookings VALUES (912, 8, 2, '2012-08-07 14:30:00', 1);
INSERT INTO public.bookings VALUES (913, 8, 0, '2012-08-07 16:30:00', 1);
INSERT INTO public.bookings VALUES (914, 8, 3, '2012-08-07 17:00:00', 2);
INSERT INTO public.bookings VALUES (915, 8, 8, '2012-08-07 19:30:00', 1);
INSERT INTO public.bookings VALUES (916, 0, 10, '2012-08-08 09:00:00', 3);
INSERT INTO public.bookings VALUES (917, 0, 6, '2012-08-08 12:30:00', 3);
INSERT INTO public.bookings VALUES (918, 0, 5, '2012-08-08 14:00:00', 3);
INSERT INTO public.bookings VALUES (919, 0, 6, '2012-08-08 16:30:00', 3);
INSERT INTO public.bookings VALUES (920, 1, 0, '2012-08-08 08:30:00', 6);
INSERT INTO public.bookings VALUES (921, 1, 10, '2012-08-08 11:30:00', 3);
INSERT INTO public.bookings VALUES (922, 1, 10, '2012-08-08 14:00:00', 3);
INSERT INTO public.bookings VALUES (923, 1, 9, '2012-08-08 19:00:00', 3);
INSERT INTO public.bookings VALUES (924, 2, 5, '2012-08-08 08:00:00', 3);
INSERT INTO public.bookings VALUES (925, 2, 9, '2012-08-08 09:30:00', 3);
INSERT INTO public.bookings VALUES (926, 2, 7, '2012-08-08 11:00:00', 3);
INSERT INTO public.bookings VALUES (927, 2, 1, '2012-08-08 14:00:00', 3);
INSERT INTO public.bookings VALUES (928, 2, 5, '2012-08-08 17:30:00', 3);
INSERT INTO public.bookings VALUES (929, 2, 1, '2012-08-08 19:00:00', 3);
INSERT INTO public.bookings VALUES (930, 3, 10, '2012-08-08 08:00:00', 2);
INSERT INTO public.bookings VALUES (931, 3, 6, '2012-08-08 10:00:00', 2);
INSERT INTO public.bookings VALUES (932, 3, 0, '2012-08-08 12:00:00', 2);
INSERT INTO public.bookings VALUES (933, 3, 10, '2012-08-08 15:30:00', 2);
INSERT INTO public.bookings VALUES (934, 3, 2, '2012-08-08 19:00:00', 2);
INSERT INTO public.bookings VALUES (935, 4, 6, '2012-08-08 08:00:00', 2);
INSERT INTO public.bookings VALUES (936, 4, 8, '2012-08-08 11:00:00', 2);
INSERT INTO public.bookings VALUES (937, 4, 9, '2012-08-08 12:30:00', 4);
INSERT INTO public.bookings VALUES (938, 4, 0, '2012-08-08 15:00:00', 2);
INSERT INTO public.bookings VALUES (939, 4, 0, '2012-08-08 16:30:00', 2);
INSERT INTO public.bookings VALUES (940, 4, 3, '2012-08-08 17:30:00', 2);
INSERT INTO public.bookings VALUES (941, 5, 0, '2012-08-08 08:00:00', 2);
INSERT INTO public.bookings VALUES (942, 6, 0, '2012-08-08 09:00:00', 2);
INSERT INTO public.bookings VALUES (943, 6, 0, '2012-08-08 11:00:00', 2);
INSERT INTO public.bookings VALUES (944, 6, 8, '2012-08-08 12:30:00', 2);
INSERT INTO public.bookings VALUES (945, 6, 6, '2012-08-08 15:00:00', 2);
INSERT INTO public.bookings VALUES (946, 6, 10, '2012-08-08 17:30:00', 2);
INSERT INTO public.bookings VALUES (947, 6, 0, '2012-08-08 19:00:00', 2);
INSERT INTO public.bookings VALUES (948, 7, 8, '2012-08-08 08:00:00', 2);
INSERT INTO public.bookings VALUES (949, 7, 9, '2012-08-08 11:00:00', 2);
INSERT INTO public.bookings VALUES (950, 7, 7, '2012-08-08 12:30:00', 2);
INSERT INTO public.bookings VALUES (951, 7, 4, '2012-08-08 14:00:00', 2);
INSERT INTO public.bookings VALUES (952, 7, 9, '2012-08-08 15:30:00', 2);
INSERT INTO public.bookings VALUES (953, 7, 10, '2012-08-08 18:30:00', 2);
INSERT INTO public.bookings VALUES (954, 8, 4, '2012-08-08 08:00:00', 1);
INSERT INTO public.bookings VALUES (955, 8, 2, '2012-08-08 09:00:00', 1);
INSERT INTO public.bookings VALUES (956, 8, 3, '2012-08-08 10:00:00', 1);
INSERT INTO public.bookings VALUES (957, 8, 3, '2012-08-08 11:00:00', 1);
INSERT INTO public.bookings VALUES (958, 8, 3, '2012-08-08 12:00:00', 1);
INSERT INTO public.bookings VALUES (959, 8, 2, '2012-08-08 13:00:00', 1);
INSERT INTO public.bookings VALUES (960, 8, 7, '2012-08-08 16:00:00', 1);
INSERT INTO public.bookings VALUES (961, 8, 1, '2012-08-08 16:30:00', 1);
INSERT INTO public.bookings VALUES (962, 8, 3, '2012-08-08 17:00:00', 1);
INSERT INTO public.bookings VALUES (963, 8, 2, '2012-08-08 17:30:00', 1);
INSERT INTO public.bookings VALUES (964, 8, 1, '2012-08-08 18:30:00', 1);
INSERT INTO public.bookings VALUES (965, 0, 6, '2012-08-09 09:30:00', 3);
INSERT INTO public.bookings VALUES (966, 0, 7, '2012-08-09 16:00:00', 3);
INSERT INTO public.bookings VALUES (967, 0, 10, '2012-08-09 17:30:00', 3);
INSERT INTO public.bookings VALUES (968, 1, 10, '2012-08-09 08:00:00', 3);
INSERT INTO public.bookings VALUES (969, 1, 0, '2012-08-09 10:00:00', 3);
INSERT INTO public.bookings VALUES (970, 1, 8, '2012-08-09 14:00:00', 3);
INSERT INTO public.bookings VALUES (971, 1, 0, '2012-08-09 17:00:00', 3);
INSERT INTO public.bookings VALUES (972, 2, 2, '2012-08-09 09:00:00', 3);
INSERT INTO public.bookings VALUES (973, 2, 1, '2012-08-09 11:00:00', 3);
INSERT INTO public.bookings VALUES (974, 2, 9, '2012-08-09 13:00:00', 3);
INSERT INTO public.bookings VALUES (975, 2, 1, '2012-08-09 14:30:00', 3);
INSERT INTO public.bookings VALUES (976, 2, 1, '2012-08-09 16:30:00', 3);
INSERT INTO public.bookings VALUES (977, 3, 10, '2012-08-09 10:00:00', 2);
INSERT INTO public.bookings VALUES (978, 3, 7, '2012-08-09 13:30:00', 2);
INSERT INTO public.bookings VALUES (979, 3, 6, '2012-08-09 14:30:00', 2);
INSERT INTO public.bookings VALUES (980, 3, 2, '2012-08-09 18:00:00', 2);
INSERT INTO public.bookings VALUES (981, 4, 0, '2012-08-09 09:00:00', 4);
INSERT INTO public.bookings VALUES (982, 4, 0, '2012-08-09 12:00:00', 4);
INSERT INTO public.bookings VALUES (983, 4, 10, '2012-08-09 16:30:00', 2);
INSERT INTO public.bookings VALUES (984, 4, 9, '2012-08-09 17:30:00', 2);
INSERT INTO public.bookings VALUES (985, 4, 8, '2012-08-09 18:30:00', 2);
INSERT INTO public.bookings VALUES (986, 4, 10, '2012-08-09 19:30:00', 2);
INSERT INTO public.bookings VALUES (987, 6, 6, '2012-08-09 11:30:00', 2);
INSERT INTO public.bookings VALUES (988, 6, 6, '2012-08-09 18:30:00', 2);
INSERT INTO public.bookings VALUES (989, 7, 8, '2012-08-09 08:00:00', 2);
INSERT INTO public.bookings VALUES (990, 7, 8, '2012-08-09 10:30:00', 2);
INSERT INTO public.bookings VALUES (991, 7, 0, '2012-08-09 12:30:00', 2);
INSERT INTO public.bookings VALUES (992, 7, 6, '2012-08-09 16:00:00', 2);
INSERT INTO public.bookings VALUES (993, 7, 2, '2012-08-09 17:00:00', 2);
INSERT INTO public.bookings VALUES (994, 7, 4, '2012-08-09 18:30:00', 2);
INSERT INTO public.bookings VALUES (995, 8, 4, '2012-08-09 10:00:00', 1);
INSERT INTO public.bookings VALUES (996, 8, 2, '2012-08-09 11:30:00', 1);
INSERT INTO public.bookings VALUES (997, 8, 6, '2012-08-09 13:00:00', 1);
INSERT INTO public.bookings VALUES (998, 8, 3, '2012-08-09 15:00:00', 1);
INSERT INTO public.bookings VALUES (999, 8, 5, '2012-08-09 15:30:00', 1);
INSERT INTO public.bookings VALUES (1000, 8, 3, '2012-08-09 17:30:00', 1);
INSERT INTO public.bookings VALUES (1001, 0, 3, '2012-08-10 08:00:00', 3);
INSERT INTO public.bookings VALUES (1002, 0, 2, '2012-08-10 09:30:00', 3);
INSERT INTO public.bookings VALUES (1003, 0, 5, '2012-08-10 11:30:00', 3);
INSERT INTO public.bookings VALUES (1004, 0, 2, '2012-08-10 13:00:00', 3);
INSERT INTO public.bookings VALUES (1005, 0, 8, '2012-08-10 16:30:00', 3);
INSERT INTO public.bookings VALUES (1006, 1, 10, '2012-08-10 08:30:00', 6);
INSERT INTO public.bookings VALUES (1007, 1, 8, '2012-08-10 12:00:00', 3);
INSERT INTO public.bookings VALUES (1008, 1, 9, '2012-08-10 14:00:00', 3);
INSERT INTO public.bookings VALUES (1009, 1, 0, '2012-08-10 16:00:00', 3);
INSERT INTO public.bookings VALUES (1010, 1, 10, '2012-08-10 18:30:00', 3);
INSERT INTO public.bookings VALUES (1011, 2, 1, '2012-08-10 08:00:00', 3);
INSERT INTO public.bookings VALUES (1012, 2, 8, '2012-08-10 09:30:00', 3);
INSERT INTO public.bookings VALUES (1013, 2, 7, '2012-08-10 17:30:00', 3);
INSERT INTO public.bookings VALUES (1014, 2, 0, '2012-08-10 19:00:00', 3);
INSERT INTO public.bookings VALUES (1015, 3, 2, '2012-08-10 08:00:00', 2);
INSERT INTO public.bookings VALUES (1016, 3, 7, '2012-08-10 10:30:00', 2);
INSERT INTO public.bookings VALUES (1017, 3, 10, '2012-08-10 11:30:00', 2);
INSERT INTO public.bookings VALUES (1018, 3, 4, '2012-08-10 14:30:00', 2);
INSERT INTO public.bookings VALUES (1019, 3, 3, '2012-08-10 18:00:00', 4);
INSERT INTO public.bookings VALUES (1020, 4, 6, '2012-08-10 08:30:00', 2);
INSERT INTO public.bookings VALUES (1021, 4, 5, '2012-08-10 10:00:00', 2);
INSERT INTO public.bookings VALUES (1022, 4, 6, '2012-08-10 12:00:00', 2);
INSERT INTO public.bookings VALUES (1023, 4, 0, '2012-08-10 13:00:00', 2);
INSERT INTO public.bookings VALUES (1024, 4, 8, '2012-08-10 14:00:00', 2);
INSERT INTO public.bookings VALUES (1025, 4, 1, '2012-08-10 15:30:00', 2);
INSERT INTO public.bookings VALUES (1026, 4, 3, '2012-08-10 16:30:00', 2);
INSERT INTO public.bookings VALUES (1027, 4, 9, '2012-08-10 19:00:00', 2);
INSERT INTO public.bookings VALUES (1028, 5, 0, '2012-08-10 13:30:00', 2);
INSERT INTO public.bookings VALUES (1029, 6, 0, '2012-08-10 09:00:00', 2);
INSERT INTO public.bookings VALUES (1030, 6, 0, '2012-08-10 11:00:00', 2);
INSERT INTO public.bookings VALUES (1031, 6, 0, '2012-08-10 12:30:00', 2);
INSERT INTO public.bookings VALUES (1032, 6, 0, '2012-08-10 15:00:00', 2);
INSERT INTO public.bookings VALUES (1033, 6, 10, '2012-08-10 16:30:00', 2);
INSERT INTO public.bookings VALUES (1034, 6, 0, '2012-08-10 18:00:00', 2);
INSERT INTO public.bookings VALUES (1035, 7, 4, '2012-08-10 09:30:00', 2);
INSERT INTO public.bookings VALUES (1036, 7, 4, '2012-08-10 11:00:00', 2);
INSERT INTO public.bookings VALUES (1037, 7, 9, '2012-08-10 13:00:00', 2);
INSERT INTO public.bookings VALUES (1038, 7, 6, '2012-08-10 15:00:00', 2);
INSERT INTO public.bookings VALUES (1039, 7, 5, '2012-08-10 16:30:00', 4);
INSERT INTO public.bookings VALUES (1040, 7, 6, '2012-08-10 18:30:00', 2);
INSERT INTO public.bookings VALUES (1041, 7, 7, '2012-08-10 19:30:00', 2);
INSERT INTO public.bookings VALUES (1042, 8, 8, '2012-08-10 09:00:00', 1);
INSERT INTO public.bookings VALUES (1043, 8, 7, '2012-08-10 10:00:00', 1);
INSERT INTO public.bookings VALUES (1044, 8, 3, '2012-08-10 11:30:00', 1);
INSERT INTO public.bookings VALUES (1045, 8, 3, '2012-08-10 12:30:00', 1);
INSERT INTO public.bookings VALUES (1046, 8, 7, '2012-08-10 14:00:00', 1);
INSERT INTO public.bookings VALUES (1047, 8, 2, '2012-08-10 14:30:00', 1);
INSERT INTO public.bookings VALUES (1048, 8, 2, '2012-08-10 15:30:00', 2);
INSERT INTO public.bookings VALUES (1049, 8, 7, '2012-08-10 17:00:00', 1);
INSERT INTO public.bookings VALUES (1050, 8, 4, '2012-08-10 17:30:00', 1);
INSERT INTO public.bookings VALUES (1051, 8, 3, '2012-08-10 20:00:00', 1);
INSERT INTO public.bookings VALUES (1052, 0, 0, '2012-08-11 08:00:00', 3);
INSERT INTO public.bookings VALUES (1053, 0, 5, '2012-08-11 10:00:00', 3);
INSERT INTO public.bookings VALUES (1054, 0, 0, '2012-08-11 12:00:00', 3);
INSERT INTO public.bookings VALUES (1055, 0, 4, '2012-08-11 13:30:00', 3);
INSERT INTO public.bookings VALUES (1056, 0, 0, '2012-08-11 15:00:00', 3);
INSERT INTO public.bookings VALUES (1057, 0, 12, '2012-08-11 16:30:00', 3);
INSERT INTO public.bookings VALUES (1058, 0, 4, '2012-08-11 18:30:00', 3);
INSERT INTO public.bookings VALUES (1059, 1, 11, '2012-08-11 08:00:00', 3);
INSERT INTO public.bookings VALUES (1060, 1, 0, '2012-08-11 10:00:00', 3);
INSERT INTO public.bookings VALUES (1061, 1, 0, '2012-08-11 12:30:00', 3);
INSERT INTO public.bookings VALUES (1062, 1, 0, '2012-08-11 14:30:00', 3);
INSERT INTO public.bookings VALUES (1063, 1, 8, '2012-08-11 16:00:00', 3);
INSERT INTO public.bookings VALUES (1064, 1, 0, '2012-08-11 17:30:00', 3);
INSERT INTO public.bookings VALUES (1065, 2, 1, '2012-08-11 09:00:00', 3);
INSERT INTO public.bookings VALUES (1066, 2, 7, '2012-08-11 11:00:00', 3);
INSERT INTO public.bookings VALUES (1067, 2, 1, '2012-08-11 18:00:00', 3);
INSERT INTO public.bookings VALUES (1068, 3, 11, '2012-08-11 12:00:00', 2);
INSERT INTO public.bookings VALUES (1069, 3, 6, '2012-08-11 14:00:00', 2);
INSERT INTO public.bookings VALUES (1070, 3, 7, '2012-08-11 17:30:00', 2);
INSERT INTO public.bookings VALUES (1071, 3, 13, '2012-08-11 19:00:00', 2);
INSERT INTO public.bookings VALUES (1072, 4, 0, '2012-08-11 10:00:00', 2);
INSERT INTO public.bookings VALUES (1073, 4, 14, '2012-08-11 11:00:00', 2);
INSERT INTO public.bookings VALUES (1074, 4, 0, '2012-08-11 12:30:00', 2);
INSERT INTO public.bookings VALUES (1075, 4, 8, '2012-08-11 14:00:00', 2);
INSERT INTO public.bookings VALUES (1076, 4, 6, '2012-08-11 16:30:00', 2);
INSERT INTO public.bookings VALUES (1077, 4, 8, '2012-08-11 18:00:00', 2);
INSERT INTO public.bookings VALUES (1078, 4, 9, '2012-08-11 19:00:00', 2);
INSERT INTO public.bookings VALUES (1079, 5, 12, '2012-08-11 19:30:00', 2);
INSERT INTO public.bookings VALUES (1080, 6, 13, '2012-08-11 08:00:00', 2);
INSERT INTO public.bookings VALUES (1081, 6, 0, '2012-08-11 09:00:00', 2);
INSERT INTO public.bookings VALUES (1082, 6, 0, '2012-08-11 14:00:00', 2);
INSERT INTO public.bookings VALUES (1083, 6, 6, '2012-08-11 15:00:00', 2);
INSERT INTO public.bookings VALUES (1084, 6, 6, '2012-08-11 17:30:00', 4);
INSERT INTO public.bookings VALUES (1085, 7, 2, '2012-08-11 08:30:00', 2);
INSERT INTO public.bookings VALUES (1086, 7, 8, '2012-08-11 11:30:00', 2);
INSERT INTO public.bookings VALUES (1087, 7, 4, '2012-08-11 15:00:00', 2);
INSERT INTO public.bookings VALUES (1088, 7, 2, '2012-08-11 16:00:00', 2);
INSERT INTO public.bookings VALUES (1089, 7, 8, '2012-08-11 19:00:00', 2);
INSERT INTO public.bookings VALUES (1090, 8, 3, '2012-08-11 08:00:00', 2);
INSERT INTO public.bookings VALUES (1091, 8, 1, '2012-08-11 11:30:00', 1);
INSERT INTO public.bookings VALUES (1092, 8, 3, '2012-08-11 12:00:00', 1);
INSERT INTO public.bookings VALUES (1093, 8, 3, '2012-08-11 13:30:00', 3);
INSERT INTO public.bookings VALUES (1094, 8, 3, '2012-08-11 16:00:00', 1);
INSERT INTO public.bookings VALUES (1095, 8, 2, '2012-08-11 17:00:00', 1);
INSERT INTO public.bookings VALUES (1096, 8, 3, '2012-08-11 17:30:00', 1);
INSERT INTO public.bookings VALUES (1097, 8, 2, '2012-08-11 18:00:00', 1);
INSERT INTO public.bookings VALUES (1098, 8, 14, '2012-08-11 19:00:00', 1);
INSERT INTO public.bookings VALUES (1099, 0, 0, '2012-08-12 08:00:00', 3);
INSERT INTO public.bookings VALUES (1100, 0, 7, '2012-08-12 10:30:00', 3);
INSERT INTO public.bookings VALUES (1101, 0, 14, '2012-08-12 13:00:00', 3);
INSERT INTO public.bookings VALUES (1102, 0, 0, '2012-08-12 14:30:00', 3);
INSERT INTO public.bookings VALUES (1103, 0, 6, '2012-08-12 16:00:00', 3);
INSERT INTO public.bookings VALUES (1104, 0, 0, '2012-08-12 17:30:00', 6);
INSERT INTO public.bookings VALUES (1105, 1, 0, '2012-08-12 10:30:00', 3);
INSERT INTO public.bookings VALUES (1106, 1, 9, '2012-08-12 13:30:00', 3);
INSERT INTO public.bookings VALUES (1107, 1, 8, '2012-08-12 19:00:00', 3);
INSERT INTO public.bookings VALUES (1108, 2, 1, '2012-08-12 11:30:00', 3);
INSERT INTO public.bookings VALUES (1109, 2, 2, '2012-08-12 13:00:00', 3);
INSERT INTO public.bookings VALUES (1110, 2, 0, '2012-08-12 14:30:00', 3);
INSERT INTO public.bookings VALUES (1111, 3, 6, '2012-08-12 08:00:00', 2);
INSERT INTO public.bookings VALUES (1112, 3, 10, '2012-08-12 09:30:00', 4);
INSERT INTO public.bookings VALUES (1113, 3, 11, '2012-08-12 14:30:00', 2);
INSERT INTO public.bookings VALUES (1114, 3, 3, '2012-08-12 17:00:00', 2);
INSERT INTO public.bookings VALUES (1115, 3, 5, '2012-08-12 19:00:00', 2);
INSERT INTO public.bookings VALUES (1116, 4, 0, '2012-08-12 09:30:00', 2);
INSERT INTO public.bookings VALUES (1117, 4, 0, '2012-08-12 12:00:00', 2);
INSERT INTO public.bookings VALUES (1118, 4, 6, '2012-08-12 13:00:00', 2);
INSERT INTO public.bookings VALUES (1119, 4, 7, '2012-08-12 16:30:00', 2);
INSERT INTO public.bookings VALUES (1120, 4, 6, '2012-08-12 18:00:00', 2);
INSERT INTO public.bookings VALUES (1121, 5, 0, '2012-08-12 09:30:00', 2);
INSERT INTO public.bookings VALUES (1122, 5, 0, '2012-08-12 12:30:00', 2);
INSERT INTO public.bookings VALUES (1123, 6, 0, '2012-08-12 09:00:00', 4);
INSERT INTO public.bookings VALUES (1124, 6, 13, '2012-08-12 13:00:00', 2);
INSERT INTO public.bookings VALUES (1125, 6, 0, '2012-08-12 14:30:00', 2);
INSERT INTO public.bookings VALUES (1126, 6, 10, '2012-08-12 17:00:00', 2);
INSERT INTO public.bookings VALUES (1127, 7, 8, '2012-08-12 11:00:00', 2);
INSERT INTO public.bookings VALUES (1128, 7, 2, '2012-08-12 12:00:00', 2);
INSERT INTO public.bookings VALUES (1129, 7, 13, '2012-08-12 14:00:00', 2);
INSERT INTO public.bookings VALUES (1130, 7, 5, '2012-08-12 15:00:00', 2);
INSERT INTO public.bookings VALUES (1131, 8, 9, '2012-08-12 08:00:00', 1);
INSERT INTO public.bookings VALUES (1132, 8, 11, '2012-08-12 10:30:00', 1);
INSERT INTO public.bookings VALUES (1133, 8, 3, '2012-08-12 12:00:00', 1);
INSERT INTO public.bookings VALUES (1134, 8, 8, '2012-08-12 12:30:00', 1);
INSERT INTO public.bookings VALUES (1135, 8, 0, '2012-08-12 13:30:00', 1);
INSERT INTO public.bookings VALUES (1136, 8, 0, '2012-08-12 14:30:00', 1);
INSERT INTO public.bookings VALUES (1137, 8, 3, '2012-08-12 19:00:00', 1);
INSERT INTO public.bookings VALUES (1138, 0, 4, '2012-08-13 08:30:00', 3);
INSERT INTO public.bookings VALUES (1139, 0, 0, '2012-08-13 11:00:00', 3);
INSERT INTO public.bookings VALUES (1140, 0, 6, '2012-08-13 15:30:00', 3);
INSERT INTO public.bookings VALUES (1141, 0, 0, '2012-08-13 18:00:00', 3);
INSERT INTO public.bookings VALUES (1142, 1, 12, '2012-08-13 08:30:00', 3);
INSERT INTO public.bookings VALUES (1143, 1, 6, '2012-08-13 11:00:00', 3);
INSERT INTO public.bookings VALUES (1144, 1, 10, '2012-08-13 12:30:00', 6);
INSERT INTO public.bookings VALUES (1145, 1, 11, '2012-08-13 15:30:00', 3);
INSERT INTO public.bookings VALUES (1146, 1, 0, '2012-08-13 17:00:00', 3);
INSERT INTO public.bookings VALUES (1147, 1, 11, '2012-08-13 19:00:00', 3);
INSERT INTO public.bookings VALUES (1148, 2, 1, '2012-08-13 08:00:00', 3);
INSERT INTO public.bookings VALUES (1149, 2, 1, '2012-08-13 11:00:00', 3);
INSERT INTO public.bookings VALUES (1150, 2, 11, '2012-08-13 13:00:00', 3);
INSERT INTO public.bookings VALUES (1151, 2, 2, '2012-08-13 14:30:00', 3);
INSERT INTO public.bookings VALUES (1152, 2, 1, '2012-08-13 17:00:00', 3);
INSERT INTO public.bookings VALUES (1153, 2, 5, '2012-08-13 19:00:00', 3);
INSERT INTO public.bookings VALUES (1154, 3, 3, '2012-08-13 08:00:00', 2);
INSERT INTO public.bookings VALUES (1155, 3, 10, '2012-08-13 11:00:00', 2);
INSERT INTO public.bookings VALUES (1156, 3, 9, '2012-08-13 12:00:00', 2);
INSERT INTO public.bookings VALUES (1157, 3, 3, '2012-08-13 13:00:00', 2);
INSERT INTO public.bookings VALUES (1158, 3, 10, '2012-08-13 15:30:00', 2);
INSERT INTO public.bookings VALUES (1159, 3, 6, '2012-08-13 17:30:00', 2);
INSERT INTO public.bookings VALUES (1160, 4, 7, '2012-08-13 08:00:00', 2);
INSERT INTO public.bookings VALUES (1161, 4, 10, '2012-08-13 09:00:00', 2);
INSERT INTO public.bookings VALUES (1162, 4, 0, '2012-08-13 10:30:00', 4);
INSERT INTO public.bookings VALUES (1163, 4, 0, '2012-08-13 14:00:00', 2);
INSERT INTO public.bookings VALUES (1164, 4, 8, '2012-08-13 15:00:00', 2);
INSERT INTO public.bookings VALUES (1165, 4, 3, '2012-08-13 16:00:00', 2);
INSERT INTO public.bookings VALUES (1166, 4, 10, '2012-08-13 19:00:00', 2);
INSERT INTO public.bookings VALUES (1167, 6, 0, '2012-08-13 08:00:00', 2);
INSERT INTO public.bookings VALUES (1168, 6, 5, '2012-08-13 12:00:00', 2);
INSERT INTO public.bookings VALUES (1169, 6, 6, '2012-08-13 13:00:00', 2);
INSERT INTO public.bookings VALUES (1170, 6, 0, '2012-08-13 17:30:00', 6);
INSERT INTO public.bookings VALUES (1171, 7, 6, '2012-08-13 08:00:00', 2);
INSERT INTO public.bookings VALUES (1172, 7, 14, '2012-08-13 09:00:00', 2);
INSERT INTO public.bookings VALUES (1173, 7, 7, '2012-08-13 10:00:00', 2);
INSERT INTO public.bookings VALUES (1174, 7, 13, '2012-08-13 13:00:00', 2);
INSERT INTO public.bookings VALUES (1175, 7, 8, '2012-08-13 14:00:00', 2);
INSERT INTO public.bookings VALUES (1176, 7, 9, '2012-08-13 17:00:00', 2);
INSERT INTO public.bookings VALUES (1177, 7, 11, '2012-08-13 18:00:00', 2);
INSERT INTO public.bookings VALUES (1178, 7, 4, '2012-08-13 19:00:00', 2);
INSERT INTO public.bookings VALUES (1179, 8, 2, '2012-08-13 08:30:00', 1);
INSERT INTO public.bookings VALUES (1180, 8, 1, '2012-08-13 10:00:00', 1);
INSERT INTO public.bookings VALUES (1181, 8, 3, '2012-08-13 11:00:00', 1);
INSERT INTO public.bookings VALUES (1182, 8, 4, '2012-08-13 12:30:00', 1);
INSERT INTO public.bookings VALUES (1183, 8, 7, '2012-08-13 14:00:00', 1);
INSERT INTO public.bookings VALUES (1184, 8, 4, '2012-08-13 15:00:00', 1);
INSERT INTO public.bookings VALUES (1185, 8, 1, '2012-08-13 16:30:00', 1);
INSERT INTO public.bookings VALUES (1186, 8, 6, '2012-08-13 17:00:00', 1);
INSERT INTO public.bookings VALUES (1187, 8, 3, '2012-08-13 18:30:00', 2);
INSERT INTO public.bookings VALUES (1188, 8, 3, '2012-08-13 20:00:00', 1);
INSERT INTO public.bookings VALUES (1189, 0, 7, '2012-08-14 09:00:00', 3);
INSERT INTO public.bookings VALUES (1190, 0, 14, '2012-08-14 10:30:00', 3);
INSERT INTO public.bookings VALUES (1191, 0, 11, '2012-08-14 13:00:00', 3);
INSERT INTO public.bookings VALUES (1192, 0, 0, '2012-08-14 15:00:00', 6);
INSERT INTO public.bookings VALUES (1193, 0, 10, '2012-08-14 18:30:00', 3);
INSERT INTO public.bookings VALUES (1194, 1, 11, '2012-08-14 10:00:00', 3);
INSERT INTO public.bookings VALUES (1195, 1, 8, '2012-08-14 11:30:00', 3);
INSERT INTO public.bookings VALUES (1196, 1, 0, '2012-08-14 16:30:00', 3);
INSERT INTO public.bookings VALUES (1197, 1, 0, '2012-08-14 18:30:00', 3);
INSERT INTO public.bookings VALUES (1198, 2, 13, '2012-08-14 08:00:00', 3);
INSERT INTO public.bookings VALUES (1199, 2, 1, '2012-08-14 10:30:00', 3);
INSERT INTO public.bookings VALUES (1200, 2, 1, '2012-08-14 13:00:00', 3);
INSERT INTO public.bookings VALUES (1201, 2, 10, '2012-08-14 15:30:00', 3);
INSERT INTO public.bookings VALUES (1202, 2, 0, '2012-08-14 17:00:00', 3);
INSERT INTO public.bookings VALUES (1203, 2, 1, '2012-08-14 19:00:00', 3);
INSERT INTO public.bookings VALUES (1204, 3, 10, '2012-08-14 10:00:00', 2);
INSERT INTO public.bookings VALUES (1205, 3, 10, '2012-08-14 13:00:00', 2);
INSERT INTO public.bookings VALUES (1206, 3, 3, '2012-08-14 18:30:00', 4);
INSERT INTO public.bookings VALUES (1207, 4, 11, '2012-08-14 08:30:00', 2);
INSERT INTO public.bookings VALUES (1208, 4, 0, '2012-08-14 11:00:00', 2);
INSERT INTO public.bookings VALUES (1209, 4, 6, '2012-08-14 12:30:00', 2);
INSERT INTO public.bookings VALUES (1210, 4, 0, '2012-08-14 14:30:00', 2);
INSERT INTO public.bookings VALUES (1211, 4, 14, '2012-08-14 16:30:00', 2);
INSERT INTO public.bookings VALUES (1212, 4, 0, '2012-08-14 18:00:00', 2);
INSERT INTO public.bookings VALUES (1213, 4, 6, '2012-08-14 19:30:00', 2);
INSERT INTO public.bookings VALUES (1214, 5, 0, '2012-08-14 12:00:00', 2);
INSERT INTO public.bookings VALUES (1215, 5, 0, '2012-08-14 13:30:00', 2);
INSERT INTO public.bookings VALUES (1216, 6, 12, '2012-08-14 09:00:00', 2);
INSERT INTO public.bookings VALUES (1217, 6, 0, '2012-08-14 12:30:00', 4);
INSERT INTO public.bookings VALUES (1218, 6, 0, '2012-08-14 16:00:00', 4);
INSERT INTO public.bookings VALUES (1219, 7, 8, '2012-08-14 09:30:00', 4);
INSERT INTO public.bookings VALUES (1220, 7, 2, '2012-08-14 11:30:00', 2);
INSERT INTO public.bookings VALUES (1221, 8, 0, '2012-08-14 08:00:00', 1);
INSERT INTO public.bookings VALUES (1222, 8, 2, '2012-08-14 08:30:00', 1);
INSERT INTO public.bookings VALUES (1223, 8, 11, '2012-08-14 09:30:00', 1);
INSERT INTO public.bookings VALUES (1224, 8, 3, '2012-08-14 11:00:00', 1);
INSERT INTO public.bookings VALUES (1225, 8, 12, '2012-08-14 12:30:00', 1);
INSERT INTO public.bookings VALUES (1226, 8, 3, '2012-08-14 13:30:00', 1);
INSERT INTO public.bookings VALUES (1227, 8, 3, '2012-08-14 16:30:00', 2);
INSERT INTO public.bookings VALUES (1228, 8, 9, '2012-08-14 18:30:00', 1);
INSERT INTO public.bookings VALUES (1229, 8, 6, '2012-08-14 19:00:00', 1);
INSERT INTO public.bookings VALUES (1230, 8, 8, '2012-08-14 19:30:00', 1);
INSERT INTO public.bookings VALUES (1231, 8, 0, '2012-08-14 20:00:00', 1);
INSERT INTO public.bookings VALUES (1232, 0, 0, '2012-08-15 08:00:00', 3);
INSERT INTO public.bookings VALUES (1233, 0, 6, '2012-08-15 11:30:00', 3);
INSERT INTO public.bookings VALUES (1234, 0, 5, '2012-08-15 13:00:00', 3);
INSERT INTO public.bookings VALUES (1235, 0, 14, '2012-08-15 15:00:00', 3);
INSERT INTO public.bookings VALUES (1236, 0, 0, '2012-08-15 16:30:00', 3);
INSERT INTO public.bookings VALUES (1237, 0, 7, '2012-08-15 18:00:00', 3);
INSERT INTO public.bookings VALUES (1238, 1, 0, '2012-08-15 08:00:00', 3);
INSERT INTO public.bookings VALUES (1239, 1, 8, '2012-08-15 09:30:00', 3);
INSERT INTO public.bookings VALUES (1240, 1, 12, '2012-08-15 11:30:00', 3);
INSERT INTO public.bookings VALUES (1241, 1, 11, '2012-08-15 14:30:00', 3);
INSERT INTO public.bookings VALUES (1242, 1, 12, '2012-08-15 16:30:00', 3);
INSERT INTO public.bookings VALUES (1243, 1, 8, '2012-08-15 18:30:00', 3);
INSERT INTO public.bookings VALUES (1244, 2, 1, '2012-08-15 08:00:00', 3);
INSERT INTO public.bookings VALUES (1245, 2, 0, '2012-08-15 10:00:00', 3);
INSERT INTO public.bookings VALUES (1246, 2, 10, '2012-08-15 12:00:00', 3);
INSERT INTO public.bookings VALUES (1247, 2, 13, '2012-08-15 13:30:00', 3);
INSERT INTO public.bookings VALUES (1248, 2, 1, '2012-08-15 15:30:00', 3);
INSERT INTO public.bookings VALUES (1249, 2, 9, '2012-08-15 18:00:00', 3);
INSERT INTO public.bookings VALUES (1250, 3, 3, '2012-08-15 11:00:00', 2);
INSERT INTO public.bookings VALUES (1251, 3, 1, '2012-08-15 13:00:00', 2);
INSERT INTO public.bookings VALUES (1252, 3, 3, '2012-08-15 14:00:00', 2);
INSERT INTO public.bookings VALUES (1253, 3, 11, '2012-08-15 16:30:00', 2);
INSERT INTO public.bookings VALUES (1254, 3, 10, '2012-08-15 18:00:00', 2);
INSERT INTO public.bookings VALUES (1255, 3, 3, '2012-08-15 19:30:00', 2);
INSERT INTO public.bookings VALUES (1256, 4, 0, '2012-08-15 08:30:00', 4);
INSERT INTO public.bookings VALUES (1257, 4, 6, '2012-08-15 10:30:00', 2);
INSERT INTO public.bookings VALUES (1258, 4, 0, '2012-08-15 13:00:00', 2);
INSERT INTO public.bookings VALUES (1259, 4, 0, '2012-08-15 15:00:00', 2);
INSERT INTO public.bookings VALUES (1260, 4, 9, '2012-08-15 16:30:00', 2);
INSERT INTO public.bookings VALUES (1261, 4, 11, '2012-08-15 18:00:00', 2);
INSERT INTO public.bookings VALUES (1262, 5, 0, '2012-08-15 12:00:00', 2);
INSERT INTO public.bookings VALUES (1263, 5, 0, '2012-08-15 16:00:00', 2);
INSERT INTO public.bookings VALUES (1264, 5, 11, '2012-08-15 19:00:00', 2);
INSERT INTO public.bookings VALUES (1265, 6, 6, '2012-08-15 08:00:00', 2);
INSERT INTO public.bookings VALUES (1266, 6, 0, '2012-08-15 10:00:00', 2);
INSERT INTO public.bookings VALUES (1267, 6, 13, '2012-08-15 11:30:00', 2);
INSERT INTO public.bookings VALUES (1268, 6, 11, '2012-08-15 12:30:00', 2);
INSERT INTO public.bookings VALUES (1269, 6, 10, '2012-08-15 13:30:00', 2);
INSERT INTO public.bookings VALUES (1270, 6, 8, '2012-08-15 15:30:00', 2);
INSERT INTO public.bookings VALUES (1271, 6, 13, '2012-08-15 17:00:00', 2);
INSERT INTO public.bookings VALUES (1272, 6, 12, '2012-08-15 18:00:00', 2);
INSERT INTO public.bookings VALUES (1273, 7, 6, '2012-08-15 15:00:00', 2);
INSERT INTO public.bookings VALUES (1274, 7, 8, '2012-08-15 17:30:00', 2);
INSERT INTO public.bookings VALUES (1275, 8, 6, '2012-08-15 09:00:00', 1);
INSERT INTO public.bookings VALUES (1276, 8, 3, '2012-08-15 10:30:00', 1);
INSERT INTO public.bookings VALUES (1277, 8, 2, '2012-08-15 11:30:00', 1);
INSERT INTO public.bookings VALUES (1278, 8, 3, '2012-08-15 13:00:00', 1);
INSERT INTO public.bookings VALUES (1279, 8, 2, '2012-08-15 14:00:00', 2);
INSERT INTO public.bookings VALUES (1280, 8, 3, '2012-08-15 15:30:00', 1);
INSERT INTO public.bookings VALUES (1281, 8, 0, '2012-08-15 16:00:00', 1);
INSERT INTO public.bookings VALUES (1282, 8, 8, '2012-08-15 17:00:00', 1);
INSERT INTO public.bookings VALUES (1283, 8, 3, '2012-08-15 17:30:00', 1);
INSERT INTO public.bookings VALUES (1284, 8, 14, '2012-08-15 19:00:00', 1);
INSERT INTO public.bookings VALUES (1285, 8, 1, '2012-08-15 19:30:00', 1);
INSERT INTO public.bookings VALUES (1286, 8, 6, '2012-08-15 20:00:00', 1);
INSERT INTO public.bookings VALUES (1287, 0, 4, '2012-08-16 08:30:00', 3);
INSERT INTO public.bookings VALUES (1288, 0, 0, '2012-08-16 11:00:00', 3);
INSERT INTO public.bookings VALUES (1289, 0, 5, '2012-08-16 12:30:00', 3);
INSERT INTO public.bookings VALUES (1290, 0, 14, '2012-08-16 14:00:00', 3);
INSERT INTO public.bookings VALUES (1291, 0, 0, '2012-08-16 15:30:00', 3);
INSERT INTO public.bookings VALUES (1292, 0, 0, '2012-08-16 17:30:00', 3);
INSERT INTO public.bookings VALUES (1293, 1, 12, '2012-08-16 08:00:00', 3);
INSERT INTO public.bookings VALUES (1294, 1, 0, '2012-08-16 13:00:00', 3);
INSERT INTO public.bookings VALUES (1295, 1, 11, '2012-08-16 14:30:00', 3);
INSERT INTO public.bookings VALUES (1296, 1, 8, '2012-08-16 16:30:00', 3);
INSERT INTO public.bookings VALUES (1297, 1, 12, '2012-08-16 18:00:00', 3);
INSERT INTO public.bookings VALUES (1298, 2, 5, '2012-08-16 08:30:00', 3);
INSERT INTO public.bookings VALUES (1299, 2, 14, '2012-08-16 10:00:00', 3);
INSERT INTO public.bookings VALUES (1300, 2, 1, '2012-08-16 13:00:00', 3);
INSERT INTO public.bookings VALUES (1301, 2, 2, '2012-08-16 15:30:00', 3);
INSERT INTO public.bookings VALUES (1302, 2, 9, '2012-08-16 17:00:00', 3);
INSERT INTO public.bookings VALUES (1303, 2, 15, '2012-08-16 18:30:00', 3);
INSERT INTO public.bookings VALUES (1304, 3, 6, '2012-08-16 11:00:00', 2);
INSERT INTO public.bookings VALUES (1305, 3, 10, '2012-08-16 16:30:00', 2);
INSERT INTO public.bookings VALUES (1306, 3, 3, '2012-08-16 17:30:00', 2);
INSERT INTO public.bookings VALUES (1307, 4, 1, '2012-08-16 08:30:00', 2);
INSERT INTO public.bookings VALUES (1308, 4, 0, '2012-08-16 11:00:00', 2);
INSERT INTO public.bookings VALUES (1309, 4, 1, '2012-08-16 12:00:00', 2);
INSERT INTO public.bookings VALUES (1310, 4, 9, '2012-08-16 13:00:00', 2);
INSERT INTO public.bookings VALUES (1311, 4, 8, '2012-08-16 14:00:00', 2);
INSERT INTO public.bookings VALUES (1312, 4, 14, '2012-08-16 15:30:00', 2);
INSERT INTO public.bookings VALUES (1313, 4, 13, '2012-08-16 18:30:00', 2);
INSERT INTO public.bookings VALUES (1314, 4, 8, '2012-08-16 19:30:00', 2);
INSERT INTO public.bookings VALUES (1315, 5, 0, '2012-08-16 11:00:00', 2);
INSERT INTO public.bookings VALUES (1316, 6, 0, '2012-08-16 08:30:00', 2);
INSERT INTO public.bookings VALUES (1317, 6, 0, '2012-08-16 11:30:00', 6);
INSERT INTO public.bookings VALUES (1318, 6, 12, '2012-08-16 15:30:00', 2);
INSERT INTO public.bookings VALUES (1319, 6, 5, '2012-08-16 17:30:00', 2);
INSERT INTO public.bookings VALUES (1320, 6, 0, '2012-08-16 18:30:00', 2);
INSERT INTO public.bookings VALUES (1321, 7, 7, '2012-08-16 10:30:00', 2);
INSERT INTO public.bookings VALUES (1322, 7, 7, '2012-08-16 13:00:00', 2);
INSERT INTO public.bookings VALUES (1323, 7, 13, '2012-08-16 14:30:00', 4);
INSERT INTO public.bookings VALUES (1324, 7, 4, '2012-08-16 16:30:00', 2);
INSERT INTO public.bookings VALUES (1325, 7, 10, '2012-08-16 18:00:00', 2);
INSERT INTO public.bookings VALUES (1326, 8, 7, '2012-08-16 08:30:00', 1);
INSERT INTO public.bookings VALUES (1327, 8, 3, '2012-08-16 09:00:00', 2);
INSERT INTO public.bookings VALUES (1328, 8, 3, '2012-08-16 10:30:00', 1);
INSERT INTO public.bookings VALUES (1329, 8, 3, '2012-08-16 12:00:00', 1);
INSERT INTO public.bookings VALUES (1330, 8, 12, '2012-08-16 13:30:00', 1);
INSERT INTO public.bookings VALUES (1331, 8, 3, '2012-08-16 14:00:00', 1);
INSERT INTO public.bookings VALUES (1332, 8, 15, '2012-08-16 14:30:00', 1);
INSERT INTO public.bookings VALUES (1333, 8, 3, '2012-08-16 15:00:00', 2);
INSERT INTO public.bookings VALUES (1334, 8, 4, '2012-08-16 16:00:00', 1);
INSERT INTO public.bookings VALUES (1335, 8, 3, '2012-08-16 19:00:00', 1);
INSERT INTO public.bookings VALUES (1336, 8, 12, '2012-08-16 19:30:00', 1);
INSERT INTO public.bookings VALUES (1337, 0, 0, '2012-08-17 08:30:00', 3);
INSERT INTO public.bookings VALUES (1338, 0, 14, '2012-08-17 12:30:00', 3);
INSERT INTO public.bookings VALUES (1339, 0, 6, '2012-08-17 14:00:00', 3);
INSERT INTO public.bookings VALUES (1340, 0, 10, '2012-08-17 16:00:00', 3);
INSERT INTO public.bookings VALUES (1341, 0, 14, '2012-08-17 17:30:00', 3);
INSERT INTO public.bookings VALUES (1342, 1, 10, '2012-08-17 08:30:00', 3);
INSERT INTO public.bookings VALUES (1343, 1, 0, '2012-08-17 11:00:00', 6);
INSERT INTO public.bookings VALUES (1344, 1, 11, '2012-08-17 15:00:00', 3);
INSERT INTO public.bookings VALUES (1345, 1, 0, '2012-08-17 17:00:00', 3);
INSERT INTO public.bookings VALUES (1346, 1, 16, '2012-08-17 19:00:00', 3);
INSERT INTO public.bookings VALUES (1347, 2, 1, '2012-08-17 09:00:00', 3);
INSERT INTO public.bookings VALUES (1348, 2, 1, '2012-08-17 12:00:00', 3);
INSERT INTO public.bookings VALUES (1349, 2, 11, '2012-08-17 13:30:00', 3);
INSERT INTO public.bookings VALUES (1350, 2, 2, '2012-08-17 16:30:00', 3);
INSERT INTO public.bookings VALUES (1351, 2, 1, '2012-08-17 18:30:00', 3);
INSERT INTO public.bookings VALUES (1352, 3, 10, '2012-08-17 10:00:00', 2);
INSERT INTO public.bookings VALUES (1353, 3, 15, '2012-08-17 11:00:00', 2);
INSERT INTO public.bookings VALUES (1354, 3, 13, '2012-08-17 14:00:00', 2);
INSERT INTO public.bookings VALUES (1355, 3, 15, '2012-08-17 17:30:00', 2);
INSERT INTO public.bookings VALUES (1356, 4, 9, '2012-08-17 08:00:00', 2);
INSERT INTO public.bookings VALUES (1357, 4, 6, '2012-08-17 09:30:00', 2);
INSERT INTO public.bookings VALUES (1358, 4, 3, '2012-08-17 12:00:00', 2);
INSERT INTO public.bookings VALUES (1359, 4, 3, '2012-08-17 13:30:00', 2);
INSERT INTO public.bookings VALUES (1360, 4, 0, '2012-08-17 14:30:00', 2);
INSERT INTO public.bookings VALUES (1361, 4, 16, '2012-08-17 15:30:00', 2);
INSERT INTO public.bookings VALUES (1362, 4, 0, '2012-08-17 16:30:00', 4);
INSERT INTO public.bookings VALUES (1363, 4, 9, '2012-08-17 19:00:00', 2);
INSERT INTO public.bookings VALUES (1364, 5, 4, '2012-08-17 13:00:00', 2);
INSERT INTO public.bookings VALUES (1365, 5, 0, '2012-08-17 15:30:00', 2);
INSERT INTO public.bookings VALUES (1366, 6, 0, '2012-08-17 08:00:00', 2);
INSERT INTO public.bookings VALUES (1367, 6, 12, '2012-08-17 09:30:00', 2);
INSERT INTO public.bookings VALUES (1368, 6, 0, '2012-08-17 11:00:00', 2);
INSERT INTO public.bookings VALUES (1369, 6, 6, '2012-08-17 12:00:00', 2);
INSERT INTO public.bookings VALUES (1370, 6, 0, '2012-08-17 15:00:00', 2);
INSERT INTO public.bookings VALUES (1371, 6, 0, '2012-08-17 17:30:00', 2);
INSERT INTO public.bookings VALUES (1372, 6, 12, '2012-08-17 18:30:00', 2);
INSERT INTO public.bookings VALUES (1373, 6, 6, '2012-08-17 19:30:00', 2);
INSERT INTO public.bookings VALUES (1374, 7, 8, '2012-08-17 08:30:00', 2);
INSERT INTO public.bookings VALUES (1375, 7, 13, '2012-08-17 12:30:00', 2);
INSERT INTO public.bookings VALUES (1376, 7, 15, '2012-08-17 14:30:00', 2);
INSERT INTO public.bookings VALUES (1377, 7, 7, '2012-08-17 16:30:00', 2);
INSERT INTO public.bookings VALUES (1378, 8, 16, '2012-08-17 08:30:00', 1);
INSERT INTO public.bookings VALUES (1379, 8, 16, '2012-08-17 10:00:00', 1);
INSERT INTO public.bookings VALUES (1380, 8, 14, '2012-08-17 11:00:00', 1);
INSERT INTO public.bookings VALUES (1381, 8, 0, '2012-08-17 12:00:00', 1);
INSERT INTO public.bookings VALUES (1382, 8, 2, '2012-08-17 14:00:00', 1);
INSERT INTO public.bookings VALUES (1383, 8, 3, '2012-08-17 14:30:00', 1);
INSERT INTO public.bookings VALUES (1384, 8, 3, '2012-08-17 15:30:00', 1);
INSERT INTO public.bookings VALUES (1385, 8, 8, '2012-08-17 16:00:00', 1);
INSERT INTO public.bookings VALUES (1386, 8, 16, '2012-08-17 16:30:00', 1);
INSERT INTO public.bookings VALUES (1387, 8, 4, '2012-08-17 18:00:00', 1);
INSERT INTO public.bookings VALUES (1388, 8, 6, '2012-08-17 18:30:00', 1);
INSERT INTO public.bookings VALUES (1389, 8, 12, '2012-08-17 19:30:00', 1);
INSERT INTO public.bookings VALUES (1390, 0, 5, '2012-08-18 08:00:00', 3);
INSERT INTO public.bookings VALUES (1391, 0, 0, '2012-08-18 11:00:00', 3);
INSERT INTO public.bookings VALUES (1392, 0, 5, '2012-08-18 12:30:00', 3);
INSERT INTO public.bookings VALUES (1393, 0, 0, '2012-08-18 14:00:00', 3);
INSERT INTO public.bookings VALUES (1394, 1, 8, '2012-08-18 09:30:00', 3);
INSERT INTO public.bookings VALUES (1395, 1, 15, '2012-08-18 12:30:00', 3);
INSERT INTO public.bookings VALUES (1396, 1, 0, '2012-08-18 14:30:00', 3);
INSERT INTO public.bookings VALUES (1397, 1, 7, '2012-08-18 17:00:00', 3);
INSERT INTO public.bookings VALUES (1398, 1, 12, '2012-08-18 18:30:00', 3);
INSERT INTO public.bookings VALUES (1399, 2, 1, '2012-08-18 08:30:00', 3);
INSERT INTO public.bookings VALUES (1400, 2, 1, '2012-08-18 11:30:00', 3);
INSERT INTO public.bookings VALUES (1401, 2, 2, '2012-08-18 16:00:00', 3);
INSERT INTO public.bookings VALUES (1402, 2, 14, '2012-08-18 18:00:00', 3);
INSERT INTO public.bookings VALUES (1403, 3, 15, '2012-08-18 08:00:00', 2);
INSERT INTO public.bookings VALUES (1404, 3, 15, '2012-08-18 11:00:00', 2);
INSERT INTO public.bookings VALUES (1405, 3, 12, '2012-08-18 13:30:00', 2);
INSERT INTO public.bookings VALUES (1406, 3, 1, '2012-08-18 19:30:00', 2);
INSERT INTO public.bookings VALUES (1407, 4, 16, '2012-08-18 08:00:00', 2);
INSERT INTO public.bookings VALUES (1408, 4, 3, '2012-08-18 09:00:00', 2);
INSERT INTO public.bookings VALUES (1409, 4, 4, '2012-08-18 10:30:00', 2);
INSERT INTO public.bookings VALUES (1410, 4, 3, '2012-08-18 11:30:00', 2);
INSERT INTO public.bookings VALUES (1411, 4, 11, '2012-08-18 12:30:00', 2);
INSERT INTO public.bookings VALUES (1412, 4, 0, '2012-08-18 13:30:00', 2);
INSERT INTO public.bookings VALUES (1413, 4, 0, '2012-08-18 15:00:00', 4);
INSERT INTO public.bookings VALUES (1414, 4, 5, '2012-08-18 17:30:00', 2);
INSERT INTO public.bookings VALUES (1415, 4, 0, '2012-08-18 18:30:00', 4);
INSERT INTO public.bookings VALUES (1416, 5, 0, '2012-08-18 11:00:00', 4);
INSERT INTO public.bookings VALUES (1417, 6, 12, '2012-08-18 09:00:00', 2);
INSERT INTO public.bookings VALUES (1418, 6, 0, '2012-08-18 11:00:00', 2);
INSERT INTO public.bookings VALUES (1419, 6, 4, '2012-08-18 12:00:00', 2);
INSERT INTO public.bookings VALUES (1420, 6, 0, '2012-08-18 13:00:00', 2);
INSERT INTO public.bookings VALUES (1421, 6, 14, '2012-08-18 14:30:00', 2);
INSERT INTO public.bookings VALUES (1422, 6, 0, '2012-08-18 16:30:00', 4);
INSERT INTO public.bookings VALUES (1423, 6, 8, '2012-08-18 19:30:00', 2);
INSERT INTO public.bookings VALUES (1424, 7, 8, '2012-08-18 12:00:00', 2);
INSERT INTO public.bookings VALUES (1425, 7, 8, '2012-08-18 13:30:00', 2);
INSERT INTO public.bookings VALUES (1426, 7, 15, '2012-08-18 15:00:00', 2);
INSERT INTO public.bookings VALUES (1427, 7, 15, '2012-08-18 16:30:00', 2);
INSERT INTO public.bookings VALUES (1428, 7, 1, '2012-08-18 18:30:00', 2);
INSERT INTO public.bookings VALUES (1429, 8, 3, '2012-08-18 08:00:00', 1);
INSERT INTO public.bookings VALUES (1430, 8, 6, '2012-08-18 08:30:00', 1);
INSERT INTO public.bookings VALUES (1431, 8, 16, '2012-08-18 09:30:00', 1);
INSERT INTO public.bookings VALUES (1432, 8, 16, '2012-08-18 11:30:00', 2);
INSERT INTO public.bookings VALUES (1433, 8, 2, '2012-08-18 12:30:00', 1);
INSERT INTO public.bookings VALUES (1434, 8, 16, '2012-08-18 13:00:00', 1);
INSERT INTO public.bookings VALUES (1435, 8, 11, '2012-08-18 13:30:00', 1);
INSERT INTO public.bookings VALUES (1436, 8, 16, '2012-08-18 14:00:00', 2);
INSERT INTO public.bookings VALUES (1437, 8, 0, '2012-08-18 16:00:00', 1);
INSERT INTO public.bookings VALUES (1438, 8, 3, '2012-08-18 16:30:00', 1);
INSERT INTO public.bookings VALUES (1439, 0, 12, '2012-08-19 08:00:00', 3);
INSERT INTO public.bookings VALUES (1440, 0, 16, '2012-08-19 10:30:00', 3);
INSERT INTO public.bookings VALUES (1441, 0, 6, '2012-08-19 13:30:00', 3);
INSERT INTO public.bookings VALUES (1442, 0, 6, '2012-08-19 17:30:00', 3);
INSERT INTO public.bookings VALUES (1443, 1, 10, '2012-08-19 08:00:00', 3);
INSERT INTO public.bookings VALUES (1444, 1, 7, '2012-08-19 11:00:00', 3);
INSERT INTO public.bookings VALUES (1445, 1, 10, '2012-08-19 12:30:00', 3);
INSERT INTO public.bookings VALUES (1446, 1, 0, '2012-08-19 15:30:00', 3);
INSERT INTO public.bookings VALUES (1447, 2, 1, '2012-08-19 09:00:00', 3);
INSERT INTO public.bookings VALUES (1448, 2, 5, '2012-08-19 12:30:00', 3);
INSERT INTO public.bookings VALUES (1449, 2, 14, '2012-08-19 16:30:00', 3);
INSERT INTO public.bookings VALUES (1450, 2, 2, '2012-08-19 18:00:00', 3);
INSERT INTO public.bookings VALUES (1451, 3, 16, '2012-08-19 08:00:00', 2);
INSERT INTO public.bookings VALUES (1452, 3, 10, '2012-08-19 09:30:00', 2);
INSERT INTO public.bookings VALUES (1453, 3, 15, '2012-08-19 11:00:00', 4);
INSERT INTO public.bookings VALUES (1454, 3, 14, '2012-08-19 15:00:00', 2);
INSERT INTO public.bookings VALUES (1455, 3, 3, '2012-08-19 18:30:00', 2);
INSERT INTO public.bookings VALUES (1456, 4, 0, '2012-08-19 09:30:00', 6);
INSERT INTO public.bookings VALUES (1457, 4, 5, '2012-08-19 14:00:00', 2);
INSERT INTO public.bookings VALUES (1458, 4, 1, '2012-08-19 15:30:00', 2);
INSERT INTO public.bookings VALUES (1459, 4, 5, '2012-08-19 16:30:00', 2);
INSERT INTO public.bookings VALUES (1460, 4, 16, '2012-08-19 17:30:00', 2);
INSERT INTO public.bookings VALUES (1461, 4, 1, '2012-08-19 19:00:00', 2);
INSERT INTO public.bookings VALUES (1462, 5, 0, '2012-08-19 17:30:00', 2);
INSERT INTO public.bookings VALUES (1463, 5, 0, '2012-08-19 19:00:00', 2);
INSERT INTO public.bookings VALUES (1464, 6, 0, '2012-08-19 09:00:00', 2);
INSERT INTO public.bookings VALUES (1465, 6, 12, '2012-08-19 10:00:00', 2);
INSERT INTO public.bookings VALUES (1466, 6, 0, '2012-08-19 12:00:00', 2);
INSERT INTO public.bookings VALUES (1467, 6, 11, '2012-08-19 13:30:00', 2);
INSERT INTO public.bookings VALUES (1468, 6, 16, '2012-08-19 14:30:00', 2);
INSERT INTO public.bookings VALUES (1469, 6, 0, '2012-08-19 16:30:00', 2);
INSERT INTO public.bookings VALUES (1470, 6, 0, '2012-08-19 18:30:00', 4);
INSERT INTO public.bookings VALUES (1471, 7, 6, '2012-08-19 08:00:00', 2);
INSERT INTO public.bookings VALUES (1472, 7, 5, '2012-08-19 11:00:00', 2);
INSERT INTO public.bookings VALUES (1473, 7, 13, '2012-08-19 13:30:00', 2);
INSERT INTO public.bookings VALUES (1474, 7, 15, '2012-08-19 17:00:00', 2);
INSERT INTO public.bookings VALUES (1475, 7, 4, '2012-08-19 18:30:00', 2);
INSERT INTO public.bookings VALUES (1476, 8, 0, '2012-08-19 10:00:00', 1);
INSERT INTO public.bookings VALUES (1477, 8, 3, '2012-08-19 11:00:00', 1);
INSERT INTO public.bookings VALUES (1478, 8, 4, '2012-08-19 12:30:00', 1);
INSERT INTO public.bookings VALUES (1479, 8, 6, '2012-08-19 13:00:00', 1);
INSERT INTO public.bookings VALUES (1480, 8, 1, '2012-08-19 15:00:00', 1);
INSERT INTO public.bookings VALUES (1481, 8, 16, '2012-08-19 15:30:00', 1);
INSERT INTO public.bookings VALUES (1482, 8, 2, '2012-08-19 17:00:00', 1);
INSERT INTO public.bookings VALUES (1483, 8, 8, '2012-08-19 17:30:00', 1);
INSERT INTO public.bookings VALUES (1484, 8, 12, '2012-08-19 19:00:00', 1);
INSERT INTO public.bookings VALUES (1485, 0, 10, '2012-08-20 08:30:00', 3);
INSERT INTO public.bookings VALUES (1486, 0, 10, '2012-08-20 10:30:00', 3);
INSERT INTO public.bookings VALUES (1487, 0, 14, '2012-08-20 12:00:00', 3);
INSERT INTO public.bookings VALUES (1488, 0, 4, '2012-08-20 14:30:00', 3);
INSERT INTO public.bookings VALUES (1489, 0, 14, '2012-08-20 16:30:00', 3);
INSERT INTO public.bookings VALUES (1490, 0, 16, '2012-08-20 19:00:00', 3);
INSERT INTO public.bookings VALUES (1491, 1, 9, '2012-08-20 08:00:00', 3);
INSERT INTO public.bookings VALUES (1492, 1, 16, '2012-08-20 09:30:00', 3);
INSERT INTO public.bookings VALUES (1493, 1, 0, '2012-08-20 12:00:00', 3);
INSERT INTO public.bookings VALUES (1494, 1, 10, '2012-08-20 13:30:00', 6);
INSERT INTO public.bookings VALUES (1495, 1, 6, '2012-08-20 16:30:00', 3);
INSERT INTO public.bookings VALUES (1496, 1, 8, '2012-08-20 18:30:00', 3);
INSERT INTO public.bookings VALUES (1497, 2, 8, '2012-08-20 08:30:00', 3);
INSERT INTO public.bookings VALUES (1498, 2, 5, '2012-08-20 10:00:00', 6);
INSERT INTO public.bookings VALUES (1499, 2, 1, '2012-08-20 13:00:00', 3);
INSERT INTO public.bookings VALUES (1500, 2, 1, '2012-08-20 15:00:00', 6);
INSERT INTO public.bookings VALUES (1501, 2, 14, '2012-08-20 19:00:00', 3);
INSERT INTO public.bookings VALUES (1502, 3, 1, '2012-08-20 08:00:00', 2);
INSERT INTO public.bookings VALUES (1503, 3, 4, '2012-08-20 11:00:00', 2);
INSERT INTO public.bookings VALUES (1504, 3, 8, '2012-08-20 12:30:00', 2);
INSERT INTO public.bookings VALUES (1505, 3, 11, '2012-08-20 15:30:00', 2);
INSERT INTO public.bookings VALUES (1506, 3, 3, '2012-08-20 17:30:00', 2);
INSERT INTO public.bookings VALUES (1507, 4, 6, '2012-08-20 08:30:00', 2);
INSERT INTO public.bookings VALUES (1508, 4, 3, '2012-08-20 09:30:00', 2);
INSERT INTO public.bookings VALUES (1509, 4, 6, '2012-08-20 10:30:00', 2);
INSERT INTO public.bookings VALUES (1510, 4, 13, '2012-08-20 11:30:00', 2);
INSERT INTO public.bookings VALUES (1511, 4, 16, '2012-08-20 12:30:00', 2);
INSERT INTO public.bookings VALUES (1512, 4, 5, '2012-08-20 13:30:00', 2);
INSERT INTO public.bookings VALUES (1513, 4, 0, '2012-08-20 14:30:00', 2);
INSERT INTO public.bookings VALUES (1514, 4, 16, '2012-08-20 16:00:00', 2);
INSERT INTO public.bookings VALUES (1515, 4, 16, '2012-08-20 17:30:00', 2);
INSERT INTO public.bookings VALUES (1516, 4, 0, '2012-08-20 18:30:00', 2);
INSERT INTO public.bookings VALUES (1517, 6, 16, '2012-08-20 08:00:00', 2);
INSERT INTO public.bookings VALUES (1518, 6, 13, '2012-08-20 09:00:00', 2);
INSERT INTO public.bookings VALUES (1519, 6, 0, '2012-08-20 10:30:00', 2);
INSERT INTO public.bookings VALUES (1520, 6, 6, '2012-08-20 11:30:00', 2);
INSERT INTO public.bookings VALUES (1521, 6, 11, '2012-08-20 12:30:00', 2);
INSERT INTO public.bookings VALUES (1522, 6, 0, '2012-08-20 14:30:00', 2);
INSERT INTO public.bookings VALUES (1523, 6, 8, '2012-08-20 16:30:00', 2);
INSERT INTO public.bookings VALUES (1524, 6, 6, '2012-08-20 19:00:00', 2);
INSERT INTO public.bookings VALUES (1525, 7, 5, '2012-08-20 08:00:00', 2);
INSERT INTO public.bookings VALUES (1526, 7, 1, '2012-08-20 11:30:00', 2);
INSERT INTO public.bookings VALUES (1527, 7, 17, '2012-08-20 12:30:00', 2);
INSERT INTO public.bookings VALUES (1528, 7, 6, '2012-08-20 14:30:00', 2);
INSERT INTO public.bookings VALUES (1529, 7, 9, '2012-08-20 16:00:00', 2);
INSERT INTO public.bookings VALUES (1530, 7, 17, '2012-08-20 17:30:00', 2);
INSERT INTO public.bookings VALUES (1531, 8, 15, '2012-08-20 10:30:00', 1);
INSERT INTO public.bookings VALUES (1532, 8, 3, '2012-08-20 11:30:00', 1);
INSERT INTO public.bookings VALUES (1533, 8, 0, '2012-08-20 13:30:00', 1);
INSERT INTO public.bookings VALUES (1534, 8, 2, '2012-08-20 14:00:00', 1);
INSERT INTO public.bookings VALUES (1535, 8, 3, '2012-08-20 17:00:00', 1);
INSERT INTO public.bookings VALUES (1536, 8, 2, '2012-08-20 18:00:00', 1);
INSERT INTO public.bookings VALUES (1537, 0, 14, '2012-08-21 09:00:00', 6);
INSERT INTO public.bookings VALUES (1538, 0, 0, '2012-08-21 13:00:00', 3);
INSERT INTO public.bookings VALUES (1539, 0, 0, '2012-08-21 18:00:00', 3);
INSERT INTO public.bookings VALUES (1540, 1, 11, '2012-08-21 09:30:00', 3);
INSERT INTO public.bookings VALUES (1541, 1, 9, '2012-08-21 11:00:00', 3);
INSERT INTO public.bookings VALUES (1542, 1, 10, '2012-08-21 12:30:00', 3);
INSERT INTO public.bookings VALUES (1543, 1, 7, '2012-08-21 14:00:00', 3);
INSERT INTO public.bookings VALUES (1544, 1, 10, '2012-08-21 16:30:00', 3);
INSERT INTO public.bookings VALUES (1545, 2, 15, '2012-08-21 08:00:00', 3);
INSERT INTO public.bookings VALUES (1546, 2, 1, '2012-08-21 09:30:00', 3);
INSERT INTO public.bookings VALUES (1547, 2, 17, '2012-08-21 11:00:00', 3);
INSERT INTO public.bookings VALUES (1548, 2, 2, '2012-08-21 12:30:00', 3);
INSERT INTO public.bookings VALUES (1549, 2, 1, '2012-08-21 15:30:00', 3);
INSERT INTO public.bookings VALUES (1550, 2, 15, '2012-08-21 17:00:00', 3);
INSERT INTO public.bookings VALUES (1551, 3, 8, '2012-08-21 10:30:00', 2);
INSERT INTO public.bookings VALUES (1552, 3, 16, '2012-08-21 12:00:00', 2);
INSERT INTO public.bookings VALUES (1553, 3, 2, '2012-08-21 16:00:00', 2);
INSERT INTO public.bookings VALUES (1554, 3, 1, '2012-08-21 18:30:00', 2);
INSERT INTO public.bookings VALUES (1555, 4, 0, '2012-08-21 08:30:00', 2);
INSERT INTO public.bookings VALUES (1556, 4, 7, '2012-08-21 10:00:00', 2);
INSERT INTO public.bookings VALUES (1557, 4, 13, '2012-08-21 11:00:00', 2);
INSERT INTO public.bookings VALUES (1558, 4, 14, '2012-08-21 12:00:00', 2);
INSERT INTO public.bookings VALUES (1559, 4, 0, '2012-08-21 13:00:00', 2);
INSERT INTO public.bookings VALUES (1560, 4, 16, '2012-08-21 14:30:00', 2);
INSERT INTO public.bookings VALUES (1561, 4, 0, '2012-08-21 16:30:00', 2);
INSERT INTO public.bookings VALUES (1562, 4, 0, '2012-08-21 18:00:00', 2);
INSERT INTO public.bookings VALUES (1563, 5, 0, '2012-08-21 08:00:00', 2);
INSERT INTO public.bookings VALUES (1564, 5, 0, '2012-08-21 18:30:00', 2);
INSERT INTO public.bookings VALUES (1565, 6, 0, '2012-08-21 09:00:00', 2);
INSERT INTO public.bookings VALUES (1566, 6, 0, '2012-08-21 10:30:00', 4);
INSERT INTO public.bookings VALUES (1567, 6, 0, '2012-08-21 14:00:00', 2);
INSERT INTO public.bookings VALUES (1568, 6, 0, '2012-08-21 15:30:00', 2);
INSERT INTO public.bookings VALUES (1569, 6, 0, '2012-08-21 17:00:00', 2);
INSERT INTO public.bookings VALUES (1570, 6, 0, '2012-08-21 19:00:00', 2);
INSERT INTO public.bookings VALUES (1571, 7, 10, '2012-08-21 09:30:00', 2);
INSERT INTO public.bookings VALUES (1572, 7, 13, '2012-08-21 13:00:00', 2);
INSERT INTO public.bookings VALUES (1573, 7, 5, '2012-08-21 15:30:00', 2);
INSERT INTO public.bookings VALUES (1574, 7, 5, '2012-08-21 17:30:00', 2);
INSERT INTO public.bookings VALUES (1575, 8, 11, '2012-08-21 08:00:00', 1);
INSERT INTO public.bookings VALUES (1576, 8, 6, '2012-08-21 09:00:00', 1);
INSERT INTO public.bookings VALUES (1577, 8, 3, '2012-08-21 09:30:00', 1);
INSERT INTO public.bookings VALUES (1578, 8, 16, '2012-08-21 10:00:00', 1);
INSERT INTO public.bookings VALUES (1579, 8, 6, '2012-08-21 10:30:00', 1);
INSERT INTO public.bookings VALUES (1580, 8, 3, '2012-08-21 11:00:00', 1);
INSERT INTO public.bookings VALUES (1581, 8, 3, '2012-08-21 12:00:00', 1);
INSERT INTO public.bookings VALUES (1582, 8, 3, '2012-08-21 13:00:00', 1);
INSERT INTO public.bookings VALUES (1583, 8, 6, '2012-08-21 13:30:00', 1);
INSERT INTO public.bookings VALUES (1584, 8, 16, '2012-08-21 16:00:00', 2);
INSERT INTO public.bookings VALUES (1585, 8, 1, '2012-08-21 19:30:00', 1);
INSERT INTO public.bookings VALUES (1586, 0, 11, '2012-08-22 08:00:00', 3);
INSERT INTO public.bookings VALUES (1587, 0, 5, '2012-08-22 10:00:00', 3);
INSERT INTO public.bookings VALUES (1588, 0, 0, '2012-08-22 11:30:00', 6);
INSERT INTO public.bookings VALUES (1589, 0, 16, '2012-08-22 15:00:00', 6);
INSERT INTO public.bookings VALUES (1590, 0, 11, '2012-08-22 18:00:00', 3);
INSERT INTO public.bookings VALUES (1591, 1, 0, '2012-08-22 08:30:00', 3);
INSERT INTO public.bookings VALUES (1592, 1, 0, '2012-08-22 10:30:00', 3);
INSERT INTO public.bookings VALUES (1593, 1, 0, '2012-08-22 13:00:00', 3);
INSERT INTO public.bookings VALUES (1594, 1, 7, '2012-08-22 15:00:00', 3);
INSERT INTO public.bookings VALUES (1595, 1, 12, '2012-08-22 17:00:00', 3);
INSERT INTO public.bookings VALUES (1596, 2, 10, '2012-08-22 09:00:00', 3);
INSERT INTO public.bookings VALUES (1597, 2, 0, '2012-08-22 10:30:00', 3);
INSERT INTO public.bookings VALUES (1598, 2, 1, '2012-08-22 12:30:00', 3);
INSERT INTO public.bookings VALUES (1599, 2, 11, '2012-08-22 15:00:00', 3);
INSERT INTO public.bookings VALUES (1600, 2, 0, '2012-08-22 16:30:00', 6);
INSERT INTO public.bookings VALUES (1601, 3, 11, '2012-08-22 10:00:00', 2);
INSERT INTO public.bookings VALUES (1602, 3, 3, '2012-08-22 11:30:00', 2);
INSERT INTO public.bookings VALUES (1603, 3, 13, '2012-08-22 13:00:00', 2);
INSERT INTO public.bookings VALUES (1604, 3, 1, '2012-08-22 14:30:00', 2);
INSERT INTO public.bookings VALUES (1605, 3, 17, '2012-08-22 15:30:00', 2);
INSERT INTO public.bookings VALUES (1606, 3, 15, '2012-08-22 16:30:00', 2);
INSERT INTO public.bookings VALUES (1607, 3, 10, '2012-08-22 18:30:00', 2);
INSERT INTO public.bookings VALUES (1608, 3, 15, '2012-08-22 19:30:00', 2);
INSERT INTO public.bookings VALUES (1609, 4, 5, '2012-08-22 08:00:00', 2);
INSERT INTO public.bookings VALUES (1610, 4, 9, '2012-08-22 09:00:00', 2);
INSERT INTO public.bookings VALUES (1611, 4, 14, '2012-08-22 10:00:00', 2);
INSERT INTO public.bookings VALUES (1612, 4, 0, '2012-08-22 11:00:00', 2);
INSERT INTO public.bookings VALUES (1613, 4, 9, '2012-08-22 12:00:00', 2);
INSERT INTO public.bookings VALUES (1614, 4, 0, '2012-08-22 14:00:00', 2);
INSERT INTO public.bookings VALUES (1615, 4, 13, '2012-08-22 15:00:00', 2);
INSERT INTO public.bookings VALUES (1616, 4, 3, '2012-08-22 16:00:00', 2);
INSERT INTO public.bookings VALUES (1617, 4, 6, '2012-08-22 17:00:00', 2);
INSERT INTO public.bookings VALUES (1618, 4, 0, '2012-08-22 18:00:00', 4);
INSERT INTO public.bookings VALUES (1619, 5, 0, '2012-08-22 18:00:00', 2);
INSERT INTO public.bookings VALUES (1620, 6, 8, '2012-08-22 08:30:00', 2);
INSERT INTO public.bookings VALUES (1621, 6, 0, '2012-08-22 09:30:00', 2);
INSERT INTO public.bookings VALUES (1622, 6, 12, '2012-08-22 11:00:00', 2);
INSERT INTO public.bookings VALUES (1623, 6, 0, '2012-08-22 12:00:00', 4);
INSERT INTO public.bookings VALUES (1624, 6, 6, '2012-08-22 14:00:00', 2);
INSERT INTO public.bookings VALUES (1625, 6, 12, '2012-08-22 15:30:00', 2);
INSERT INTO public.bookings VALUES (1626, 6, 0, '2012-08-22 18:00:00', 4);
INSERT INTO public.bookings VALUES (1627, 7, 6, '2012-08-22 09:30:00', 2);
INSERT INTO public.bookings VALUES (1628, 7, 4, '2012-08-22 11:30:00', 2);
INSERT INTO public.bookings VALUES (1629, 7, 8, '2012-08-22 15:00:00', 2);
INSERT INTO public.bookings VALUES (1630, 7, 1, '2012-08-22 16:00:00', 2);
INSERT INTO public.bookings VALUES (1631, 7, 13, '2012-08-22 17:30:00', 2);
INSERT INTO public.bookings VALUES (1632, 8, 8, '2012-08-22 08:00:00', 1);
INSERT INTO public.bookings VALUES (1633, 8, 7, '2012-08-22 11:30:00', 1);
INSERT INTO public.bookings VALUES (1634, 8, 8, '2012-08-22 12:00:00', 1);
INSERT INTO public.bookings VALUES (1635, 8, 6, '2012-08-22 12:30:00', 1);
INSERT INTO public.bookings VALUES (1636, 8, 3, '2012-08-22 15:00:00', 1);
INSERT INTO public.bookings VALUES (1637, 8, 2, '2012-08-22 15:30:00', 1);
INSERT INTO public.bookings VALUES (1638, 8, 15, '2012-08-22 16:00:00', 1);
INSERT INTO public.bookings VALUES (1639, 8, 2, '2012-08-22 17:00:00', 1);
INSERT INTO public.bookings VALUES (1640, 8, 3, '2012-08-22 19:00:00', 1);
INSERT INTO public.bookings VALUES (1641, 8, 4, '2012-08-22 19:30:00', 1);
INSERT INTO public.bookings VALUES (1642, 8, 9, '2012-08-22 20:00:00', 1);
INSERT INTO public.bookings VALUES (1643, 0, 11, '2012-08-23 08:30:00', 3);
INSERT INTO public.bookings VALUES (1644, 0, 14, '2012-08-23 11:30:00', 3);
INSERT INTO public.bookings VALUES (1645, 0, 10, '2012-08-23 13:00:00', 3);
INSERT INTO public.bookings VALUES (1646, 0, 5, '2012-08-23 15:30:00', 3);
INSERT INTO public.bookings VALUES (1647, 0, 12, '2012-08-23 17:00:00', 3);
INSERT INTO public.bookings VALUES (1648, 1, 12, '2012-08-23 09:00:00', 3);
INSERT INTO public.bookings VALUES (1649, 1, 11, '2012-08-23 10:30:00', 3);
INSERT INTO public.bookings VALUES (1650, 1, 0, '2012-08-23 13:00:00', 3);
INSERT INTO public.bookings VALUES (1651, 1, 16, '2012-08-23 14:30:00', 3);
INSERT INTO public.bookings VALUES (1652, 1, 10, '2012-08-23 16:00:00', 3);
INSERT INTO public.bookings VALUES (1653, 1, 9, '2012-08-23 17:30:00', 3);
INSERT INTO public.bookings VALUES (1654, 1, 15, '2012-08-23 19:00:00', 3);
INSERT INTO public.bookings VALUES (1655, 2, 14, '2012-08-23 09:30:00', 3);
INSERT INTO public.bookings VALUES (1656, 2, 1, '2012-08-23 11:00:00', 3);
INSERT INTO public.bookings VALUES (1657, 2, 9, '2012-08-23 13:30:00', 3);
INSERT INTO public.bookings VALUES (1658, 2, 8, '2012-08-23 15:30:00', 3);
INSERT INTO public.bookings VALUES (1659, 3, 15, '2012-08-23 09:30:00', 2);
INSERT INTO public.bookings VALUES (1660, 3, 3, '2012-08-23 10:30:00', 2);
INSERT INTO public.bookings VALUES (1661, 3, 4, '2012-08-23 14:00:00', 2);
INSERT INTO public.bookings VALUES (1662, 3, 1, '2012-08-23 15:00:00', 2);
INSERT INTO public.bookings VALUES (1663, 3, 17, '2012-08-23 16:00:00', 2);
INSERT INTO public.bookings VALUES (1664, 3, 3, '2012-08-23 17:00:00', 2);
INSERT INTO public.bookings VALUES (1665, 3, 16, '2012-08-23 19:00:00', 2);
INSERT INTO public.bookings VALUES (1666, 4, 0, '2012-08-23 08:30:00', 4);
INSERT INTO public.bookings VALUES (1667, 4, 0, '2012-08-23 11:00:00', 2);
INSERT INTO public.bookings VALUES (1668, 4, 11, '2012-08-23 12:00:00', 2);
INSERT INTO public.bookings VALUES (1669, 4, 1, '2012-08-23 13:00:00', 2);
INSERT INTO public.bookings VALUES (1670, 4, 5, '2012-08-23 14:30:00', 2);
INSERT INTO public.bookings VALUES (1671, 4, 14, '2012-08-23 15:30:00', 2);
INSERT INTO public.bookings VALUES (1672, 4, 2, '2012-08-23 16:30:00', 2);
INSERT INTO public.bookings VALUES (1673, 4, 8, '2012-08-23 17:30:00', 2);
INSERT INTO public.bookings VALUES (1674, 4, 3, '2012-08-23 18:30:00', 2);
INSERT INTO public.bookings VALUES (1675, 5, 0, '2012-08-23 12:00:00', 2);
INSERT INTO public.bookings VALUES (1676, 5, 0, '2012-08-23 16:30:00', 2);
INSERT INTO public.bookings VALUES (1677, 6, 1, '2012-08-23 08:00:00', 2);
INSERT INTO public.bookings VALUES (1678, 6, 0, '2012-08-23 09:00:00', 4);
INSERT INTO public.bookings VALUES (1679, 6, 13, '2012-08-23 13:00:00', 2);
INSERT INTO public.bookings VALUES (1680, 6, 12, '2012-08-23 14:00:00', 4);
INSERT INTO public.bookings VALUES (1681, 6, 17, '2012-08-23 18:00:00', 2);
INSERT INTO public.bookings VALUES (1682, 7, 4, '2012-08-23 11:00:00', 2);
INSERT INTO public.bookings VALUES (1683, 7, 8, '2012-08-23 14:00:00', 2);
INSERT INTO public.bookings VALUES (1684, 7, 13, '2012-08-23 16:00:00', 2);
INSERT INTO public.bookings VALUES (1685, 7, 11, '2012-08-23 17:00:00', 2);
INSERT INTO public.bookings VALUES (1686, 7, 10, '2012-08-23 18:30:00', 2);
INSERT INTO public.bookings VALUES (1687, 7, 6, '2012-08-23 19:30:00', 2);
INSERT INTO public.bookings VALUES (1688, 8, 17, '2012-08-23 09:00:00', 1);
INSERT INTO public.bookings VALUES (1689, 8, 16, '2012-08-23 09:30:00', 1);
INSERT INTO public.bookings VALUES (1690, 8, 6, '2012-08-23 10:00:00', 1);
INSERT INTO public.bookings VALUES (1691, 8, 4, '2012-08-23 10:30:00', 1);
INSERT INTO public.bookings VALUES (1692, 8, 3, '2012-08-23 13:00:00', 1);
INSERT INTO public.bookings VALUES (1693, 8, 3, '2012-08-23 14:30:00', 2);
INSERT INTO public.bookings VALUES (1694, 8, 9, '2012-08-23 15:30:00', 1);
INSERT INTO public.bookings VALUES (1695, 8, 1, '2012-08-23 16:00:00', 1);
INSERT INTO public.bookings VALUES (1696, 8, 16, '2012-08-23 17:30:00', 1);
INSERT INTO public.bookings VALUES (1697, 8, 16, '2012-08-23 18:30:00', 1);
INSERT INTO public.bookings VALUES (1698, 8, 17, '2012-08-23 19:00:00', 1);
INSERT INTO public.bookings VALUES (1699, 8, 16, '2012-08-23 20:00:00', 1);
INSERT INTO public.bookings VALUES (1700, 0, 14, '2012-08-24 09:00:00', 3);
INSERT INTO public.bookings VALUES (1701, 0, 2, '2012-08-24 11:00:00', 3);
INSERT INTO public.bookings VALUES (1702, 0, 0, '2012-08-24 12:30:00', 6);
INSERT INTO public.bookings VALUES (1703, 0, 6, '2012-08-24 15:30:00', 3);
INSERT INTO public.bookings VALUES (1704, 0, 16, '2012-08-24 17:00:00', 3);
INSERT INTO public.bookings VALUES (1705, 0, 8, '2012-08-24 19:00:00', 3);
INSERT INTO public.bookings VALUES (1706, 1, 12, '2012-08-24 08:00:00', 3);
INSERT INTO public.bookings VALUES (1707, 1, 9, '2012-08-24 09:30:00', 3);
INSERT INTO public.bookings VALUES (1708, 1, 0, '2012-08-24 11:30:00', 3);
INSERT INTO public.bookings VALUES (1709, 1, 8, '2012-08-24 13:00:00', 3);
INSERT INTO public.bookings VALUES (1710, 1, 10, '2012-08-24 15:30:00', 3);
INSERT INTO public.bookings VALUES (1711, 1, 12, '2012-08-24 18:00:00', 3);
INSERT INTO public.bookings VALUES (1712, 2, 13, '2012-08-24 08:00:00', 3);
INSERT INTO public.bookings VALUES (1713, 2, 0, '2012-08-24 11:00:00', 3);
INSERT INTO public.bookings VALUES (1714, 2, 15, '2012-08-24 13:00:00', 3);
INSERT INTO public.bookings VALUES (1715, 2, 16, '2012-08-24 15:00:00', 3);
INSERT INTO public.bookings VALUES (1716, 2, 12, '2012-08-24 16:30:00', 3);
INSERT INTO public.bookings VALUES (1717, 3, 1, '2012-08-24 08:30:00', 2);
INSERT INTO public.bookings VALUES (1718, 3, 3, '2012-08-24 11:00:00', 2);
INSERT INTO public.bookings VALUES (1719, 3, 17, '2012-08-24 14:00:00', 2);
INSERT INTO public.bookings VALUES (1720, 3, 8, '2012-08-24 16:30:00', 2);
INSERT INTO public.bookings VALUES (1721, 3, 15, '2012-08-24 17:30:00', 2);
INSERT INTO public.bookings VALUES (1722, 3, 10, '2012-08-24 18:30:00', 2);
INSERT INTO public.bookings VALUES (1723, 4, 0, '2012-08-24 08:00:00', 2);
INSERT INTO public.bookings VALUES (1724, 4, 3, '2012-08-24 10:00:00', 2);
INSERT INTO public.bookings VALUES (1725, 4, 9, '2012-08-24 12:00:00', 2);
INSERT INTO public.bookings VALUES (1726, 4, 14, '2012-08-24 13:00:00', 2);
INSERT INTO public.bookings VALUES (1727, 4, 3, '2012-08-24 14:00:00', 2);
INSERT INTO public.bookings VALUES (1728, 4, 0, '2012-08-24 17:00:00', 2);
INSERT INTO public.bookings VALUES (1729, 4, 3, '2012-08-24 18:00:00', 2);
INSERT INTO public.bookings VALUES (1730, 4, 0, '2012-08-24 19:00:00', 2);
INSERT INTO public.bookings VALUES (1731, 5, 0, '2012-08-24 18:30:00', 2);
INSERT INTO public.bookings VALUES (1732, 6, 6, '2012-08-24 09:30:00', 2);
INSERT INTO public.bookings VALUES (1733, 6, 0, '2012-08-24 11:00:00', 2);
INSERT INTO public.bookings VALUES (1734, 6, 14, '2012-08-24 12:00:00', 2);
INSERT INTO public.bookings VALUES (1735, 6, 0, '2012-08-24 14:30:00', 2);
INSERT INTO public.bookings VALUES (1736, 6, 11, '2012-08-24 17:00:00', 2);
INSERT INTO public.bookings VALUES (1737, 6, 14, '2012-08-24 18:30:00', 2);
INSERT INTO public.bookings VALUES (1738, 6, 0, '2012-08-24 19:30:00', 2);
INSERT INTO public.bookings VALUES (1739, 7, 15, '2012-08-24 09:30:00', 2);
INSERT INTO public.bookings VALUES (1740, 7, 17, '2012-08-24 13:00:00', 2);
INSERT INTO public.bookings VALUES (1741, 7, 13, '2012-08-24 14:00:00', 2);
INSERT INTO public.bookings VALUES (1742, 7, 4, '2012-08-24 17:00:00', 2);
INSERT INTO public.bookings VALUES (1743, 7, 2, '2012-08-24 18:30:00', 2);
INSERT INTO public.bookings VALUES (1744, 8, 3, '2012-08-24 08:30:00', 1);
INSERT INTO public.bookings VALUES (1745, 8, 16, '2012-08-24 11:00:00', 1);
INSERT INTO public.bookings VALUES (1746, 8, 16, '2012-08-24 13:30:00', 1);
INSERT INTO public.bookings VALUES (1747, 8, 14, '2012-08-24 14:00:00', 1);
INSERT INTO public.bookings VALUES (1748, 8, 14, '2012-08-24 17:30:00', 1);
INSERT INTO public.bookings VALUES (1749, 0, 8, '2012-08-25 08:00:00', 3);
INSERT INTO public.bookings VALUES (1750, 0, 7, '2012-08-25 11:00:00', 3);
INSERT INTO public.bookings VALUES (1751, 0, 0, '2012-08-25 12:30:00', 3);
INSERT INTO public.bookings VALUES (1752, 0, 5, '2012-08-25 14:00:00', 3);
INSERT INTO public.bookings VALUES (1753, 0, 0, '2012-08-25 15:30:00', 3);
INSERT INTO public.bookings VALUES (1754, 0, 17, '2012-08-25 17:00:00', 3);
INSERT INTO public.bookings VALUES (1755, 1, 9, '2012-08-25 08:00:00', 3);
INSERT INTO public.bookings VALUES (1756, 1, 11, '2012-08-25 11:30:00', 3);
INSERT INTO public.bookings VALUES (1757, 1, 0, '2012-08-25 13:30:00', 9);
INSERT INTO public.bookings VALUES (1758, 1, 15, '2012-08-25 18:30:00', 3);
INSERT INTO public.bookings VALUES (1759, 2, 2, '2012-08-25 08:00:00', 3);
INSERT INTO public.bookings VALUES (1760, 2, 1, '2012-08-25 09:30:00', 3);
INSERT INTO public.bookings VALUES (1761, 2, 14, '2012-08-25 11:00:00', 3);
INSERT INTO public.bookings VALUES (1762, 2, 1, '2012-08-25 12:30:00', 3);
INSERT INTO public.bookings VALUES (1763, 2, 1, '2012-08-25 16:30:00', 3);
INSERT INTO public.bookings VALUES (1764, 3, 16, '2012-08-25 08:00:00', 2);
INSERT INTO public.bookings VALUES (1765, 3, 16, '2012-08-25 09:30:00', 2);
INSERT INTO public.bookings VALUES (1766, 3, 0, '2012-08-25 12:00:00', 2);
INSERT INTO public.bookings VALUES (1767, 3, 15, '2012-08-25 14:30:00', 2);
INSERT INTO public.bookings VALUES (1768, 3, 11, '2012-08-25 18:30:00', 2);
INSERT INTO public.bookings VALUES (1769, 3, 3, '2012-08-25 19:30:00', 2);
INSERT INTO public.bookings VALUES (1770, 4, 14, '2012-08-25 08:00:00', 2);
INSERT INTO public.bookings VALUES (1771, 4, 0, '2012-08-25 09:30:00', 2);
INSERT INTO public.bookings VALUES (1772, 4, 6, '2012-08-25 10:30:00', 2);
INSERT INTO public.bookings VALUES (1773, 4, 10, '2012-08-25 11:30:00', 2);
INSERT INTO public.bookings VALUES (1774, 4, 3, '2012-08-25 12:30:00', 2);
INSERT INTO public.bookings VALUES (1775, 4, 11, '2012-08-25 14:00:00', 2);
INSERT INTO public.bookings VALUES (1776, 4, 13, '2012-08-25 15:30:00', 4);
INSERT INTO public.bookings VALUES (1777, 4, 3, '2012-08-25 17:30:00', 2);
INSERT INTO public.bookings VALUES (1778, 5, 11, '2012-08-25 08:00:00', 2);
INSERT INTO public.bookings VALUES (1779, 5, 0, '2012-08-25 14:30:00', 2);
INSERT INTO public.bookings VALUES (1780, 6, 0, '2012-08-25 08:30:00', 4);
INSERT INTO public.bookings VALUES (1781, 6, 0, '2012-08-25 11:00:00', 2);
INSERT INTO public.bookings VALUES (1782, 6, 12, '2012-08-25 14:00:00', 2);
INSERT INTO public.bookings VALUES (1783, 6, 0, '2012-08-25 18:30:00', 2);
INSERT INTO public.bookings VALUES (1784, 6, 6, '2012-08-25 19:30:00', 2);
INSERT INTO public.bookings VALUES (1785, 7, 15, '2012-08-25 08:30:00', 2);
INSERT INTO public.bookings VALUES (1786, 7, 2, '2012-08-25 09:30:00', 2);
INSERT INTO public.bookings VALUES (1787, 7, 4, '2012-08-25 11:00:00', 2);
INSERT INTO public.bookings VALUES (1788, 7, 13, '2012-08-25 14:00:00', 2);
INSERT INTO public.bookings VALUES (1789, 7, 8, '2012-08-25 15:00:00', 2);
INSERT INTO public.bookings VALUES (1790, 7, 0, '2012-08-25 19:00:00', 2);
INSERT INTO public.bookings VALUES (1791, 8, 15, '2012-08-25 08:00:00', 1);
INSERT INTO public.bookings VALUES (1792, 8, 3, '2012-08-25 09:30:00', 3);
INSERT INTO public.bookings VALUES (1793, 8, 16, '2012-08-25 11:00:00', 1);
INSERT INTO public.bookings VALUES (1794, 8, 2, '2012-08-25 12:00:00', 1);
INSERT INTO public.bookings VALUES (1795, 8, 16, '2012-08-25 12:30:00', 2);
INSERT INTO public.bookings VALUES (1796, 8, 3, '2012-08-25 13:30:00', 1);
INSERT INTO public.bookings VALUES (1797, 8, 16, '2012-08-25 14:30:00', 1);
INSERT INTO public.bookings VALUES (1798, 8, 6, '2012-08-25 15:00:00', 1);
INSERT INTO public.bookings VALUES (1799, 8, 3, '2012-08-25 15:30:00', 3);
INSERT INTO public.bookings VALUES (1800, 8, 2, '2012-08-25 17:30:00', 1);
INSERT INTO public.bookings VALUES (1801, 8, 16, '2012-08-25 19:00:00', 1);
INSERT INTO public.bookings VALUES (1802, 0, 11, '2012-08-26 08:30:00', 3);
INSERT INTO public.bookings VALUES (1803, 0, 6, '2012-08-26 10:30:00', 3);
INSERT INTO public.bookings VALUES (1804, 0, 11, '2012-08-26 12:00:00', 3);
INSERT INTO public.bookings VALUES (1805, 0, 0, '2012-08-26 15:00:00', 3);
INSERT INTO public.bookings VALUES (1806, 0, 6, '2012-08-26 17:00:00', 3);
INSERT INTO public.bookings VALUES (1807, 0, 5, '2012-08-26 19:00:00', 3);
INSERT INTO public.bookings VALUES (1808, 1, 12, '2012-08-26 08:30:00', 3);
INSERT INTO public.bookings VALUES (1809, 1, 11, '2012-08-26 10:30:00', 3);
INSERT INTO public.bookings VALUES (1810, 1, 0, '2012-08-26 13:00:00', 6);
INSERT INTO public.bookings VALUES (1811, 1, 13, '2012-08-26 16:00:00', 3);
INSERT INTO public.bookings VALUES (1812, 1, 0, '2012-08-26 17:30:00', 3);
INSERT INTO public.bookings VALUES (1813, 2, 1, '2012-08-26 08:30:00', 3);
INSERT INTO public.bookings VALUES (1814, 2, 16, '2012-08-26 10:00:00', 3);
INSERT INTO public.bookings VALUES (1815, 2, 1, '2012-08-26 11:30:00', 3);
INSERT INTO public.bookings VALUES (1816, 2, 1, '2012-08-26 15:30:00', 3);
INSERT INTO public.bookings VALUES (1817, 2, 0, '2012-08-26 17:30:00', 3);
INSERT INTO public.bookings VALUES (1818, 3, 3, '2012-08-26 08:00:00', 2);
INSERT INTO public.bookings VALUES (1819, 3, 13, '2012-08-26 13:00:00', 2);
INSERT INTO public.bookings VALUES (1820, 3, 10, '2012-08-26 16:00:00', 2);
INSERT INTO public.bookings VALUES (1821, 3, 0, '2012-08-26 18:00:00', 2);
INSERT INTO public.bookings VALUES (1822, 3, 6, '2012-08-26 19:30:00', 2);
INSERT INTO public.bookings VALUES (1823, 4, 0, '2012-08-26 08:00:00', 4);
INSERT INTO public.bookings VALUES (1824, 4, 14, '2012-08-26 10:00:00', 2);
INSERT INTO public.bookings VALUES (1825, 4, 0, '2012-08-26 11:30:00', 2);
INSERT INTO public.bookings VALUES (1826, 4, 10, '2012-08-26 13:00:00', 2);
INSERT INTO public.bookings VALUES (1827, 4, 0, '2012-08-26 15:30:00', 2);
INSERT INTO public.bookings VALUES (1828, 4, 3, '2012-08-26 18:30:00', 2);
INSERT INTO public.bookings VALUES (1829, 5, 0, '2012-08-26 08:00:00', 2);
INSERT INTO public.bookings VALUES (1830, 6, 0, '2012-08-26 08:00:00', 2);
INSERT INTO public.bookings VALUES (1831, 6, 0, '2012-08-26 11:00:00', 2);
INSERT INTO public.bookings VALUES (1832, 6, 12, '2012-08-26 12:00:00', 2);
INSERT INTO public.bookings VALUES (1833, 6, 0, '2012-08-26 15:00:00', 2);
INSERT INTO public.bookings VALUES (1834, 6, 12, '2012-08-26 16:00:00', 2);
INSERT INTO public.bookings VALUES (1835, 6, 0, '2012-08-26 18:30:00', 4);
INSERT INTO public.bookings VALUES (1836, 7, 4, '2012-08-26 08:00:00', 2);
INSERT INTO public.bookings VALUES (1837, 7, 17, '2012-08-26 10:00:00', 2);
INSERT INTO public.bookings VALUES (1838, 7, 8, '2012-08-26 11:30:00', 2);
INSERT INTO public.bookings VALUES (1839, 7, 4, '2012-08-26 13:30:00', 2);
INSERT INTO public.bookings VALUES (1840, 7, 7, '2012-08-26 16:30:00', 2);
INSERT INTO public.bookings VALUES (1841, 7, 7, '2012-08-26 18:00:00', 2);
INSERT INTO public.bookings VALUES (1842, 7, 0, '2012-08-26 19:00:00', 2);
INSERT INTO public.bookings VALUES (1843, 8, 15, '2012-08-26 08:00:00', 1);
INSERT INTO public.bookings VALUES (1844, 8, 3, '2012-08-26 09:30:00', 1);
INSERT INTO public.bookings VALUES (1845, 8, 3, '2012-08-26 10:30:00', 2);
INSERT INTO public.bookings VALUES (1846, 8, 16, '2012-08-26 11:30:00', 1);
INSERT INTO public.bookings VALUES (1847, 8, 3, '2012-08-26 12:00:00', 1);
INSERT INTO public.bookings VALUES (1848, 8, 15, '2012-08-26 12:30:00', 1);
INSERT INTO public.bookings VALUES (1849, 8, 3, '2012-08-26 14:00:00', 1);
INSERT INTO public.bookings VALUES (1850, 8, 16, '2012-08-26 14:30:00', 1);
INSERT INTO public.bookings VALUES (1851, 8, 3, '2012-08-26 15:30:00', 1);
INSERT INTO public.bookings VALUES (1852, 8, 0, '2012-08-26 16:00:00', 1);
INSERT INTO public.bookings VALUES (1853, 8, 0, '2012-08-26 17:00:00', 1);
INSERT INTO public.bookings VALUES (1854, 8, 3, '2012-08-26 18:00:00', 1);
INSERT INTO public.bookings VALUES (1855, 8, 8, '2012-08-26 20:00:00', 1);
INSERT INTO public.bookings VALUES (1856, 0, 0, '2012-08-27 09:00:00', 3);
INSERT INTO public.bookings VALUES (1857, 0, 5, '2012-08-27 10:30:00', 3);
INSERT INTO public.bookings VALUES (1858, 0, 17, '2012-08-27 13:00:00', 3);
INSERT INTO public.bookings VALUES (1859, 0, 7, '2012-08-27 15:30:00', 3);
INSERT INTO public.bookings VALUES (1860, 0, 0, '2012-08-27 17:30:00', 6);
INSERT INTO public.bookings VALUES (1861, 1, 12, '2012-08-27 08:30:00', 3);
INSERT INTO public.bookings VALUES (1862, 1, 0, '2012-08-27 11:00:00', 3);
INSERT INTO public.bookings VALUES (1863, 1, 9, '2012-08-27 12:30:00', 3);
INSERT INTO public.bookings VALUES (1864, 1, 8, '2012-08-27 14:30:00', 3);
INSERT INTO public.bookings VALUES (1865, 1, 9, '2012-08-27 16:30:00', 3);
INSERT INTO public.bookings VALUES (1866, 1, 10, '2012-08-27 18:30:00', 3);
INSERT INTO public.bookings VALUES (1867, 2, 0, '2012-08-27 08:00:00', 3);
INSERT INTO public.bookings VALUES (1868, 2, 0, '2012-08-27 11:00:00', 3);
INSERT INTO public.bookings VALUES (1869, 2, 2, '2012-08-27 14:30:00', 3);
INSERT INTO public.bookings VALUES (1870, 2, 2, '2012-08-27 16:30:00', 3);
INSERT INTO public.bookings VALUES (1871, 3, 15, '2012-08-27 09:30:00', 2);
INSERT INTO public.bookings VALUES (1872, 3, 0, '2012-08-27 11:30:00', 2);
INSERT INTO public.bookings VALUES (1873, 3, 11, '2012-08-27 14:00:00', 2);
INSERT INTO public.bookings VALUES (1874, 3, 16, '2012-08-27 17:00:00', 2);
INSERT INTO public.bookings VALUES (1875, 3, 16, '2012-08-27 19:30:00', 2);
INSERT INTO public.bookings VALUES (1876, 4, 9, '2012-08-27 08:30:00', 2);
INSERT INTO public.bookings VALUES (1877, 4, 5, '2012-08-27 09:30:00', 2);
INSERT INTO public.bookings VALUES (1878, 4, 3, '2012-08-27 10:30:00', 2);
INSERT INTO public.bookings VALUES (1879, 4, 0, '2012-08-27 12:00:00', 2);
INSERT INTO public.bookings VALUES (1880, 4, 8, '2012-08-27 13:30:00', 2);
INSERT INTO public.bookings VALUES (1881, 4, 13, '2012-08-27 14:30:00', 2);
INSERT INTO public.bookings VALUES (1882, 4, 11, '2012-08-27 15:30:00', 2);
INSERT INTO public.bookings VALUES (1883, 4, 0, '2012-08-27 16:30:00', 2);
INSERT INTO public.bookings VALUES (1884, 4, 11, '2012-08-27 18:00:00', 2);
INSERT INTO public.bookings VALUES (1885, 4, 12, '2012-08-27 19:00:00', 2);
INSERT INTO public.bookings VALUES (1886, 5, 20, '2012-08-27 09:00:00', 2);
INSERT INTO public.bookings VALUES (1887, 5, 0, '2012-08-27 10:30:00', 2);
INSERT INTO public.bookings VALUES (1888, 5, 12, '2012-08-27 14:00:00', 2);
INSERT INTO public.bookings VALUES (1889, 6, 0, '2012-08-27 08:00:00', 2);
INSERT INTO public.bookings VALUES (1890, 6, 0, '2012-08-27 09:30:00', 4);
INSERT INTO public.bookings VALUES (1891, 6, 6, '2012-08-27 13:00:00', 2);
INSERT INTO public.bookings VALUES (1892, 6, 0, '2012-08-27 15:00:00', 2);
INSERT INTO public.bookings VALUES (1893, 6, 12, '2012-08-27 16:30:00', 2);
INSERT INTO public.bookings VALUES (1894, 6, 0, '2012-08-27 17:30:00', 2);
INSERT INTO public.bookings VALUES (1895, 6, 1, '2012-08-27 19:00:00', 2);
INSERT INTO public.bookings VALUES (1896, 7, 17, '2012-08-27 09:00:00', 2);
INSERT INTO public.bookings VALUES (1897, 7, 4, '2012-08-27 10:30:00', 2);
INSERT INTO public.bookings VALUES (1898, 7, 2, '2012-08-27 12:30:00', 2);
INSERT INTO public.bookings VALUES (1899, 7, 14, '2012-08-27 13:30:00', 2);
INSERT INTO public.bookings VALUES (1900, 7, 4, '2012-08-27 14:30:00', 2);
INSERT INTO public.bookings VALUES (1901, 7, 13, '2012-08-27 17:00:00', 2);
INSERT INTO public.bookings VALUES (1902, 7, 8, '2012-08-27 18:00:00', 2);
INSERT INTO public.bookings VALUES (1903, 7, 15, '2012-08-27 19:00:00', 2);
INSERT INTO public.bookings VALUES (1904, 8, 9, '2012-08-27 08:00:00', 1);
INSERT INTO public.bookings VALUES (1905, 8, 16, '2012-08-27 10:00:00', 1);
INSERT INTO public.bookings VALUES (1906, 8, 16, '2012-08-27 11:00:00', 3);
INSERT INTO public.bookings VALUES (1907, 8, 3, '2012-08-27 13:30:00', 1);
INSERT INTO public.bookings VALUES (1908, 8, 9, '2012-08-27 14:30:00', 1);
INSERT INTO public.bookings VALUES (1909, 8, 16, '2012-08-27 15:00:00', 1);
INSERT INTO public.bookings VALUES (1910, 8, 4, '2012-08-27 15:30:00', 1);
INSERT INTO public.bookings VALUES (1911, 8, 12, '2012-08-27 16:00:00', 1);
INSERT INTO public.bookings VALUES (1912, 8, 11, '2012-08-27 17:00:00', 1);
INSERT INTO public.bookings VALUES (1913, 8, 3, '2012-08-27 20:00:00', 1);
INSERT INTO public.bookings VALUES (1914, 0, 11, '2012-08-28 08:30:00', 3);
INSERT INTO public.bookings VALUES (1915, 0, 14, '2012-08-28 10:00:00', 3);
INSERT INTO public.bookings VALUES (1916, 0, 10, '2012-08-28 11:30:00', 3);
INSERT INTO public.bookings VALUES (1917, 0, 17, '2012-08-28 14:30:00', 3);
INSERT INTO public.bookings VALUES (1918, 0, 6, '2012-08-28 16:00:00', 3);
INSERT INTO public.bookings VALUES (1919, 0, 16, '2012-08-28 17:30:00', 3);
INSERT INTO public.bookings VALUES (1920, 1, 12, '2012-08-28 08:30:00', 3);
INSERT INTO public.bookings VALUES (1921, 1, 11, '2012-08-28 13:00:00', 3);
INSERT INTO public.bookings VALUES (1922, 1, 9, '2012-08-28 14:30:00', 3);
INSERT INTO public.bookings VALUES (1923, 1, 12, '2012-08-28 19:00:00', 3);
INSERT INTO public.bookings VALUES (1924, 2, 17, '2012-08-28 08:30:00', 3);
INSERT INTO public.bookings VALUES (1925, 2, 1, '2012-08-28 10:30:00', 3);
INSERT INTO public.bookings VALUES (1926, 2, 2, '2012-08-28 12:00:00', 3);
INSERT INTO public.bookings VALUES (1927, 2, 1, '2012-08-28 13:30:00', 9);
INSERT INTO public.bookings VALUES (1928, 2, 0, '2012-08-28 18:00:00', 3);
INSERT INTO public.bookings VALUES (1929, 3, 8, '2012-08-28 11:30:00', 2);
INSERT INTO public.bookings VALUES (1930, 3, 15, '2012-08-28 13:00:00', 2);
INSERT INTO public.bookings VALUES (1931, 3, 20, '2012-08-28 14:00:00', 2);
INSERT INTO public.bookings VALUES (1932, 3, 17, '2012-08-28 18:30:00', 2);
INSERT INTO public.bookings VALUES (1933, 4, 8, '2012-08-28 08:30:00', 2);
INSERT INTO public.bookings VALUES (1934, 4, 3, '2012-08-28 10:30:00', 2);
INSERT INTO public.bookings VALUES (1935, 4, 0, '2012-08-28 11:30:00', 4);
INSERT INTO public.bookings VALUES (1936, 4, 17, '2012-08-28 13:30:00', 2);
INSERT INTO public.bookings VALUES (1937, 4, 10, '2012-08-28 15:30:00', 2);
INSERT INTO public.bookings VALUES (1938, 4, 0, '2012-08-28 16:30:00', 2);
INSERT INTO public.bookings VALUES (1939, 4, 13, '2012-08-28 18:30:00', 2);
INSERT INTO public.bookings VALUES (1940, 4, 20, '2012-08-28 19:30:00', 2);
INSERT INTO public.bookings VALUES (1941, 5, 0, '2012-08-28 09:00:00', 2);
INSERT INTO public.bookings VALUES (1942, 5, 7, '2012-08-28 10:30:00', 2);
INSERT INTO public.bookings VALUES (1943, 5, 0, '2012-08-28 16:00:00', 2);
INSERT INTO public.bookings VALUES (1944, 5, 0, '2012-08-28 18:00:00', 2);
INSERT INTO public.bookings VALUES (1945, 6, 6, '2012-08-28 08:00:00', 2);
INSERT INTO public.bookings VALUES (1946, 6, 0, '2012-08-28 10:30:00', 4);
INSERT INTO public.bookings VALUES (1947, 6, 14, '2012-08-28 12:30:00', 2);
INSERT INTO public.bookings VALUES (1948, 6, 12, '2012-08-28 18:00:00', 2);
INSERT INTO public.bookings VALUES (1949, 7, 13, '2012-08-28 08:00:00', 2);
INSERT INTO public.bookings VALUES (1950, 7, 2, '2012-08-28 09:00:00', 2);
INSERT INTO public.bookings VALUES (1951, 7, 8, '2012-08-28 10:00:00', 2);
INSERT INTO public.bookings VALUES (1952, 7, 9, '2012-08-28 13:30:00', 2);
INSERT INTO public.bookings VALUES (1953, 7, 15, '2012-08-28 14:30:00', 2);
INSERT INTO public.bookings VALUES (1954, 7, 4, '2012-08-28 17:00:00', 2);
INSERT INTO public.bookings VALUES (1955, 7, 2, '2012-08-28 18:00:00', 2);
INSERT INTO public.bookings VALUES (1956, 7, 4, '2012-08-28 19:00:00', 2);
INSERT INTO public.bookings VALUES (1957, 8, 16, '2012-08-28 08:00:00', 1);
INSERT INTO public.bookings VALUES (1958, 8, 3, '2012-08-28 09:30:00', 1);
INSERT INTO public.bookings VALUES (1959, 8, 16, '2012-08-28 10:00:00', 1);
INSERT INTO public.bookings VALUES (1960, 8, 2, '2012-08-28 11:30:00', 1);
INSERT INTO public.bookings VALUES (1961, 8, 12, '2012-08-28 12:00:00', 1);
INSERT INTO public.bookings VALUES (1962, 8, 16, '2012-08-28 13:00:00', 1);
INSERT INTO public.bookings VALUES (1963, 8, 4, '2012-08-28 13:30:00', 1);
INSERT INTO public.bookings VALUES (1964, 8, 16, '2012-08-28 15:30:00', 1);
INSERT INTO public.bookings VALUES (1965, 8, 3, '2012-08-28 17:00:00', 2);
INSERT INTO public.bookings VALUES (1966, 8, 0, '2012-08-28 19:00:00', 1);
INSERT INTO public.bookings VALUES (1967, 0, 0, '2012-08-29 08:30:00', 3);
INSERT INTO public.bookings VALUES (1968, 0, 7, '2012-08-29 11:30:00', 3);
INSERT INTO public.bookings VALUES (1969, 0, 10, '2012-08-29 13:30:00', 3);
INSERT INTO public.bookings VALUES (1970, 0, 0, '2012-08-29 16:00:00', 3);
INSERT INTO public.bookings VALUES (1971, 0, 9, '2012-08-29 17:30:00', 3);
INSERT INTO public.bookings VALUES (1972, 0, 0, '2012-08-29 19:00:00', 3);
INSERT INTO public.bookings VALUES (1973, 1, 12, '2012-08-29 08:00:00', 3);
INSERT INTO public.bookings VALUES (1974, 1, 10, '2012-08-29 10:00:00', 3);
INSERT INTO public.bookings VALUES (1975, 1, 9, '2012-08-29 13:30:00', 3);
INSERT INTO public.bookings VALUES (1976, 1, 10, '2012-08-29 16:30:00', 3);
INSERT INTO public.bookings VALUES (1977, 1, 8, '2012-08-29 18:00:00', 3);
INSERT INTO public.bookings VALUES (1978, 2, 1, '2012-08-29 08:30:00', 3);
INSERT INTO public.bookings VALUES (1979, 2, 1, '2012-08-29 10:30:00', 3);
INSERT INTO public.bookings VALUES (1980, 2, 8, '2012-08-29 12:00:00', 3);
INSERT INTO public.bookings VALUES (1981, 2, 8, '2012-08-29 14:00:00', 3);
INSERT INTO public.bookings VALUES (1982, 2, 6, '2012-08-29 15:30:00', 3);
INSERT INTO public.bookings VALUES (1983, 2, 1, '2012-08-29 17:30:00', 3);
INSERT INTO public.bookings VALUES (1984, 2, 11, '2012-08-29 19:00:00', 3);
INSERT INTO public.bookings VALUES (1985, 3, 3, '2012-08-29 08:30:00', 2);
INSERT INTO public.bookings VALUES (1986, 3, 3, '2012-08-29 10:30:00', 2);
INSERT INTO public.bookings VALUES (1987, 3, 1, '2012-08-29 14:00:00', 2);
INSERT INTO public.bookings VALUES (1988, 3, 14, '2012-08-29 16:00:00', 2);
INSERT INTO public.bookings VALUES (1989, 3, 16, '2012-08-29 17:00:00', 2);
INSERT INTO public.bookings VALUES (1990, 3, 3, '2012-08-29 18:30:00', 4);
INSERT INTO public.bookings VALUES (1991, 4, 0, '2012-08-29 08:30:00', 2);
INSERT INTO public.bookings VALUES (1992, 4, 13, '2012-08-29 10:00:00', 2);
INSERT INTO public.bookings VALUES (1993, 4, 0, '2012-08-29 11:00:00', 2);
INSERT INTO public.bookings VALUES (1994, 4, 1, '2012-08-29 12:00:00', 2);
INSERT INTO public.bookings VALUES (1995, 4, 0, '2012-08-29 13:00:00', 4);
INSERT INTO public.bookings VALUES (1996, 4, 5, '2012-08-29 15:00:00', 2);
INSERT INTO public.bookings VALUES (1997, 4, 0, '2012-08-29 16:30:00', 2);
INSERT INTO public.bookings VALUES (1998, 4, 14, '2012-08-29 18:00:00', 2);
INSERT INTO public.bookings VALUES (1999, 4, 20, '2012-08-29 19:30:00', 2);
INSERT INTO public.bookings VALUES (2000, 6, 0, '2012-08-29 08:00:00', 2);
INSERT INTO public.bookings VALUES (2001, 6, 6, '2012-08-29 10:30:00', 4);
INSERT INTO public.bookings VALUES (2002, 6, 0, '2012-08-29 13:00:00', 2);
INSERT INTO public.bookings VALUES (2003, 6, 0, '2012-08-29 15:30:00', 2);
INSERT INTO public.bookings VALUES (2004, 6, 12, '2012-08-29 17:30:00', 2);
INSERT INTO public.bookings VALUES (2005, 6, 12, '2012-08-29 19:00:00', 2);
INSERT INTO public.bookings VALUES (2006, 7, 8, '2012-08-29 10:00:00', 2);
INSERT INTO public.bookings VALUES (2007, 7, 15, '2012-08-29 13:00:00', 2);
INSERT INTO public.bookings VALUES (2008, 7, 4, '2012-08-29 15:00:00', 2);
INSERT INTO public.bookings VALUES (2009, 7, 2, '2012-08-29 16:30:00', 2);
INSERT INTO public.bookings VALUES (2010, 7, 13, '2012-08-29 17:30:00', 2);
INSERT INTO public.bookings VALUES (2011, 7, 4, '2012-08-29 18:30:00', 2);
INSERT INTO public.bookings VALUES (2012, 7, 8, '2012-08-29 19:30:00', 2);
INSERT INTO public.bookings VALUES (2013, 8, 15, '2012-08-29 08:00:00', 1);
INSERT INTO public.bookings VALUES (2014, 8, 0, '2012-08-29 11:30:00', 1);
INSERT INTO public.bookings VALUES (2015, 8, 3, '2012-08-29 13:30:00', 1);
INSERT INTO public.bookings VALUES (2016, 8, 16, '2012-08-29 14:00:00', 1);
INSERT INTO public.bookings VALUES (2017, 8, 3, '2012-08-29 15:00:00', 2);
INSERT INTO public.bookings VALUES (2018, 8, 0, '2012-08-29 17:30:00', 1);
INSERT INTO public.bookings VALUES (2019, 8, 16, '2012-08-29 18:30:00', 1);
INSERT INTO public.bookings VALUES (2020, 8, 1, '2012-08-29 19:30:00', 1);
INSERT INTO public.bookings VALUES (2021, 0, 0, '2012-08-30 08:00:00', 3);
INSERT INTO public.bookings VALUES (2022, 0, 17, '2012-08-30 09:30:00', 3);
INSERT INTO public.bookings VALUES (2023, 0, 5, '2012-08-30 12:30:00', 3);
INSERT INTO public.bookings VALUES (2024, 0, 0, '2012-08-30 14:00:00', 3);
INSERT INTO public.bookings VALUES (2025, 0, 5, '2012-08-30 16:00:00', 3);
INSERT INTO public.bookings VALUES (2026, 1, 8, '2012-08-30 08:00:00', 3);
INSERT INTO public.bookings VALUES (2027, 1, 10, '2012-08-30 12:30:00', 3);
INSERT INTO public.bookings VALUES (2028, 1, 11, '2012-08-30 14:00:00', 3);
INSERT INTO public.bookings VALUES (2029, 1, 0, '2012-08-30 16:00:00', 3);
INSERT INTO public.bookings VALUES (2030, 1, 0, '2012-08-30 19:00:00', 3);
INSERT INTO public.bookings VALUES (2031, 2, 1, '2012-08-30 11:00:00', 3);
INSERT INTO public.bookings VALUES (2032, 2, 15, '2012-08-30 12:30:00', 3);
INSERT INTO public.bookings VALUES (2033, 2, 1, '2012-08-30 14:00:00', 3);
INSERT INTO public.bookings VALUES (2034, 2, 7, '2012-08-30 17:00:00', 3);
INSERT INTO public.bookings VALUES (2035, 2, 21, '2012-08-30 19:00:00', 3);
INSERT INTO public.bookings VALUES (2036, 3, 10, '2012-08-30 08:00:00', 2);
INSERT INTO public.bookings VALUES (2037, 3, 6, '2012-08-30 09:30:00', 2);
INSERT INTO public.bookings VALUES (2038, 3, 14, '2012-08-30 12:30:00', 2);
INSERT INTO public.bookings VALUES (2039, 3, 20, '2012-08-30 15:00:00', 2);
INSERT INTO public.bookings VALUES (2040, 3, 20, '2012-08-30 16:30:00', 2);
INSERT INTO public.bookings VALUES (2041, 3, 16, '2012-08-30 17:30:00', 2);
INSERT INTO public.bookings VALUES (2042, 3, 6, '2012-08-30 19:30:00', 2);
INSERT INTO public.bookings VALUES (2043, 4, 0, '2012-08-30 08:00:00', 2);
INSERT INTO public.bookings VALUES (2044, 4, 13, '2012-08-30 09:00:00', 2);
INSERT INTO public.bookings VALUES (2045, 4, 0, '2012-08-30 10:00:00', 2);
INSERT INTO public.bookings VALUES (2046, 4, 10, '2012-08-30 14:30:00', 2);
INSERT INTO public.bookings VALUES (2047, 4, 11, '2012-08-30 15:30:00', 2);
INSERT INTO public.bookings VALUES (2048, 4, 1, '2012-08-30 16:30:00', 2);
INSERT INTO public.bookings VALUES (2049, 4, 0, '2012-08-30 18:30:00', 2);
INSERT INTO public.bookings VALUES (2050, 6, 12, '2012-08-30 08:00:00', 6);
INSERT INTO public.bookings VALUES (2051, 6, 12, '2012-08-30 11:30:00', 2);
INSERT INTO public.bookings VALUES (2052, 6, 0, '2012-08-30 13:00:00', 4);
INSERT INTO public.bookings VALUES (2053, 6, 0, '2012-08-30 15:30:00', 2);
INSERT INTO public.bookings VALUES (2054, 6, 12, '2012-08-30 16:30:00', 2);
INSERT INTO public.bookings VALUES (2055, 6, 0, '2012-08-30 17:30:00', 2);
INSERT INTO public.bookings VALUES (2056, 7, 0, '2012-08-30 11:30:00', 2);
INSERT INTO public.bookings VALUES (2057, 7, 4, '2012-08-30 14:30:00', 2);
INSERT INTO public.bookings VALUES (2058, 7, 15, '2012-08-30 17:30:00', 2);
INSERT INTO public.bookings VALUES (2059, 7, 8, '2012-08-30 19:00:00', 2);
INSERT INTO public.bookings VALUES (2060, 8, 1, '2012-08-30 08:00:00', 1);
INSERT INTO public.bookings VALUES (2061, 8, 21, '2012-08-30 10:00:00', 1);
INSERT INTO public.bookings VALUES (2062, 8, 3, '2012-08-30 10:30:00', 1);
INSERT INTO public.bookings VALUES (2063, 8, 20, '2012-08-30 11:00:00', 1);
INSERT INTO public.bookings VALUES (2064, 8, 17, '2012-08-30 12:30:00', 1);
INSERT INTO public.bookings VALUES (2065, 8, 3, '2012-08-30 13:00:00', 1);
INSERT INTO public.bookings VALUES (2066, 8, 2, '2012-08-30 14:00:00', 1);
INSERT INTO public.bookings VALUES (2067, 8, 21, '2012-08-30 15:30:00', 3);
INSERT INTO public.bookings VALUES (2068, 8, 3, '2012-08-30 18:00:00', 1);
INSERT INTO public.bookings VALUES (2069, 8, 6, '2012-08-30 19:00:00', 1);
INSERT INTO public.bookings VALUES (2070, 8, 16, '2012-08-30 19:30:00', 1);
INSERT INTO public.bookings VALUES (2071, 8, 9, '2012-08-30 20:00:00', 1);
INSERT INTO public.bookings VALUES (2072, 0, 5, '2012-08-31 09:00:00', 3);
INSERT INTO public.bookings VALUES (2073, 0, 0, '2012-08-31 10:30:00', 3);
INSERT INTO public.bookings VALUES (2074, 0, 11, '2012-08-31 12:00:00', 3);
INSERT INTO public.bookings VALUES (2075, 0, 6, '2012-08-31 14:30:00', 3);
INSERT INTO public.bookings VALUES (2076, 0, 2, '2012-08-31 16:30:00', 3);
INSERT INTO public.bookings VALUES (2077, 0, 5, '2012-08-31 19:00:00', 3);
INSERT INTO public.bookings VALUES (2078, 1, 0, '2012-08-31 08:00:00', 3);
INSERT INTO public.bookings VALUES (2079, 1, 0, '2012-08-31 10:30:00', 3);
INSERT INTO public.bookings VALUES (2080, 1, 12, '2012-08-31 12:00:00', 3);
INSERT INTO public.bookings VALUES (2081, 1, 8, '2012-08-31 13:30:00', 3);
INSERT INTO public.bookings VALUES (2082, 1, 10, '2012-08-31 15:00:00', 6);
INSERT INTO public.bookings VALUES (2083, 1, 8, '2012-08-31 18:30:00', 3);
INSERT INTO public.bookings VALUES (2084, 2, 2, '2012-08-31 08:30:00', 3);
INSERT INTO public.bookings VALUES (2085, 2, 0, '2012-08-31 11:00:00', 3);
INSERT INTO public.bookings VALUES (2086, 2, 16, '2012-08-31 12:30:00', 3);
INSERT INTO public.bookings VALUES (2087, 2, 21, '2012-08-31 14:00:00', 3);
INSERT INTO public.bookings VALUES (2088, 2, 21, '2012-08-31 17:00:00', 3);
INSERT INTO public.bookings VALUES (2089, 2, 0, '2012-08-31 19:00:00', 3);
INSERT INTO public.bookings VALUES (2090, 3, 20, '2012-08-31 09:00:00', 2);
INSERT INTO public.bookings VALUES (2091, 3, 10, '2012-08-31 10:30:00', 2);
INSERT INTO public.bookings VALUES (2092, 3, 3, '2012-08-31 12:30:00', 2);
INSERT INTO public.bookings VALUES (2093, 3, 20, '2012-08-31 19:30:00', 2);
INSERT INTO public.bookings VALUES (2094, 4, 0, '2012-08-31 08:30:00', 2);
INSERT INTO public.bookings VALUES (2095, 4, 0, '2012-08-31 10:00:00', 2);
INSERT INTO public.bookings VALUES (2096, 4, 14, '2012-08-31 12:30:00', 2);
INSERT INTO public.bookings VALUES (2097, 4, 0, '2012-08-31 13:30:00', 2);
INSERT INTO public.bookings VALUES (2098, 4, 11, '2012-08-31 14:30:00', 4);
INSERT INTO public.bookings VALUES (2099, 4, 9, '2012-08-31 16:30:00', 2);
INSERT INTO public.bookings VALUES (2100, 4, 6, '2012-08-31 18:00:00', 2);
INSERT INTO public.bookings VALUES (2101, 4, 11, '2012-08-31 19:00:00', 2);
INSERT INTO public.bookings VALUES (2102, 5, 0, '2012-08-31 09:30:00', 2);
INSERT INTO public.bookings VALUES (2103, 5, 0, '2012-08-31 11:00:00', 2);
INSERT INTO public.bookings VALUES (2104, 5, 0, '2012-08-31 15:00:00', 2);
INSERT INTO public.bookings VALUES (2105, 5, 11, '2012-08-31 17:00:00', 2);
INSERT INTO public.bookings VALUES (2106, 6, 1, '2012-08-31 09:00:00', 4);
INSERT INTO public.bookings VALUES (2107, 6, 0, '2012-08-31 11:00:00', 4);
INSERT INTO public.bookings VALUES (2108, 6, 0, '2012-08-31 14:30:00', 4);
INSERT INTO public.bookings VALUES (2109, 6, 12, '2012-08-31 18:00:00', 4);
INSERT INTO public.bookings VALUES (2110, 7, 9, '2012-08-31 08:00:00', 2);
INSERT INTO public.bookings VALUES (2111, 7, 5, '2012-08-31 11:30:00', 2);
INSERT INTO public.bookings VALUES (2112, 7, 17, '2012-08-31 13:00:00', 2);
INSERT INTO public.bookings VALUES (2113, 7, 15, '2012-08-31 15:00:00', 2);
INSERT INTO public.bookings VALUES (2114, 7, 17, '2012-08-31 16:30:00', 2);
INSERT INTO public.bookings VALUES (2115, 7, 13, '2012-08-31 17:30:00', 2);
INSERT INTO public.bookings VALUES (2116, 7, 10, '2012-08-31 18:30:00', 2);
INSERT INTO public.bookings VALUES (2117, 8, 17, '2012-08-31 08:30:00', 1);
INSERT INTO public.bookings VALUES (2118, 8, 3, '2012-08-31 10:00:00', 1);
INSERT INTO public.bookings VALUES (2119, 8, 21, '2012-08-31 12:30:00', 2);
INSERT INTO public.bookings VALUES (2120, 8, 3, '2012-08-31 13:30:00', 1);
INSERT INTO public.bookings VALUES (2121, 8, 15, '2012-08-31 14:00:00', 1);
INSERT INTO public.bookings VALUES (2122, 8, 3, '2012-08-31 14:30:00', 1);
INSERT INTO public.bookings VALUES (2123, 8, 16, '2012-08-31 16:00:00', 1);
INSERT INTO public.bookings VALUES (2124, 8, 6, '2012-08-31 16:30:00', 1);
INSERT INTO public.bookings VALUES (2125, 8, 3, '2012-08-31 17:00:00', 1);
INSERT INTO public.bookings VALUES (2126, 8, 2, '2012-08-31 18:00:00', 1);
INSERT INTO public.bookings VALUES (2127, 8, 20, '2012-08-31 18:30:00', 1);
INSERT INTO public.bookings VALUES (2128, 8, 21, '2012-08-31 19:00:00', 1);
INSERT INTO public.bookings VALUES (2129, 8, 21, '2012-08-31 20:00:00', 1);
INSERT INTO public.bookings VALUES (2130, 0, 0, '2012-09-01 08:00:00', 3);
INSERT INTO public.bookings VALUES (2131, 0, 17, '2012-09-01 11:00:00', 3);
INSERT INTO public.bookings VALUES (2132, 0, 7, '2012-09-01 12:30:00', 3);
INSERT INTO public.bookings VALUES (2133, 0, 6, '2012-09-01 15:00:00', 3);
INSERT INTO public.bookings VALUES (2134, 0, 4, '2012-09-01 17:00:00', 3);
INSERT INTO public.bookings VALUES (2135, 1, 0, '2012-09-01 08:00:00', 3);
INSERT INTO public.bookings VALUES (2136, 1, 11, '2012-09-01 09:30:00', 3);
INSERT INTO public.bookings VALUES (2137, 1, 10, '2012-09-01 11:00:00', 3);
INSERT INTO public.bookings VALUES (2138, 1, 12, '2012-09-01 14:30:00', 3);
INSERT INTO public.bookings VALUES (2139, 1, 0, '2012-09-01 16:30:00', 3);
INSERT INTO public.bookings VALUES (2140, 1, 12, '2012-09-01 19:00:00', 3);
INSERT INTO public.bookings VALUES (2141, 2, 1, '2012-09-01 09:00:00', 3);
INSERT INTO public.bookings VALUES (2142, 2, 21, '2012-09-01 13:30:00', 3);
INSERT INTO public.bookings VALUES (2143, 2, 1, '2012-09-01 16:30:00', 3);
INSERT INTO public.bookings VALUES (2144, 2, 15, '2012-09-01 18:00:00', 3);
INSERT INTO public.bookings VALUES (2145, 3, 17, '2012-09-01 08:30:00', 2);
INSERT INTO public.bookings VALUES (2146, 3, 13, '2012-09-01 09:30:00', 2);
INSERT INTO public.bookings VALUES (2147, 3, 15, '2012-09-01 10:30:00', 2);
INSERT INTO public.bookings VALUES (2148, 3, 17, '2012-09-01 12:30:00', 2);
INSERT INTO public.bookings VALUES (2149, 3, 17, '2012-09-01 14:00:00', 2);
INSERT INTO public.bookings VALUES (2150, 3, 16, '2012-09-01 15:00:00', 2);
INSERT INTO public.bookings VALUES (2151, 3, 0, '2012-09-01 16:30:00', 2);
INSERT INTO public.bookings VALUES (2152, 3, 16, '2012-09-01 18:00:00', 2);
INSERT INTO public.bookings VALUES (2153, 3, 17, '2012-09-01 19:00:00', 2);
INSERT INTO public.bookings VALUES (2154, 4, 8, '2012-09-01 08:30:00', 2);
INSERT INTO public.bookings VALUES (2155, 4, 9, '2012-09-01 11:00:00', 2);
INSERT INTO public.bookings VALUES (2156, 4, 11, '2012-09-01 12:30:00', 2);
INSERT INTO public.bookings VALUES (2157, 4, 0, '2012-09-01 13:30:00', 6);
INSERT INTO public.bookings VALUES (2158, 4, 0, '2012-09-01 17:30:00', 2);
INSERT INTO public.bookings VALUES (2159, 4, 16, '2012-09-01 19:30:00', 2);
INSERT INTO public.bookings VALUES (2160, 5, 0, '2012-09-01 09:30:00', 2);
INSERT INTO public.bookings VALUES (2161, 5, 7, '2012-09-01 15:30:00', 2);
INSERT INTO public.bookings VALUES (2162, 6, 0, '2012-09-01 09:30:00', 8);
INSERT INTO public.bookings VALUES (2163, 6, 4, '2012-09-01 15:00:00', 2);
INSERT INTO public.bookings VALUES (2164, 6, 0, '2012-09-01 16:00:00', 4);
INSERT INTO public.bookings VALUES (2165, 6, 2, '2012-09-01 18:00:00', 2);
INSERT INTO public.bookings VALUES (2166, 7, 21, '2012-09-01 08:30:00', 2);
INSERT INTO public.bookings VALUES (2167, 7, 2, '2012-09-01 11:30:00', 2);
INSERT INTO public.bookings VALUES (2168, 7, 1, '2012-09-01 14:00:00', 2);
INSERT INTO public.bookings VALUES (2169, 7, 15, '2012-09-01 15:00:00', 2);
INSERT INTO public.bookings VALUES (2170, 7, 13, '2012-09-01 17:30:00', 2);
INSERT INTO public.bookings VALUES (2171, 7, 9, '2012-09-01 19:00:00', 2);
INSERT INTO public.bookings VALUES (2172, 8, 17, '2012-09-01 10:00:00', 1);
INSERT INTO public.bookings VALUES (2173, 8, 1, '2012-09-01 10:30:00', 1);
INSERT INTO public.bookings VALUES (2174, 8, 14, '2012-09-01 11:00:00', 1);
INSERT INTO public.bookings VALUES (2175, 8, 21, '2012-09-01 11:30:00', 1);
INSERT INTO public.bookings VALUES (2176, 8, 21, '2012-09-01 15:00:00', 1);
INSERT INTO public.bookings VALUES (2177, 8, 3, '2012-09-01 16:00:00', 1);
INSERT INTO public.bookings VALUES (2178, 8, 20, '2012-09-01 18:00:00', 1);
INSERT INTO public.bookings VALUES (2179, 8, 3, '2012-09-01 18:30:00', 1);
INSERT INTO public.bookings VALUES (2180, 8, 7, '2012-09-01 19:30:00', 1);
INSERT INTO public.bookings VALUES (2181, 0, 10, '2012-09-02 08:30:00', 3);
INSERT INTO public.bookings VALUES (2182, 0, 0, '2012-09-02 10:30:00', 3);
INSERT INTO public.bookings VALUES (2183, 0, 12, '2012-09-02 12:00:00', 3);
INSERT INTO public.bookings VALUES (2184, 0, 5, '2012-09-02 15:00:00', 3);
INSERT INTO public.bookings VALUES (2185, 0, 6, '2012-09-02 18:00:00', 3);
INSERT INTO public.bookings VALUES (2186, 1, 15, '2012-09-02 08:30:00', 3);
INSERT INTO public.bookings VALUES (2187, 1, 11, '2012-09-02 12:30:00', 3);
INSERT INTO public.bookings VALUES (2188, 1, 10, '2012-09-02 16:00:00', 6);
INSERT INTO public.bookings VALUES (2189, 1, 0, '2012-09-02 19:00:00', 3);
INSERT INTO public.bookings VALUES (2190, 2, 0, '2012-09-02 09:30:00', 3);
INSERT INTO public.bookings VALUES (2191, 2, 21, '2012-09-02 11:00:00', 3);
INSERT INTO public.bookings VALUES (2192, 2, 0, '2012-09-02 12:30:00', 3);
INSERT INTO public.bookings VALUES (2193, 2, 9, '2012-09-02 15:30:00', 3);
INSERT INTO public.bookings VALUES (2194, 2, 5, '2012-09-02 17:00:00', 3);
INSERT INTO public.bookings VALUES (2195, 2, 0, '2012-09-02 19:00:00', 3);
INSERT INTO public.bookings VALUES (2196, 3, 15, '2012-09-02 13:30:00', 2);
INSERT INTO public.bookings VALUES (2197, 3, 3, '2012-09-02 14:30:00', 2);
INSERT INTO public.bookings VALUES (2198, 3, 15, '2012-09-02 16:30:00', 2);
INSERT INTO public.bookings VALUES (2199, 3, 15, '2012-09-02 18:00:00', 2);
INSERT INTO public.bookings VALUES (2200, 3, 17, '2012-09-02 19:30:00', 2);
INSERT INTO public.bookings VALUES (2201, 4, 0, '2012-09-02 08:00:00', 2);
INSERT INTO public.bookings VALUES (2202, 4, 0, '2012-09-02 09:30:00', 6);
INSERT INTO public.bookings VALUES (2203, 4, 5, '2012-09-02 12:30:00', 2);
INSERT INTO public.bookings VALUES (2204, 4, 0, '2012-09-02 13:30:00', 4);
INSERT INTO public.bookings VALUES (2205, 4, 20, '2012-09-02 15:30:00', 2);
INSERT INTO public.bookings VALUES (2206, 4, 8, '2012-09-02 16:30:00', 2);
INSERT INTO public.bookings VALUES (2207, 4, 14, '2012-09-02 17:30:00', 2);
INSERT INTO public.bookings VALUES (2208, 4, 0, '2012-09-02 18:30:00', 2);
INSERT INTO public.bookings VALUES (2209, 5, 0, '2012-09-02 09:30:00', 2);
INSERT INTO public.bookings VALUES (2210, 5, 0, '2012-09-02 11:30:00', 2);
INSERT INTO public.bookings VALUES (2211, 6, 0, '2012-09-02 08:30:00', 4);
INSERT INTO public.bookings VALUES (2212, 6, 0, '2012-09-02 11:00:00', 2);
INSERT INTO public.bookings VALUES (2213, 6, 10, '2012-09-02 14:00:00', 2);
INSERT INTO public.bookings VALUES (2214, 6, 0, '2012-09-02 15:00:00', 4);
INSERT INTO public.bookings VALUES (2215, 6, 0, '2012-09-02 17:30:00', 2);
INSERT INTO public.bookings VALUES (2216, 6, 0, '2012-09-02 19:00:00', 2);
INSERT INTO public.bookings VALUES (2217, 7, 17, '2012-09-02 08:30:00', 2);
INSERT INTO public.bookings VALUES (2218, 7, 2, '2012-09-02 10:30:00', 2);
INSERT INTO public.bookings VALUES (2219, 7, 22, '2012-09-02 11:30:00', 2);
INSERT INTO public.bookings VALUES (2220, 7, 7, '2012-09-02 13:00:00', 2);
INSERT INTO public.bookings VALUES (2221, 7, 8, '2012-09-02 14:30:00', 2);
INSERT INTO public.bookings VALUES (2222, 7, 2, '2012-09-02 16:30:00', 2);
INSERT INTO public.bookings VALUES (2223, 7, 2, '2012-09-02 18:30:00', 2);
INSERT INTO public.bookings VALUES (2224, 8, 20, '2012-09-02 08:00:00', 1);
INSERT INTO public.bookings VALUES (2225, 8, 3, '2012-09-02 08:30:00', 1);
INSERT INTO public.bookings VALUES (2226, 8, 16, '2012-09-02 09:30:00', 2);
INSERT INTO public.bookings VALUES (2227, 8, 3, '2012-09-02 10:30:00', 1);
INSERT INTO public.bookings VALUES (2228, 8, 3, '2012-09-02 11:30:00', 1);
INSERT INTO public.bookings VALUES (2229, 8, 7, '2012-09-02 12:30:00', 1);
INSERT INTO public.bookings VALUES (2230, 8, 16, '2012-09-02 13:00:00', 1);
INSERT INTO public.bookings VALUES (2231, 8, 16, '2012-09-02 16:00:00', 1);
INSERT INTO public.bookings VALUES (2232, 8, 3, '2012-09-02 17:30:00', 1);
INSERT INTO public.bookings VALUES (2233, 8, 21, '2012-09-02 18:30:00', 1);
INSERT INTO public.bookings VALUES (2234, 8, 3, '2012-09-02 19:00:00', 1);
INSERT INTO public.bookings VALUES (2235, 8, 16, '2012-09-02 20:00:00', 1);
INSERT INTO public.bookings VALUES (2236, 0, 0, '2012-09-03 08:00:00', 6);
INSERT INTO public.bookings VALUES (2237, 0, 11, '2012-09-03 11:00:00', 6);
INSERT INTO public.bookings VALUES (2238, 0, 14, '2012-09-03 14:00:00', 3);
INSERT INTO public.bookings VALUES (2239, 0, 0, '2012-09-03 15:30:00', 3);
INSERT INTO public.bookings VALUES (2240, 0, 16, '2012-09-03 18:00:00', 3);
INSERT INTO public.bookings VALUES (2241, 1, 12, '2012-09-03 08:00:00', 3);
INSERT INTO public.bookings VALUES (2242, 1, 0, '2012-09-03 10:00:00', 6);
INSERT INTO public.bookings VALUES (2243, 1, 0, '2012-09-03 13:30:00', 3);
INSERT INTO public.bookings VALUES (2244, 1, 8, '2012-09-03 15:00:00', 6);
INSERT INTO public.bookings VALUES (2245, 1, 11, '2012-09-03 18:00:00', 3);
INSERT INTO public.bookings VALUES (2246, 2, 21, '2012-09-03 08:30:00', 3);
INSERT INTO public.bookings VALUES (2247, 2, 12, '2012-09-03 10:00:00', 3);
INSERT INTO public.bookings VALUES (2248, 2, 9, '2012-09-03 12:30:00', 3);
INSERT INTO public.bookings VALUES (2249, 2, 17, '2012-09-03 14:00:00', 3);
INSERT INTO public.bookings VALUES (2250, 2, 0, '2012-09-03 19:00:00', 3);
INSERT INTO public.bookings VALUES (2251, 3, 22, '2012-09-03 09:30:00', 2);
INSERT INTO public.bookings VALUES (2252, 3, 21, '2012-09-03 11:30:00', 2);
INSERT INTO public.bookings VALUES (2253, 3, 13, '2012-09-03 12:30:00', 2);
INSERT INTO public.bookings VALUES (2254, 3, 20, '2012-09-03 13:30:00', 4);
INSERT INTO public.bookings VALUES (2255, 3, 17, '2012-09-03 17:30:00', 2);
INSERT INTO public.bookings VALUES (2256, 3, 20, '2012-09-03 19:00:00', 2);
INSERT INTO public.bookings VALUES (2257, 4, 0, '2012-09-03 08:00:00', 2);
INSERT INTO public.bookings VALUES (2258, 4, 8, '2012-09-03 09:30:00', 2);
INSERT INTO public.bookings VALUES (2259, 4, 0, '2012-09-03 11:00:00', 4);
INSERT INTO public.bookings VALUES (2260, 4, 8, '2012-09-03 13:00:00', 2);
INSERT INTO public.bookings VALUES (2261, 4, 0, '2012-09-03 15:00:00', 2);
INSERT INTO public.bookings VALUES (2262, 4, 3, '2012-09-03 16:00:00', 2);
INSERT INTO public.bookings VALUES (2263, 4, 0, '2012-09-03 17:00:00', 2);
INSERT INTO public.bookings VALUES (2264, 4, 14, '2012-09-03 19:00:00', 2);
INSERT INTO public.bookings VALUES (2265, 5, 10, '2012-09-03 11:30:00', 2);
INSERT INTO public.bookings VALUES (2266, 6, 6, '2012-09-03 11:00:00', 2);
INSERT INTO public.bookings VALUES (2267, 6, 0, '2012-09-03 12:00:00', 2);
INSERT INTO public.bookings VALUES (2268, 6, 0, '2012-09-03 13:30:00', 4);
INSERT INTO public.bookings VALUES (2269, 6, 6, '2012-09-03 16:00:00', 4);
INSERT INTO public.bookings VALUES (2270, 6, 12, '2012-09-03 18:30:00', 2);
INSERT INTO public.bookings VALUES (2271, 6, 0, '2012-09-03 19:30:00', 2);
INSERT INTO public.bookings VALUES (2272, 7, 15, '2012-09-03 09:30:00', 2);
INSERT INTO public.bookings VALUES (2273, 7, 4, '2012-09-03 12:00:00', 4);
INSERT INTO public.bookings VALUES (2274, 7, 15, '2012-09-03 15:00:00', 2);
INSERT INTO public.bookings VALUES (2275, 7, 15, '2012-09-03 17:00:00', 2);
INSERT INTO public.bookings VALUES (2276, 7, 1, '2012-09-03 18:00:00', 2);
INSERT INTO public.bookings VALUES (2277, 7, 7, '2012-09-03 19:00:00', 2);
INSERT INTO public.bookings VALUES (2278, 8, 2, '2012-09-03 08:00:00', 1);
INSERT INTO public.bookings VALUES (2279, 8, 7, '2012-09-03 08:30:00', 1);
INSERT INTO public.bookings VALUES (2280, 8, 16, '2012-09-03 10:00:00', 1);
INSERT INTO public.bookings VALUES (2281, 8, 1, '2012-09-03 10:30:00', 1);
INSERT INTO public.bookings VALUES (2282, 8, 0, '2012-09-03 11:30:00', 1);
INSERT INTO public.bookings VALUES (2283, 8, 3, '2012-09-03 13:00:00', 1);
INSERT INTO public.bookings VALUES (2284, 8, 21, '2012-09-03 14:00:00', 1);
INSERT INTO public.bookings VALUES (2285, 8, 3, '2012-09-03 15:00:00', 1);
INSERT INTO public.bookings VALUES (2286, 8, 21, '2012-09-03 15:30:00', 1);
INSERT INTO public.bookings VALUES (2287, 8, 21, '2012-09-03 17:00:00', 1);
INSERT INTO public.bookings VALUES (2288, 8, 16, '2012-09-03 17:30:00', 1);
INSERT INTO public.bookings VALUES (2289, 8, 20, '2012-09-03 18:30:00', 1);
INSERT INTO public.bookings VALUES (2290, 8, 21, '2012-09-03 20:00:00', 1);
INSERT INTO public.bookings VALUES (2291, 0, 11, '2012-09-04 08:30:00', 3);
INSERT INTO public.bookings VALUES (2292, 0, 0, '2012-09-04 10:00:00', 3);
INSERT INTO public.bookings VALUES (2293, 0, 10, '2012-09-04 11:30:00', 3);
INSERT INTO public.bookings VALUES (2294, 0, 0, '2012-09-04 13:30:00', 3);
INSERT INTO public.bookings VALUES (2295, 0, 5, '2012-09-04 15:00:00', 3);
INSERT INTO public.bookings VALUES (2296, 0, 0, '2012-09-04 16:30:00', 3);
INSERT INTO public.bookings VALUES (2297, 1, 0, '2012-09-04 10:00:00', 3);
INSERT INTO public.bookings VALUES (2298, 1, 8, '2012-09-04 12:00:00', 3);
INSERT INTO public.bookings VALUES (2299, 1, 0, '2012-09-04 14:00:00', 3);
INSERT INTO public.bookings VALUES (2300, 1, 0, '2012-09-04 16:00:00', 3);
INSERT INTO public.bookings VALUES (2301, 1, 9, '2012-09-04 17:30:00', 3);
INSERT INTO public.bookings VALUES (2302, 1, 24, '2012-09-04 19:00:00', 3);
INSERT INTO public.bookings VALUES (2303, 2, 21, '2012-09-04 08:00:00', 3);
INSERT INTO public.bookings VALUES (2304, 2, 14, '2012-09-04 09:30:00', 3);
INSERT INTO public.bookings VALUES (2305, 2, 15, '2012-09-04 11:00:00', 3);
INSERT INTO public.bookings VALUES (2306, 2, 0, '2012-09-04 12:30:00', 3);
INSERT INTO public.bookings VALUES (2307, 2, 0, '2012-09-04 15:00:00', 3);
INSERT INTO public.bookings VALUES (2308, 2, 5, '2012-09-04 16:30:00', 3);
INSERT INTO public.bookings VALUES (2309, 2, 2, '2012-09-04 18:00:00', 3);
INSERT INTO public.bookings VALUES (2310, 3, 20, '2012-09-04 10:30:00', 2);
INSERT INTO public.bookings VALUES (2311, 3, 21, '2012-09-04 11:30:00', 2);
INSERT INTO public.bookings VALUES (2312, 3, 17, '2012-09-04 13:30:00', 2);
INSERT INTO public.bookings VALUES (2313, 3, 21, '2012-09-04 15:00:00', 2);
INSERT INTO public.bookings VALUES (2314, 3, 20, '2012-09-04 17:30:00', 2);
INSERT INTO public.bookings VALUES (2315, 3, 22, '2012-09-04 18:30:00', 2);
INSERT INTO public.bookings VALUES (2316, 4, 0, '2012-09-04 08:00:00', 2);
INSERT INTO public.bookings VALUES (2317, 4, 3, '2012-09-04 10:30:00', 2);
INSERT INTO public.bookings VALUES (2318, 4, 0, '2012-09-04 11:30:00', 2);
INSERT INTO public.bookings VALUES (2319, 4, 7, '2012-09-04 12:30:00', 2);
INSERT INTO public.bookings VALUES (2320, 4, 0, '2012-09-04 13:30:00', 2);
INSERT INTO public.bookings VALUES (2321, 4, 3, '2012-09-04 15:00:00', 2);
INSERT INTO public.bookings VALUES (2322, 4, 0, '2012-09-04 16:00:00', 2);
INSERT INTO public.bookings VALUES (2323, 4, 0, '2012-09-04 17:30:00', 2);
INSERT INTO public.bookings VALUES (2324, 4, 11, '2012-09-04 18:30:00', 2);
INSERT INTO public.bookings VALUES (2325, 4, 8, '2012-09-04 19:30:00', 2);
INSERT INTO public.bookings VALUES (2326, 5, 0, '2012-09-04 09:30:00', 2);
INSERT INTO public.bookings VALUES (2327, 5, 0, '2012-09-04 12:30:00', 2);
INSERT INTO public.bookings VALUES (2328, 6, 0, '2012-09-04 08:00:00', 4);
INSERT INTO public.bookings VALUES (2329, 6, 0, '2012-09-04 11:00:00', 2);
INSERT INTO public.bookings VALUES (2330, 6, 12, '2012-09-04 12:00:00', 2);
INSERT INTO public.bookings VALUES (2331, 6, 0, '2012-09-04 13:30:00', 2);
INSERT INTO public.bookings VALUES (2332, 6, 5, '2012-09-04 18:30:00', 2);
INSERT INTO public.bookings VALUES (2333, 7, 22, '2012-09-04 08:00:00', 2);
INSERT INTO public.bookings VALUES (2334, 7, 8, '2012-09-04 09:00:00', 2);
INSERT INTO public.bookings VALUES (2335, 7, 7, '2012-09-04 10:00:00', 2);
INSERT INTO public.bookings VALUES (2336, 7, 24, '2012-09-04 11:00:00', 2);
INSERT INTO public.bookings VALUES (2337, 7, 5, '2012-09-04 13:00:00', 2);
INSERT INTO public.bookings VALUES (2338, 7, 24, '2012-09-04 16:00:00', 2);
INSERT INTO public.bookings VALUES (2339, 7, 0, '2012-09-04 17:30:00', 2);
INSERT INTO public.bookings VALUES (2340, 7, 14, '2012-09-04 19:00:00', 2);
INSERT INTO public.bookings VALUES (2341, 8, 3, '2012-09-04 08:00:00', 1);
INSERT INTO public.bookings VALUES (2342, 8, 3, '2012-09-04 09:00:00', 1);
INSERT INTO public.bookings VALUES (2343, 8, 20, '2012-09-04 09:30:00', 1);
INSERT INTO public.bookings VALUES (2344, 8, 21, '2012-09-04 10:00:00', 3);
INSERT INTO public.bookings VALUES (2345, 8, 0, '2012-09-04 13:00:00', 1);
INSERT INTO public.bookings VALUES (2346, 8, 21, '2012-09-04 13:30:00', 1);
INSERT INTO public.bookings VALUES (2347, 8, 3, '2012-09-04 14:00:00', 1);
INSERT INTO public.bookings VALUES (2348, 8, 8, '2012-09-04 15:00:00', 2);
INSERT INTO public.bookings VALUES (2349, 8, 21, '2012-09-04 16:00:00', 1);
INSERT INTO public.bookings VALUES (2350, 8, 3, '2012-09-04 18:30:00', 1);
INSERT INTO public.bookings VALUES (2351, 8, 21, '2012-09-04 19:30:00', 1);
INSERT INTO public.bookings VALUES (2352, 8, 16, '2012-09-04 20:00:00', 1);
INSERT INTO public.bookings VALUES (2353, 0, 22, '2012-09-05 08:00:00', 3);
INSERT INTO public.bookings VALUES (2354, 0, 12, '2012-09-05 09:30:00', 3);
INSERT INTO public.bookings VALUES (2355, 0, 0, '2012-09-05 11:00:00', 3);
INSERT INTO public.bookings VALUES (2356, 0, 2, '2012-09-05 14:00:00', 3);
INSERT INTO public.bookings VALUES (2357, 0, 6, '2012-09-05 15:30:00', 3);
INSERT INTO public.bookings VALUES (2358, 0, 17, '2012-09-05 18:00:00', 3);
INSERT INTO public.bookings VALUES (2359, 1, 1, '2012-09-05 08:00:00', 3);
INSERT INTO public.bookings VALUES (2360, 1, 10, '2012-09-05 09:30:00', 3);
INSERT INTO public.bookings VALUES (2361, 1, 24, '2012-09-05 12:00:00', 3);
INSERT INTO public.bookings VALUES (2362, 1, 8, '2012-09-05 15:30:00', 3);
INSERT INTO public.bookings VALUES (2363, 1, 12, '2012-09-05 18:00:00', 3);
INSERT INTO public.bookings VALUES (2364, 2, 7, '2012-09-05 08:30:00', 3);
INSERT INTO public.bookings VALUES (2365, 2, 13, '2012-09-05 11:30:00', 3);
INSERT INTO public.bookings VALUES (2366, 2, 1, '2012-09-05 13:00:00', 3);
INSERT INTO public.bookings VALUES (2367, 2, 24, '2012-09-05 16:30:00', 3);
INSERT INTO public.bookings VALUES (2368, 2, 1, '2012-09-05 18:00:00', 3);
INSERT INTO public.bookings VALUES (2369, 3, 16, '2012-09-05 08:30:00', 2);
INSERT INTO public.bookings VALUES (2370, 3, 15, '2012-09-05 09:30:00', 2);
INSERT INTO public.bookings VALUES (2371, 3, 2, '2012-09-05 12:00:00', 2);
INSERT INTO public.bookings VALUES (2372, 3, 10, '2012-09-05 15:30:00', 2);
INSERT INTO public.bookings VALUES (2373, 3, 10, '2012-09-05 19:30:00', 2);
INSERT INTO public.bookings VALUES (2374, 4, 24, '2012-09-05 08:00:00', 2);
INSERT INTO public.bookings VALUES (2375, 4, 0, '2012-09-05 09:00:00', 4);
INSERT INTO public.bookings VALUES (2376, 4, 0, '2012-09-05 11:30:00', 2);
INSERT INTO public.bookings VALUES (2377, 4, 16, '2012-09-05 12:30:00', 2);
INSERT INTO public.bookings VALUES (2378, 4, 0, '2012-09-05 13:30:00', 6);
INSERT INTO public.bookings VALUES (2379, 4, 11, '2012-09-05 17:00:00', 2);
INSERT INTO public.bookings VALUES (2380, 4, 0, '2012-09-05 18:00:00', 2);
INSERT INTO public.bookings VALUES (2381, 4, 9, '2012-09-05 19:00:00', 2);
INSERT INTO public.bookings VALUES (2382, 5, 0, '2012-09-05 09:00:00', 2);
INSERT INTO public.bookings VALUES (2383, 5, 0, '2012-09-05 11:00:00', 2);
INSERT INTO public.bookings VALUES (2384, 5, 0, '2012-09-05 12:30:00', 2);
INSERT INTO public.bookings VALUES (2385, 6, 0, '2012-09-05 08:30:00', 4);
INSERT INTO public.bookings VALUES (2386, 6, 0, '2012-09-05 11:00:00', 2);
INSERT INTO public.bookings VALUES (2387, 6, 11, '2012-09-05 13:00:00', 2);
INSERT INTO public.bookings VALUES (2388, 6, 0, '2012-09-05 14:00:00', 2);
INSERT INTO public.bookings VALUES (2389, 6, 0, '2012-09-05 15:30:00', 6);
INSERT INTO public.bookings VALUES (2390, 7, 8, '2012-09-05 08:00:00', 2);
INSERT INTO public.bookings VALUES (2391, 7, 4, '2012-09-05 10:00:00', 2);
INSERT INTO public.bookings VALUES (2392, 7, 15, '2012-09-05 11:00:00', 2);
INSERT INTO public.bookings VALUES (2393, 7, 7, '2012-09-05 13:00:00', 2);
INSERT INTO public.bookings VALUES (2394, 7, 4, '2012-09-05 15:00:00', 2);
INSERT INTO public.bookings VALUES (2395, 7, 9, '2012-09-05 16:30:00', 2);
INSERT INTO public.bookings VALUES (2396, 7, 5, '2012-09-05 18:30:00', 2);
INSERT INTO public.bookings VALUES (2397, 8, 20, '2012-09-05 09:00:00', 1);
INSERT INTO public.bookings VALUES (2398, 8, 14, '2012-09-05 10:30:00', 1);
INSERT INTO public.bookings VALUES (2399, 8, 3, '2012-09-05 11:00:00', 2);
INSERT INTO public.bookings VALUES (2400, 8, 20, '2012-09-05 13:00:00', 1);
INSERT INTO public.bookings VALUES (2401, 8, 2, '2012-09-05 13:30:00', 1);
INSERT INTO public.bookings VALUES (2402, 8, 21, '2012-09-05 14:00:00', 1);
INSERT INTO public.bookings VALUES (2403, 8, 0, '2012-09-05 14:30:00', 1);
INSERT INTO public.bookings VALUES (2404, 8, 9, '2012-09-05 15:00:00', 1);
INSERT INTO public.bookings VALUES (2405, 8, 2, '2012-09-05 15:30:00', 1);
INSERT INTO public.bookings VALUES (2406, 8, 16, '2012-09-05 16:00:00', 1);
INSERT INTO public.bookings VALUES (2407, 8, 6, '2012-09-05 17:00:00', 1);
INSERT INTO public.bookings VALUES (2408, 8, 8, '2012-09-05 17:30:00', 1);
INSERT INTO public.bookings VALUES (2409, 8, 2, '2012-09-05 19:00:00', 1);
INSERT INTO public.bookings VALUES (2410, 8, 1, '2012-09-05 20:00:00', 1);
INSERT INTO public.bookings VALUES (2411, 0, 17, '2012-09-06 08:30:00', 3);
INSERT INTO public.bookings VALUES (2412, 0, 11, '2012-09-06 10:30:00', 3);
INSERT INTO public.bookings VALUES (2413, 0, 22, '2012-09-06 12:00:00', 3);
INSERT INTO public.bookings VALUES (2414, 0, 11, '2012-09-06 16:30:00', 3);
INSERT INTO public.bookings VALUES (2415, 0, 4, '2012-09-06 19:00:00', 3);
INSERT INTO public.bookings VALUES (2416, 1, 0, '2012-09-06 08:30:00', 3);
INSERT INTO public.bookings VALUES (2417, 1, 8, '2012-09-06 10:00:00', 3);
INSERT INTO public.bookings VALUES (2418, 1, 0, '2012-09-06 11:30:00', 3);
INSERT INTO public.bookings VALUES (2419, 1, 9, '2012-09-06 13:00:00', 3);
INSERT INTO public.bookings VALUES (2420, 1, 12, '2012-09-06 16:30:00', 6);
INSERT INTO public.bookings VALUES (2421, 2, 9, '2012-09-06 08:00:00', 3);
INSERT INTO public.bookings VALUES (2422, 2, 15, '2012-09-06 09:30:00', 3);
INSERT INTO public.bookings VALUES (2423, 2, 21, '2012-09-06 12:00:00', 3);
INSERT INTO public.bookings VALUES (2424, 2, 12, '2012-09-06 13:30:00', 3);
INSERT INTO public.bookings VALUES (2425, 2, 17, '2012-09-06 15:00:00', 3);
INSERT INTO public.bookings VALUES (2426, 2, 1, '2012-09-06 17:30:00', 3);
INSERT INTO public.bookings VALUES (2427, 2, 21, '2012-09-06 19:00:00', 3);
INSERT INTO public.bookings VALUES (2428, 3, 13, '2012-09-06 08:30:00', 2);
INSERT INTO public.bookings VALUES (2429, 3, 15, '2012-09-06 11:00:00', 2);
INSERT INTO public.bookings VALUES (2430, 3, 17, '2012-09-06 13:00:00', 2);
INSERT INTO public.bookings VALUES (2431, 3, 13, '2012-09-06 14:30:00', 2);
INSERT INTO public.bookings VALUES (2432, 3, 20, '2012-09-06 15:30:00', 2);
INSERT INTO public.bookings VALUES (2433, 3, 15, '2012-09-06 17:30:00', 2);
INSERT INTO public.bookings VALUES (2434, 4, 0, '2012-09-06 08:00:00', 2);
INSERT INTO public.bookings VALUES (2435, 4, 2, '2012-09-06 09:30:00', 2);
INSERT INTO public.bookings VALUES (2436, 4, 24, '2012-09-06 10:30:00', 2);
INSERT INTO public.bookings VALUES (2437, 4, 13, '2012-09-06 12:00:00', 2);
INSERT INTO public.bookings VALUES (2438, 4, 0, '2012-09-06 13:00:00', 2);
INSERT INTO public.bookings VALUES (2439, 4, 6, '2012-09-06 14:00:00', 2);
INSERT INTO public.bookings VALUES (2440, 4, 0, '2012-09-06 15:00:00', 4);
INSERT INTO public.bookings VALUES (2441, 4, 7, '2012-09-06 17:30:00', 2);
INSERT INTO public.bookings VALUES (2442, 4, 16, '2012-09-06 18:30:00', 2);
INSERT INTO public.bookings VALUES (2443, 4, 8, '2012-09-06 19:30:00', 2);
INSERT INTO public.bookings VALUES (2444, 5, 0, '2012-09-06 11:00:00', 2);
INSERT INTO public.bookings VALUES (2445, 6, 0, '2012-09-06 09:00:00', 4);
INSERT INTO public.bookings VALUES (2446, 6, 0, '2012-09-06 11:30:00', 2);
INSERT INTO public.bookings VALUES (2447, 6, 14, '2012-09-06 12:30:00', 2);
INSERT INTO public.bookings VALUES (2448, 6, 0, '2012-09-06 13:30:00', 2);
INSERT INTO public.bookings VALUES (2449, 6, 0, '2012-09-06 15:30:00', 2);
INSERT INTO public.bookings VALUES (2450, 6, 0, '2012-09-06 17:00:00', 2);
INSERT INTO public.bookings VALUES (2451, 6, 0, '2012-09-06 18:30:00', 2);
INSERT INTO public.bookings VALUES (2452, 6, 13, '2012-09-06 19:30:00', 2);
INSERT INTO public.bookings VALUES (2453, 7, 0, '2012-09-06 09:00:00', 2);
INSERT INTO public.bookings VALUES (2454, 7, 15, '2012-09-06 12:30:00', 2);
INSERT INTO public.bookings VALUES (2455, 7, 24, '2012-09-06 16:30:00', 2);
INSERT INTO public.bookings VALUES (2456, 7, 10, '2012-09-06 17:30:00', 2);
INSERT INTO public.bookings VALUES (2457, 7, 0, '2012-09-06 18:30:00', 2);
INSERT INTO public.bookings VALUES (2458, 8, 21, '2012-09-06 09:00:00', 1);
INSERT INTO public.bookings VALUES (2459, 8, 24, '2012-09-06 09:30:00', 1);
INSERT INTO public.bookings VALUES (2460, 8, 16, '2012-09-06 10:00:00', 1);
INSERT INTO public.bookings VALUES (2461, 8, 7, '2012-09-06 11:00:00', 1);
INSERT INTO public.bookings VALUES (2462, 8, 9, '2012-09-06 11:30:00', 1);
INSERT INTO public.bookings VALUES (2463, 8, 3, '2012-09-06 12:00:00', 1);
INSERT INTO public.bookings VALUES (2464, 8, 0, '2012-09-06 13:30:00', 1);
INSERT INTO public.bookings VALUES (2465, 8, 20, '2012-09-06 14:00:00', 1);
INSERT INTO public.bookings VALUES (2466, 8, 24, '2012-09-06 15:00:00', 1);
INSERT INTO public.bookings VALUES (2467, 8, 3, '2012-09-06 16:30:00', 1);
INSERT INTO public.bookings VALUES (2468, 8, 22, '2012-09-06 17:00:00', 1);
INSERT INTO public.bookings VALUES (2469, 8, 16, '2012-09-06 18:00:00', 1);
INSERT INTO public.bookings VALUES (2470, 8, 2, '2012-09-06 19:00:00', 1);
INSERT INTO public.bookings VALUES (2471, 8, 3, '2012-09-06 19:30:00', 2);
INSERT INTO public.bookings VALUES (2472, 0, 0, '2012-09-07 08:00:00', 3);
INSERT INTO public.bookings VALUES (2473, 0, 14, '2012-09-07 09:30:00', 6);
INSERT INTO public.bookings VALUES (2474, 0, 0, '2012-09-07 12:30:00', 3);
INSERT INTO public.bookings VALUES (2475, 0, 11, '2012-09-07 14:00:00', 3);
INSERT INTO public.bookings VALUES (2476, 0, 17, '2012-09-07 16:00:00', 3);
INSERT INTO public.bookings VALUES (2477, 0, 14, '2012-09-07 18:00:00', 3);
INSERT INTO public.bookings VALUES (2478, 1, 9, '2012-09-07 08:00:00', 3);
INSERT INTO public.bookings VALUES (2479, 1, 12, '2012-09-07 11:00:00', 3);
INSERT INTO public.bookings VALUES (2480, 1, 11, '2012-09-07 12:30:00', 3);
INSERT INTO public.bookings VALUES (2481, 1, 24, '2012-09-07 14:30:00', 3);
INSERT INTO public.bookings VALUES (2482, 1, 12, '2012-09-07 16:30:00', 3);
INSERT INTO public.bookings VALUES (2483, 1, 9, '2012-09-07 18:00:00', 3);
INSERT INTO public.bookings VALUES (2484, 2, 1, '2012-09-07 08:00:00', 3);
INSERT INTO public.bookings VALUES (2485, 2, 5, '2012-09-07 09:30:00', 3);
INSERT INTO public.bookings VALUES (2486, 2, 1, '2012-09-07 11:00:00', 3);
INSERT INTO public.bookings VALUES (2487, 2, 0, '2012-09-07 12:30:00', 3);
INSERT INTO public.bookings VALUES (2488, 2, 1, '2012-09-07 14:00:00', 6);
INSERT INTO public.bookings VALUES (2489, 2, 0, '2012-09-07 17:00:00', 3);
INSERT INTO public.bookings VALUES (2490, 2, 1, '2012-09-07 19:00:00', 3);
INSERT INTO public.bookings VALUES (2491, 3, 16, '2012-09-07 08:30:00', 2);
INSERT INTO public.bookings VALUES (2492, 3, 15, '2012-09-07 11:00:00', 2);
INSERT INTO public.bookings VALUES (2493, 3, 20, '2012-09-07 14:30:00', 2);
INSERT INTO public.bookings VALUES (2494, 3, 7, '2012-09-07 17:00:00', 2);
INSERT INTO public.bookings VALUES (2495, 3, 10, '2012-09-07 19:00:00', 2);
INSERT INTO public.bookings VALUES (2496, 4, 3, '2012-09-07 08:30:00', 4);
INSERT INTO public.bookings VALUES (2497, 4, 6, '2012-09-07 11:00:00', 2);
INSERT INTO public.bookings VALUES (2498, 4, 20, '2012-09-07 12:00:00', 2);
INSERT INTO public.bookings VALUES (2499, 4, 5, '2012-09-07 13:00:00', 2);
INSERT INTO public.bookings VALUES (2500, 4, 16, '2012-09-07 14:30:00', 2);
INSERT INTO public.bookings VALUES (2501, 4, 0, '2012-09-07 16:00:00', 2);
INSERT INTO public.bookings VALUES (2502, 4, 10, '2012-09-07 18:00:00', 2);
INSERT INTO public.bookings VALUES (2503, 4, 13, '2012-09-07 19:00:00', 2);
INSERT INTO public.bookings VALUES (2504, 5, 24, '2012-09-07 11:30:00', 2);
INSERT INTO public.bookings VALUES (2505, 5, 3, '2012-09-07 14:30:00', 2);
INSERT INTO public.bookings VALUES (2506, 6, 0, '2012-09-07 09:30:00', 8);
INSERT INTO public.bookings VALUES (2507, 6, 0, '2012-09-07 14:00:00', 2);
INSERT INTO public.bookings VALUES (2508, 6, 6, '2012-09-07 16:30:00', 2);
INSERT INTO public.bookings VALUES (2509, 7, 8, '2012-09-07 09:00:00', 2);
INSERT INTO public.bookings VALUES (2510, 7, 9, '2012-09-07 11:30:00', 2);
INSERT INTO public.bookings VALUES (2511, 7, 4, '2012-09-07 13:30:00', 2);
INSERT INTO public.bookings VALUES (2512, 7, 15, '2012-09-07 15:00:00', 2);
INSERT INTO public.bookings VALUES (2513, 7, 5, '2012-09-07 17:00:00', 2);
INSERT INTO public.bookings VALUES (2514, 7, 5, '2012-09-07 19:00:00', 2);
INSERT INTO public.bookings VALUES (2515, 8, 24, '2012-09-07 08:30:00', 1);
INSERT INTO public.bookings VALUES (2516, 8, 3, '2012-09-07 10:30:00', 1);
INSERT INTO public.bookings VALUES (2517, 8, 21, '2012-09-07 11:00:00', 1);
INSERT INTO public.bookings VALUES (2518, 8, 3, '2012-09-07 11:30:00', 1);
INSERT INTO public.bookings VALUES (2519, 8, 17, '2012-09-07 12:00:00', 1);
INSERT INTO public.bookings VALUES (2520, 8, 3, '2012-09-07 13:00:00', 1);
INSERT INTO public.bookings VALUES (2521, 8, 20, '2012-09-07 13:30:00', 1);
INSERT INTO public.bookings VALUES (2522, 8, 16, '2012-09-07 14:00:00', 1);
INSERT INTO public.bookings VALUES (2523, 8, 21, '2012-09-07 14:30:00', 2);
INSERT INTO public.bookings VALUES (2524, 8, 4, '2012-09-07 15:30:00', 1);
INSERT INTO public.bookings VALUES (2525, 8, 21, '2012-09-07 16:30:00', 1);
INSERT INTO public.bookings VALUES (2526, 8, 2, '2012-09-07 18:00:00', 1);
INSERT INTO public.bookings VALUES (2527, 8, 7, '2012-09-07 18:30:00', 1);
INSERT INTO public.bookings VALUES (2528, 8, 16, '2012-09-07 20:00:00', 1);
INSERT INTO public.bookings VALUES (2529, 0, 5, '2012-09-08 08:00:00', 3);
INSERT INTO public.bookings VALUES (2530, 0, 0, '2012-09-08 09:30:00', 3);
INSERT INTO public.bookings VALUES (2531, 0, 7, '2012-09-08 11:00:00', 3);
INSERT INTO public.bookings VALUES (2532, 0, 0, '2012-09-08 12:30:00', 3);
INSERT INTO public.bookings VALUES (2533, 0, 11, '2012-09-08 15:00:00', 3);
INSERT INTO public.bookings VALUES (2534, 0, 17, '2012-09-08 16:30:00', 3);
INSERT INTO public.bookings VALUES (2535, 0, 16, '2012-09-08 18:30:00', 3);
INSERT INTO public.bookings VALUES (2536, 1, 10, '2012-09-08 08:00:00', 3);
INSERT INTO public.bookings VALUES (2537, 1, 24, '2012-09-08 09:30:00', 3);
INSERT INTO public.bookings VALUES (2538, 1, 9, '2012-09-08 11:30:00', 3);
INSERT INTO public.bookings VALUES (2539, 1, 0, '2012-09-08 13:00:00', 3);
INSERT INTO public.bookings VALUES (2540, 1, 9, '2012-09-08 15:00:00', 6);
INSERT INTO public.bookings VALUES (2541, 2, 8, '2012-09-08 08:30:00', 3);
INSERT INTO public.bookings VALUES (2542, 2, 21, '2012-09-08 10:00:00', 3);
INSERT INTO public.bookings VALUES (2543, 2, 26, '2012-09-08 13:00:00', 3);
INSERT INTO public.bookings VALUES (2544, 2, 1, '2012-09-08 15:00:00', 3);
INSERT INTO public.bookings VALUES (2545, 2, 21, '2012-09-08 16:30:00', 3);
INSERT INTO public.bookings VALUES (2546, 2, 1, '2012-09-08 18:30:00', 3);
INSERT INTO public.bookings VALUES (2547, 3, 6, '2012-09-08 08:00:00', 2);
INSERT INTO public.bookings VALUES (2548, 3, 2, '2012-09-08 09:00:00', 2);
INSERT INTO public.bookings VALUES (2549, 3, 15, '2012-09-08 10:00:00', 2);
INSERT INTO public.bookings VALUES (2550, 3, 11, '2012-09-08 12:00:00', 2);
INSERT INTO public.bookings VALUES (2551, 3, 20, '2012-09-08 13:00:00', 2);
INSERT INTO public.bookings VALUES (2552, 3, 20, '2012-09-08 16:00:00', 2);
INSERT INTO public.bookings VALUES (2553, 3, 1, '2012-09-08 17:30:00', 2);
INSERT INTO public.bookings VALUES (2554, 3, 9, '2012-09-08 18:30:00', 2);
INSERT INTO public.bookings VALUES (2555, 3, 15, '2012-09-08 19:30:00', 2);
INSERT INTO public.bookings VALUES (2556, 4, 20, '2012-09-08 08:00:00', 2);
INSERT INTO public.bookings VALUES (2557, 4, 0, '2012-09-08 09:30:00', 8);
INSERT INTO public.bookings VALUES (2558, 4, 3, '2012-09-08 13:30:00', 2);
INSERT INTO public.bookings VALUES (2559, 4, 0, '2012-09-08 14:30:00', 4);
INSERT INTO public.bookings VALUES (2560, 4, 13, '2012-09-08 16:30:00', 2);
INSERT INTO public.bookings VALUES (2561, 4, 13, '2012-09-08 18:00:00', 2);
INSERT INTO public.bookings VALUES (2562, 4, 0, '2012-09-08 19:00:00', 2);
INSERT INTO public.bookings VALUES (2563, 5, 24, '2012-09-08 15:30:00', 2);
INSERT INTO public.bookings VALUES (2564, 6, 0, '2012-09-08 09:00:00', 2);
INSERT INTO public.bookings VALUES (2565, 6, 6, '2012-09-08 13:30:00', 2);
INSERT INTO public.bookings VALUES (2566, 6, 0, '2012-09-08 16:00:00', 2);
INSERT INTO public.bookings VALUES (2567, 6, 4, '2012-09-08 17:00:00', 2);
INSERT INTO public.bookings VALUES (2568, 6, 0, '2012-09-08 18:00:00', 4);
INSERT INTO public.bookings VALUES (2569, 7, 6, '2012-09-08 09:30:00', 2);
INSERT INTO public.bookings VALUES (2570, 7, 4, '2012-09-08 11:30:00', 2);
INSERT INTO public.bookings VALUES (2571, 7, 13, '2012-09-08 12:30:00', 2);
INSERT INTO public.bookings VALUES (2572, 7, 0, '2012-09-08 13:30:00', 2);
INSERT INTO public.bookings VALUES (2573, 7, 15, '2012-09-08 14:30:00', 2);
INSERT INTO public.bookings VALUES (2574, 7, 8, '2012-09-08 15:30:00', 2);
INSERT INTO public.bookings VALUES (2575, 7, 1, '2012-09-08 16:30:00', 2);
INSERT INTO public.bookings VALUES (2576, 7, 15, '2012-09-08 18:00:00', 2);
INSERT INTO public.bookings VALUES (2577, 8, 21, '2012-09-08 08:00:00', 1);
INSERT INTO public.bookings VALUES (2578, 8, 3, '2012-09-08 08:30:00', 1);
INSERT INTO public.bookings VALUES (2579, 8, 22, '2012-09-08 09:00:00', 1);
INSERT INTO public.bookings VALUES (2580, 8, 0, '2012-09-08 09:30:00', 1);
INSERT INTO public.bookings VALUES (2581, 8, 16, '2012-09-08 10:00:00', 1);
INSERT INTO public.bookings VALUES (2582, 8, 3, '2012-09-08 10:30:00', 2);
INSERT INTO public.bookings VALUES (2583, 8, 0, '2012-09-08 11:30:00', 1);
INSERT INTO public.bookings VALUES (2584, 8, 6, '2012-09-08 13:00:00', 1);
INSERT INTO public.bookings VALUES (2585, 8, 22, '2012-09-08 15:30:00', 1);
INSERT INTO public.bookings VALUES (2586, 8, 16, '2012-09-08 16:30:00', 1);
INSERT INTO public.bookings VALUES (2587, 8, 7, '2012-09-08 17:00:00', 1);
INSERT INTO public.bookings VALUES (2588, 8, 3, '2012-09-08 17:30:00', 1);
INSERT INTO public.bookings VALUES (2589, 8, 8, '2012-09-08 19:30:00', 1);
INSERT INTO public.bookings VALUES (2590, 0, 5, '2012-09-09 08:00:00', 3);
INSERT INTO public.bookings VALUES (2591, 0, 16, '2012-09-09 09:30:00', 3);
INSERT INTO public.bookings VALUES (2592, 0, 26, '2012-09-09 12:00:00', 3);
INSERT INTO public.bookings VALUES (2593, 0, 7, '2012-09-09 15:00:00', 3);
INSERT INTO public.bookings VALUES (2594, 0, 0, '2012-09-09 17:00:00', 3);
INSERT INTO public.bookings VALUES (2595, 0, 24, '2012-09-09 18:30:00', 3);
INSERT INTO public.bookings VALUES (2596, 1, 8, '2012-09-09 08:00:00', 3);
INSERT INTO public.bookings VALUES (2597, 1, 0, '2012-09-09 10:00:00', 3);
INSERT INTO public.bookings VALUES (2598, 1, 16, '2012-09-09 13:00:00', 3);
INSERT INTO public.bookings VALUES (2599, 1, 10, '2012-09-09 14:30:00', 3);
INSERT INTO public.bookings VALUES (2600, 1, 15, '2012-09-09 16:00:00', 3);
INSERT INTO public.bookings VALUES (2601, 1, 0, '2012-09-09 17:30:00', 6);
INSERT INTO public.bookings VALUES (2602, 2, 21, '2012-09-09 08:30:00', 3);
INSERT INTO public.bookings VALUES (2603, 2, 1, '2012-09-09 11:00:00', 3);
INSERT INTO public.bookings VALUES (2604, 2, 1, '2012-09-09 13:00:00', 6);
INSERT INTO public.bookings VALUES (2605, 2, 5, '2012-09-09 16:30:00', 3);
INSERT INTO public.bookings VALUES (2606, 2, 14, '2012-09-09 18:30:00', 3);
INSERT INTO public.bookings VALUES (2607, 3, 22, '2012-09-09 09:00:00', 2);
INSERT INTO public.bookings VALUES (2608, 3, 10, '2012-09-09 10:00:00', 2);
INSERT INTO public.bookings VALUES (2609, 3, 20, '2012-09-09 13:00:00', 2);
INSERT INTO public.bookings VALUES (2610, 3, 0, '2012-09-09 15:30:00', 2);
INSERT INTO public.bookings VALUES (2611, 3, 21, '2012-09-09 16:30:00', 2);
INSERT INTO public.bookings VALUES (2612, 3, 0, '2012-09-09 18:00:00', 2);
INSERT INTO public.bookings VALUES (2613, 3, 6, '2012-09-09 19:00:00', 2);
INSERT INTO public.bookings VALUES (2614, 4, 13, '2012-09-09 08:00:00', 2);
INSERT INTO public.bookings VALUES (2615, 4, 7, '2012-09-09 09:00:00', 2);
INSERT INTO public.bookings VALUES (2616, 4, 20, '2012-09-09 10:00:00', 2);
INSERT INTO public.bookings VALUES (2617, 4, 0, '2012-09-09 11:00:00', 4);
INSERT INTO public.bookings VALUES (2618, 4, 3, '2012-09-09 13:30:00', 2);
INSERT INTO public.bookings VALUES (2619, 4, 11, '2012-09-09 14:30:00', 2);
INSERT INTO public.bookings VALUES (2620, 4, 20, '2012-09-09 15:30:00', 2);
INSERT INTO public.bookings VALUES (2621, 4, 0, '2012-09-09 17:00:00', 2);
INSERT INTO public.bookings VALUES (2622, 4, 11, '2012-09-09 18:00:00', 2);
INSERT INTO public.bookings VALUES (2623, 4, 13, '2012-09-09 19:00:00', 2);
INSERT INTO public.bookings VALUES (2624, 5, 0, '2012-09-09 14:00:00', 2);
INSERT INTO public.bookings VALUES (2625, 6, 0, '2012-09-09 08:30:00', 2);
INSERT INTO public.bookings VALUES (2626, 6, 0, '2012-09-09 11:00:00', 6);
INSERT INTO public.bookings VALUES (2627, 6, 12, '2012-09-09 14:00:00', 2);
INSERT INTO public.bookings VALUES (2628, 6, 14, '2012-09-09 15:30:00', 2);
INSERT INTO public.bookings VALUES (2629, 6, 0, '2012-09-09 16:30:00', 4);
INSERT INTO public.bookings VALUES (2630, 6, 26, '2012-09-09 18:30:00', 2);
INSERT INTO public.bookings VALUES (2631, 6, 21, '2012-09-09 19:30:00', 2);
INSERT INTO public.bookings VALUES (2632, 7, 22, '2012-09-09 08:00:00', 2);
INSERT INTO public.bookings VALUES (2633, 7, 22, '2012-09-09 10:30:00', 2);
INSERT INTO public.bookings VALUES (2634, 7, 21, '2012-09-09 14:00:00', 2);
INSERT INTO public.bookings VALUES (2635, 7, 4, '2012-09-09 17:00:00', 2);
INSERT INTO public.bookings VALUES (2636, 7, 7, '2012-09-09 18:00:00', 2);
INSERT INTO public.bookings VALUES (2637, 7, 4, '2012-09-09 19:30:00', 2);
INSERT INTO public.bookings VALUES (2638, 8, 16, '2012-09-09 08:00:00', 1);
INSERT INTO public.bookings VALUES (2639, 8, 0, '2012-09-09 08:30:00', 1);
INSERT INTO public.bookings VALUES (2640, 8, 16, '2012-09-09 09:00:00', 1);
INSERT INTO public.bookings VALUES (2641, 8, 3, '2012-09-09 09:30:00', 1);
INSERT INTO public.bookings VALUES (2642, 8, 2, '2012-09-09 10:00:00', 1);
INSERT INTO public.bookings VALUES (2643, 8, 21, '2012-09-09 10:30:00', 1);
INSERT INTO public.bookings VALUES (2644, 8, 5, '2012-09-09 11:00:00', 1);
INSERT INTO public.bookings VALUES (2645, 8, 15, '2012-09-09 11:30:00', 1);
INSERT INTO public.bookings VALUES (2646, 8, 3, '2012-09-09 12:00:00', 2);
INSERT INTO public.bookings VALUES (2647, 8, 0, '2012-09-09 13:00:00', 1);
INSERT INTO public.bookings VALUES (2648, 8, 0, '2012-09-09 14:30:00', 1);
INSERT INTO public.bookings VALUES (2649, 8, 16, '2012-09-09 16:30:00', 1);
INSERT INTO public.bookings VALUES (2650, 8, 9, '2012-09-09 17:00:00', 1);
INSERT INTO public.bookings VALUES (2651, 8, 17, '2012-09-09 17:30:00', 1);
INSERT INTO public.bookings VALUES (2652, 8, 6, '2012-09-09 18:00:00', 1);
INSERT INTO public.bookings VALUES (2653, 8, 3, '2012-09-09 18:30:00', 1);
INSERT INTO public.bookings VALUES (2654, 8, 16, '2012-09-09 19:00:00', 1);
INSERT INTO public.bookings VALUES (2655, 8, 3, '2012-09-09 19:30:00', 1);
INSERT INTO public.bookings VALUES (2656, 8, 16, '2012-09-09 20:00:00', 1);
INSERT INTO public.bookings VALUES (2657, 0, 22, '2012-09-10 10:30:00', 3);
INSERT INTO public.bookings VALUES (2658, 0, 14, '2012-09-10 12:00:00', 3);
INSERT INTO public.bookings VALUES (2659, 0, 0, '2012-09-10 13:30:00', 3);
INSERT INTO public.bookings VALUES (2660, 0, 14, '2012-09-10 15:30:00', 3);
INSERT INTO public.bookings VALUES (2661, 0, 10, '2012-09-10 18:30:00', 3);
INSERT INTO public.bookings VALUES (2662, 1, 24, '2012-09-10 08:00:00', 3);
INSERT INTO public.bookings VALUES (2663, 1, 0, '2012-09-10 09:30:00', 3);
INSERT INTO public.bookings VALUES (2664, 1, 0, '2012-09-10 13:00:00', 3);
INSERT INTO public.bookings VALUES (2665, 1, 15, '2012-09-10 14:30:00', 3);
INSERT INTO public.bookings VALUES (2666, 1, 0, '2012-09-10 16:00:00', 3);
INSERT INTO public.bookings VALUES (2667, 1, 12, '2012-09-10 17:30:00', 3);
INSERT INTO public.bookings VALUES (2668, 1, 0, '2012-09-10 19:00:00', 3);
INSERT INTO public.bookings VALUES (2669, 2, 1, '2012-09-10 09:00:00', 6);
INSERT INTO public.bookings VALUES (2670, 2, 21, '2012-09-10 12:00:00', 3);
INSERT INTO public.bookings VALUES (2671, 2, 21, '2012-09-10 14:00:00', 3);
INSERT INTO public.bookings VALUES (2672, 2, 0, '2012-09-10 15:30:00', 3);
INSERT INTO public.bookings VALUES (2673, 2, 6, '2012-09-10 19:00:00', 3);
INSERT INTO public.bookings VALUES (2674, 3, 6, '2012-09-10 08:30:00', 2);
INSERT INTO public.bookings VALUES (2675, 3, 15, '2012-09-10 09:30:00', 2);
INSERT INTO public.bookings VALUES (2676, 3, 15, '2012-09-10 11:00:00', 2);
INSERT INTO public.bookings VALUES (2677, 3, 15, '2012-09-10 13:00:00', 2);
INSERT INTO public.bookings VALUES (2678, 3, 16, '2012-09-10 15:00:00', 2);
INSERT INTO public.bookings VALUES (2679, 3, 2, '2012-09-10 16:30:00', 2);
INSERT INTO public.bookings VALUES (2680, 3, 16, '2012-09-10 17:30:00', 2);
INSERT INTO public.bookings VALUES (2681, 3, 17, '2012-09-10 18:30:00', 2);
INSERT INTO public.bookings VALUES (2682, 3, 15, '2012-09-10 19:30:00', 2);
INSERT INTO public.bookings VALUES (2683, 4, 4, '2012-09-10 08:00:00', 2);
INSERT INTO public.bookings VALUES (2684, 4, 13, '2012-09-10 09:00:00', 4);
INSERT INTO public.bookings VALUES (2685, 4, 20, '2012-09-10 11:30:00', 2);
INSERT INTO public.bookings VALUES (2686, 4, 11, '2012-09-10 12:30:00', 2);
INSERT INTO public.bookings VALUES (2687, 4, 1, '2012-09-10 13:30:00', 2);
INSERT INTO public.bookings VALUES (2688, 4, 10, '2012-09-10 14:30:00', 2);
INSERT INTO public.bookings VALUES (2689, 4, 12, '2012-09-10 15:30:00', 2);
INSERT INTO public.bookings VALUES (2690, 4, 17, '2012-09-10 17:00:00', 2);
INSERT INTO public.bookings VALUES (2691, 4, 14, '2012-09-10 18:00:00', 2);
INSERT INTO public.bookings VALUES (2692, 4, 0, '2012-09-10 19:00:00', 2);
INSERT INTO public.bookings VALUES (2693, 5, 0, '2012-09-10 10:00:00', 2);
INSERT INTO public.bookings VALUES (2694, 5, 0, '2012-09-10 11:30:00', 2);
INSERT INTO public.bookings VALUES (2695, 6, 0, '2012-09-10 08:30:00', 2);
INSERT INTO public.bookings VALUES (2696, 6, 11, '2012-09-10 09:30:00', 2);
INSERT INTO public.bookings VALUES (2697, 6, 8, '2012-09-10 11:00:00', 2);
INSERT INTO public.bookings VALUES (2698, 6, 12, '2012-09-10 12:30:00', 2);
INSERT INTO public.bookings VALUES (2699, 6, 0, '2012-09-10 14:00:00', 6);
INSERT INTO public.bookings VALUES (2700, 6, 0, '2012-09-10 17:30:00', 2);
INSERT INTO public.bookings VALUES (2701, 6, 12, '2012-09-10 19:00:00', 2);
INSERT INTO public.bookings VALUES (2702, 7, 22, '2012-09-10 09:30:00', 2);
INSERT INTO public.bookings VALUES (2703, 7, 4, '2012-09-10 11:30:00', 2);
INSERT INTO public.bookings VALUES (2704, 7, 24, '2012-09-10 15:00:00', 2);
INSERT INTO public.bookings VALUES (2705, 7, 10, '2012-09-10 16:00:00', 2);
INSERT INTO public.bookings VALUES (2706, 7, 15, '2012-09-10 17:30:00', 2);
INSERT INTO public.bookings VALUES (2707, 7, 4, '2012-09-10 18:30:00', 2);
INSERT INTO public.bookings VALUES (2708, 7, 7, '2012-09-10 19:30:00', 2);
INSERT INTO public.bookings VALUES (2709, 8, 15, '2012-09-10 08:30:00', 1);
INSERT INTO public.bookings VALUES (2710, 8, 26, '2012-09-10 10:30:00', 1);
INSERT INTO public.bookings VALUES (2711, 8, 5, '2012-09-10 12:00:00', 1);
INSERT INTO public.bookings VALUES (2712, 8, 16, '2012-09-10 12:30:00', 1);
INSERT INTO public.bookings VALUES (2713, 8, 2, '2012-09-10 13:00:00', 1);
INSERT INTO public.bookings VALUES (2714, 8, 16, '2012-09-10 13:30:00', 1);
INSERT INTO public.bookings VALUES (2715, 8, 3, '2012-09-10 15:00:00', 1);
INSERT INTO public.bookings VALUES (2716, 8, 21, '2012-09-10 15:30:00', 1);
INSERT INTO public.bookings VALUES (2717, 8, 24, '2012-09-10 16:00:00', 1);
INSERT INTO public.bookings VALUES (2718, 8, 16, '2012-09-10 16:30:00', 1);
INSERT INTO public.bookings VALUES (2719, 8, 21, '2012-09-10 17:30:00', 1);
INSERT INTO public.bookings VALUES (2720, 8, 3, '2012-09-10 19:30:00', 1);
INSERT INTO public.bookings VALUES (2721, 8, 21, '2012-09-10 20:00:00', 1);
INSERT INTO public.bookings VALUES (2722, 0, 5, '2012-09-11 09:00:00', 3);
INSERT INTO public.bookings VALUES (2723, 0, 6, '2012-09-11 10:30:00', 3);
INSERT INTO public.bookings VALUES (2724, 0, 7, '2012-09-11 12:00:00', 3);
INSERT INTO public.bookings VALUES (2725, 0, 17, '2012-09-11 14:30:00', 3);
INSERT INTO public.bookings VALUES (2726, 0, 11, '2012-09-11 16:00:00', 3);
INSERT INTO public.bookings VALUES (2727, 0, 26, '2012-09-11 19:00:00', 3);
INSERT INTO public.bookings VALUES (2728, 1, 9, '2012-09-11 08:00:00', 3);
INSERT INTO public.bookings VALUES (2729, 1, 11, '2012-09-11 09:30:00', 3);
INSERT INTO public.bookings VALUES (2730, 1, 8, '2012-09-11 11:00:00', 3);
INSERT INTO public.bookings VALUES (2731, 1, 12, '2012-09-11 12:30:00', 3);
INSERT INTO public.bookings VALUES (2732, 1, 11, '2012-09-11 14:30:00', 3);
INSERT INTO public.bookings VALUES (2733, 1, 9, '2012-09-11 16:00:00', 3);
INSERT INTO public.bookings VALUES (2734, 1, 11, '2012-09-11 17:30:00', 6);
INSERT INTO public.bookings VALUES (2735, 2, 2, '2012-09-11 11:00:00', 3);
INSERT INTO public.bookings VALUES (2736, 2, 1, '2012-09-11 12:30:00', 3);
INSERT INTO public.bookings VALUES (2737, 2, 8, '2012-09-11 14:00:00', 3);
INSERT INTO public.bookings VALUES (2738, 2, 21, '2012-09-11 17:00:00', 6);
INSERT INTO public.bookings VALUES (2739, 3, 22, '2012-09-11 08:00:00', 2);
INSERT INTO public.bookings VALUES (2740, 3, 16, '2012-09-11 09:30:00', 2);
INSERT INTO public.bookings VALUES (2741, 3, 21, '2012-09-11 11:00:00', 2);
INSERT INTO public.bookings VALUES (2742, 3, 6, '2012-09-11 12:00:00', 2);
INSERT INTO public.bookings VALUES (2743, 3, 15, '2012-09-11 13:30:00', 2);
INSERT INTO public.bookings VALUES (2744, 3, 2, '2012-09-11 18:00:00', 2);
INSERT INTO public.bookings VALUES (2745, 3, 6, '2012-09-11 19:30:00', 2);
INSERT INTO public.bookings VALUES (2746, 4, 3, '2012-09-11 08:00:00', 2);
INSERT INTO public.bookings VALUES (2747, 4, 6, '2012-09-11 09:00:00', 2);
INSERT INTO public.bookings VALUES (2748, 4, 0, '2012-09-11 10:00:00', 4);
INSERT INTO public.bookings VALUES (2749, 4, 13, '2012-09-11 12:30:00', 2);
INSERT INTO public.bookings VALUES (2750, 4, 16, '2012-09-11 13:30:00', 2);
INSERT INTO public.bookings VALUES (2751, 4, 3, '2012-09-11 14:30:00', 2);
INSERT INTO public.bookings VALUES (2752, 4, 0, '2012-09-11 15:30:00', 2);
INSERT INTO public.bookings VALUES (2753, 4, 8, '2012-09-11 16:30:00', 2);
INSERT INTO public.bookings VALUES (2754, 4, 0, '2012-09-11 18:00:00', 2);
INSERT INTO public.bookings VALUES (2755, 4, 14, '2012-09-11 19:00:00', 2);
INSERT INTO public.bookings VALUES (2756, 5, 0, '2012-09-11 11:30:00', 2);
INSERT INTO public.bookings VALUES (2757, 5, 0, '2012-09-11 18:00:00', 2);
INSERT INTO public.bookings VALUES (2758, 6, 12, '2012-09-11 08:00:00', 2);
INSERT INTO public.bookings VALUES (2759, 6, 0, '2012-09-11 09:00:00', 2);
INSERT INTO public.bookings VALUES (2760, 6, 12, '2012-09-11 10:30:00', 4);
INSERT INTO public.bookings VALUES (2761, 6, 0, '2012-09-11 12:30:00', 4);
INSERT INTO public.bookings VALUES (2762, 6, 16, '2012-09-11 14:30:00', 2);
INSERT INTO public.bookings VALUES (2763, 6, 0, '2012-09-11 15:30:00', 4);
INSERT INTO public.bookings VALUES (2764, 6, 12, '2012-09-11 17:30:00', 2);
INSERT INTO public.bookings VALUES (2765, 6, 0, '2012-09-11 18:30:00', 2);
INSERT INTO public.bookings VALUES (2766, 6, 12, '2012-09-11 19:30:00', 2);
INSERT INTO public.bookings VALUES (2767, 7, 10, '2012-09-11 08:30:00', 2);
INSERT INTO public.bookings VALUES (2768, 7, 13, '2012-09-11 09:30:00', 2);
INSERT INTO public.bookings VALUES (2769, 7, 7, '2012-09-11 11:00:00', 2);
INSERT INTO public.bookings VALUES (2770, 7, 6, '2012-09-11 13:30:00', 2);
INSERT INTO public.bookings VALUES (2771, 7, 4, '2012-09-11 14:30:00', 2);
INSERT INTO public.bookings VALUES (2772, 7, 24, '2012-09-11 16:30:00', 2);
INSERT INTO public.bookings VALUES (2773, 7, 10, '2012-09-11 18:00:00', 2);
INSERT INTO public.bookings VALUES (2774, 7, 15, '2012-09-11 19:00:00', 2);
INSERT INTO public.bookings VALUES (2775, 8, 24, '2012-09-11 08:30:00', 1);
INSERT INTO public.bookings VALUES (2776, 8, 3, '2012-09-11 09:00:00', 1);
INSERT INTO public.bookings VALUES (2777, 8, 21, '2012-09-11 09:30:00', 1);
INSERT INTO public.bookings VALUES (2778, 8, 0, '2012-09-11 10:30:00', 1);
INSERT INTO public.bookings VALUES (2779, 8, 16, '2012-09-11 11:00:00', 1);
INSERT INTO public.bookings VALUES (2780, 8, 3, '2012-09-11 12:00:00', 2);
INSERT INTO public.bookings VALUES (2781, 8, 21, '2012-09-11 13:00:00', 1);
INSERT INTO public.bookings VALUES (2782, 8, 21, '2012-09-11 14:00:00', 2);
INSERT INTO public.bookings VALUES (2783, 8, 22, '2012-09-11 15:00:00', 1);
INSERT INTO public.bookings VALUES (2784, 8, 8, '2012-09-11 15:30:00', 1);
INSERT INTO public.bookings VALUES (2785, 8, 3, '2012-09-11 17:00:00', 2);
INSERT INTO public.bookings VALUES (2786, 8, 3, '2012-09-11 18:30:00', 2);
INSERT INTO public.bookings VALUES (2787, 0, 22, '2012-09-12 08:30:00', 3);
INSERT INTO public.bookings VALUES (2788, 0, 0, '2012-09-12 10:00:00', 3);
INSERT INTO public.bookings VALUES (2789, 0, 4, '2012-09-12 11:30:00', 3);
INSERT INTO public.bookings VALUES (2790, 0, 26, '2012-09-12 13:00:00', 3);
INSERT INTO public.bookings VALUES (2791, 0, 5, '2012-09-12 15:00:00', 3);
INSERT INTO public.bookings VALUES (2792, 0, 0, '2012-09-12 16:30:00', 3);
INSERT INTO public.bookings VALUES (2793, 0, 16, '2012-09-12 18:00:00', 3);
INSERT INTO public.bookings VALUES (2794, 1, 11, '2012-09-12 08:30:00', 3);
INSERT INTO public.bookings VALUES (2795, 1, 0, '2012-09-12 10:00:00', 3);
INSERT INTO public.bookings VALUES (2796, 1, 14, '2012-09-12 12:00:00', 3);
INSERT INTO public.bookings VALUES (2797, 1, 11, '2012-09-12 13:30:00', 3);
INSERT INTO public.bookings VALUES (2798, 1, 0, '2012-09-12 15:00:00', 6);
INSERT INTO public.bookings VALUES (2799, 1, 10, '2012-09-12 18:30:00', 3);
INSERT INTO public.bookings VALUES (2800, 2, 24, '2012-09-12 08:00:00', 3);
INSERT INTO public.bookings VALUES (2801, 2, 12, '2012-09-12 09:30:00', 3);
INSERT INTO public.bookings VALUES (2802, 2, 9, '2012-09-12 11:00:00', 3);
INSERT INTO public.bookings VALUES (2803, 2, 13, '2012-09-12 14:30:00', 3);
INSERT INTO public.bookings VALUES (2804, 2, 9, '2012-09-12 16:00:00', 3);
INSERT INTO public.bookings VALUES (2805, 2, 2, '2012-09-12 17:30:00', 6);
INSERT INTO public.bookings VALUES (2806, 3, 15, '2012-09-12 09:00:00', 2);
INSERT INTO public.bookings VALUES (2807, 3, 20, '2012-09-12 12:30:00', 2);
INSERT INTO public.bookings VALUES (2808, 3, 10, '2012-09-12 13:30:00', 2);
INSERT INTO public.bookings VALUES (2809, 3, 3, '2012-09-12 14:30:00', 2);
INSERT INTO public.bookings VALUES (2810, 3, 16, '2012-09-12 15:30:00', 2);
INSERT INTO public.bookings VALUES (2811, 3, 0, '2012-09-12 19:00:00', 2);
INSERT INTO public.bookings VALUES (2812, 4, 16, '2012-09-12 08:00:00', 2);
INSERT INTO public.bookings VALUES (2813, 4, 0, '2012-09-12 09:00:00', 2);
INSERT INTO public.bookings VALUES (2814, 4, 0, '2012-09-12 10:30:00', 2);
INSERT INTO public.bookings VALUES (2815, 4, 13, '2012-09-12 11:30:00', 2);
INSERT INTO public.bookings VALUES (2816, 4, 0, '2012-09-12 12:30:00', 4);
INSERT INTO public.bookings VALUES (2817, 4, 16, '2012-09-12 14:30:00', 2);
INSERT INTO public.bookings VALUES (2818, 4, 0, '2012-09-12 15:30:00', 2);
INSERT INTO public.bookings VALUES (2819, 4, 3, '2012-09-12 16:30:00', 2);
INSERT INTO public.bookings VALUES (2820, 4, 1, '2012-09-12 17:30:00', 2);
INSERT INTO public.bookings VALUES (2821, 4, 7, '2012-09-12 19:00:00', 2);
INSERT INTO public.bookings VALUES (2822, 5, 0, '2012-09-12 16:30:00', 2);
INSERT INTO public.bookings VALUES (2823, 6, 0, '2012-09-12 08:30:00', 4);
INSERT INTO public.bookings VALUES (2824, 6, 0, '2012-09-12 11:00:00', 6);
INSERT INTO public.bookings VALUES (2825, 6, 24, '2012-09-12 14:00:00', 2);
INSERT INTO public.bookings VALUES (2826, 6, 0, '2012-09-12 15:00:00', 4);
INSERT INTO public.bookings VALUES (2827, 6, 0, '2012-09-12 17:30:00', 4);
INSERT INTO public.bookings VALUES (2828, 7, 5, '2012-09-12 08:30:00', 2);
INSERT INTO public.bookings VALUES (2829, 7, 4, '2012-09-12 09:30:00', 2);
INSERT INTO public.bookings VALUES (2830, 7, 15, '2012-09-12 10:30:00', 2);
INSERT INTO public.bookings VALUES (2831, 7, 24, '2012-09-12 13:00:00', 2);
INSERT INTO public.bookings VALUES (2832, 7, 7, '2012-09-12 15:30:00', 2);
INSERT INTO public.bookings VALUES (2833, 7, 22, '2012-09-12 17:30:00', 2);
INSERT INTO public.bookings VALUES (2834, 8, 1, '2012-09-12 10:00:00', 1);
INSERT INTO public.bookings VALUES (2835, 8, 16, '2012-09-12 11:00:00', 1);
INSERT INTO public.bookings VALUES (2836, 8, 3, '2012-09-12 11:30:00', 1);
INSERT INTO public.bookings VALUES (2837, 8, 16, '2012-09-12 12:00:00', 1);
INSERT INTO public.bookings VALUES (2838, 8, 21, '2012-09-12 12:30:00', 2);
INSERT INTO public.bookings VALUES (2839, 8, 1, '2012-09-12 13:30:00', 1);
INSERT INTO public.bookings VALUES (2840, 8, 5, '2012-09-12 14:00:00', 1);
INSERT INTO public.bookings VALUES (2841, 8, 2, '2012-09-12 14:30:00', 1);
INSERT INTO public.bookings VALUES (2842, 8, 22, '2012-09-12 15:30:00', 1);
INSERT INTO public.bookings VALUES (2843, 8, 3, '2012-09-12 16:00:00', 1);
INSERT INTO public.bookings VALUES (2844, 8, 4, '2012-09-12 18:00:00', 1);
INSERT INTO public.bookings VALUES (2845, 8, 21, '2012-09-12 18:30:00', 2);
INSERT INTO public.bookings VALUES (2846, 0, 5, '2012-09-13 09:00:00', 3);
INSERT INTO public.bookings VALUES (2847, 0, 0, '2012-09-13 10:30:00', 6);
INSERT INTO public.bookings VALUES (2848, 0, 7, '2012-09-13 13:30:00', 3);
INSERT INTO public.bookings VALUES (2849, 0, 10, '2012-09-13 16:00:00', 3);
INSERT INTO public.bookings VALUES (2850, 0, 0, '2012-09-13 17:30:00', 6);
INSERT INTO public.bookings VALUES (2851, 1, 8, '2012-09-13 08:30:00', 3);
INSERT INTO public.bookings VALUES (2852, 1, 11, '2012-09-13 10:30:00', 3);
INSERT INTO public.bookings VALUES (2853, 1, 0, '2012-09-13 12:00:00', 6);
INSERT INTO public.bookings VALUES (2854, 1, 12, '2012-09-13 15:00:00', 3);
INSERT INTO public.bookings VALUES (2855, 1, 8, '2012-09-13 16:30:00', 3);
INSERT INTO public.bookings VALUES (2856, 1, 24, '2012-09-13 18:30:00', 3);
INSERT INTO public.bookings VALUES (2857, 2, 11, '2012-09-13 08:00:00', 3);
INSERT INTO public.bookings VALUES (2858, 2, 1, '2012-09-13 09:30:00', 3);
INSERT INTO public.bookings VALUES (2859, 2, 2, '2012-09-13 11:00:00', 3);
INSERT INTO public.bookings VALUES (2860, 2, 10, '2012-09-13 13:00:00', 3);
INSERT INTO public.bookings VALUES (2861, 2, 15, '2012-09-13 14:30:00', 3);
INSERT INTO public.bookings VALUES (2862, 2, 21, '2012-09-13 16:30:00', 3);
INSERT INTO public.bookings VALUES (2863, 2, 11, '2012-09-13 18:00:00', 3);
INSERT INTO public.bookings VALUES (2864, 3, 16, '2012-09-13 08:00:00', 2);
INSERT INTO public.bookings VALUES (2865, 3, 3, '2012-09-13 09:00:00', 2);
INSERT INTO public.bookings VALUES (2866, 3, 17, '2012-09-13 10:00:00', 2);
INSERT INTO public.bookings VALUES (2867, 3, 22, '2012-09-13 11:30:00', 2);
INSERT INTO public.bookings VALUES (2868, 3, 24, '2012-09-13 13:00:00', 2);
INSERT INTO public.bookings VALUES (2869, 3, 3, '2012-09-13 14:00:00', 2);
INSERT INTO public.bookings VALUES (2870, 3, 11, '2012-09-13 16:00:00', 2);
INSERT INTO public.bookings VALUES (2871, 3, 3, '2012-09-13 17:30:00', 2);
INSERT INTO public.bookings VALUES (2872, 3, 17, '2012-09-13 18:30:00', 2);
INSERT INTO public.bookings VALUES (2873, 3, 4, '2012-09-13 19:30:00', 2);
INSERT INTO public.bookings VALUES (2874, 4, 7, '2012-09-13 08:00:00', 2);
INSERT INTO public.bookings VALUES (2875, 4, 20, '2012-09-13 09:00:00', 2);
INSERT INTO public.bookings VALUES (2876, 4, 6, '2012-09-13 10:30:00', 2);
INSERT INTO public.bookings VALUES (2877, 4, 5, '2012-09-13 11:30:00', 2);
INSERT INTO public.bookings VALUES (2878, 4, 21, '2012-09-13 12:30:00', 2);
INSERT INTO public.bookings VALUES (2879, 4, 20, '2012-09-13 14:00:00', 2);
INSERT INTO public.bookings VALUES (2880, 4, 9, '2012-09-13 15:30:00', 2);
INSERT INTO public.bookings VALUES (2881, 4, 20, '2012-09-13 17:00:00', 2);
INSERT INTO public.bookings VALUES (2882, 4, 0, '2012-09-13 18:00:00', 2);
INSERT INTO public.bookings VALUES (2883, 4, 5, '2012-09-13 19:00:00', 2);
INSERT INTO public.bookings VALUES (2884, 5, 0, '2012-09-13 08:30:00', 2);
INSERT INTO public.bookings VALUES (2885, 5, 0, '2012-09-13 16:00:00', 2);
INSERT INTO public.bookings VALUES (2886, 5, 0, '2012-09-13 19:00:00', 2);
INSERT INTO public.bookings VALUES (2887, 6, 12, '2012-09-13 09:00:00', 2);
INSERT INTO public.bookings VALUES (2888, 6, 0, '2012-09-13 10:30:00', 14);
INSERT INTO public.bookings VALUES (2889, 6, 0, '2012-09-13 18:00:00', 2);
INSERT INTO public.bookings VALUES (2890, 6, 6, '2012-09-13 19:30:00', 2);
INSERT INTO public.bookings VALUES (2891, 7, 14, '2012-09-13 08:00:00', 2);
INSERT INTO public.bookings VALUES (2892, 7, 4, '2012-09-13 09:30:00', 2);
INSERT INTO public.bookings VALUES (2893, 7, 17, '2012-09-13 12:30:00', 2);
INSERT INTO public.bookings VALUES (2894, 7, 5, '2012-09-13 13:30:00', 2);
INSERT INTO public.bookings VALUES (2895, 7, 4, '2012-09-13 14:30:00', 2);
INSERT INTO public.bookings VALUES (2896, 7, 15, '2012-09-13 17:00:00', 2);
INSERT INTO public.bookings VALUES (2897, 7, 0, '2012-09-13 18:00:00', 2);
INSERT INTO public.bookings VALUES (2898, 7, 9, '2012-09-13 19:00:00', 2);
INSERT INTO public.bookings VALUES (2899, 8, 20, '2012-09-13 08:00:00', 1);
INSERT INTO public.bookings VALUES (2900, 8, 15, '2012-09-13 09:00:00', 1);
INSERT INTO public.bookings VALUES (2901, 8, 21, '2012-09-13 09:30:00', 1);
INSERT INTO public.bookings VALUES (2902, 8, 21, '2012-09-13 10:30:00', 1);
INSERT INTO public.bookings VALUES (2903, 8, 16, '2012-09-13 11:00:00', 1);
INSERT INTO public.bookings VALUES (2904, 8, 21, '2012-09-13 11:30:00', 1);
INSERT INTO public.bookings VALUES (2905, 8, 0, '2012-09-13 12:00:00', 1);
INSERT INTO public.bookings VALUES (2906, 8, 24, '2012-09-13 12:30:00', 1);
INSERT INTO public.bookings VALUES (2907, 8, 3, '2012-09-13 13:30:00', 1);
INSERT INTO public.bookings VALUES (2908, 8, 16, '2012-09-13 14:30:00', 1);
INSERT INTO public.bookings VALUES (2909, 8, 21, '2012-09-13 15:00:00', 1);
INSERT INTO public.bookings VALUES (2910, 8, 21, '2012-09-13 16:00:00', 1);
INSERT INTO public.bookings VALUES (2911, 8, 16, '2012-09-13 18:00:00', 1);
INSERT INTO public.bookings VALUES (2912, 8, 21, '2012-09-13 18:30:00', 1);
INSERT INTO public.bookings VALUES (2913, 8, 0, '2012-09-13 19:00:00', 1);
INSERT INTO public.bookings VALUES (2914, 8, 21, '2012-09-13 19:30:00', 1);
INSERT INTO public.bookings VALUES (2915, 8, 15, '2012-09-13 20:00:00', 1);
INSERT INTO public.bookings VALUES (2916, 0, 6, '2012-09-14 08:00:00', 3);
INSERT INTO public.bookings VALUES (2917, 0, 17, '2012-09-14 10:00:00', 3);
INSERT INTO public.bookings VALUES (2918, 0, 5, '2012-09-14 12:30:00', 3);
INSERT INTO public.bookings VALUES (2919, 0, 3, '2012-09-14 14:00:00', 3);
INSERT INTO public.bookings VALUES (2920, 0, 0, '2012-09-14 16:00:00', 3);
INSERT INTO public.bookings VALUES (2921, 0, 26, '2012-09-14 17:30:00', 3);
INSERT INTO public.bookings VALUES (2922, 0, 0, '2012-09-14 19:00:00', 3);
INSERT INTO public.bookings VALUES (2923, 1, 11, '2012-09-14 08:00:00', 6);
INSERT INTO public.bookings VALUES (2924, 1, 8, '2012-09-14 11:00:00', 6);
INSERT INTO public.bookings VALUES (2925, 1, 0, '2012-09-14 14:00:00', 3);
INSERT INTO public.bookings VALUES (2926, 1, 0, '2012-09-14 17:00:00', 6);
INSERT INTO public.bookings VALUES (2927, 2, 1, '2012-09-14 08:00:00', 3);
INSERT INTO public.bookings VALUES (2928, 2, 21, '2012-09-14 11:00:00', 3);
INSERT INTO public.bookings VALUES (2929, 2, 1, '2012-09-14 13:00:00', 3);
INSERT INTO public.bookings VALUES (2930, 2, 5, '2012-09-14 16:00:00', 3);
INSERT INTO public.bookings VALUES (2931, 2, 9, '2012-09-14 18:00:00', 3);
INSERT INTO public.bookings VALUES (2932, 3, 15, '2012-09-14 08:30:00', 2);
INSERT INTO public.bookings VALUES (2933, 3, 16, '2012-09-14 11:00:00', 2);
INSERT INTO public.bookings VALUES (2934, 3, 20, '2012-09-14 12:30:00', 2);
INSERT INTO public.bookings VALUES (2935, 3, 21, '2012-09-14 18:30:00', 2);
INSERT INTO public.bookings VALUES (2936, 4, 14, '2012-09-14 08:00:00', 2);
INSERT INTO public.bookings VALUES (2937, 4, 0, '2012-09-14 09:00:00', 2);
INSERT INTO public.bookings VALUES (2938, 4, 13, '2012-09-14 11:00:00', 2);
INSERT INTO public.bookings VALUES (2939, 4, 9, '2012-09-14 12:00:00', 2);
INSERT INTO public.bookings VALUES (2940, 4, 0, '2012-09-14 13:00:00', 2);
INSERT INTO public.bookings VALUES (2941, 4, 13, '2012-09-14 14:00:00', 4);
INSERT INTO public.bookings VALUES (2942, 4, 0, '2012-09-14 16:00:00', 2);
INSERT INTO public.bookings VALUES (2943, 4, 6, '2012-09-14 18:00:00', 2);
INSERT INTO public.bookings VALUES (2944, 4, 20, '2012-09-14 19:00:00', 2);
INSERT INTO public.bookings VALUES (2945, 5, 15, '2012-09-14 09:30:00', 2);
INSERT INTO public.bookings VALUES (2946, 5, 0, '2012-09-14 11:00:00', 4);
INSERT INTO public.bookings VALUES (2947, 6, 12, '2012-09-14 08:30:00', 2);
INSERT INTO public.bookings VALUES (2948, 6, 0, '2012-09-14 09:30:00', 4);
INSERT INTO public.bookings VALUES (2949, 6, 0, '2012-09-14 12:30:00', 2);
INSERT INTO public.bookings VALUES (2950, 6, 16, '2012-09-14 14:00:00', 2);
INSERT INTO public.bookings VALUES (2951, 6, 0, '2012-09-14 15:00:00', 2);
INSERT INTO public.bookings VALUES (2952, 6, 12, '2012-09-14 16:00:00', 2);
INSERT INTO public.bookings VALUES (2953, 6, 17, '2012-09-14 17:30:00', 2);
INSERT INTO public.bookings VALUES (2954, 7, 10, '2012-09-14 08:30:00', 2);
INSERT INTO public.bookings VALUES (2955, 7, 24, '2012-09-14 12:00:00', 2);
INSERT INTO public.bookings VALUES (2956, 7, 9, '2012-09-14 13:30:00', 2);
INSERT INTO public.bookings VALUES (2957, 7, 21, '2012-09-14 16:30:00', 2);
INSERT INTO public.bookings VALUES (2958, 7, 24, '2012-09-14 18:00:00', 2);
INSERT INTO public.bookings VALUES (2959, 8, 3, '2012-09-14 08:00:00', 1);
INSERT INTO public.bookings VALUES (2960, 8, 16, '2012-09-14 08:30:00', 1);
INSERT INTO public.bookings VALUES (2961, 8, 2, '2012-09-14 09:00:00', 1);
INSERT INTO public.bookings VALUES (2962, 8, 21, '2012-09-14 09:30:00', 1);
INSERT INTO public.bookings VALUES (2963, 8, 3, '2012-09-14 10:00:00', 1);
INSERT INTO public.bookings VALUES (2964, 8, 9, '2012-09-14 10:30:00', 1);
INSERT INTO public.bookings VALUES (2965, 8, 3, '2012-09-14 11:00:00', 2);
INSERT INTO public.bookings VALUES (2966, 8, 20, '2012-09-14 12:00:00', 1);
INSERT INTO public.bookings VALUES (2967, 8, 21, '2012-09-14 13:00:00', 1);
INSERT INTO public.bookings VALUES (2968, 8, 16, '2012-09-14 13:30:00', 1);
INSERT INTO public.bookings VALUES (2969, 8, 24, '2012-09-14 14:00:00', 1);
INSERT INTO public.bookings VALUES (2970, 8, 20, '2012-09-14 15:00:00', 1);
INSERT INTO public.bookings VALUES (2971, 8, 22, '2012-09-14 15:30:00', 1);
INSERT INTO public.bookings VALUES (2972, 8, 16, '2012-09-14 16:00:00', 1);
INSERT INTO public.bookings VALUES (2973, 8, 3, '2012-09-14 16:30:00', 1);
INSERT INTO public.bookings VALUES (2974, 8, 15, '2012-09-14 17:00:00', 1);
INSERT INTO public.bookings VALUES (2975, 8, 16, '2012-09-14 17:30:00', 2);
INSERT INTO public.bookings VALUES (2976, 8, 11, '2012-09-14 19:00:00', 1);
INSERT INTO public.bookings VALUES (2977, 8, 2, '2012-09-14 19:30:00', 1);
INSERT INTO public.bookings VALUES (2978, 0, 0, '2012-09-15 08:00:00', 12);
INSERT INTO public.bookings VALUES (2979, 0, 11, '2012-09-15 14:00:00', 3);
INSERT INTO public.bookings VALUES (2980, 0, 7, '2012-09-15 16:30:00', 3);
INSERT INTO public.bookings VALUES (2981, 0, 17, '2012-09-15 18:00:00', 3);
INSERT INTO public.bookings VALUES (2982, 1, 10, '2012-09-15 08:00:00', 3);
INSERT INTO public.bookings VALUES (2983, 1, 11, '2012-09-15 10:00:00', 3);
INSERT INTO public.bookings VALUES (2984, 1, 24, '2012-09-15 13:00:00', 6);
INSERT INTO public.bookings VALUES (2985, 1, 12, '2012-09-15 16:00:00', 3);
INSERT INTO public.bookings VALUES (2986, 2, 0, '2012-09-15 08:00:00', 3);
INSERT INTO public.bookings VALUES (2987, 2, 1, '2012-09-15 10:30:00', 3);
INSERT INTO public.bookings VALUES (2988, 2, 0, '2012-09-15 12:00:00', 3);
INSERT INTO public.bookings VALUES (2989, 2, 14, '2012-09-15 13:30:00', 3);
INSERT INTO public.bookings VALUES (2990, 2, 26, '2012-09-15 15:30:00', 3);
INSERT INTO public.bookings VALUES (2991, 2, 0, '2012-09-15 17:30:00', 3);
INSERT INTO public.bookings VALUES (2992, 3, 1, '2012-09-15 08:00:00', 2);
INSERT INTO public.bookings VALUES (2993, 3, 14, '2012-09-15 09:30:00', 2);
INSERT INTO public.bookings VALUES (2994, 3, 22, '2012-09-15 10:30:00', 2);
INSERT INTO public.bookings VALUES (2995, 3, 21, '2012-09-15 11:30:00', 2);
INSERT INTO public.bookings VALUES (2996, 3, 20, '2012-09-15 12:30:00', 2);
INSERT INTO public.bookings VALUES (2997, 3, 3, '2012-09-15 14:30:00', 2);
INSERT INTO public.bookings VALUES (2998, 3, 11, '2012-09-15 15:30:00', 2);
INSERT INTO public.bookings VALUES (2999, 3, 0, '2012-09-15 17:30:00', 2);
INSERT INTO public.bookings VALUES (3000, 3, 11, '2012-09-15 19:30:00', 2);
INSERT INTO public.bookings VALUES (3001, 4, 13, '2012-09-15 08:00:00', 2);
INSERT INTO public.bookings VALUES (3002, 4, 0, '2012-09-15 09:00:00', 2);
INSERT INTO public.bookings VALUES (3003, 4, 17, '2012-09-15 10:00:00', 2);
INSERT INTO public.bookings VALUES (3004, 4, 3, '2012-09-15 11:00:00', 2);
INSERT INTO public.bookings VALUES (3005, 4, 0, '2012-09-15 12:00:00', 8);
INSERT INTO public.bookings VALUES (3006, 4, 24, '2012-09-15 16:00:00', 2);
INSERT INTO public.bookings VALUES (3007, 4, 16, '2012-09-15 17:00:00', 4);
INSERT INTO public.bookings VALUES (3008, 4, 14, '2012-09-15 19:00:00', 2);
INSERT INTO public.bookings VALUES (3009, 5, 0, '2012-09-15 12:30:00', 2);
INSERT INTO public.bookings VALUES (3010, 6, 0, '2012-09-15 08:00:00', 2);
INSERT INTO public.bookings VALUES (3011, 6, 0, '2012-09-15 09:30:00', 4);
INSERT INTO public.bookings VALUES (3012, 6, 11, '2012-09-15 11:30:00', 2);
INSERT INTO public.bookings VALUES (3013, 6, 22, '2012-09-15 12:30:00', 2);
INSERT INTO public.bookings VALUES (3014, 6, 12, '2012-09-15 14:00:00', 2);
INSERT INTO public.bookings VALUES (3015, 6, 1, '2012-09-15 15:00:00', 2);
INSERT INTO public.bookings VALUES (3016, 6, 4, '2012-09-15 16:00:00', 2);
INSERT INTO public.bookings VALUES (3017, 6, 15, '2012-09-15 17:30:00', 2);
INSERT INTO public.bookings VALUES (3018, 6, 0, '2012-09-15 18:30:00', 4);
INSERT INTO public.bookings VALUES (3019, 7, 17, '2012-09-15 08:30:00', 2);
INSERT INTO public.bookings VALUES (3020, 7, 2, '2012-09-15 09:30:00', 2);
INSERT INTO public.bookings VALUES (3021, 7, 8, '2012-09-15 10:30:00', 2);
INSERT INTO public.bookings VALUES (3022, 7, 15, '2012-09-15 13:00:00', 2);
INSERT INTO public.bookings VALUES (3023, 7, 22, '2012-09-15 14:00:00', 2);
INSERT INTO public.bookings VALUES (3024, 7, 13, '2012-09-15 15:00:00', 2);
INSERT INTO public.bookings VALUES (3025, 7, 10, '2012-09-15 16:00:00', 2);
INSERT INTO public.bookings VALUES (3026, 7, 13, '2012-09-15 19:30:00', 2);
INSERT INTO public.bookings VALUES (3027, 8, 21, '2012-09-15 08:00:00', 1);
INSERT INTO public.bookings VALUES (3028, 8, 16, '2012-09-15 08:30:00', 1);
INSERT INTO public.bookings VALUES (3029, 8, 15, '2012-09-15 09:00:00', 1);
INSERT INTO public.bookings VALUES (3030, 8, 16, '2012-09-15 09:30:00', 1);
INSERT INTO public.bookings VALUES (3031, 8, 15, '2012-09-15 10:30:00', 1);
INSERT INTO public.bookings VALUES (3032, 8, 16, '2012-09-15 11:00:00', 2);
INSERT INTO public.bookings VALUES (3033, 8, 3, '2012-09-15 12:00:00', 1);
INSERT INTO public.bookings VALUES (3034, 8, 21, '2012-09-15 12:30:00', 2);
INSERT INTO public.bookings VALUES (3035, 8, 6, '2012-09-15 13:30:00', 1);
INSERT INTO public.bookings VALUES (3036, 8, 15, '2012-09-15 15:00:00', 1);
INSERT INTO public.bookings VALUES (3037, 8, 6, '2012-09-15 15:30:00', 1);
INSERT INTO public.bookings VALUES (3038, 8, 21, '2012-09-15 16:30:00', 1);
INSERT INTO public.bookings VALUES (3039, 8, 21, '2012-09-15 19:00:00', 1);
INSERT INTO public.bookings VALUES (3040, 8, 3, '2012-09-15 19:30:00', 1);
INSERT INTO public.bookings VALUES (3041, 0, 0, '2012-09-16 08:00:00', 9);
INSERT INTO public.bookings VALUES (3042, 0, 11, '2012-09-16 12:30:00', 3);
INSERT INTO public.bookings VALUES (3043, 0, 6, '2012-09-16 14:00:00', 3);
INSERT INTO public.bookings VALUES (3044, 0, 0, '2012-09-16 15:30:00', 3);
INSERT INTO public.bookings VALUES (3045, 0, 24, '2012-09-16 17:00:00', 3);
INSERT INTO public.bookings VALUES (3046, 0, 10, '2012-09-16 18:30:00', 3);
INSERT INTO public.bookings VALUES (3047, 1, 8, '2012-09-16 08:00:00', 3);
INSERT INTO public.bookings VALUES (3048, 1, 0, '2012-09-16 09:30:00', 6);
INSERT INTO public.bookings VALUES (3049, 1, 16, '2012-09-16 12:30:00', 3);
INSERT INTO public.bookings VALUES (3050, 1, 8, '2012-09-16 14:00:00', 3);
INSERT INTO public.bookings VALUES (3051, 1, 12, '2012-09-16 15:30:00', 3);
INSERT INTO public.bookings VALUES (3052, 1, 0, '2012-09-16 17:30:00', 6);
INSERT INTO public.bookings VALUES (3053, 2, 2, '2012-09-16 08:30:00', 3);
INSERT INTO public.bookings VALUES (3054, 2, 1, '2012-09-16 10:30:00', 3);
INSERT INTO public.bookings VALUES (3055, 2, 12, '2012-09-16 12:00:00', 3);
INSERT INTO public.bookings VALUES (3056, 2, 21, '2012-09-16 13:30:00', 3);
INSERT INTO public.bookings VALUES (3057, 2, 7, '2012-09-16 15:30:00', 3);
INSERT INTO public.bookings VALUES (3058, 2, 21, '2012-09-16 17:00:00', 3);
INSERT INTO public.bookings VALUES (3059, 2, 21, '2012-09-16 19:00:00', 3);
INSERT INTO public.bookings VALUES (3060, 3, 1, '2012-09-16 09:00:00', 2);
INSERT INTO public.bookings VALUES (3061, 3, 14, '2012-09-16 10:00:00', 2);
INSERT INTO public.bookings VALUES (3062, 3, 0, '2012-09-16 13:00:00', 2);
INSERT INTO public.bookings VALUES (3063, 3, 22, '2012-09-16 16:30:00', 2);
INSERT INTO public.bookings VALUES (3064, 3, 16, '2012-09-16 17:30:00', 2);
INSERT INTO public.bookings VALUES (3065, 3, 15, '2012-09-16 18:30:00', 2);
INSERT INTO public.bookings VALUES (3066, 4, 1, '2012-09-16 08:00:00', 2);
INSERT INTO public.bookings VALUES (3067, 4, 0, '2012-09-16 09:00:00', 2);
INSERT INTO public.bookings VALUES (3068, 4, 8, '2012-09-16 10:00:00', 4);
INSERT INTO public.bookings VALUES (3069, 4, 13, '2012-09-16 12:00:00', 4);
INSERT INTO public.bookings VALUES (3070, 4, 3, '2012-09-16 14:00:00', 4);
INSERT INTO public.bookings VALUES (3071, 4, 0, '2012-09-16 16:00:00', 2);
INSERT INTO public.bookings VALUES (3072, 4, 0, '2012-09-16 17:30:00', 4);
INSERT INTO public.bookings VALUES (3073, 4, 14, '2012-09-16 19:30:00', 2);
INSERT INTO public.bookings VALUES (3074, 5, 22, '2012-09-16 08:30:00', 2);
INSERT INTO public.bookings VALUES (3075, 6, 11, '2012-09-16 08:00:00', 2);
INSERT INTO public.bookings VALUES (3076, 6, 0, '2012-09-16 09:00:00', 2);
INSERT INTO public.bookings VALUES (3077, 6, 12, '2012-09-16 10:30:00', 2);
INSERT INTO public.bookings VALUES (3078, 6, 2, '2012-09-16 12:00:00', 2);
INSERT INTO public.bookings VALUES (3079, 6, 10, '2012-09-16 13:30:00', 2);
INSERT INTO public.bookings VALUES (3080, 6, 0, '2012-09-16 14:30:00', 4);
INSERT INTO public.bookings VALUES (3081, 6, 0, '2012-09-16 17:30:00', 6);
INSERT INTO public.bookings VALUES (3082, 7, 10, '2012-09-16 08:30:00', 2);
INSERT INTO public.bookings VALUES (3083, 7, 10, '2012-09-16 10:30:00', 2);
INSERT INTO public.bookings VALUES (3084, 7, 9, '2012-09-16 11:30:00', 2);
INSERT INTO public.bookings VALUES (3085, 7, 15, '2012-09-16 12:30:00', 2);
INSERT INTO public.bookings VALUES (3086, 7, 13, '2012-09-16 14:00:00', 2);
INSERT INTO public.bookings VALUES (3087, 7, 8, '2012-09-16 15:30:00', 2);
INSERT INTO public.bookings VALUES (3088, 7, 27, '2012-09-16 16:30:00', 2);
INSERT INTO public.bookings VALUES (3089, 7, 27, '2012-09-16 19:00:00', 2);
INSERT INTO public.bookings VALUES (3090, 8, 21, '2012-09-16 09:30:00', 1);
INSERT INTO public.bookings VALUES (3091, 8, 3, '2012-09-16 10:30:00', 2);
INSERT INTO public.bookings VALUES (3092, 8, 21, '2012-09-16 12:00:00', 1);
INSERT INTO public.bookings VALUES (3093, 8, 27, '2012-09-16 13:30:00', 1);
INSERT INTO public.bookings VALUES (3094, 8, 16, '2012-09-16 14:30:00', 1);
INSERT INTO public.bookings VALUES (3095, 8, 21, '2012-09-16 15:00:00', 1);
INSERT INTO public.bookings VALUES (3096, 8, 27, '2012-09-16 15:30:00', 1);
INSERT INTO public.bookings VALUES (3097, 8, 16, '2012-09-16 16:30:00', 1);
INSERT INTO public.bookings VALUES (3098, 8, 3, '2012-09-16 17:00:00', 1);
INSERT INTO public.bookings VALUES (3099, 8, 3, '2012-09-16 18:00:00', 1);
INSERT INTO public.bookings VALUES (3100, 8, 2, '2012-09-16 19:00:00', 1);
INSERT INTO public.bookings VALUES (3101, 8, 3, '2012-09-16 20:00:00', 1);
INSERT INTO public.bookings VALUES (3102, 0, 22, '2012-09-17 08:00:00', 3);
INSERT INTO public.bookings VALUES (3103, 0, 0, '2012-09-17 09:30:00', 3);
INSERT INTO public.bookings VALUES (3104, 0, 13, '2012-09-17 11:00:00', 3);
INSERT INTO public.bookings VALUES (3105, 0, 7, '2012-09-17 14:00:00', 3);
INSERT INTO public.bookings VALUES (3106, 0, 0, '2012-09-17 16:30:00', 3);
INSERT INTO public.bookings VALUES (3107, 0, 26, '2012-09-17 18:00:00', 3);
INSERT INTO public.bookings VALUES (3108, 1, 8, '2012-09-17 08:30:00', 3);
INSERT INTO public.bookings VALUES (3109, 1, 9, '2012-09-17 10:00:00', 3);
INSERT INTO public.bookings VALUES (3110, 1, 0, '2012-09-17 11:30:00', 3);
INSERT INTO public.bookings VALUES (3111, 1, 0, '2012-09-17 13:30:00', 3);
INSERT INTO public.bookings VALUES (3112, 1, 8, '2012-09-17 16:00:00', 3);
INSERT INTO public.bookings VALUES (3113, 1, 9, '2012-09-17 17:30:00', 3);
INSERT INTO public.bookings VALUES (3114, 1, 8, '2012-09-17 19:00:00', 3);
INSERT INTO public.bookings VALUES (3115, 2, 5, '2012-09-17 08:30:00', 3);
INSERT INTO public.bookings VALUES (3116, 2, 12, '2012-09-17 10:00:00', 3);
INSERT INTO public.bookings VALUES (3117, 2, 21, '2012-09-17 12:00:00', 3);
INSERT INTO public.bookings VALUES (3118, 2, 12, '2012-09-17 13:30:00', 3);
INSERT INTO public.bookings VALUES (3119, 2, 0, '2012-09-17 15:00:00', 3);
INSERT INTO public.bookings VALUES (3120, 2, 1, '2012-09-17 18:00:00', 3);
INSERT INTO public.bookings VALUES (3121, 3, 21, '2012-09-17 08:30:00', 2);
INSERT INTO public.bookings VALUES (3122, 3, 22, '2012-09-17 09:30:00', 4);
INSERT INTO public.bookings VALUES (3123, 3, 15, '2012-09-17 12:00:00', 2);
INSERT INTO public.bookings VALUES (3124, 3, 22, '2012-09-17 14:00:00', 2);
INSERT INTO public.bookings VALUES (3125, 3, 16, '2012-09-17 16:30:00', 2);
INSERT INTO public.bookings VALUES (3126, 3, 13, '2012-09-17 17:30:00', 2);
INSERT INTO public.bookings VALUES (3127, 3, 3, '2012-09-17 18:30:00', 2);
INSERT INTO public.bookings VALUES (3128, 4, 7, '2012-09-17 08:00:00', 2);
INSERT INTO public.bookings VALUES (3129, 4, 0, '2012-09-17 09:30:00', 2);
INSERT INTO public.bookings VALUES (3130, 4, 0, '2012-09-17 11:00:00', 4);
INSERT INTO public.bookings VALUES (3131, 4, 10, '2012-09-17 13:00:00', 2);
INSERT INTO public.bookings VALUES (3132, 4, 20, '2012-09-17 14:30:00', 2);
INSERT INTO public.bookings VALUES (3133, 4, 16, '2012-09-17 15:30:00', 2);
INSERT INTO public.bookings VALUES (3134, 4, 0, '2012-09-17 16:30:00', 2);
INSERT INTO public.bookings VALUES (3135, 4, 5, '2012-09-17 17:30:00', 2);
INSERT INTO public.bookings VALUES (3136, 4, 14, '2012-09-17 18:30:00', 2);
INSERT INTO public.bookings VALUES (3137, 4, 0, '2012-09-17 19:30:00', 2);
INSERT INTO public.bookings VALUES (3138, 5, 0, '2012-09-17 12:00:00', 2);
INSERT INTO public.bookings VALUES (3139, 5, 24, '2012-09-17 15:00:00', 2);
INSERT INTO public.bookings VALUES (3140, 6, 0, '2012-09-17 08:00:00', 4);
INSERT INTO public.bookings VALUES (3141, 6, 0, '2012-09-17 10:30:00', 4);
INSERT INTO public.bookings VALUES (3142, 6, 5, '2012-09-17 12:30:00', 2);
INSERT INTO public.bookings VALUES (3143, 6, 0, '2012-09-17 13:30:00', 2);
INSERT INTO public.bookings VALUES (3144, 6, 0, '2012-09-17 15:00:00', 8);
INSERT INTO public.bookings VALUES (3145, 7, 10, '2012-09-17 08:00:00', 2);
INSERT INTO public.bookings VALUES (3146, 7, 21, '2012-09-17 10:00:00', 2);
INSERT INTO public.bookings VALUES (3147, 7, 17, '2012-09-17 11:00:00', 2);
INSERT INTO public.bookings VALUES (3148, 7, 15, '2012-09-17 14:00:00', 2);
INSERT INTO public.bookings VALUES (3149, 7, 0, '2012-09-17 15:00:00', 2);
INSERT INTO public.bookings VALUES (3150, 7, 22, '2012-09-17 16:30:00', 2);
INSERT INTO public.bookings VALUES (3151, 7, 20, '2012-09-17 18:30:00', 2);
INSERT INTO public.bookings VALUES (3152, 7, 1, '2012-09-17 19:30:00', 2);
INSERT INTO public.bookings VALUES (3153, 8, 15, '2012-09-17 09:30:00', 1);
INSERT INTO public.bookings VALUES (3154, 8, 16, '2012-09-17 11:00:00', 1);
INSERT INTO public.bookings VALUES (3155, 8, 0, '2012-09-17 12:00:00', 1);
INSERT INTO public.bookings VALUES (3156, 8, 8, '2012-09-17 12:30:00', 1);
INSERT INTO public.bookings VALUES (3157, 8, 1, '2012-09-17 13:30:00', 1);
INSERT INTO public.bookings VALUES (3158, 8, 11, '2012-09-17 14:00:00', 1);
INSERT INTO public.bookings VALUES (3159, 8, 3, '2012-09-17 15:00:00', 1);
INSERT INTO public.bookings VALUES (3160, 8, 1, '2012-09-17 15:30:00', 1);
INSERT INTO public.bookings VALUES (3161, 8, 2, '2012-09-17 16:00:00', 1);
INSERT INTO public.bookings VALUES (3162, 8, 21, '2012-09-17 16:30:00', 1);
INSERT INTO public.bookings VALUES (3163, 8, 3, '2012-09-17 17:00:00', 1);
INSERT INTO public.bookings VALUES (3164, 8, 21, '2012-09-17 17:30:00', 1);
INSERT INTO public.bookings VALUES (3165, 8, 21, '2012-09-17 19:00:00', 1);
INSERT INTO public.bookings VALUES (3166, 8, 2, '2012-09-17 20:00:00', 1);
INSERT INTO public.bookings VALUES (3167, 0, 28, '2012-09-18 09:00:00', 3);
INSERT INTO public.bookings VALUES (3168, 0, 6, '2012-09-18 10:30:00', 3);
INSERT INTO public.bookings VALUES (3169, 0, 11, '2012-09-18 12:00:00', 3);
INSERT INTO public.bookings VALUES (3170, 0, 16, '2012-09-18 13:30:00', 3);
INSERT INTO public.bookings VALUES (3171, 0, 5, '2012-09-18 16:00:00', 3);
INSERT INTO public.bookings VALUES (3172, 0, 28, '2012-09-18 17:30:00', 3);
INSERT INTO public.bookings VALUES (3173, 0, 14, '2012-09-18 19:00:00', 3);
INSERT INTO public.bookings VALUES (3174, 1, 10, '2012-09-18 08:00:00', 3);
INSERT INTO public.bookings VALUES (3175, 1, 12, '2012-09-18 09:30:00', 6);
INSERT INTO public.bookings VALUES (3176, 1, 0, '2012-09-18 13:30:00', 3);
INSERT INTO public.bookings VALUES (3177, 1, 11, '2012-09-18 16:00:00', 3);
INSERT INTO public.bookings VALUES (3178, 1, 10, '2012-09-18 18:00:00', 3);
INSERT INTO public.bookings VALUES (3179, 2, 16, '2012-09-18 08:00:00', 3);
INSERT INTO public.bookings VALUES (3180, 2, 21, '2012-09-18 10:00:00', 3);
INSERT INTO public.bookings VALUES (3181, 2, 21, '2012-09-18 13:00:00', 3);
INSERT INTO public.bookings VALUES (3182, 2, 1, '2012-09-18 14:30:00', 3);
INSERT INTO public.bookings VALUES (3183, 2, 24, '2012-09-18 16:00:00', 3);
INSERT INTO public.bookings VALUES (3184, 2, 13, '2012-09-18 17:30:00', 3);
INSERT INTO public.bookings VALUES (3185, 3, 3, '2012-09-18 08:00:00', 4);
INSERT INTO public.bookings VALUES (3186, 3, 20, '2012-09-18 10:00:00', 2);
INSERT INTO public.bookings VALUES (3187, 3, 13, '2012-09-18 11:30:00', 2);
INSERT INTO public.bookings VALUES (3188, 3, 3, '2012-09-18 13:00:00', 4);
INSERT INTO public.bookings VALUES (3189, 3, 21, '2012-09-18 17:00:00', 2);
INSERT INTO public.bookings VALUES (3190, 3, 15, '2012-09-18 18:00:00', 2);
INSERT INTO public.bookings VALUES (3191, 3, 3, '2012-09-18 19:30:00', 2);
INSERT INTO public.bookings VALUES (3192, 4, 5, '2012-09-18 08:30:00', 2);
INSERT INTO public.bookings VALUES (3193, 4, 0, '2012-09-18 09:30:00', 2);
INSERT INTO public.bookings VALUES (3194, 4, 13, '2012-09-18 10:30:00', 2);
INSERT INTO public.bookings VALUES (3195, 4, 1, '2012-09-18 11:30:00', 2);
INSERT INTO public.bookings VALUES (3196, 4, 13, '2012-09-18 12:30:00', 2);
INSERT INTO public.bookings VALUES (3197, 4, 0, '2012-09-18 15:00:00', 2);
INSERT INTO public.bookings VALUES (3198, 4, 13, '2012-09-18 16:00:00', 2);
INSERT INTO public.bookings VALUES (3199, 4, 0, '2012-09-18 17:00:00', 2);
INSERT INTO public.bookings VALUES (3200, 4, 4, '2012-09-18 18:00:00', 2);
INSERT INTO public.bookings VALUES (3201, 4, 0, '2012-09-18 19:00:00', 2);
INSERT INTO public.bookings VALUES (3202, 5, 0, '2012-09-18 08:30:00', 2);
INSERT INTO public.bookings VALUES (3203, 5, 0, '2012-09-18 18:00:00', 2);
INSERT INTO public.bookings VALUES (3204, 6, 0, '2012-09-18 08:30:00', 2);
INSERT INTO public.bookings VALUES (3205, 6, 9, '2012-09-18 09:30:00', 2);
INSERT INTO public.bookings VALUES (3206, 6, 0, '2012-09-18 11:00:00', 2);
INSERT INTO public.bookings VALUES (3207, 6, 8, '2012-09-18 14:00:00', 2);
INSERT INTO public.bookings VALUES (3208, 6, 0, '2012-09-18 15:00:00', 6);
INSERT INTO public.bookings VALUES (3209, 6, 0, '2012-09-18 18:30:00', 4);
INSERT INTO public.bookings VALUES (3210, 7, 7, '2012-09-18 10:00:00', 2);
INSERT INTO public.bookings VALUES (3211, 7, 0, '2012-09-18 11:00:00', 2);
INSERT INTO public.bookings VALUES (3212, 7, 27, '2012-09-18 16:00:00', 2);
INSERT INTO public.bookings VALUES (3213, 7, 8, '2012-09-18 18:00:00', 2);
INSERT INTO public.bookings VALUES (3214, 8, 21, '2012-09-18 08:30:00', 1);
INSERT INTO public.bookings VALUES (3215, 8, 15, '2012-09-18 10:00:00', 1);
INSERT INTO public.bookings VALUES (3216, 8, 0, '2012-09-18 10:30:00', 1);
INSERT INTO public.bookings VALUES (3217, 8, 7, '2012-09-18 11:00:00', 1);
INSERT INTO public.bookings VALUES (3218, 8, 3, '2012-09-18 12:00:00', 1);
INSERT INTO public.bookings VALUES (3219, 8, 28, '2012-09-18 13:30:00', 1);
INSERT INTO public.bookings VALUES (3220, 8, 15, '2012-09-18 14:00:00', 1);
INSERT INTO public.bookings VALUES (3221, 8, 4, '2012-09-18 14:30:00', 1);
INSERT INTO public.bookings VALUES (3222, 8, 24, '2012-09-18 15:30:00', 1);
INSERT INTO public.bookings VALUES (3223, 8, 3, '2012-09-18 16:00:00', 1);
INSERT INTO public.bookings VALUES (3224, 8, 21, '2012-09-18 16:30:00', 1);
INSERT INTO public.bookings VALUES (3225, 8, 9, '2012-09-18 17:00:00', 1);
INSERT INTO public.bookings VALUES (3226, 8, 0, '2012-09-18 17:30:00', 1);
INSERT INTO public.bookings VALUES (3227, 8, 3, '2012-09-18 18:00:00', 1);
INSERT INTO public.bookings VALUES (3228, 8, 0, '2012-09-18 19:00:00', 1);
INSERT INTO public.bookings VALUES (3229, 8, 28, '2012-09-18 20:00:00', 1);
INSERT INTO public.bookings VALUES (3230, 0, 16, '2012-09-19 08:00:00', 3);
INSERT INTO public.bookings VALUES (3231, 0, 28, '2012-09-19 09:30:00', 3);
INSERT INTO public.bookings VALUES (3232, 0, 0, '2012-09-19 11:00:00', 6);
INSERT INTO public.bookings VALUES (3233, 0, 28, '2012-09-19 15:00:00', 3);
INSERT INTO public.bookings VALUES (3234, 0, 24, '2012-09-19 16:30:00', 3);
INSERT INTO public.bookings VALUES (3235, 0, 14, '2012-09-19 18:00:00', 3);
INSERT INTO public.bookings VALUES (3236, 1, 0, '2012-09-19 09:30:00', 3);
INSERT INTO public.bookings VALUES (3237, 1, 1, '2012-09-19 11:00:00', 3);
INSERT INTO public.bookings VALUES (3238, 1, 0, '2012-09-19 13:00:00', 3);
INSERT INTO public.bookings VALUES (3239, 1, 4, '2012-09-19 16:00:00', 3);
INSERT INTO public.bookings VALUES (3240, 1, 10, '2012-09-19 18:00:00', 3);
INSERT INTO public.bookings VALUES (3241, 2, 1, '2012-09-19 08:00:00', 3);
INSERT INTO public.bookings VALUES (3242, 2, 16, '2012-09-19 10:00:00', 3);
INSERT INTO public.bookings VALUES (3243, 2, 9, '2012-09-19 11:30:00', 3);
INSERT INTO public.bookings VALUES (3244, 2, 21, '2012-09-19 13:00:00', 3);
INSERT INTO public.bookings VALUES (3245, 2, 29, '2012-09-19 14:30:00', 3);
INSERT INTO public.bookings VALUES (3246, 2, 30, '2012-09-19 17:00:00', 3);
INSERT INTO public.bookings VALUES (3247, 3, 22, '2012-09-19 08:00:00', 2);
INSERT INTO public.bookings VALUES (3248, 3, 15, '2012-09-19 09:30:00', 2);
INSERT INTO public.bookings VALUES (3249, 3, 3, '2012-09-19 10:30:00', 2);
INSERT INTO public.bookings VALUES (3250, 3, 3, '2012-09-19 12:00:00', 2);
INSERT INTO public.bookings VALUES (3251, 3, 2, '2012-09-19 13:00:00', 2);
INSERT INTO public.bookings VALUES (3252, 3, 1, '2012-09-19 16:00:00', 2);
INSERT INTO public.bookings VALUES (3253, 3, 21, '2012-09-19 19:00:00', 2);
INSERT INTO public.bookings VALUES (3254, 4, 20, '2012-09-19 08:00:00', 2);
INSERT INTO public.bookings VALUES (3255, 4, 5, '2012-09-19 09:00:00', 2);
INSERT INTO public.bookings VALUES (3256, 4, 0, '2012-09-19 10:00:00', 4);
INSERT INTO public.bookings VALUES (3257, 4, 5, '2012-09-19 12:00:00', 2);
INSERT INTO public.bookings VALUES (3258, 4, 0, '2012-09-19 13:30:00', 6);
INSERT INTO public.bookings VALUES (3259, 4, 16, '2012-09-19 17:00:00', 2);
INSERT INTO public.bookings VALUES (3260, 4, 0, '2012-09-19 18:00:00', 2);
INSERT INTO public.bookings VALUES (3261, 4, 13, '2012-09-19 19:00:00', 2);
INSERT INTO public.bookings VALUES (3262, 5, 10, '2012-09-19 10:30:00', 2);
INSERT INTO public.bookings VALUES (3263, 5, 7, '2012-09-19 12:30:00', 2);
INSERT INTO public.bookings VALUES (3264, 5, 0, '2012-09-19 13:30:00', 2);
INSERT INTO public.bookings VALUES (3265, 5, 0, '2012-09-19 15:30:00', 2);
INSERT INTO public.bookings VALUES (3266, 5, 0, '2012-09-19 19:30:00', 2);
INSERT INTO public.bookings VALUES (3267, 6, 0, '2012-09-19 08:00:00', 2);
INSERT INTO public.bookings VALUES (3268, 6, 8, '2012-09-19 09:00:00', 2);
INSERT INTO public.bookings VALUES (3269, 6, 14, '2012-09-19 10:00:00', 4);
INSERT INTO public.bookings VALUES (3270, 6, 0, '2012-09-19 12:30:00', 2);
INSERT INTO public.bookings VALUES (3271, 6, 12, '2012-09-19 13:30:00', 2);
INSERT INTO public.bookings VALUES (3272, 6, 0, '2012-09-19 15:00:00', 2);
INSERT INTO public.bookings VALUES (3273, 6, 12, '2012-09-19 16:30:00', 2);
INSERT INTO public.bookings VALUES (3274, 6, 4, '2012-09-19 17:30:00', 2);
INSERT INTO public.bookings VALUES (3275, 7, 10, '2012-09-19 08:00:00', 2);
INSERT INTO public.bookings VALUES (3276, 7, 27, '2012-09-19 09:30:00', 2);
INSERT INTO public.bookings VALUES (3277, 7, 15, '2012-09-19 10:30:00', 2);
INSERT INTO public.bookings VALUES (3278, 7, 4, '2012-09-19 13:00:00', 4);
INSERT INTO public.bookings VALUES (3279, 7, 27, '2012-09-19 15:00:00', 2);
INSERT INTO public.bookings VALUES (3280, 7, 15, '2012-09-19 16:30:00', 2);
INSERT INTO public.bookings VALUES (3281, 7, 6, '2012-09-19 18:00:00', 2);
INSERT INTO public.bookings VALUES (3282, 8, 21, '2012-09-19 08:00:00', 1);
INSERT INTO public.bookings VALUES (3283, 8, 3, '2012-09-19 08:30:00', 2);
INSERT INTO public.bookings VALUES (3284, 8, 29, '2012-09-19 09:30:00', 1);
INSERT INTO public.bookings VALUES (3285, 8, 3, '2012-09-19 10:00:00', 1);
INSERT INTO public.bookings VALUES (3286, 8, 12, '2012-09-19 10:30:00', 1);
INSERT INTO public.bookings VALUES (3287, 8, 30, '2012-09-19 11:30:00', 1);
INSERT INTO public.bookings VALUES (3288, 8, 28, '2012-09-19 12:00:00', 1);
INSERT INTO public.bookings VALUES (3289, 8, 29, '2012-09-19 12:30:00', 1);
INSERT INTO public.bookings VALUES (3290, 8, 24, '2012-09-19 13:30:00', 1);
INSERT INTO public.bookings VALUES (3291, 8, 29, '2012-09-19 14:00:00', 1);
INSERT INTO public.bookings VALUES (3292, 8, 16, '2012-09-19 14:30:00', 2);
INSERT INTO public.bookings VALUES (3293, 8, 22, '2012-09-19 17:30:00', 1);
INSERT INTO public.bookings VALUES (3294, 8, 29, '2012-09-19 18:00:00', 1);
INSERT INTO public.bookings VALUES (3295, 8, 3, '2012-09-19 18:30:00', 1);
INSERT INTO public.bookings VALUES (3296, 8, 8, '2012-09-19 19:00:00', 1);
INSERT INTO public.bookings VALUES (3297, 8, 15, '2012-09-19 19:30:00', 1);
INSERT INTO public.bookings VALUES (3298, 0, 14, '2012-09-20 08:00:00', 3);
INSERT INTO public.bookings VALUES (3299, 0, 0, '2012-09-20 09:30:00', 6);
INSERT INTO public.bookings VALUES (3300, 0, 0, '2012-09-20 13:00:00', 3);
INSERT INTO public.bookings VALUES (3301, 0, 17, '2012-09-20 15:30:00', 3);
INSERT INTO public.bookings VALUES (3302, 0, 26, '2012-09-20 17:00:00', 3);
INSERT INTO public.bookings VALUES (3303, 0, 5, '2012-09-20 18:30:00', 3);
INSERT INTO public.bookings VALUES (3304, 1, 11, '2012-09-20 08:30:00', 3);
INSERT INTO public.bookings VALUES (3305, 1, 10, '2012-09-20 10:30:00', 3);
INSERT INTO public.bookings VALUES (3306, 1, 30, '2012-09-20 12:30:00', 3);
INSERT INTO public.bookings VALUES (3307, 1, 10, '2012-09-20 14:00:00', 3);
INSERT INTO public.bookings VALUES (3308, 1, 9, '2012-09-20 16:00:00', 3);
INSERT INTO public.bookings VALUES (3309, 1, 0, '2012-09-20 17:30:00', 3);
INSERT INTO public.bookings VALUES (3310, 1, 24, '2012-09-20 19:00:00', 3);
INSERT INTO public.bookings VALUES (3311, 2, 21, '2012-09-20 08:00:00', 6);
INSERT INTO public.bookings VALUES (3312, 2, 0, '2012-09-20 11:00:00', 3);
INSERT INTO public.bookings VALUES (3313, 2, 14, '2012-09-20 12:30:00', 3);
INSERT INTO public.bookings VALUES (3314, 2, 1, '2012-09-20 14:00:00', 3);
INSERT INTO public.bookings VALUES (3315, 2, 2, '2012-09-20 15:30:00', 3);
INSERT INTO public.bookings VALUES (3316, 2, 14, '2012-09-20 17:30:00', 3);
INSERT INTO public.bookings VALUES (3317, 3, 1, '2012-09-20 09:30:00', 2);
INSERT INTO public.bookings VALUES (3318, 3, 21, '2012-09-20 15:00:00', 2);
INSERT INTO public.bookings VALUES (3319, 3, 30, '2012-09-20 18:30:00', 4);
INSERT INTO public.bookings VALUES (3320, 4, 0, '2012-09-20 08:00:00', 2);
INSERT INTO public.bookings VALUES (3321, 4, 14, '2012-09-20 09:30:00', 2);
INSERT INTO public.bookings VALUES (3322, 4, 0, '2012-09-20 10:30:00', 4);
INSERT INTO public.bookings VALUES (3323, 4, 3, '2012-09-20 12:30:00', 4);
INSERT INTO public.bookings VALUES (3324, 4, 0, '2012-09-20 15:00:00', 2);
INSERT INTO public.bookings VALUES (3325, 4, 0, '2012-09-20 16:30:00', 2);
INSERT INTO public.bookings VALUES (3326, 4, 20, '2012-09-20 18:00:00', 2);
INSERT INTO public.bookings VALUES (3327, 4, 8, '2012-09-20 19:30:00', 2);
INSERT INTO public.bookings VALUES (3328, 5, 0, '2012-09-20 11:00:00', 2);
INSERT INTO public.bookings VALUES (3329, 5, 0, '2012-09-20 13:30:00', 2);
INSERT INTO public.bookings VALUES (3330, 5, 0, '2012-09-20 16:30:00', 2);
INSERT INTO public.bookings VALUES (3331, 5, 0, '2012-09-20 18:30:00', 2);
INSERT INTO public.bookings VALUES (3332, 6, 6, '2012-09-20 08:00:00', 2);
INSERT INTO public.bookings VALUES (3333, 6, 0, '2012-09-20 09:30:00', 6);
INSERT INTO public.bookings VALUES (3334, 6, 0, '2012-09-20 14:00:00', 2);
INSERT INTO public.bookings VALUES (3335, 6, 28, '2012-09-20 15:30:00', 2);
INSERT INTO public.bookings VALUES (3336, 7, 0, '2012-09-20 08:30:00', 2);
INSERT INTO public.bookings VALUES (3337, 7, 24, '2012-09-20 09:30:00', 2);
INSERT INTO public.bookings VALUES (3338, 7, 9, '2012-09-20 13:00:00', 2);
INSERT INTO public.bookings VALUES (3339, 7, 8, '2012-09-20 14:00:00', 2);
INSERT INTO public.bookings VALUES (3340, 7, 4, '2012-09-20 15:00:00', 2);
INSERT INTO public.bookings VALUES (3341, 7, 22, '2012-09-20 16:00:00', 2);
INSERT INTO public.bookings VALUES (3342, 7, 15, '2012-09-20 17:30:00', 2);
INSERT INTO public.bookings VALUES (3343, 7, 8, '2012-09-20 18:30:00', 2);
INSERT INTO public.bookings VALUES (3344, 7, 33, '2012-09-20 19:30:00', 2);
INSERT INTO public.bookings VALUES (3345, 8, 33, '2012-09-20 08:00:00', 1);
INSERT INTO public.bookings VALUES (3346, 8, 24, '2012-09-20 08:30:00', 1);
INSERT INTO public.bookings VALUES (3347, 8, 20, '2012-09-20 09:00:00', 1);
INSERT INTO public.bookings VALUES (3348, 8, 3, '2012-09-20 10:00:00', 1);
INSERT INTO public.bookings VALUES (3349, 8, 20, '2012-09-20 10:30:00', 1);
INSERT INTO public.bookings VALUES (3350, 8, 24, '2012-09-20 11:00:00', 1);
INSERT INTO public.bookings VALUES (3351, 8, 28, '2012-09-20 11:30:00', 1);
INSERT INTO public.bookings VALUES (3352, 8, 3, '2012-09-20 12:00:00', 1);
INSERT INTO public.bookings VALUES (3353, 8, 33, '2012-09-20 12:30:00', 1);
INSERT INTO public.bookings VALUES (3354, 8, 16, '2012-09-20 13:00:00', 1);
INSERT INTO public.bookings VALUES (3355, 8, 21, '2012-09-20 13:30:00', 1);
INSERT INTO public.bookings VALUES (3356, 8, 28, '2012-09-20 14:00:00', 1);
INSERT INTO public.bookings VALUES (3357, 8, 3, '2012-09-20 16:00:00', 1);
INSERT INTO public.bookings VALUES (3358, 8, 0, '2012-09-20 19:00:00', 2);
INSERT INTO public.bookings VALUES (3359, 8, 16, '2012-09-20 20:00:00', 1);
INSERT INTO public.bookings VALUES (3360, 0, 26, '2012-09-21 08:00:00', 3);
INSERT INTO public.bookings VALUES (3361, 0, 11, '2012-09-21 09:30:00', 3);
INSERT INTO public.bookings VALUES (3362, 0, 22, '2012-09-21 12:00:00', 3);
INSERT INTO public.bookings VALUES (3363, 0, 16, '2012-09-21 13:30:00', 3);
INSERT INTO public.bookings VALUES (3364, 0, 5, '2012-09-21 15:30:00', 3);
INSERT INTO public.bookings VALUES (3365, 0, 17, '2012-09-21 17:00:00', 6);
INSERT INTO public.bookings VALUES (3366, 1, 12, '2012-09-21 08:00:00', 3);
INSERT INTO public.bookings VALUES (3367, 1, 16, '2012-09-21 10:00:00', 3);
INSERT INTO public.bookings VALUES (3368, 1, 1, '2012-09-21 11:30:00', 3);
INSERT INTO public.bookings VALUES (3369, 1, 9, '2012-09-21 14:00:00', 3);
INSERT INTO public.bookings VALUES (3370, 1, 10, '2012-09-21 16:00:00', 3);
INSERT INTO public.bookings VALUES (3371, 1, 27, '2012-09-21 18:00:00', 3);
INSERT INTO public.bookings VALUES (3372, 2, 9, '2012-09-21 09:00:00', 3);
INSERT INTO public.bookings VALUES (3373, 2, 21, '2012-09-21 10:30:00', 3);
INSERT INTO public.bookings VALUES (3374, 2, 9, '2012-09-21 12:00:00', 3);
INSERT INTO public.bookings VALUES (3375, 2, 0, '2012-09-21 14:00:00', 6);
INSERT INTO public.bookings VALUES (3376, 3, 29, '2012-09-21 09:00:00', 2);
INSERT INTO public.bookings VALUES (3377, 3, 30, '2012-09-21 10:00:00', 2);
INSERT INTO public.bookings VALUES (3378, 3, 2, '2012-09-21 11:00:00', 2);
INSERT INTO public.bookings VALUES (3379, 3, 20, '2012-09-21 13:00:00', 2);
INSERT INTO public.bookings VALUES (3380, 3, 21, '2012-09-21 14:00:00', 2);
INSERT INTO public.bookings VALUES (3381, 3, 4, '2012-09-21 15:30:00', 2);
INSERT INTO public.bookings VALUES (3382, 3, 30, '2012-09-21 16:30:00', 2);
INSERT INTO public.bookings VALUES (3383, 3, 29, '2012-09-21 18:30:00', 2);
INSERT INTO public.bookings VALUES (3384, 3, 1, '2012-09-21 19:30:00', 2);
INSERT INTO public.bookings VALUES (3385, 4, 16, '2012-09-21 08:30:00', 2);
INSERT INTO public.bookings VALUES (3386, 4, 14, '2012-09-21 09:30:00', 2);
INSERT INTO public.bookings VALUES (3387, 4, 0, '2012-09-21 10:30:00', 2);
INSERT INTO public.bookings VALUES (3388, 4, 8, '2012-09-21 11:30:00', 2);
INSERT INTO public.bookings VALUES (3389, 4, 0, '2012-09-21 13:00:00', 2);
INSERT INTO public.bookings VALUES (3390, 4, 14, '2012-09-21 14:30:00', 2);
INSERT INTO public.bookings VALUES (3391, 4, 0, '2012-09-21 15:30:00', 2);
INSERT INTO public.bookings VALUES (3392, 4, 9, '2012-09-21 16:30:00', 2);
INSERT INTO public.bookings VALUES (3393, 4, 1, '2012-09-21 17:30:00', 2);
INSERT INTO public.bookings VALUES (3394, 4, 3, '2012-09-21 18:30:00', 2);
INSERT INTO public.bookings VALUES (3395, 4, 20, '2012-09-21 19:30:00', 2);
INSERT INTO public.bookings VALUES (3396, 5, 15, '2012-09-21 12:00:00', 2);
INSERT INTO public.bookings VALUES (3397, 5, 0, '2012-09-21 17:30:00', 2);
INSERT INTO public.bookings VALUES (3398, 6, 0, '2012-09-21 09:30:00', 2);
INSERT INTO public.bookings VALUES (3399, 6, 13, '2012-09-21 10:30:00', 2);
INSERT INTO public.bookings VALUES (3400, 6, 0, '2012-09-21 11:30:00', 4);
INSERT INTO public.bookings VALUES (3401, 6, 0, '2012-09-21 14:00:00', 2);
INSERT INTO public.bookings VALUES (3402, 6, 12, '2012-09-21 15:30:00', 2);
INSERT INTO public.bookings VALUES (3403, 6, 12, '2012-09-21 17:30:00', 2);
INSERT INTO public.bookings VALUES (3404, 6, 14, '2012-09-21 18:30:00', 4);
INSERT INTO public.bookings VALUES (3405, 7, 21, '2012-09-21 08:30:00', 2);
INSERT INTO public.bookings VALUES (3406, 7, 5, '2012-09-21 09:30:00', 2);
INSERT INTO public.bookings VALUES (3407, 7, 10, '2012-09-21 11:30:00', 2);
INSERT INTO public.bookings VALUES (3408, 7, 24, '2012-09-21 13:00:00', 2);
INSERT INTO public.bookings VALUES (3409, 7, 4, '2012-09-21 14:30:00', 2);
INSERT INTO public.bookings VALUES (3410, 7, 24, '2012-09-21 16:00:00', 2);
INSERT INTO public.bookings VALUES (3411, 7, 13, '2012-09-21 17:00:00', 2);
INSERT INTO public.bookings VALUES (3412, 7, 5, '2012-09-21 19:00:00', 2);
INSERT INTO public.bookings VALUES (3413, 8, 33, '2012-09-21 08:30:00', 2);
INSERT INTO public.bookings VALUES (3414, 8, 21, '2012-09-21 09:30:00', 2);
INSERT INTO public.bookings VALUES (3415, 8, 28, '2012-09-21 10:30:00', 1);
INSERT INTO public.bookings VALUES (3416, 8, 3, '2012-09-21 11:00:00', 1);
INSERT INTO public.bookings VALUES (3417, 8, 29, '2012-09-21 12:30:00', 1);
INSERT INTO public.bookings VALUES (3418, 8, 12, '2012-09-21 13:00:00', 1);
INSERT INTO public.bookings VALUES (3419, 8, 28, '2012-09-21 14:00:00', 1);
INSERT INTO public.bookings VALUES (3420, 8, 29, '2012-09-21 14:30:00', 1);
INSERT INTO public.bookings VALUES (3421, 8, 6, '2012-09-21 15:00:00', 1);
INSERT INTO public.bookings VALUES (3422, 8, 3, '2012-09-21 16:00:00', 1);
INSERT INTO public.bookings VALUES (3423, 8, 15, '2012-09-21 16:30:00', 1);
INSERT INTO public.bookings VALUES (3424, 8, 8, '2012-09-21 17:00:00', 1);
INSERT INTO public.bookings VALUES (3425, 8, 29, '2012-09-21 18:00:00', 1);
INSERT INTO public.bookings VALUES (3426, 8, 33, '2012-09-21 18:30:00', 1);
INSERT INTO public.bookings VALUES (3427, 8, 30, '2012-09-21 19:00:00', 1);
INSERT INTO public.bookings VALUES (3428, 8, 3, '2012-09-21 19:30:00', 1);
INSERT INTO public.bookings VALUES (3429, 0, 0, '2012-09-22 08:30:00', 3);
INSERT INTO public.bookings VALUES (3430, 0, 11, '2012-09-22 10:00:00', 6);
INSERT INTO public.bookings VALUES (3431, 0, 0, '2012-09-22 13:00:00', 3);
INSERT INTO public.bookings VALUES (3432, 0, 6, '2012-09-22 15:00:00', 3);
INSERT INTO public.bookings VALUES (3433, 0, 14, '2012-09-22 16:30:00', 3);
INSERT INTO public.bookings VALUES (3434, 0, 10, '2012-09-22 18:00:00', 3);
INSERT INTO public.bookings VALUES (3435, 1, 5, '2012-09-22 09:00:00', 3);
INSERT INTO public.bookings VALUES (3436, 1, 10, '2012-09-22 11:00:00', 3);
INSERT INTO public.bookings VALUES (3437, 1, 8, '2012-09-22 12:30:00', 3);
INSERT INTO public.bookings VALUES (3438, 1, 15, '2012-09-22 14:00:00', 3);
INSERT INTO public.bookings VALUES (3439, 1, 12, '2012-09-22 16:00:00', 3);
INSERT INTO public.bookings VALUES (3440, 1, 0, '2012-09-22 17:30:00', 3);
INSERT INTO public.bookings VALUES (3441, 2, 24, '2012-09-22 08:00:00', 3);
INSERT INTO public.bookings VALUES (3442, 2, 0, '2012-09-22 09:30:00', 3);
INSERT INTO public.bookings VALUES (3443, 2, 1, '2012-09-22 11:30:00', 3);
INSERT INTO public.bookings VALUES (3444, 2, 2, '2012-09-22 13:30:00', 3);
INSERT INTO public.bookings VALUES (3445, 2, 1, '2012-09-22 15:30:00', 3);
INSERT INTO public.bookings VALUES (3446, 2, 24, '2012-09-22 17:00:00', 3);
INSERT INTO public.bookings VALUES (3447, 3, 29, '2012-09-22 08:30:00', 2);
INSERT INTO public.bookings VALUES (3448, 3, 20, '2012-09-22 11:00:00', 2);
INSERT INTO public.bookings VALUES (3449, 3, 21, '2012-09-22 13:00:00', 2);
INSERT INTO public.bookings VALUES (3450, 3, 30, '2012-09-22 16:30:00', 2);
INSERT INTO public.bookings VALUES (3451, 3, 22, '2012-09-22 18:30:00', 4);
INSERT INTO public.bookings VALUES (3452, 4, 0, '2012-09-22 08:00:00', 2);
INSERT INTO public.bookings VALUES (3453, 4, 14, '2012-09-22 09:00:00', 2);
INSERT INTO public.bookings VALUES (3454, 4, 7, '2012-09-22 10:00:00', 2);
INSERT INTO public.bookings VALUES (3455, 4, 0, '2012-09-22 11:00:00', 2);
INSERT INTO public.bookings VALUES (3456, 4, 24, '2012-09-22 12:00:00', 2);
INSERT INTO public.bookings VALUES (3457, 4, 0, '2012-09-22 13:00:00', 2);
INSERT INTO public.bookings VALUES (3458, 4, 16, '2012-09-22 14:00:00', 2);
INSERT INTO public.bookings VALUES (3459, 4, 0, '2012-09-22 15:00:00', 8);
INSERT INTO public.bookings VALUES (3460, 4, 2, '2012-09-22 19:00:00', 2);
INSERT INTO public.bookings VALUES (3461, 5, 0, '2012-09-22 12:30:00', 2);
INSERT INTO public.bookings VALUES (3462, 6, 6, '2012-09-22 09:00:00', 2);
INSERT INTO public.bookings VALUES (3463, 6, 0, '2012-09-22 10:30:00', 2);
INSERT INTO public.bookings VALUES (3464, 6, 4, '2012-09-22 11:30:00', 2);
INSERT INTO public.bookings VALUES (3465, 6, 12, '2012-09-22 12:30:00', 2);
INSERT INTO public.bookings VALUES (3466, 6, 0, '2012-09-22 13:30:00', 2);
INSERT INTO public.bookings VALUES (3467, 6, 8, '2012-09-22 14:30:00', 2);
INSERT INTO public.bookings VALUES (3468, 6, 0, '2012-09-22 15:30:00', 4);
INSERT INTO public.bookings VALUES (3469, 6, 12, '2012-09-22 17:30:00', 2);
INSERT INTO public.bookings VALUES (3470, 7, 10, '2012-09-22 08:00:00', 2);
INSERT INTO public.bookings VALUES (3471, 7, 4, '2012-09-22 09:30:00', 2);
INSERT INTO public.bookings VALUES (3472, 7, 27, '2012-09-22 11:00:00', 2);
INSERT INTO public.bookings VALUES (3473, 7, 4, '2012-09-22 13:00:00', 2);
INSERT INTO public.bookings VALUES (3474, 7, 30, '2012-09-22 15:00:00', 2);
INSERT INTO public.bookings VALUES (3475, 7, 33, '2012-09-22 16:00:00', 2);
INSERT INTO public.bookings VALUES (3476, 7, 17, '2012-09-22 18:00:00', 2);
INSERT INTO public.bookings VALUES (3477, 7, 27, '2012-09-22 19:00:00', 2);
INSERT INTO public.bookings VALUES (3478, 8, 22, '2012-09-22 08:00:00', 1);
INSERT INTO public.bookings VALUES (3479, 8, 28, '2012-09-22 08:30:00', 1);
INSERT INTO public.bookings VALUES (3480, 8, 17, '2012-09-22 09:30:00', 1);
INSERT INTO public.bookings VALUES (3481, 8, 21, '2012-09-22 10:00:00', 1);
INSERT INTO public.bookings VALUES (3482, 8, 21, '2012-09-22 11:30:00', 1);
INSERT INTO public.bookings VALUES (3483, 8, 22, '2012-09-22 12:00:00', 1);
INSERT INTO public.bookings VALUES (3484, 8, 29, '2012-09-22 13:30:00', 1);
INSERT INTO public.bookings VALUES (3485, 8, 24, '2012-09-22 15:30:00', 1);
INSERT INTO public.bookings VALUES (3486, 8, 3, '2012-09-22 16:30:00', 1);
INSERT INTO public.bookings VALUES (3487, 8, 28, '2012-09-22 17:00:00', 1);
INSERT INTO public.bookings VALUES (3488, 8, 3, '2012-09-22 18:30:00', 2);
INSERT INTO public.bookings VALUES (3489, 8, 21, '2012-09-22 19:30:00', 1);
INSERT INTO public.bookings VALUES (3490, 8, 11, '2012-09-22 20:00:00', 1);
INSERT INTO public.bookings VALUES (3491, 0, 7, '2012-09-23 08:00:00', 3);
INSERT INTO public.bookings VALUES (3492, 0, 10, '2012-09-23 09:30:00', 3);
INSERT INTO public.bookings VALUES (3493, 0, 15, '2012-09-23 11:00:00', 3);
INSERT INTO public.bookings VALUES (3494, 0, 26, '2012-09-23 12:30:00', 3);
INSERT INTO public.bookings VALUES (3495, 0, 35, '2012-09-23 14:00:00', 3);
INSERT INTO public.bookings VALUES (3496, 0, 2, '2012-09-23 16:30:00', 3);
INSERT INTO public.bookings VALUES (3497, 0, 17, '2012-09-23 18:00:00', 3);
INSERT INTO public.bookings VALUES (3498, 1, 0, '2012-09-23 08:30:00', 3);
INSERT INTO public.bookings VALUES (3499, 1, 24, '2012-09-23 10:30:00', 3);
INSERT INTO public.bookings VALUES (3500, 1, 8, '2012-09-23 12:00:00', 3);
INSERT INTO public.bookings VALUES (3501, 1, 24, '2012-09-23 13:30:00', 3);
INSERT INTO public.bookings VALUES (3502, 1, 15, '2012-09-23 15:00:00', 3);
INSERT INTO public.bookings VALUES (3503, 1, 35, '2012-09-23 16:30:00', 3);
INSERT INTO public.bookings VALUES (3504, 1, 0, '2012-09-23 18:00:00', 3);
INSERT INTO public.bookings VALUES (3505, 2, 1, '2012-09-23 08:00:00', 3);
INSERT INTO public.bookings VALUES (3506, 2, 1, '2012-09-23 11:00:00', 3);
INSERT INTO public.bookings VALUES (3507, 2, 16, '2012-09-23 12:30:00', 3);
INSERT INTO public.bookings VALUES (3508, 2, 29, '2012-09-23 14:00:00', 3);
INSERT INTO public.bookings VALUES (3509, 2, 9, '2012-09-23 15:30:00', 3);
INSERT INTO public.bookings VALUES (3510, 2, 7, '2012-09-23 17:00:00', 3);
INSERT INTO public.bookings VALUES (3511, 3, 3, '2012-09-23 08:00:00', 2);
INSERT INTO public.bookings VALUES (3512, 3, 22, '2012-09-23 09:30:00', 2);
INSERT INTO public.bookings VALUES (3513, 3, 3, '2012-09-23 10:30:00', 2);
INSERT INTO public.bookings VALUES (3514, 3, 22, '2012-09-23 12:30:00', 2);
INSERT INTO public.bookings VALUES (3515, 3, 15, '2012-09-23 13:30:00', 2);
INSERT INTO public.bookings VALUES (3516, 3, 22, '2012-09-23 15:00:00', 2);
INSERT INTO public.bookings VALUES (3517, 3, 3, '2012-09-23 16:00:00', 2);
INSERT INTO public.bookings VALUES (3518, 3, 22, '2012-09-23 17:30:00', 2);
INSERT INTO public.bookings VALUES (3519, 3, 10, '2012-09-23 19:00:00', 2);
INSERT INTO public.bookings VALUES (3520, 4, 11, '2012-09-23 08:00:00', 2);
INSERT INTO public.bookings VALUES (3521, 4, 16, '2012-09-23 09:30:00', 2);
INSERT INTO public.bookings VALUES (3522, 4, 9, '2012-09-23 10:30:00', 2);
INSERT INTO public.bookings VALUES (3523, 4, 0, '2012-09-23 11:30:00', 2);
INSERT INTO public.bookings VALUES (3524, 4, 6, '2012-09-23 12:30:00', 2);
INSERT INTO public.bookings VALUES (3525, 4, 13, '2012-09-23 13:30:00', 4);
INSERT INTO public.bookings VALUES (3526, 4, 22, '2012-09-23 16:00:00', 2);
INSERT INTO public.bookings VALUES (3527, 4, 0, '2012-09-23 17:00:00', 2);
INSERT INTO public.bookings VALUES (3528, 4, 11, '2012-09-23 18:00:00', 2);
INSERT INTO public.bookings VALUES (3529, 4, 1, '2012-09-23 19:00:00', 2);
INSERT INTO public.bookings VALUES (3530, 5, 0, '2012-09-23 15:00:00', 2);
INSERT INTO public.bookings VALUES (3531, 6, 0, '2012-09-23 08:00:00', 4);
INSERT INTO public.bookings VALUES (3532, 6, 0, '2012-09-23 10:30:00', 2);
INSERT INTO public.bookings VALUES (3533, 6, 0, '2012-09-23 12:00:00', 2);
INSERT INTO public.bookings VALUES (3534, 6, 0, '2012-09-23 13:30:00', 6);
INSERT INTO public.bookings VALUES (3535, 6, 12, '2012-09-23 16:30:00', 2);
INSERT INTO public.bookings VALUES (3536, 6, 15, '2012-09-23 17:30:00', 2);
INSERT INTO public.bookings VALUES (3537, 6, 0, '2012-09-23 19:00:00', 2);
INSERT INTO public.bookings VALUES (3538, 7, 8, '2012-09-23 09:00:00', 2);
INSERT INTO public.bookings VALUES (3539, 7, 17, '2012-09-23 10:00:00', 2);
INSERT INTO public.bookings VALUES (3540, 7, 9, '2012-09-23 11:30:00', 2);
INSERT INTO public.bookings VALUES (3541, 7, 27, '2012-09-23 15:00:00', 2);
INSERT INTO public.bookings VALUES (3542, 7, 15, '2012-09-23 16:30:00', 2);
INSERT INTO public.bookings VALUES (3543, 7, 14, '2012-09-23 17:30:00', 2);
INSERT INTO public.bookings VALUES (3544, 7, 0, '2012-09-23 19:00:00', 2);
INSERT INTO public.bookings VALUES (3545, 8, 33, '2012-09-23 08:00:00', 1);
INSERT INTO public.bookings VALUES (3546, 8, 28, '2012-09-23 08:30:00', 1);
INSERT INTO public.bookings VALUES (3547, 8, 0, '2012-09-23 09:00:00', 1);
INSERT INTO public.bookings VALUES (3548, 8, 3, '2012-09-23 09:30:00', 1);
INSERT INTO public.bookings VALUES (3549, 8, 0, '2012-09-23 10:00:00', 1);
INSERT INTO public.bookings VALUES (3550, 8, 29, '2012-09-23 10:30:00', 1);
INSERT INTO public.bookings VALUES (3551, 8, 3, '2012-09-23 11:30:00', 1);
INSERT INTO public.bookings VALUES (3552, 8, 30, '2012-09-23 12:00:00', 1);
INSERT INTO public.bookings VALUES (3553, 8, 21, '2012-09-23 13:00:00', 2);
INSERT INTO public.bookings VALUES (3554, 8, 0, '2012-09-23 15:00:00', 1);
INSERT INTO public.bookings VALUES (3555, 8, 16, '2012-09-23 15:30:00', 1);
INSERT INTO public.bookings VALUES (3556, 8, 13, '2012-09-23 16:00:00', 1);
INSERT INTO public.bookings VALUES (3557, 8, 6, '2012-09-23 16:30:00', 1);
INSERT INTO public.bookings VALUES (3558, 8, 29, '2012-09-23 17:00:00', 1);
INSERT INTO public.bookings VALUES (3559, 8, 28, '2012-09-23 17:30:00', 1);
INSERT INTO public.bookings VALUES (3560, 8, 6, '2012-09-23 18:00:00', 1);
INSERT INTO public.bookings VALUES (3561, 8, 28, '2012-09-23 19:00:00', 1);
INSERT INTO public.bookings VALUES (3562, 8, 29, '2012-09-23 19:30:00', 1);
INSERT INTO public.bookings VALUES (3563, 0, 0, '2012-09-24 08:00:00', 9);
INSERT INTO public.bookings VALUES (3564, 0, 35, '2012-09-24 12:30:00', 3);
INSERT INTO public.bookings VALUES (3565, 0, 0, '2012-09-24 14:00:00', 3);
INSERT INTO public.bookings VALUES (3566, 0, 14, '2012-09-24 15:30:00', 6);
INSERT INTO public.bookings VALUES (3567, 0, 11, '2012-09-24 18:30:00', 3);
INSERT INTO public.bookings VALUES (3568, 1, 28, '2012-09-24 08:00:00', 3);
INSERT INTO public.bookings VALUES (3569, 1, 10, '2012-09-24 09:30:00', 3);
INSERT INTO public.bookings VALUES (3570, 1, 10, '2012-09-24 12:00:00', 6);
INSERT INTO public.bookings VALUES (3571, 1, 16, '2012-09-24 15:00:00', 3);
INSERT INTO public.bookings VALUES (3572, 1, 0, '2012-09-24 16:30:00', 3);
INSERT INTO public.bookings VALUES (3573, 1, 24, '2012-09-24 19:00:00', 3);
INSERT INTO public.bookings VALUES (3574, 2, 21, '2012-09-24 08:00:00', 3);
INSERT INTO public.bookings VALUES (3575, 2, 0, '2012-09-24 09:30:00', 3);
INSERT INTO public.bookings VALUES (3576, 2, 1, '2012-09-24 11:30:00', 3);
INSERT INTO public.bookings VALUES (3577, 2, 3, '2012-09-24 13:00:00', 3);
INSERT INTO public.bookings VALUES (3578, 2, 12, '2012-09-24 14:30:00', 3);
INSERT INTO public.bookings VALUES (3579, 2, 7, '2012-09-24 16:30:00', 3);
INSERT INTO public.bookings VALUES (3580, 2, 3, '2012-09-24 18:00:00', 3);
INSERT INTO public.bookings VALUES (3581, 3, 0, '2012-09-24 08:00:00', 2);
INSERT INTO public.bookings VALUES (3582, 3, 21, '2012-09-24 09:30:00', 2);
INSERT INTO public.bookings VALUES (3583, 3, 16, '2012-09-24 12:00:00', 2);
INSERT INTO public.bookings VALUES (3584, 3, 15, '2012-09-24 13:00:00', 2);
INSERT INTO public.bookings VALUES (3585, 3, 2, '2012-09-24 14:30:00', 2);
INSERT INTO public.bookings VALUES (3586, 3, 20, '2012-09-24 15:30:00', 2);
INSERT INTO public.bookings VALUES (3587, 3, 22, '2012-09-24 17:00:00', 2);
INSERT INTO public.bookings VALUES (3588, 3, 16, '2012-09-24 18:00:00', 2);
INSERT INTO public.bookings VALUES (3589, 3, 0, '2012-09-24 19:00:00', 2);
INSERT INTO public.bookings VALUES (3590, 4, 11, '2012-09-24 08:00:00', 2);
INSERT INTO public.bookings VALUES (3591, 4, 14, '2012-09-24 09:00:00', 2);
INSERT INTO public.bookings VALUES (3592, 4, 0, '2012-09-24 10:30:00', 2);
INSERT INTO public.bookings VALUES (3593, 4, 0, '2012-09-24 12:00:00', 2);
INSERT INTO public.bookings VALUES (3594, 4, 20, '2012-09-24 13:00:00', 2);
INSERT INTO public.bookings VALUES (3595, 4, 0, '2012-09-24 14:00:00', 2);
INSERT INTO public.bookings VALUES (3596, 4, 8, '2012-09-24 15:00:00', 2);
INSERT INTO public.bookings VALUES (3597, 4, 6, '2012-09-24 16:00:00', 2);
INSERT INTO public.bookings VALUES (3598, 4, 8, '2012-09-24 17:00:00', 2);
INSERT INTO public.bookings VALUES (3599, 4, 35, '2012-09-24 18:00:00', 2);
INSERT INTO public.bookings VALUES (3600, 4, 0, '2012-09-24 19:00:00', 2);
INSERT INTO public.bookings VALUES (3601, 5, 14, '2012-09-24 11:00:00', 2);
INSERT INTO public.bookings VALUES (3602, 5, 0, '2012-09-24 14:00:00', 2);
INSERT INTO public.bookings VALUES (3603, 6, 0, '2012-09-24 08:00:00', 2);
INSERT INTO public.bookings VALUES (3604, 6, 9, '2012-09-24 09:30:00', 2);
INSERT INTO public.bookings VALUES (3605, 6, 0, '2012-09-24 10:30:00', 2);
INSERT INTO public.bookings VALUES (3606, 6, 0, '2012-09-24 12:00:00', 4);
INSERT INTO public.bookings VALUES (3607, 6, 14, '2012-09-24 14:00:00', 2);
INSERT INTO public.bookings VALUES (3608, 6, 0, '2012-09-24 15:00:00', 4);
INSERT INTO public.bookings VALUES (3609, 6, 12, '2012-09-24 17:00:00', 2);
INSERT INTO public.bookings VALUES (3610, 6, 33, '2012-09-24 18:00:00', 2);
INSERT INTO public.bookings VALUES (3611, 6, 17, '2012-09-24 19:00:00', 2);
INSERT INTO public.bookings VALUES (3612, 7, 24, '2012-09-24 08:30:00', 2);
INSERT INTO public.bookings VALUES (3613, 7, 22, '2012-09-24 13:00:00', 2);
INSERT INTO public.bookings VALUES (3614, 7, 9, '2012-09-24 14:30:00', 2);
INSERT INTO public.bookings VALUES (3615, 7, 17, '2012-09-24 15:30:00', 2);
INSERT INTO public.bookings VALUES (3616, 7, 28, '2012-09-24 16:30:00', 2);
INSERT INTO public.bookings VALUES (3617, 7, 10, '2012-09-24 17:30:00', 2);
INSERT INTO public.bookings VALUES (3618, 7, 8, '2012-09-24 19:00:00', 2);
INSERT INTO public.bookings VALUES (3619, 8, 0, '2012-09-24 08:00:00', 1);
INSERT INTO public.bookings VALUES (3620, 8, 29, '2012-09-24 08:30:00', 1);
INSERT INTO public.bookings VALUES (3621, 8, 0, '2012-09-24 09:00:00', 1);
INSERT INTO public.bookings VALUES (3622, 8, 3, '2012-09-24 09:30:00', 2);
INSERT INTO public.bookings VALUES (3623, 8, 8, '2012-09-24 10:30:00', 1);
INSERT INTO public.bookings VALUES (3624, 8, 0, '2012-09-24 12:00:00', 1);
INSERT INTO public.bookings VALUES (3625, 8, 28, '2012-09-24 12:30:00', 1);
INSERT INTO public.bookings VALUES (3626, 8, 21, '2012-09-24 13:30:00', 1);
INSERT INTO public.bookings VALUES (3627, 8, 2, '2012-09-24 14:00:00', 1);
INSERT INTO public.bookings VALUES (3628, 8, 3, '2012-09-24 14:30:00', 1);
INSERT INTO public.bookings VALUES (3629, 8, 2, '2012-09-24 16:00:00', 1);
INSERT INTO public.bookings VALUES (3630, 8, 22, '2012-09-24 16:30:00', 1);
INSERT INTO public.bookings VALUES (3631, 8, 0, '2012-09-24 17:00:00', 1);
INSERT INTO public.bookings VALUES (3632, 8, 29, '2012-09-24 17:30:00', 1);
INSERT INTO public.bookings VALUES (3633, 8, 16, '2012-09-24 19:00:00', 1);
INSERT INTO public.bookings VALUES (3634, 8, 29, '2012-09-24 19:30:00', 1);
INSERT INTO public.bookings VALUES (3635, 0, 12, '2012-09-25 08:00:00', 3);
INSERT INTO public.bookings VALUES (3636, 0, 2, '2012-09-25 09:30:00', 6);
INSERT INTO public.bookings VALUES (3637, 0, 16, '2012-09-25 13:00:00', 3);
INSERT INTO public.bookings VALUES (3638, 0, 0, '2012-09-25 15:00:00', 6);
INSERT INTO public.bookings VALUES (3639, 0, 11, '2012-09-25 18:00:00', 3);
INSERT INTO public.bookings VALUES (3640, 1, 9, '2012-09-25 08:00:00', 3);
INSERT INTO public.bookings VALUES (3641, 1, 12, '2012-09-25 10:00:00', 3);
INSERT INTO public.bookings VALUES (3642, 1, 0, '2012-09-25 11:30:00', 3);
INSERT INTO public.bookings VALUES (3643, 1, 12, '2012-09-25 13:00:00', 3);
INSERT INTO public.bookings VALUES (3644, 1, 11, '2012-09-25 14:30:00', 3);
INSERT INTO public.bookings VALUES (3645, 1, 35, '2012-09-25 16:30:00', 3);
INSERT INTO public.bookings VALUES (3646, 1, 0, '2012-09-25 18:30:00', 3);
INSERT INTO public.bookings VALUES (3647, 2, 29, '2012-09-25 08:00:00', 6);
INSERT INTO public.bookings VALUES (3648, 2, 11, '2012-09-25 11:30:00', 3);
INSERT INTO public.bookings VALUES (3649, 2, 13, '2012-09-25 14:30:00', 3);
INSERT INTO public.bookings VALUES (3650, 2, 0, '2012-09-25 16:00:00', 3);
INSERT INTO public.bookings VALUES (3651, 2, 33, '2012-09-25 17:30:00', 3);
INSERT INTO public.bookings VALUES (3652, 3, 20, '2012-09-25 08:00:00', 2);
INSERT INTO public.bookings VALUES (3653, 3, 17, '2012-09-25 11:00:00', 2);
INSERT INTO public.bookings VALUES (3654, 3, 22, '2012-09-25 12:30:00', 2);
INSERT INTO public.bookings VALUES (3655, 3, 35, '2012-09-25 13:30:00', 2);
INSERT INTO public.bookings VALUES (3656, 3, 20, '2012-09-25 17:30:00', 2);
INSERT INTO public.bookings VALUES (3657, 3, 17, '2012-09-25 19:00:00', 2);
INSERT INTO public.bookings VALUES (3658, 4, 8, '2012-09-25 08:00:00', 2);
INSERT INTO public.bookings VALUES (3659, 4, 20, '2012-09-25 09:00:00', 2);
INSERT INTO public.bookings VALUES (3660, 4, 14, '2012-09-25 10:00:00', 2);
INSERT INTO public.bookings VALUES (3661, 4, 0, '2012-09-25 11:30:00', 4);
INSERT INTO public.bookings VALUES (3662, 4, 8, '2012-09-25 13:30:00', 2);
INSERT INTO public.bookings VALUES (3663, 4, 3, '2012-09-25 14:30:00', 2);
INSERT INTO public.bookings VALUES (3664, 4, 0, '2012-09-25 15:30:00', 2);
INSERT INTO public.bookings VALUES (3665, 4, 20, '2012-09-25 16:30:00', 2);
INSERT INTO public.bookings VALUES (3666, 4, 4, '2012-09-25 17:30:00', 2);
INSERT INTO public.bookings VALUES (3667, 4, 6, '2012-09-25 18:30:00', 2);
INSERT INTO public.bookings VALUES (3668, 4, 3, '2012-09-25 19:30:00', 2);
INSERT INTO public.bookings VALUES (3669, 5, 0, '2012-09-25 08:30:00', 2);
INSERT INTO public.bookings VALUES (3670, 5, 0, '2012-09-25 11:30:00', 2);
INSERT INTO public.bookings VALUES (3671, 5, 0, '2012-09-25 16:00:00', 2);
INSERT INTO public.bookings VALUES (3672, 6, 0, '2012-09-25 08:00:00', 4);
INSERT INTO public.bookings VALUES (3673, 6, 8, '2012-09-25 10:00:00', 2);
INSERT INTO public.bookings VALUES (3674, 6, 0, '2012-09-25 11:00:00', 2);
INSERT INTO public.bookings VALUES (3675, 6, 2, '2012-09-25 12:30:00', 2);
INSERT INTO public.bookings VALUES (3676, 6, 0, '2012-09-25 14:00:00', 2);
INSERT INTO public.bookings VALUES (3677, 6, 0, '2012-09-25 15:30:00', 4);
INSERT INTO public.bookings VALUES (3678, 7, 21, '2012-09-25 09:30:00', 2);
INSERT INTO public.bookings VALUES (3679, 7, 10, '2012-09-25 12:30:00', 2);
INSERT INTO public.bookings VALUES (3680, 7, 0, '2012-09-25 13:30:00', 2);
INSERT INTO public.bookings VALUES (3681, 7, 7, '2012-09-25 14:30:00', 2);
INSERT INTO public.bookings VALUES (3682, 7, 33, '2012-09-25 15:30:00', 4);
INSERT INTO public.bookings VALUES (3683, 7, 2, '2012-09-25 18:30:00', 2);
INSERT INTO public.bookings VALUES (3684, 8, 15, '2012-09-25 08:00:00', 1);
INSERT INTO public.bookings VALUES (3685, 8, 21, '2012-09-25 09:00:00', 1);
INSERT INTO public.bookings VALUES (3686, 8, 3, '2012-09-25 09:30:00', 1);
INSERT INTO public.bookings VALUES (3687, 8, 29, '2012-09-25 12:30:00', 1);
INSERT INTO public.bookings VALUES (3688, 8, 3, '2012-09-25 13:30:00', 1);
INSERT INTO public.bookings VALUES (3689, 8, 29, '2012-09-25 14:00:00', 1);
INSERT INTO public.bookings VALUES (3690, 8, 16, '2012-09-25 15:00:00', 1);
INSERT INTO public.bookings VALUES (3691, 8, 28, '2012-09-25 15:30:00', 1);
INSERT INTO public.bookings VALUES (3692, 8, 28, '2012-09-25 17:00:00', 1);
INSERT INTO public.bookings VALUES (3693, 8, 21, '2012-09-25 17:30:00', 1);
INSERT INTO public.bookings VALUES (3694, 8, 3, '2012-09-25 18:30:00', 1);
INSERT INTO public.bookings VALUES (3695, 8, 16, '2012-09-25 19:00:00', 1);
INSERT INTO public.bookings VALUES (3696, 8, 33, '2012-09-25 19:30:00', 1);
INSERT INTO public.bookings VALUES (3697, 0, 5, '2012-09-26 08:00:00', 3);
INSERT INTO public.bookings VALUES (3698, 0, 0, '2012-09-26 09:30:00', 3);
INSERT INTO public.bookings VALUES (3699, 0, 6, '2012-09-26 11:00:00', 3);
INSERT INTO public.bookings VALUES (3700, 0, 11, '2012-09-26 13:30:00', 3);
INSERT INTO public.bookings VALUES (3701, 0, 0, '2012-09-26 15:00:00', 6);
INSERT INTO public.bookings VALUES (3702, 0, 22, '2012-09-26 18:00:00', 3);
INSERT INTO public.bookings VALUES (3703, 1, 0, '2012-09-26 08:00:00', 3);
INSERT INTO public.bookings VALUES (3704, 1, 0, '2012-09-26 10:30:00', 3);
INSERT INTO public.bookings VALUES (3705, 1, 9, '2012-09-26 12:00:00', 3);
INSERT INTO public.bookings VALUES (3706, 1, 35, '2012-09-26 14:00:00', 3);
INSERT INTO public.bookings VALUES (3707, 1, 12, '2012-09-26 15:30:00', 6);
INSERT INTO public.bookings VALUES (3708, 1, 11, '2012-09-26 18:30:00', 3);
INSERT INTO public.bookings VALUES (3709, 2, 1, '2012-09-26 08:00:00', 3);
INSERT INTO public.bookings VALUES (3710, 2, 2, '2012-09-26 09:30:00', 3);
INSERT INTO public.bookings VALUES (3711, 2, 10, '2012-09-26 11:00:00', 3);
INSERT INTO public.bookings VALUES (3712, 2, 1, '2012-09-26 12:30:00', 3);
INSERT INTO public.bookings VALUES (3713, 2, 0, '2012-09-26 14:00:00', 3);
INSERT INTO public.bookings VALUES (3714, 2, 1, '2012-09-26 15:30:00', 3);
INSERT INTO public.bookings VALUES (3715, 2, 17, '2012-09-26 17:00:00', 3);
INSERT INTO public.bookings VALUES (3716, 2, 12, '2012-09-26 18:30:00', 3);
INSERT INTO public.bookings VALUES (3717, 3, 15, '2012-09-26 11:00:00', 2);
INSERT INTO public.bookings VALUES (3718, 3, 30, '2012-09-26 12:00:00', 2);
INSERT INTO public.bookings VALUES (3719, 3, 3, '2012-09-26 15:00:00', 2);
INSERT INTO public.bookings VALUES (3720, 3, 22, '2012-09-26 16:00:00', 2);
INSERT INTO public.bookings VALUES (3721, 3, 15, '2012-09-26 18:30:00', 2);
INSERT INTO public.bookings VALUES (3722, 3, 9, '2012-09-26 19:30:00', 2);
INSERT INTO public.bookings VALUES (3723, 4, 3, '2012-09-26 08:00:00', 2);
INSERT INTO public.bookings VALUES (3724, 4, 0, '2012-09-26 09:00:00', 2);
INSERT INTO public.bookings VALUES (3725, 4, 33, '2012-09-26 10:00:00', 2);
INSERT INTO public.bookings VALUES (3726, 4, 20, '2012-09-26 11:00:00', 4);
INSERT INTO public.bookings VALUES (3727, 4, 29, '2012-09-26 13:00:00', 2);
INSERT INTO public.bookings VALUES (3728, 4, 0, '2012-09-26 14:00:00', 2);
INSERT INTO public.bookings VALUES (3729, 4, 5, '2012-09-26 15:30:00', 2);
INSERT INTO public.bookings VALUES (3730, 4, 0, '2012-09-26 16:30:00', 2);
INSERT INTO public.bookings VALUES (3731, 4, 14, '2012-09-26 17:30:00', 2);
INSERT INTO public.bookings VALUES (3732, 4, 20, '2012-09-26 18:30:00', 2);
INSERT INTO public.bookings VALUES (3733, 5, 0, '2012-09-26 18:30:00', 2);
INSERT INTO public.bookings VALUES (3734, 6, 0, '2012-09-26 08:00:00', 2);
INSERT INTO public.bookings VALUES (3735, 6, 0, '2012-09-26 09:30:00', 2);
INSERT INTO public.bookings VALUES (3736, 6, 30, '2012-09-26 10:30:00', 2);
INSERT INTO public.bookings VALUES (3737, 6, 0, '2012-09-26 11:30:00', 2);
INSERT INTO public.bookings VALUES (3738, 6, 0, '2012-09-26 13:00:00', 8);
INSERT INTO public.bookings VALUES (3739, 6, 10, '2012-09-26 17:00:00', 2);
INSERT INTO public.bookings VALUES (3740, 6, 21, '2012-09-26 18:00:00', 2);
INSERT INTO public.bookings VALUES (3741, 6, 0, '2012-09-26 19:00:00', 2);
INSERT INTO public.bookings VALUES (3742, 7, 7, '2012-09-26 09:00:00', 2);
INSERT INTO public.bookings VALUES (3743, 7, 24, '2012-09-26 10:30:00', 2);
INSERT INTO public.bookings VALUES (3744, 7, 5, '2012-09-26 11:30:00', 2);
INSERT INTO public.bookings VALUES (3745, 7, 27, '2012-09-26 14:30:00', 2);
INSERT INTO public.bookings VALUES (3746, 7, 24, '2012-09-26 16:00:00', 2);
INSERT INTO public.bookings VALUES (3747, 7, 5, '2012-09-26 17:30:00', 2);
INSERT INTO public.bookings VALUES (3748, 8, 0, '2012-09-26 08:30:00', 1);
INSERT INTO public.bookings VALUES (3749, 8, 30, '2012-09-26 09:00:00', 1);
INSERT INTO public.bookings VALUES (3750, 8, 16, '2012-09-26 09:30:00', 1);
INSERT INTO public.bookings VALUES (3751, 8, 21, '2012-09-26 10:00:00', 1);
INSERT INTO public.bookings VALUES (3752, 8, 29, '2012-09-26 10:30:00', 1);
INSERT INTO public.bookings VALUES (3753, 8, 16, '2012-09-26 11:30:00', 1);
INSERT INTO public.bookings VALUES (3754, 8, 29, '2012-09-26 12:00:00', 2);
INSERT INTO public.bookings VALUES (3755, 8, 28, '2012-09-26 13:00:00', 1);
INSERT INTO public.bookings VALUES (3756, 8, 3, '2012-09-26 14:00:00', 2);
INSERT INTO public.bookings VALUES (3757, 8, 20, '2012-09-26 15:30:00', 1);
INSERT INTO public.bookings VALUES (3758, 8, 3, '2012-09-26 16:00:00', 1);
INSERT INTO public.bookings VALUES (3759, 8, 28, '2012-09-26 17:00:00', 1);
INSERT INTO public.bookings VALUES (3760, 8, 21, '2012-09-26 19:00:00', 1);
INSERT INTO public.bookings VALUES (3761, 8, 29, '2012-09-26 19:30:00', 1);
INSERT INTO public.bookings VALUES (3762, 8, 24, '2012-09-26 20:00:00', 1);
INSERT INTO public.bookings VALUES (3763, 0, 11, '2012-09-27 09:00:00', 3);
INSERT INTO public.bookings VALUES (3764, 0, 6, '2012-09-27 11:00:00', 3);
INSERT INTO public.bookings VALUES (3765, 0, 17, '2012-09-27 13:00:00', 3);
INSERT INTO public.bookings VALUES (3766, 0, 26, '2012-09-27 16:00:00', 3);
INSERT INTO public.bookings VALUES (3767, 0, 0, '2012-09-27 17:30:00', 6);
INSERT INTO public.bookings VALUES (3768, 1, 0, '2012-09-27 08:00:00', 9);
INSERT INTO public.bookings VALUES (3769, 1, 8, '2012-09-27 12:30:00', 3);
INSERT INTO public.bookings VALUES (3770, 1, 0, '2012-09-27 14:30:00', 3);
INSERT INTO public.bookings VALUES (3771, 1, 35, '2012-09-27 16:00:00', 3);
INSERT INTO public.bookings VALUES (3772, 1, 10, '2012-09-27 17:30:00', 3);
INSERT INTO public.bookings VALUES (3773, 2, 1, '2012-09-27 08:00:00', 3);
INSERT INTO public.bookings VALUES (3774, 2, 24, '2012-09-27 10:00:00', 3);
INSERT INTO public.bookings VALUES (3775, 2, 36, '2012-09-27 11:30:00', 3);
INSERT INTO public.bookings VALUES (3776, 2, 30, '2012-09-27 15:30:00', 3);
INSERT INTO public.bookings VALUES (3777, 2, 11, '2012-09-27 17:30:00', 3);
INSERT INTO public.bookings VALUES (3778, 2, 2, '2012-09-27 19:00:00', 3);
INSERT INTO public.bookings VALUES (3779, 3, 15, '2012-09-27 08:30:00', 2);
INSERT INTO public.bookings VALUES (3780, 3, 22, '2012-09-27 09:30:00', 2);
INSERT INTO public.bookings VALUES (3781, 3, 0, '2012-09-27 12:00:00', 2);
INSERT INTO public.bookings VALUES (3782, 3, 15, '2012-09-27 13:00:00', 2);
INSERT INTO public.bookings VALUES (3783, 3, 15, '2012-09-27 15:30:00', 2);
INSERT INTO public.bookings VALUES (3784, 3, 20, '2012-09-27 17:30:00', 2);
INSERT INTO public.bookings VALUES (3785, 3, 0, '2012-09-27 18:30:00', 2);
INSERT INTO public.bookings VALUES (3786, 4, 0, '2012-09-27 08:00:00', 2);
INSERT INTO public.bookings VALUES (3787, 4, 24, '2012-09-27 09:00:00', 2);
INSERT INTO public.bookings VALUES (3788, 4, 35, '2012-09-27 10:00:00', 2);
INSERT INTO public.bookings VALUES (3789, 4, 20, '2012-09-27 11:00:00', 2);
INSERT INTO public.bookings VALUES (3790, 4, 0, '2012-09-27 12:00:00', 2);
INSERT INTO public.bookings VALUES (3791, 4, 12, '2012-09-27 13:00:00', 2);
INSERT INTO public.bookings VALUES (3792, 4, 24, '2012-09-27 14:00:00', 2);
INSERT INTO public.bookings VALUES (3793, 4, 36, '2012-09-27 15:00:00', 2);
INSERT INTO public.bookings VALUES (3794, 4, 0, '2012-09-27 16:00:00', 2);
INSERT INTO public.bookings VALUES (3795, 4, 7, '2012-09-27 17:00:00', 2);
INSERT INTO public.bookings VALUES (3796, 4, 35, '2012-09-27 18:00:00', 2);
INSERT INTO public.bookings VALUES (3797, 4, 6, '2012-09-27 19:00:00', 2);
INSERT INTO public.bookings VALUES (3798, 5, 0, '2012-09-27 10:30:00', 2);
INSERT INTO public.bookings VALUES (3799, 5, 22, '2012-09-27 16:30:00', 2);
INSERT INTO public.bookings VALUES (3800, 6, 0, '2012-09-27 08:00:00', 2);
INSERT INTO public.bookings VALUES (3801, 6, 12, '2012-09-27 09:30:00', 2);
INSERT INTO public.bookings VALUES (3802, 6, 0, '2012-09-27 10:30:00', 2);
INSERT INTO public.bookings VALUES (3803, 6, 0, '2012-09-27 12:00:00', 6);
INSERT INTO public.bookings VALUES (3804, 6, 12, '2012-09-27 15:00:00', 4);
INSERT INTO public.bookings VALUES (3805, 6, 0, '2012-09-27 19:00:00', 2);
INSERT INTO public.bookings VALUES (3806, 7, 24, '2012-09-27 08:00:00', 2);
INSERT INTO public.bookings VALUES (3807, 7, 4, '2012-09-27 09:30:00', 2);
INSERT INTO public.bookings VALUES (3808, 7, 10, '2012-09-27 12:00:00', 2);
INSERT INTO public.bookings VALUES (3809, 7, 10, '2012-09-27 13:30:00', 2);
INSERT INTO public.bookings VALUES (3810, 7, 8, '2012-09-27 15:00:00', 2);
INSERT INTO public.bookings VALUES (3811, 7, 9, '2012-09-27 16:00:00', 2);
INSERT INTO public.bookings VALUES (3812, 7, 24, '2012-09-27 18:30:00', 2);
INSERT INTO public.bookings VALUES (3813, 7, 17, '2012-09-27 19:30:00', 2);
INSERT INTO public.bookings VALUES (3814, 8, 28, '2012-09-27 08:00:00', 1);
INSERT INTO public.bookings VALUES (3815, 8, 2, '2012-09-27 08:30:00', 1);
INSERT INTO public.bookings VALUES (3816, 8, 29, '2012-09-27 09:00:00', 1);
INSERT INTO public.bookings VALUES (3817, 8, 33, '2012-09-27 10:30:00', 1);
INSERT INTO public.bookings VALUES (3818, 8, 3, '2012-09-27 11:00:00', 1);
INSERT INTO public.bookings VALUES (3819, 8, 29, '2012-09-27 13:30:00', 1);
INSERT INTO public.bookings VALUES (3820, 8, 22, '2012-09-27 14:00:00', 1);
INSERT INTO public.bookings VALUES (3821, 8, 29, '2012-09-27 15:00:00', 1);
INSERT INTO public.bookings VALUES (3822, 8, 0, '2012-09-27 15:30:00', 1);
INSERT INTO public.bookings VALUES (3823, 8, 20, '2012-09-27 16:00:00', 1);
INSERT INTO public.bookings VALUES (3824, 8, 8, '2012-09-27 16:30:00', 1);
INSERT INTO public.bookings VALUES (3825, 8, 16, '2012-09-27 17:00:00', 1);
INSERT INTO public.bookings VALUES (3826, 8, 27, '2012-09-27 18:00:00', 1);
INSERT INTO public.bookings VALUES (3827, 8, 3, '2012-09-27 19:30:00', 1);
INSERT INTO public.bookings VALUES (3828, 8, 29, '2012-09-27 20:00:00', 1);
INSERT INTO public.bookings VALUES (3829, 0, 35, '2012-09-28 08:30:00', 3);
INSERT INTO public.bookings VALUES (3830, 0, 16, '2012-09-28 10:00:00', 3);
INSERT INTO public.bookings VALUES (3831, 0, 28, '2012-09-28 11:30:00', 3);
INSERT INTO public.bookings VALUES (3832, 0, 0, '2012-09-28 13:00:00', 3);
INSERT INTO public.bookings VALUES (3833, 0, 0, '2012-09-28 15:00:00', 3);
INSERT INTO public.bookings VALUES (3834, 0, 0, '2012-09-28 17:00:00', 3);
INSERT INTO public.bookings VALUES (3835, 1, 10, '2012-09-28 08:00:00', 3);
INSERT INTO public.bookings VALUES (3836, 1, 0, '2012-09-28 09:30:00', 9);
INSERT INTO public.bookings VALUES (3837, 1, 8, '2012-09-28 14:00:00', 3);
INSERT INTO public.bookings VALUES (3838, 1, 0, '2012-09-28 15:30:00', 3);
INSERT INTO public.bookings VALUES (3839, 1, 0, '2012-09-28 17:30:00', 6);
INSERT INTO public.bookings VALUES (3840, 2, 2, '2012-09-28 08:00:00', 3);
INSERT INTO public.bookings VALUES (3841, 2, 21, '2012-09-28 09:30:00', 3);
INSERT INTO public.bookings VALUES (3842, 2, 21, '2012-09-28 11:30:00', 3);
INSERT INTO public.bookings VALUES (3843, 2, 1, '2012-09-28 13:00:00', 3);
INSERT INTO public.bookings VALUES (3844, 2, 5, '2012-09-28 14:30:00', 3);
INSERT INTO public.bookings VALUES (3845, 2, 17, '2012-09-28 16:00:00', 3);
INSERT INTO public.bookings VALUES (3846, 2, 0, '2012-09-28 17:30:00', 3);
INSERT INTO public.bookings VALUES (3847, 2, 1, '2012-09-28 19:00:00', 3);
INSERT INTO public.bookings VALUES (3848, 3, 30, '2012-09-28 09:00:00', 2);
INSERT INTO public.bookings VALUES (3849, 3, 15, '2012-09-28 10:30:00', 2);
INSERT INTO public.bookings VALUES (3850, 3, 13, '2012-09-28 11:30:00', 2);
INSERT INTO public.bookings VALUES (3851, 3, 22, '2012-09-28 12:30:00', 2);
INSERT INTO public.bookings VALUES (3852, 3, 15, '2012-09-28 14:00:00', 2);
INSERT INTO public.bookings VALUES (3853, 3, 24, '2012-09-28 15:30:00', 2);
INSERT INTO public.bookings VALUES (3854, 3, 22, '2012-09-28 17:30:00', 2);
INSERT INTO public.bookings VALUES (3855, 3, 20, '2012-09-28 19:00:00', 2);
INSERT INTO public.bookings VALUES (3856, 4, 24, '2012-09-28 08:00:00', 2);
INSERT INTO public.bookings VALUES (3857, 4, 0, '2012-09-28 09:00:00', 4);
INSERT INTO public.bookings VALUES (3858, 4, 14, '2012-09-28 11:30:00', 2);
INSERT INTO public.bookings VALUES (3859, 4, 0, '2012-09-28 12:30:00', 4);
INSERT INTO public.bookings VALUES (3860, 4, 16, '2012-09-28 14:30:00', 2);
INSERT INTO public.bookings VALUES (3861, 4, 0, '2012-09-28 15:30:00', 2);
INSERT INTO public.bookings VALUES (3862, 4, 5, '2012-09-28 16:30:00', 2);
INSERT INTO public.bookings VALUES (3863, 4, 0, '2012-09-28 17:30:00', 2);
INSERT INTO public.bookings VALUES (3864, 4, 8, '2012-09-28 18:30:00', 2);
INSERT INTO public.bookings VALUES (3865, 4, 7, '2012-09-28 19:30:00', 2);
INSERT INTO public.bookings VALUES (3866, 5, 0, '2012-09-28 10:30:00', 2);
INSERT INTO public.bookings VALUES (3867, 5, 0, '2012-09-28 13:00:00', 2);
INSERT INTO public.bookings VALUES (3868, 5, 11, '2012-09-28 16:00:00', 2);
INSERT INTO public.bookings VALUES (3869, 5, 0, '2012-09-28 17:00:00', 4);
INSERT INTO public.bookings VALUES (3870, 6, 0, '2012-09-28 08:00:00', 6);
INSERT INTO public.bookings VALUES (3871, 6, 12, '2012-09-28 11:00:00', 2);
INSERT INTO public.bookings VALUES (3872, 6, 0, '2012-09-28 12:00:00', 2);
INSERT INTO public.bookings VALUES (3873, 6, 16, '2012-09-28 13:30:00', 2);
INSERT INTO public.bookings VALUES (3874, 6, 0, '2012-09-28 14:30:00', 2);
INSERT INTO public.bookings VALUES (3875, 6, 0, '2012-09-28 16:00:00', 6);
INSERT INTO public.bookings VALUES (3876, 6, 12, '2012-09-28 19:30:00', 2);
INSERT INTO public.bookings VALUES (3877, 7, 17, '2012-09-28 08:00:00', 2);
INSERT INTO public.bookings VALUES (3878, 7, 27, '2012-09-28 09:00:00', 2);
INSERT INTO public.bookings VALUES (3879, 7, 9, '2012-09-28 12:00:00', 2);
INSERT INTO public.bookings VALUES (3880, 7, 21, '2012-09-28 13:30:00', 2);
INSERT INTO public.bookings VALUES (3881, 7, 27, '2012-09-28 15:00:00', 2);
INSERT INTO public.bookings VALUES (3882, 7, 8, '2012-09-28 16:30:00', 2);
INSERT INTO public.bookings VALUES (3883, 7, 6, '2012-09-28 18:00:00', 2);
INSERT INTO public.bookings VALUES (3884, 8, 21, '2012-09-28 08:00:00', 1);
INSERT INTO public.bookings VALUES (3885, 8, 28, '2012-09-28 09:30:00', 1);
INSERT INTO public.bookings VALUES (3886, 8, 3, '2012-09-28 10:30:00', 1);
INSERT INTO public.bookings VALUES (3887, 8, 3, '2012-09-28 12:00:00', 1);
INSERT INTO public.bookings VALUES (3888, 8, 29, '2012-09-28 12:30:00', 1);
INSERT INTO public.bookings VALUES (3889, 8, 28, '2012-09-28 13:00:00', 1);
INSERT INTO public.bookings VALUES (3890, 8, 3, '2012-09-28 13:30:00', 2);
INSERT INTO public.bookings VALUES (3891, 8, 30, '2012-09-28 15:30:00', 1);
INSERT INTO public.bookings VALUES (3892, 8, 12, '2012-09-28 16:30:00', 1);
INSERT INTO public.bookings VALUES (3893, 8, 0, '2012-09-28 17:00:00', 1);
INSERT INTO public.bookings VALUES (3894, 8, 3, '2012-09-28 17:30:00', 1);
INSERT INTO public.bookings VALUES (3895, 8, 29, '2012-09-28 18:00:00', 1);
INSERT INTO public.bookings VALUES (3896, 8, 10, '2012-09-28 18:30:00', 1);
INSERT INTO public.bookings VALUES (3897, 8, 21, '2012-09-28 19:30:00', 1);
INSERT INTO public.bookings VALUES (3898, 8, 16, '2012-09-28 20:00:00', 1);
INSERT INTO public.bookings VALUES (3899, 0, 0, '2012-09-29 08:00:00', 3);
INSERT INTO public.bookings VALUES (3900, 0, 11, '2012-09-29 11:30:00', 6);
INSERT INTO public.bookings VALUES (3901, 0, 6, '2012-09-29 14:30:00', 3);
INSERT INTO public.bookings VALUES (3902, 0, 28, '2012-09-29 16:00:00', 3);
INSERT INTO public.bookings VALUES (3903, 0, 20, '2012-09-29 17:30:00', 3);
INSERT INTO public.bookings VALUES (3904, 1, 0, '2012-09-29 10:00:00', 3);
INSERT INTO public.bookings VALUES (3905, 1, 8, '2012-09-29 11:30:00', 3);
INSERT INTO public.bookings VALUES (3906, 1, 10, '2012-09-29 13:00:00', 3);
INSERT INTO public.bookings VALUES (3907, 1, 12, '2012-09-29 14:30:00', 3);
INSERT INTO public.bookings VALUES (3908, 1, 0, '2012-09-29 16:00:00', 3);
INSERT INTO public.bookings VALUES (3909, 1, 10, '2012-09-29 18:00:00', 3);
INSERT INTO public.bookings VALUES (3910, 2, 1, '2012-09-29 08:00:00', 3);
INSERT INTO public.bookings VALUES (3911, 2, 36, '2012-09-29 09:30:00', 3);
INSERT INTO public.bookings VALUES (3912, 2, 14, '2012-09-29 11:00:00', 3);
INSERT INTO public.bookings VALUES (3913, 2, 21, '2012-09-29 12:30:00', 3);
INSERT INTO public.bookings VALUES (3914, 2, 1, '2012-09-29 14:00:00', 3);
INSERT INTO public.bookings VALUES (3915, 2, 24, '2012-09-29 15:30:00', 3);
INSERT INTO public.bookings VALUES (3916, 2, 12, '2012-09-29 17:00:00', 3);
INSERT INTO public.bookings VALUES (3917, 2, 16, '2012-09-29 18:30:00', 3);
INSERT INTO public.bookings VALUES (3918, 3, 2, '2012-09-29 08:30:00', 2);
INSERT INTO public.bookings VALUES (3919, 3, 21, '2012-09-29 09:30:00', 2);
INSERT INTO public.bookings VALUES (3920, 3, 6, '2012-09-29 11:00:00', 2);
INSERT INTO public.bookings VALUES (3921, 3, 13, '2012-09-29 13:00:00', 2);
INSERT INTO public.bookings VALUES (3922, 3, 16, '2012-09-29 14:00:00', 2);
INSERT INTO public.bookings VALUES (3923, 3, 20, '2012-09-29 16:00:00', 2);
INSERT INTO public.bookings VALUES (3924, 3, 21, '2012-09-29 19:30:00', 2);
INSERT INTO public.bookings VALUES (3925, 4, 16, '2012-09-29 08:00:00', 2);
INSERT INTO public.bookings VALUES (3926, 4, 0, '2012-09-29 09:30:00', 2);
INSERT INTO public.bookings VALUES (3927, 4, 3, '2012-09-29 10:30:00', 2);
INSERT INTO public.bookings VALUES (3928, 4, 20, '2012-09-29 11:30:00', 2);
INSERT INTO public.bookings VALUES (3929, 4, 5, '2012-09-29 12:30:00', 2);
INSERT INTO public.bookings VALUES (3930, 4, 0, '2012-09-29 13:30:00', 2);
INSERT INTO public.bookings VALUES (3931, 4, 3, '2012-09-29 14:30:00', 2);
INSERT INTO public.bookings VALUES (3932, 4, 0, '2012-09-29 15:30:00', 2);
INSERT INTO public.bookings VALUES (3933, 4, 16, '2012-09-29 16:30:00', 2);
INSERT INTO public.bookings VALUES (3934, 4, 13, '2012-09-29 17:30:00', 2);
INSERT INTO public.bookings VALUES (3935, 4, 36, '2012-09-29 18:30:00', 2);
INSERT INTO public.bookings VALUES (3936, 4, 24, '2012-09-29 19:30:00', 2);
INSERT INTO public.bookings VALUES (3937, 5, 0, '2012-09-29 12:30:00', 2);
INSERT INTO public.bookings VALUES (3938, 6, 6, '2012-09-29 08:00:00', 2);
INSERT INTO public.bookings VALUES (3939, 6, 0, '2012-09-29 09:00:00', 4);
INSERT INTO public.bookings VALUES (3940, 6, 24, '2012-09-29 11:00:00', 2);
INSERT INTO public.bookings VALUES (3941, 6, 0, '2012-09-29 12:00:00', 2);
INSERT INTO public.bookings VALUES (3942, 6, 12, '2012-09-29 13:00:00', 2);
INSERT INTO public.bookings VALUES (3943, 6, 0, '2012-09-29 14:00:00', 2);
INSERT INTO public.bookings VALUES (3944, 6, 27, '2012-09-29 17:00:00', 2);
INSERT INTO public.bookings VALUES (3945, 6, 0, '2012-09-29 18:00:00', 4);
INSERT INTO public.bookings VALUES (3946, 7, 8, '2012-09-29 08:30:00', 2);
INSERT INTO public.bookings VALUES (3947, 7, 4, '2012-09-29 10:00:00', 2);
INSERT INTO public.bookings VALUES (3948, 7, 0, '2012-09-29 12:30:00', 2);
INSERT INTO public.bookings VALUES (3949, 7, 24, '2012-09-29 13:30:00', 2);
INSERT INTO public.bookings VALUES (3950, 7, 8, '2012-09-29 14:30:00', 2);
INSERT INTO public.bookings VALUES (3951, 7, 27, '2012-09-29 15:30:00', 2);
INSERT INTO public.bookings VALUES (3952, 7, 8, '2012-09-29 16:30:00', 2);
INSERT INTO public.bookings VALUES (3953, 7, 15, '2012-09-29 18:30:00', 2);
INSERT INTO public.bookings VALUES (3954, 7, 27, '2012-09-29 19:30:00', 2);
INSERT INTO public.bookings VALUES (3955, 8, 12, '2012-09-29 08:00:00', 1);
INSERT INTO public.bookings VALUES (3956, 8, 3, '2012-09-29 08:30:00', 1);
INSERT INTO public.bookings VALUES (3957, 8, 21, '2012-09-29 09:00:00', 1);
INSERT INTO public.bookings VALUES (3958, 8, 29, '2012-09-29 10:00:00', 1);
INSERT INTO public.bookings VALUES (3959, 8, 28, '2012-09-29 10:30:00', 1);
INSERT INTO public.bookings VALUES (3960, 8, 2, '2012-09-29 11:00:00', 2);
INSERT INTO public.bookings VALUES (3961, 8, 29, '2012-09-29 12:00:00', 2);
INSERT INTO public.bookings VALUES (3962, 8, 20, '2012-09-29 13:00:00', 1);
INSERT INTO public.bookings VALUES (3963, 8, 28, '2012-09-29 13:30:00', 1);
INSERT INTO public.bookings VALUES (3964, 8, 3, '2012-09-29 14:00:00', 1);
INSERT INTO public.bookings VALUES (3965, 8, 28, '2012-09-29 14:30:00', 1);
INSERT INTO public.bookings VALUES (3966, 8, 12, '2012-09-29 16:00:00', 1);
INSERT INTO public.bookings VALUES (3967, 8, 26, '2012-09-29 16:30:00', 1);
INSERT INTO public.bookings VALUES (3968, 8, 15, '2012-09-29 17:00:00', 1);
INSERT INTO public.bookings VALUES (3969, 8, 28, '2012-09-29 17:30:00', 1);
INSERT INTO public.bookings VALUES (3970, 8, 29, '2012-09-29 18:00:00', 2);
INSERT INTO public.bookings VALUES (3971, 8, 4, '2012-09-29 19:30:00', 1);
INSERT INTO public.bookings VALUES (3972, 8, 33, '2012-09-29 20:00:00', 1);
INSERT INTO public.bookings VALUES (3973, 0, 4, '2012-09-30 08:00:00', 3);
INSERT INTO public.bookings VALUES (3974, 0, 35, '2012-09-30 09:30:00', 3);
INSERT INTO public.bookings VALUES (3975, 0, 0, '2012-09-30 11:00:00', 6);
INSERT INTO public.bookings VALUES (3976, 0, 36, '2012-09-30 14:00:00', 3);
INSERT INTO public.bookings VALUES (3977, 0, 24, '2012-09-30 16:00:00', 3);
INSERT INTO public.bookings VALUES (3978, 0, 0, '2012-09-30 17:30:00', 3);
INSERT INTO public.bookings VALUES (3979, 0, 24, '2012-09-30 19:00:00', 3);
INSERT INTO public.bookings VALUES (3980, 1, 8, '2012-09-30 08:30:00', 3);
INSERT INTO public.bookings VALUES (3981, 1, 0, '2012-09-30 10:00:00', 3);
INSERT INTO public.bookings VALUES (3982, 1, 10, '2012-09-30 11:30:00', 3);
INSERT INTO public.bookings VALUES (3983, 1, 11, '2012-09-30 13:30:00', 6);
INSERT INTO public.bookings VALUES (3984, 1, 10, '2012-09-30 16:30:00', 3);
INSERT INTO public.bookings VALUES (3985, 1, 8, '2012-09-30 18:30:00', 3);
INSERT INTO public.bookings VALUES (3986, 2, 1, '2012-09-30 08:00:00', 3);
INSERT INTO public.bookings VALUES (3987, 2, 17, '2012-09-30 09:30:00', 3);
INSERT INTO public.bookings VALUES (3988, 2, 29, '2012-09-30 11:00:00', 3);
INSERT INTO public.bookings VALUES (3989, 2, 35, '2012-09-30 12:30:00', 3);
INSERT INTO public.bookings VALUES (3990, 2, 1, '2012-09-30 14:00:00', 6);
INSERT INTO public.bookings VALUES (3991, 2, 5, '2012-09-30 17:00:00', 3);
INSERT INTO public.bookings VALUES (3992, 2, 35, '2012-09-30 18:30:00', 3);
INSERT INTO public.bookings VALUES (3993, 3, 24, '2012-09-30 08:00:00', 2);
INSERT INTO public.bookings VALUES (3994, 3, 3, '2012-09-30 09:30:00', 2);
INSERT INTO public.bookings VALUES (3995, 3, 36, '2012-09-30 10:30:00', 2);
INSERT INTO public.bookings VALUES (3996, 3, 36, '2012-09-30 12:00:00', 2);
INSERT INTO public.bookings VALUES (3997, 3, 0, '2012-09-30 14:30:00', 2);
INSERT INTO public.bookings VALUES (3998, 3, 1, '2012-09-30 18:30:00', 2);
INSERT INTO public.bookings VALUES (3999, 4, 13, '2012-09-30 08:00:00', 2);
INSERT INTO public.bookings VALUES (4000, 4, 16, '2012-09-30 09:00:00', 2);
INSERT INTO public.bookings VALUES (4001, 4, 0, '2012-09-30 10:00:00', 2);
INSERT INTO public.bookings VALUES (4002, 4, 20, '2012-09-30 11:00:00', 2);
INSERT INTO public.bookings VALUES (4003, 4, 4, '2012-09-30 12:30:00', 2);
INSERT INTO public.bookings VALUES (4004, 4, 3, '2012-09-30 13:30:00', 2);
INSERT INTO public.bookings VALUES (4005, 4, 20, '2012-09-30 15:00:00', 2);
INSERT INTO public.bookings VALUES (4006, 4, 0, '2012-09-30 16:00:00', 2);
INSERT INTO public.bookings VALUES (4007, 4, 3, '2012-09-30 17:00:00', 2);
INSERT INTO public.bookings VALUES (4008, 4, 0, '2012-09-30 18:00:00', 2);
INSERT INTO public.bookings VALUES (4009, 5, 0, '2012-09-30 11:30:00', 2);
INSERT INTO public.bookings VALUES (4010, 5, 0, '2012-09-30 19:30:00', 2);
INSERT INTO public.bookings VALUES (4011, 6, 0, '2012-09-30 08:00:00', 2);
INSERT INTO public.bookings VALUES (4012, 6, 27, '2012-09-30 09:30:00', 2);
INSERT INTO public.bookings VALUES (4013, 6, 0, '2012-09-30 11:00:00', 2);
INSERT INTO public.bookings VALUES (4014, 6, 0, '2012-09-30 12:30:00', 2);
INSERT INTO public.bookings VALUES (4015, 6, 12, '2012-09-30 14:00:00', 2);
INSERT INTO public.bookings VALUES (4016, 6, 0, '2012-09-30 15:30:00', 2);
INSERT INTO public.bookings VALUES (4017, 6, 35, '2012-09-30 16:30:00', 2);
INSERT INTO public.bookings VALUES (4018, 6, 0, '2012-09-30 17:30:00', 2);
INSERT INTO public.bookings VALUES (4019, 6, 0, '2012-09-30 19:00:00', 2);
INSERT INTO public.bookings VALUES (4020, 7, 27, '2012-09-30 08:30:00', 2);
INSERT INTO public.bookings VALUES (4021, 7, 33, '2012-09-30 09:30:00', 2);
INSERT INTO public.bookings VALUES (4022, 7, 33, '2012-09-30 11:00:00', 2);
INSERT INTO public.bookings VALUES (4023, 7, 5, '2012-09-30 14:30:00', 2);
INSERT INTO public.bookings VALUES (4024, 7, 15, '2012-09-30 16:30:00', 2);
INSERT INTO public.bookings VALUES (4025, 7, 24, '2012-09-30 17:30:00', 2);
INSERT INTO public.bookings VALUES (4026, 7, 5, '2012-09-30 19:00:00', 2);
INSERT INTO public.bookings VALUES (4027, 8, 16, '2012-09-30 08:00:00', 1);
INSERT INTO public.bookings VALUES (4028, 8, 21, '2012-09-30 08:30:00', 2);
INSERT INTO public.bookings VALUES (4029, 8, 3, '2012-09-30 10:30:00', 1);
INSERT INTO public.bookings VALUES (4030, 8, 16, '2012-09-30 11:00:00', 1);
INSERT INTO public.bookings VALUES (4031, 8, 3, '2012-09-30 11:30:00', 1);
INSERT INTO public.bookings VALUES (4032, 8, 17, '2012-09-30 12:00:00', 1);
INSERT INTO public.bookings VALUES (4033, 8, 21, '2012-09-30 12:30:00', 1);
INSERT INTO public.bookings VALUES (4034, 8, 3, '2012-09-30 13:00:00', 1);
INSERT INTO public.bookings VALUES (4035, 8, 29, '2012-09-30 13:30:00', 1);
INSERT INTO public.bookings VALUES (4036, 8, 28, '2012-09-30 14:30:00', 1);
INSERT INTO public.bookings VALUES (4037, 8, 29, '2012-09-30 15:30:00', 1);
INSERT INTO public.bookings VALUES (4038, 8, 29, '2012-09-30 16:30:00', 2);
INSERT INTO public.bookings VALUES (4039, 8, 29, '2012-09-30 18:00:00', 1);
INSERT INTO public.bookings VALUES (4040, 8, 21, '2012-09-30 18:30:00', 1);
INSERT INTO public.bookings VALUES (4041, 8, 16, '2012-09-30 19:00:00', 1);
INSERT INTO public.bookings VALUES (4042, 8, 29, '2012-09-30 19:30:00', 1);
INSERT INTO public.bookings VALUES (4043, 8, 5, '2013-01-01 15:30:00', 1);


--
-- Data for Name: dndclasses; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.dndclasses VALUES (1, NULL, 'Warrior');
INSERT INTO public.dndclasses VALUES (2, NULL, 'Wizard');
INSERT INTO public.dndclasses VALUES (3, NULL, 'Priest');
INSERT INTO public.dndclasses VALUES (4, NULL, 'Rogue');
INSERT INTO public.dndclasses VALUES (5, 1, 'Fighter');
INSERT INTO public.dndclasses VALUES (6, 1, 'Paladin');
INSERT INTO public.dndclasses VALUES (7, 1, 'Ranger');
INSERT INTO public.dndclasses VALUES (8, 2, 'Mage');
INSERT INTO public.dndclasses VALUES (9, 2, 'Specialist wizard');
INSERT INTO public.dndclasses VALUES (10, 3, 'Cleric');
INSERT INTO public.dndclasses VALUES (11, 3, 'Druid');
INSERT INTO public.dndclasses VALUES (12, 3, 'Priest of specific mythos');
INSERT INTO public.dndclasses VALUES (13, 4, 'Thief');
INSERT INTO public.dndclasses VALUES (14, 4, 'Bard');
INSERT INTO public.dndclasses VALUES (15, 13, 'Assassin');


--
-- Data for Name: facilities; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.facilities VALUES (0, 'Tennis Court 1', 5, 25, 10000, 200);
INSERT INTO public.facilities VALUES (1, 'Tennis Court 2', 5, 25, 8000, 200);
INSERT INTO public.facilities VALUES (2, 'Badminton Court', 0, 15.5, 4000, 50);
INSERT INTO public.facilities VALUES (3, 'Table Tennis', 0, 5, 320, 10);
INSERT INTO public.facilities VALUES (4, 'Massage Room 1', 35, 80, 4000, 3000);
INSERT INTO public.facilities VALUES (5, 'Massage Room 2', 35, 80, 4000, 3000);
INSERT INTO public.facilities VALUES (6, 'Squash Court', 3.5, 17.5, 5000, 80);
INSERT INTO public.facilities VALUES (7, 'Snooker Table', 0, 5, 450, 15);
INSERT INTO public.facilities VALUES (8, 'Pool Table', 0, 5, 400, 15);


--
-- Data for Name: foo; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.foo VALUES (1, 2, 'three');
INSERT INTO public.foo VALUES (4, 5, 'six');


--
-- Data for Name: members; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.members VALUES (0, 'GUEST', 'GUEST', 'GUEST', 0, '(000) 000-0000', NULL, '2012-07-01 00:00:00');
INSERT INTO public.members VALUES (1, 'Smith', 'Darren', '8 Bloomsbury Close, Boston', 4321, '555-555-5555', NULL, '2012-07-02 12:02:05');
INSERT INTO public.members VALUES (2, 'Smith', 'Tracy', '8 Bloomsbury Close, New York', 4321, '555-555-5555', NULL, '2012-07-02 12:08:23');
INSERT INTO public.members VALUES (3, 'Rownam', 'Tim', '23 Highway Way, Boston', 23423, '(844) 693-0723', NULL, '2012-07-03 09:32:15');
INSERT INTO public.members VALUES (4, 'Joplette', 'Janice', '20 Crossing Road, New York', 234, '(833) 942-4710', 1, '2012-07-03 10:25:05');
INSERT INTO public.members VALUES (5, 'Butters', 'Gerald', '1065 Huntingdon Avenue, Boston', 56754, '(844) 078-4130', 1, '2012-07-09 10:44:09');
INSERT INTO public.members VALUES (6, 'Tracy', 'Burton', '3 Tunisia Drive, Boston', 45678, '(822) 354-9973', NULL, '2012-07-15 08:52:55');
INSERT INTO public.members VALUES (7, 'Dare', 'Nancy', '6 Hunting Lodge Way, Boston', 10383, '(833) 776-4001', 4, '2012-07-25 08:59:12');
INSERT INTO public.members VALUES (8, 'Boothe', 'Tim', '3 Bloomsbury Close, Reading, 00234', 234, '(811) 433-2547', 3, '2012-07-25 16:02:35');
INSERT INTO public.members VALUES (9, 'Stibbons', 'Ponder', '5 Dragons Way, Winchester', 87630, '(833) 160-3900', 6, '2012-07-25 17:09:05');
INSERT INTO public.members VALUES (10, 'Owen', 'Charles', '52 Cheshire Grove, Winchester, 28563', 28563, '(855) 542-5251', 1, '2012-08-03 19:42:37');
INSERT INTO public.members VALUES (11, 'Jones', 'David', '976 Gnats Close, Reading', 33862, '(844) 536-8036', 4, '2012-08-06 16:32:55');
INSERT INTO public.members VALUES (12, 'Baker', 'Anne', '55 Powdery Street, Boston', 80743, '844-076-5141', 9, '2012-08-10 14:23:22');
INSERT INTO public.members VALUES (13, 'Farrell', 'Jemima', '103 Firth Avenue, North Reading', 57392, '(855) 016-0163', NULL, '2012-08-10 14:28:01');
INSERT INTO public.members VALUES (14, 'Smith', 'Jack', '252 Binkington Way, Boston', 69302, '(822) 163-3254', 1, '2012-08-10 16:22:05');
INSERT INTO public.members VALUES (15, 'Bader', 'Florence', '264 Ursula Drive, Westford', 84923, '(833) 499-3527', 9, '2012-08-10 17:52:03');
INSERT INTO public.members VALUES (16, 'Baker', 'Timothy', '329 James Street, Reading', 58393, '833-941-0824', 13, '2012-08-15 10:34:25');
INSERT INTO public.members VALUES (17, 'Pinker', 'David', '5 Impreza Road, Boston', 65332, '811 409-6734', 13, '2012-08-16 11:32:47');
INSERT INTO public.members VALUES (20, 'Genting', 'Matthew', '4 Nunnington Place, Wingfield, Boston', 52365, '(811) 972-1377', 5, '2012-08-19 14:55:55');
INSERT INTO public.members VALUES (21, 'Mackenzie', 'Anna', '64 Perkington Lane, Reading', 64577, '(822) 661-2898', 1, '2012-08-26 09:32:05');
INSERT INTO public.members VALUES (22, 'Coplin', 'Joan', '85 Bard Street, Bloomington, Boston', 43533, '(822) 499-2232', 16, '2012-08-29 08:32:41');
INSERT INTO public.members VALUES (24, 'Sarwin', 'Ramnaresh', '12 Bullington Lane, Boston', 65464, '(822) 413-1470', 15, '2012-09-01 08:44:42');
INSERT INTO public.members VALUES (26, 'Jones', 'Douglas', '976 Gnats Close, Reading', 11986, '844 536-8036', 11, '2012-09-02 18:43:05');
INSERT INTO public.members VALUES (27, 'Rumney', 'Henrietta', '3 Burkington Plaza, Boston', 78533, '(822) 989-8876', 20, '2012-09-05 08:42:35');
INSERT INTO public.members VALUES (28, 'Farrell', 'David', '437 Granite Farm Road, Westford', 43532, '(855) 755-9876', NULL, '2012-09-15 08:22:05');
INSERT INTO public.members VALUES (29, 'Worthington-Smyth', 'Henry', '55 Jagbi Way, North Reading', 97676, '(855) 894-3758', 2, '2012-09-17 12:27:15');
INSERT INTO public.members VALUES (30, 'Purview', 'Millicent', '641 Drudgery Close, Burnington, Boston', 34232, '(855) 941-9786', 2, '2012-09-18 19:04:01');
INSERT INTO public.members VALUES (33, 'Tupperware', 'Hyacinth', '33 Cheerful Plaza, Drake Road, Westford', 68666, '(822) 665-5327', NULL, '2012-09-18 19:32:05');
INSERT INTO public.members VALUES (35, 'Hunt', 'John', '5 Bullington Lane, Boston', 54333, '(899) 720-6978', 30, '2012-09-19 11:32:45');
INSERT INTO public.members VALUES (36, 'Crumpet', 'Erica', 'Crimson Road, North Reading', 75655, '(811) 732-4816', 2, '2012-09-22 08:36:38');
INSERT INTO public.members VALUES (37, 'Smith', 'Darren', '3 Funktown, Denzington, Boston', 66796, '(822) 577-3541', NULL, '2012-09-26 18:08:45');


--
-- Data for Name: onlyfib; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.onlyfib VALUES (5);
INSERT INTO public.onlyfib VALUES (8);


--
-- Data for Name: payroll; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.payroll VALUES (1, 'Mark Stone', 'Accounting', 16000.00);
INSERT INTO public.payroll VALUES (2, 'Maria Stone', 'Accounting', 13000.00);
INSERT INTO public.payroll VALUES (3, 'Geetha Singh', 'Accounting', 13000.00);
INSERT INTO public.payroll VALUES (4, 'Richard Hathaway', 'Accounting', 14000.00);
INSERT INTO public.payroll VALUES (5, 'Joseph Bastion', 'Accounting', 14000.00);
INSERT INTO public.payroll VALUES (6, 'Arthur Prince', 'Production', 12000.00);
INSERT INTO public.payroll VALUES (7, 'Adele Morse', 'Production', 13000.00);
INSERT INTO public.payroll VALUES (8, 'Sheamus O Kelly', 'Production', 24000.00);
INSERT INTO public.payroll VALUES (9, 'Sheilah Flask', 'Production', 24000.00);
INSERT INTO public.payroll VALUES (10, 'Brian James', 'Production', 16000.00);
INSERT INTO public.payroll VALUES (11, 'Adam Scott', 'Production', 16000.00);
INSERT INTO public.payroll VALUES (12, 'Maurice Moss', 'IT', 12000.00);
INSERT INTO public.payroll VALUES (13, 'Roy', 'IT', 12001.00);
INSERT INTO public.payroll VALUES (14, 'Jen Barber', 'IT', 28000.00);
INSERT INTO public.payroll VALUES (15, 'Richard Hammond', 'IT', 10000.00);
INSERT INTO public.payroll VALUES (16, 'James May', 'IT', 10000.00);
INSERT INTO public.payroll VALUES (18, 'Jeremy Clarkson', 'IT', 10000.00);
INSERT INTO public.payroll VALUES (17, 'John Doe', 'IT', 100000.00);


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: root
--



--
-- Data for Name: products_citus; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.products_citus VALUES (1, 'product name', 10, 5);


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.schema_migrations VALUES ('20240219182555');
INSERT INTO public.schema_migrations VALUES ('20240221212444');
INSERT INTO public.schema_migrations VALUES ('20240224084030');
INSERT INTO public.schema_migrations VALUES ('20240224164745');
INSERT INTO public.schema_migrations VALUES ('20240224212847');
INSERT INTO public.schema_migrations VALUES ('20240225152915');
INSERT INTO public.schema_migrations VALUES ('20240226205418');
INSERT INTO public.schema_migrations VALUES ('20240229223930');
INSERT INTO public.schema_migrations VALUES ('20240307072143');
INSERT INTO public.schema_migrations VALUES ('20240307073252');
INSERT INTO public.schema_migrations VALUES ('20240309102104');
INSERT INTO public.schema_migrations VALUES ('20240311171026');
INSERT INTO public.schema_migrations VALUES ('20240311213900');


--
-- Data for Name: table1; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.table1 VALUES (5, 30, 'meters');


--
-- Data for Name: table2; Type: TABLE DATA; Schema: public; Owner: root
--

INSERT INTO public.table2 VALUES (1, 30, 'meters', 'root', 'INSERT', '2024-03-16 21:46:13.910799');
INSERT INTO public.table2 VALUES (2, 10, 'inches', 'root', 'INSERT', '2024-03-16 21:46:13.910799');
INSERT INTO public.table2 VALUES (2, 20, 'inches', 'root', 'UPDATE', '2024-03-16 21:46:13.910799');
INSERT INTO public.table2 VALUES (2, 20, 'inches', 'root', 'DELETE', '2024-03-16 21:46:13.910799');
INSERT INTO public.table2 VALUES (3, 50, 'inches', 'root', 'INSERT', '2024-03-16 21:46:13.910799');
INSERT INTO public.table2 VALUES (1, NULL, NULL, 'root', 'TRUNCATE', '2024-03-16 21:46:13.910799');
INSERT INTO public.table2 VALUES (4, 50, 'inches', 'root', 'INSERT', '2024-03-16 21:46:13.910799');
INSERT INTO public.table2 VALUES (4, 50, 'inches', 'root', 'DELETE', '2024-03-16 21:46:13.910799');
INSERT INTO public.table2 VALUES (5, 30, 'meters', 'root', 'INSERT', '2024-03-16 21:46:13.910799');


--
-- Name: accounts_account_id_seq; Type: SEQUENCE SET; Schema: public; Owner: root
--

SELECT pg_catalog.setval('public.accounts_account_id_seq', 2, true);


--
-- Name: dndclasses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: root
--

SELECT pg_catalog.setval('public.dndclasses_id_seq', 1, false);


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: root
--

SELECT pg_catalog.setval('public.products_id_seq', 1, false);


--
-- Name: table1_key_seq; Type: SEQUENCE SET; Schema: public; Owner: root
--

SELECT pg_catalog.setval('public.table1_key_seq', 5, true);


--
-- Name: table2_key_seq; Type: SEQUENCE SET; Schema: public; Owner: root
--

SELECT pg_catalog.setval('public.table2_key_seq', 1, true);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (account_id);


--
-- Name: bookings bookings_pk; Type: CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pk PRIMARY KEY (bookid);


--
-- Name: dndclasses dndclasses_pkey; Type: CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.dndclasses
    ADD CONSTRAINT dndclasses_pkey PRIMARY KEY (id);


--
-- Name: facilities facilities_pk; Type: CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.facilities
    ADD CONSTRAINT facilities_pk PRIMARY KEY (facid);


--
-- Name: members members_pk; Type: CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.members
    ADD CONSTRAINT members_pk PRIMARY KEY (memid);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: table1 table1_pkey; Type: CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.table1
    ADD CONSTRAINT table1_pkey PRIMARY KEY (key);


--
-- Name: bookings.facid_memid; Type: INDEX; Schema: public; Owner: root
--

CREATE INDEX "bookings.facid_memid" ON public.bookings USING btree (facid, memid);


--
-- Name: bookings.facid_starttime; Type: INDEX; Schema: public; Owner: root
--

CREATE INDEX "bookings.facid_starttime" ON public.bookings USING btree (facid, starttime);


--
-- Name: bookings.memid_facid; Type: INDEX; Schema: public; Owner: root
--

CREATE INDEX "bookings.memid_facid" ON public.bookings USING btree (memid, facid);


--
-- Name: bookings.memid_starttime; Type: INDEX; Schema: public; Owner: root
--

CREATE INDEX "bookings.memid_starttime" ON public.bookings USING btree (memid, starttime);


--
-- Name: bookings.starttime; Type: INDEX; Schema: public; Owner: root
--

CREATE INDEX "bookings.starttime" ON public.bookings USING btree (starttime);


--
-- Name: members.joindate; Type: INDEX; Schema: public; Owner: root
--

CREATE INDEX "members.joindate" ON public.members USING btree (joindate);


--
-- Name: members.recommendedby; Type: INDEX; Schema: public; Owner: root
--

CREATE INDEX "members.recommendedby" ON public.members USING btree (recommendedby);


--
-- Name: products products_notify_event; Type: TRIGGER; Schema: public; Owner: root
--

CREATE TRIGGER products_notify_event AFTER INSERT OR DELETE OR UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.notify_event();


--
-- Name: table1 table1_tr; Type: TRIGGER; Schema: public; Owner: root
--

CREATE TRIGGER table1_tr BEFORE INSERT OR DELETE OR UPDATE ON public.table1 FOR EACH ROW EXECUTE FUNCTION public.shadow('mydb', 'table2');


--
-- Name: table1 table1_tr1; Type: TRIGGER; Schema: public; Owner: root
--

CREATE TRIGGER table1_tr1 BEFORE TRUNCATE ON public.table1 FOR EACH STATEMENT EXECUTE FUNCTION public.shadow('mydb', 'table2');


--
-- Name: dndclasses dndclasses_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.dndclasses
    ADD CONSTRAINT dndclasses_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.dndclasses(id);


--
-- Name: bookings fk_bookings_facid; Type: FK CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT fk_bookings_facid FOREIGN KEY (facid) REFERENCES public.facilities(facid);


--
-- Name: bookings fk_bookings_memid; Type: FK CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT fk_bookings_memid FOREIGN KEY (memid) REFERENCES public.members(memid);


--
-- Name: members fk_members_recommendedby; Type: FK CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.members
    ADD CONSTRAINT fk_members_recommendedby FOREIGN KEY (recommendedby) REFERENCES public.members(memid) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

