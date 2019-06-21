CREATE TABLE public.acessos
(
    id integer NOT NULL,
    data_hora timestamp without time zone NOT NULL,
    CONSTRAINT "Acessos_pkey" PRIMARY KEY (id)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE public.acessos
    OWNER to postgres;

-------------------------------------------------

CREATE SEQUENCE public.acessos_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    CACHE 1;

ALTER SEQUENCE public.acessos_seq
    OWNER TO postgres;