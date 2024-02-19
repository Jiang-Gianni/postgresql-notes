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

SET default_tablespace = '';

SET default_table_access_method = heap;

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
-- Name: products id; Type: DEFAULT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: root
--

COPY public.products (id, name, quantity) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: root
--

COPY public.schema_migrations (version) FROM stdin;
20240219182555
\.


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: root
--

SELECT pg_catalog.setval('public.products_id_seq', 1, false);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: root
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: products products_notify_event; Type: TRIGGER; Schema: public; Owner: root
--

CREATE TRIGGER products_notify_event AFTER INSERT OR DELETE OR UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.notify_event();


--
-- PostgreSQL database dump complete
--

