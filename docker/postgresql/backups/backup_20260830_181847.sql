--
-- PostgreSQL database dump
--

\restrict ry91l2fm4zZSkBdVJpvXMLqUH4xTekKp8j0ovt7QbDIJMfMdaNTuHOhW0XVRV1e

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: appointment_scheduler; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA appointment_scheduler;


ALTER SCHEMA appointment_scheduler OWNER TO postgres;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO postgres;

--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA appointment_scheduler;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA appointment_scheduler;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: prevent_appointment_audit_mutation(); Type: FUNCTION; Schema: appointment_scheduler; Owner: postgres
--

CREATE FUNCTION appointment_scheduler.prevent_appointment_audit_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'appointment audit events are append-only';
END;
$$;


ALTER FUNCTION appointment_scheduler.prevent_appointment_audit_mutation() OWNER TO postgres;

--
-- Name: reject_appointment_during_time_off(); Type: FUNCTION; Schema: appointment_scheduler; Owner: postgres
--

CREATE FUNCTION appointment_scheduler.reject_appointment_during_time_off() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.deleted_at IS NULL
     AND NEW.status IN ('requested', 'checked_in', 'in_progress') THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.technician_id::text, 0));
    IF EXISTS (
      SELECT 1
      FROM appointment_scheduler.technician_time_off
      WHERE technician_id = NEW.technician_id
        AND deleted_at IS NULL
        AND starts_at < NEW.ends_at
        AND ends_at > NEW.starts_at
    ) THEN
      RAISE EXCEPTION 'appointment overlaps technician time off'
        USING ERRCODE = '23P01', CONSTRAINT = 'appointments_no_technician_time_off';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION appointment_scheduler.reject_appointment_during_time_off() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: appointment_audit_events; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.appointment_audit_events (
    appointment_audit_event_id uuid DEFAULT gen_random_uuid() NOT NULL,
    appointment_id uuid NOT NULL,
    actor_user_id uuid,
    event_type character varying(64) NOT NULL,
    before_data jsonb,
    after_data jsonb,
    occurred_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.appointment_audit_events OWNER TO postgres;

--
-- Name: appointment_idempotency; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.appointment_idempotency (
    idempotency_key character varying(255) NOT NULL,
    appointment_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE appointment_scheduler.appointment_idempotency OWNER TO postgres;

--
-- Name: appointment_resource_reservations; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.appointment_resource_reservations (
    appointment_resource_reservation_id uuid DEFAULT gen_random_uuid() CONSTRAINT appointment_resource_reserv_appointment_resource_reser_not_null NOT NULL,
    appointment_id uuid NOT NULL,
    resource_type character varying(32) NOT NULL,
    resource_id uuid NOT NULL,
    reserved_starts_at timestamp with time zone NOT NULL,
    reserved_ends_at timestamp with time zone NOT NULL,
    status character varying(32) NOT NULL,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    released_at timestamp with time zone,
    assigned_by_user_id uuid NOT NULL,
    reason text,
    CONSTRAINT appointment_resource_reservations_interval_check CHECK ((reserved_ends_at > reserved_starts_at)),
    CONSTRAINT appointment_resource_reservations_status_check CHECK (((status)::text = ANY ((ARRAY['requested'::character varying, 'checked_in'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT appointment_resource_reservations_type_check CHECK (((resource_type)::text = ANY ((ARRAY['technician'::character varying, 'service_bay'::character varying])::text[])))
);


ALTER TABLE appointment_scheduler.appointment_resource_reservations OWNER TO postgres;

--
-- Name: appointments; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.appointments (
    appointment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    reference_code character varying(50) NOT NULL,
    customer_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    dealership_id uuid NOT NULL,
    service_type_id uuid NOT NULL,
    technician_id uuid NOT NULL,
    service_bay_id uuid NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    status character varying(32) NOT NULL,
    notes text,
    created_by_user_id uuid NOT NULL,
    cancelled_by_user_id uuid,
    cancellation_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    cancelled_at timestamp with time zone,
    checked_in_at timestamp with time zone,
    in_progress_at timestamp with time zone,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    actual_ends_at timestamp with time zone,
    planned_duration_minutes integer,
    CONSTRAINT appointments_cancel_reason_check CHECK ((((status)::text <> 'cancelled'::text) OR (cancellation_reason IS NOT NULL))),
    CONSTRAINT appointments_planned_duration_positive CHECK (((planned_duration_minutes IS NULL) OR (planned_duration_minutes > 0))),
    CONSTRAINT appointments_status_check CHECK (((status)::text = ANY ((ARRAY['requested'::character varying, 'checked_in'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT appointments_time_range_check CHECK ((ends_at > starts_at))
);


ALTER TABLE appointment_scheduler.appointments OWNER TO postgres;

--
-- Name: bay_capabilities; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.bay_capabilities (
    bay_capability_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(100) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.bay_capabilities OWNER TO postgres;

--
-- Name: customer_dealerships; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.customer_dealerships (
    customer_id uuid NOT NULL,
    dealership_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.customer_dealerships OWNER TO postgres;

--
-- Name: customers; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.customers (
    customer_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    phone character varying(50) NOT NULL,
    email character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.customers OWNER TO postgres;

--
-- Name: dealership_operation_time; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.dealership_operation_time (
    dealership_operation_time_id uuid DEFAULT gen_random_uuid() NOT NULL,
    dealership_id uuid NOT NULL,
    day_of_week smallint NOT NULL,
    opens_at time without time zone NOT NULL,
    closes_at time without time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT dealership_operation_time_day_check CHECK (((day_of_week >= 1) AND (day_of_week <= 7))),
    CONSTRAINT dealership_operation_time_hours_check CHECK ((closes_at > opens_at))
);


ALTER TABLE appointment_scheduler.dealership_operation_time OWNER TO postgres;

--
-- Name: dealerships; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.dealerships (
    dealership_id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    code character varying(50) NOT NULL,
    address text NOT NULL,
    timezone character varying(64) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.dealerships OWNER TO postgres;

--
-- Name: roles; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.roles (
    role_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(64) NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.roles OWNER TO postgres;

--
-- Name: schema_migrations; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.schema_migrations (
    version bigint NOT NULL,
    dirty boolean NOT NULL
);


ALTER TABLE appointment_scheduler.schema_migrations OWNER TO postgres;

--
-- Name: service_bay_capabilities; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.service_bay_capabilities (
    service_bay_capability_id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_bay_id uuid NOT NULL,
    bay_capability_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.service_bay_capabilities OWNER TO postgres;

--
-- Name: service_bays; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.service_bays (
    service_bay_id uuid DEFAULT gen_random_uuid() NOT NULL,
    dealership_id uuid NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(255) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.service_bays OWNER TO postgres;

--
-- Name: service_type_required_bay_capabilities; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.service_type_required_bay_capabilities (
    service_type_required_bay_capability_id uuid DEFAULT gen_random_uuid() CONSTRAINT service_type_required_bay_c_service_type_required_bay__not_null NOT NULL,
    service_type_id uuid NOT NULL,
    bay_capability_id uuid CONSTRAINT service_type_required_bay_capabiliti_bay_capability_id_not_null NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.service_type_required_bay_capabilities OWNER TO postgres;

--
-- Name: service_type_required_skills; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.service_type_required_skills (
    service_type_required_skill_id uuid DEFAULT gen_random_uuid() CONSTRAINT service_type_required_skill_service_type_required_skil_not_null NOT NULL,
    service_type_id uuid NOT NULL,
    skill_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.service_type_required_skills OWNER TO postgres;

--
-- Name: service_types; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.service_types (
    service_type_id uuid DEFAULT gen_random_uuid() NOT NULL,
    dealership_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    default_duration_minutes integer NOT NULL,
    min_duration_minutes integer NOT NULL,
    max_duration_minutes integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT service_types_default_duration_positive CHECK ((default_duration_minutes > 0)),
    CONSTRAINT service_types_duration_range_check CHECK ((max_duration_minutes >= min_duration_minutes)),
    CONSTRAINT service_types_min_duration_positive CHECK ((min_duration_minutes > 0))
);


ALTER TABLE appointment_scheduler.service_types OWNER TO postgres;

--
-- Name: skills; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.skills (
    skill_id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(100) NOT NULL,
    name character varying(255) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.skills OWNER TO postgres;

--
-- Name: technician_shifts; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.technician_shifts (
    technician_shift_id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    day_of_week smallint NOT NULL,
    starts_at time without time zone NOT NULL,
    ends_at time without time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT technician_shifts_day_check CHECK (((day_of_week >= 1) AND (day_of_week <= 7))),
    CONSTRAINT technician_shifts_hours_check CHECK ((ends_at > starts_at))
);


ALTER TABLE appointment_scheduler.technician_shifts OWNER TO postgres;

--
-- Name: technician_skills; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.technician_skills (
    technician_skill_id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    skill_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.technician_skills OWNER TO postgres;

--
-- Name: technician_time_off; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.technician_time_off (
    technician_time_off_id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    reason text,
    created_by_user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT technician_time_off_range_check CHECK ((ends_at > starts_at))
);


ALTER TABLE appointment_scheduler.technician_time_off OWNER TO postgres;

--
-- Name: technicians; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.technicians (
    technician_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.technicians OWNER TO postgres;

--
-- Name: user_roles; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.user_roles (
    user_role_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    role_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE appointment_scheduler.user_roles OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.users (
    user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_user_id uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid NOT NULL,
    name character varying(255) NOT NULL,
    phone character varying(50),
    email character varying(255),
    dealership_id uuid NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE appointment_scheduler.users OWNER TO postgres;

--
-- Name: vehicles; Type: TABLE; Schema: appointment_scheduler; Owner: postgres
--

CREATE TABLE appointment_scheduler.vehicles (
    vehicle_id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    vin character varying(17),
    registration_plate character varying(32),
    make character varying(100) NOT NULL,
    model character varying(100) NOT NULL,
    model_year smallint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT vehicles_identity_check CHECK (((vin IS NOT NULL) OR (registration_plate IS NOT NULL)))
);


ALTER TABLE appointment_scheduler.vehicles OWNER TO postgres;

--
-- Name: roles; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.roles (
    role_id character varying(36) NOT NULL,
    name character varying(16) NOT NULL,
    CONSTRAINT roles_name_check CHECK (((name)::text = ANY ((ARRAY['superadmin'::character varying, 'admin'::character varying, 'user'::character varying])::text[])))
);


ALTER TABLE auth.roles OWNER TO postgres;

--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.schema_migrations (
    version bigint NOT NULL,
    dirty boolean NOT NULL
);


ALTER TABLE auth.schema_migrations OWNER TO postgres;

--
-- Name: user_roles; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.user_roles (
    user_id character varying(36) NOT NULL,
    role_id character varying(36) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE auth.user_roles OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.users (
    user_id character varying(36) NOT NULL,
    full_name character varying(255) DEFAULT ''::character varying NOT NULL,
    email bytea NOT NULL,
    email_lookup bytea NOT NULL,
    email_to character varying(255),
    hashed_password character varying(255) NOT NULL,
    hashed_password_1 character varying(255) DEFAULT ''::character varying NOT NULL,
    hashed_password_2 character varying(255) DEFAULT ''::character varying NOT NULL,
    token_ver integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    status character varying(16) DEFAULT 'active'::character varying NOT NULL,
    CONSTRAINT users_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'disabled'::character varying, 'deleted'::character varying])::text[]))),
    CONSTRAINT users_token_ver_positive CHECK ((token_ver > 0))
);


ALTER TABLE auth.users OWNER TO postgres;

--
-- Data for Name: appointment_audit_events; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.appointment_audit_events (appointment_audit_event_id, appointment_id, actor_user_id, event_type, before_data, after_data, occurred_at) FROM stdin;
f8c23f78-1748-51ea-a440-c0d6ca105e53	c1be6607-1700-5bd1-8c30-a11a772a9d39	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d10df630-0001-5f8c-a155-73249544a458	c1be6607-1700-5bd1-8c30-a11a772a9d39	a73801eb-398a-54d0-8e82-e50c59407287	completed	\N	{"status": "completed"}	2026-08-27 00:00:00+00
1a618417-38b1-590c-8a95-5b6141a707c0	51d98f33-5a44-55b5-b473-3c834876a284	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
2c826550-0565-503c-94ca-2ca78974f75b	51d98f33-5a44-55b5-b473-3c834876a284	a73801eb-398a-54d0-8e82-e50c59407287	cancelled	\N	{"status": "cancelled"}	2026-08-27 00:00:00+00
439b7f3c-b2a7-5a8b-b552-af6ed067b29f	c36806f7-30b8-5e1a-b19a-5de4afc3ba82	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
409ff9cd-f0cb-5cc4-89ac-1b44249c2256	512f2cc0-21f1-5582-bde7-92d1d446501a	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
760a3f48-a3ad-59d2-83dc-3a6d6f276076	512f2cc0-21f1-5582-bde7-92d1d446501a	a73801eb-398a-54d0-8e82-e50c59407287	checked_in	\N	{"status": "checked_in"}	2026-08-27 00:00:00+00
7ff6384d-4826-5f4d-a546-5ef1ce55ccd6	70d87942-32d1-57e6-b368-8a78f441f5d4	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
43627c58-a6e0-5236-aabb-ed6eb8f83187	70d87942-32d1-57e6-b368-8a78f441f5d4	a73801eb-398a-54d0-8e82-e50c59407287	in_progress	\N	{"status": "in_progress"}	2026-08-27 00:00:00+00
3896bb22-bcb4-5ed4-8406-e656072b3268	32276637-d152-5de4-b70c-f479d93301a3	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
f0319e50-4ec5-59dd-a024-168edcbebf45	32276637-d152-5de4-b70c-f479d93301a3	a73801eb-398a-54d0-8e82-e50c59407287	completed	\N	{"status": "completed"}	2026-08-27 01:00:00+00
5be4323b-ddb0-53df-8380-186dd5e44418	028f3e80-dddf-5362-b6e7-9cca35ffe13a	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ed26e8b7-9fa7-5e6e-baf5-5d1db6b2f2a5	028f3e80-dddf-5362-b6e7-9cca35ffe13a	a73801eb-398a-54d0-8e82-e50c59407287	cancelled	\N	{"status": "cancelled"}	2026-08-27 01:00:00+00
e37e23d9-cf06-563b-855b-b9405c6aa12f	4b5fe5f0-1672-5971-9882-360d05edf5f5	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
518692da-7db6-531c-b231-d65eecbae6ed	505c41f3-ab0e-5258-9049-bde98a3211bd	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
e027f0d7-c749-59b0-9d1f-76a9a0132641	505c41f3-ab0e-5258-9049-bde98a3211bd	a73801eb-398a-54d0-8e82-e50c59407287	checked_in	\N	{"status": "checked_in"}	2026-08-27 01:00:00+00
b58865eb-f8d8-5982-962b-aec3911d33a0	c3de56e7-38d4-59b4-ac0d-72e210bdbf95	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d19726f4-1f84-580e-bbdd-a3cc07c00bff	c3de56e7-38d4-59b4-ac0d-72e210bdbf95	a73801eb-398a-54d0-8e82-e50c59407287	in_progress	\N	{"status": "in_progress"}	2026-08-27 01:00:00+00
f9ef1fce-eecc-510b-b711-86fc903386fc	68dd5464-9979-56fb-9177-c11bb97f88eb	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d930eae4-b4d7-536c-a9ad-08b56a802d5b	68dd5464-9979-56fb-9177-c11bb97f88eb	a73801eb-398a-54d0-8e82-e50c59407287	completed	\N	{"status": "completed"}	2026-08-28 02:00:00+00
134dc964-1a4b-5191-9977-78d85c2946eb	6e8ddc03-dd54-58a1-b707-6f638c67cdc6	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d310d6bd-ad91-5ff7-9d45-54b6afa99192	6e8ddc03-dd54-58a1-b707-6f638c67cdc6	a73801eb-398a-54d0-8e82-e50c59407287	cancelled	\N	{"status": "cancelled"}	2026-08-28 02:00:00+00
eba20111-4283-57d6-bb7d-09c85dfaf6d3	ba1eb83b-2463-5459-b573-6091d22f893e	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
6d29a318-e895-57ba-811d-70d27fb58b7d	b42f07e6-193a-573e-83f5-8f0efb29cc9e	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
c1764863-edc0-5983-b897-1a9348a4db72	b42f07e6-193a-573e-83f5-8f0efb29cc9e	a73801eb-398a-54d0-8e82-e50c59407287	checked_in	\N	{"status": "checked_in"}	2026-08-28 02:00:00+00
25aafc64-6d60-554a-aa26-7e8ab2b2afd0	f7eb979a-71c5-59c7-9f6d-cc67215c0a42	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
1dc4756d-d2e1-5657-af55-1c85afe49e0d	f7eb979a-71c5-59c7-9f6d-cc67215c0a42	a73801eb-398a-54d0-8e82-e50c59407287	in_progress	\N	{"status": "in_progress"}	2026-08-28 02:00:00+00
60782e7a-19e9-526f-937a-0811821a9846	89cbbf80-8ed3-5794-ba37-a2bcadf57dd9	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
4eb7ba53-faa9-5dea-b6d5-fd5b6b8dc902	89cbbf80-8ed3-5794-ba37-a2bcadf57dd9	a73801eb-398a-54d0-8e82-e50c59407287	completed	\N	{"status": "completed"}	2026-08-28 03:00:00+00
266fc47f-8825-5d16-b6f6-41ab5a0f647c	8ee6032a-ec74-5a8a-a084-2ef75bacc8ea	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
4cce4e43-c847-5c0d-b701-410f22686bc9	8ee6032a-ec74-5a8a-a084-2ef75bacc8ea	a73801eb-398a-54d0-8e82-e50c59407287	cancelled	\N	{"status": "cancelled"}	2026-08-28 03:00:00+00
fe46a0ec-631b-5d40-9f73-19dbda807379	8e39ab31-f7f9-53b5-9d5c-ce33ff187b07	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
44c796a9-17fe-5ad7-bf84-8fb57ee2e554	fd1b3303-a5de-5e71-92ee-e18a700ff091	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
4b803852-3f7f-5fed-bd9d-58408225103f	fd1b3303-a5de-5e71-92ee-e18a700ff091	a73801eb-398a-54d0-8e82-e50c59407287	checked_in	\N	{"status": "checked_in"}	2026-08-28 03:00:00+00
2c091c0d-4b54-501c-af69-6ce196092f0f	508a1ec3-6d18-5080-9ea8-d288caec0e52	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
26b51a93-e4d2-54c5-9c08-5f8dabe15821	508a1ec3-6d18-5080-9ea8-d288caec0e52	a73801eb-398a-54d0-8e82-e50c59407287	in_progress	\N	{"status": "in_progress"}	2026-08-28 03:00:00+00
ca2c364e-c799-596c-bc8b-cec787e57be0	ccb0b729-659c-5948-91af-a3d00ade05b8	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
e63b433e-ddff-5126-b88d-9dadb7028324	ccb0b729-659c-5948-91af-a3d00ade05b8	a73801eb-398a-54d0-8e82-e50c59407287	completed	\N	{"status": "completed"}	2026-09-03 04:00:00+00
bde938fd-3f38-5cd7-a111-33e588752e37	6a047d7d-bdbf-5067-869b-69daf14ca320	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
14cab6ec-38d6-5bdc-a532-a7d2501dddea	6a047d7d-bdbf-5067-869b-69daf14ca320	a73801eb-398a-54d0-8e82-e50c59407287	cancelled	\N	{"status": "cancelled"}	2026-09-03 04:00:00+00
8a03ffb4-e1b2-5255-9498-684b4504a73e	233400f6-3b7f-5648-bb71-202b2aec854c	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
8022e787-10ac-5b57-b240-664e91e5994e	cde45d35-f67e-5f9f-aeb2-06b49e2aad3d	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
f111f995-51a4-58ac-8edc-c7317c402602	cde45d35-f67e-5f9f-aeb2-06b49e2aad3d	a73801eb-398a-54d0-8e82-e50c59407287	checked_in	\N	{"status": "checked_in"}	2026-09-03 04:00:00+00
1c559442-76f0-5e27-8f3b-de606d0d2448	b8453e21-1f95-5e6b-ab8e-d7a919f85dff	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
7b0725ae-02a5-5c13-8f91-ce244d1a465e	b8453e21-1f95-5e6b-ab8e-d7a919f85dff	a73801eb-398a-54d0-8e82-e50c59407287	in_progress	\N	{"status": "in_progress"}	2026-09-03 04:00:00+00
c424532f-6e34-51c3-9a0e-e0384090bb37	f8726250-0119-59ae-8c57-702615784cc1	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
6da6a730-2a5b-5793-9a44-9a26c8adcae1	f8726250-0119-59ae-8c57-702615784cc1	a73801eb-398a-54d0-8e82-e50c59407287	completed	\N	{"status": "completed"}	2026-09-03 05:00:00+00
6753253e-ea78-531a-9cee-a385adceeabc	97cff4f4-8a65-55fc-9f01-e3d97cdb097a	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
4ec67a86-973b-531b-b5e6-6692f53e2cb6	97cff4f4-8a65-55fc-9f01-e3d97cdb097a	a73801eb-398a-54d0-8e82-e50c59407287	cancelled	\N	{"status": "cancelled"}	2026-09-03 05:00:00+00
7d51113a-8f26-5c3f-86f0-3580ee3faddc	71bfbd58-db4e-5e66-be5c-7b3c8973b14e	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
b0454f56-acd4-5d51-a743-d9707d2c3162	0d1929f8-6dbd-5ec0-bed5-3bd2891793dc	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
7dc8373a-4800-5b15-88c3-6caeaa6daa7a	0d1929f8-6dbd-5ec0-bed5-3bd2891793dc	a73801eb-398a-54d0-8e82-e50c59407287	checked_in	\N	{"status": "checked_in"}	2026-09-03 05:00:00+00
72b33396-b4e5-58c4-91b8-75c4facdff12	5fe8bcc3-eef7-5412-9325-4799e84653d5	a73801eb-398a-54d0-8e82-e50c59407287	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
8f5c5150-c4da-5606-be42-a969f3c9c01f	5fe8bcc3-eef7-5412-9325-4799e84653d5	a73801eb-398a-54d0-8e82-e50c59407287	in_progress	\N	{"status": "in_progress"}	2026-09-03 05:00:00+00
454e506b-c109-5912-9700-566c2a2c88bf	eda78781-d975-5169-ab34-444c65348509	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
5d6658cb-47be-5c35-90fb-6461944de4fd	eda78781-d975-5169-ab34-444c65348509	ded9e174-90f2-5ea7-9b35-86728f8544f7	completed	\N	{"status": "completed"}	2026-08-26 22:00:00+00
4478f8ea-1456-50a2-9c2e-64db2548c8df	e9a173fd-770c-5f71-911a-330de6bd6f15	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
e223a829-3b8f-5bb0-bfe2-2b36dc09ff5f	e9a173fd-770c-5f71-911a-330de6bd6f15	ded9e174-90f2-5ea7-9b35-86728f8544f7	cancelled	\N	{"status": "cancelled"}	2026-08-26 22:00:00+00
fbb6f2b5-9208-5be4-b96b-12d7a901f918	746e6df4-6a1a-5f90-a351-d465c3557099	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
c8bc9115-030f-5510-8363-4638016a366b	913fbedb-c4d5-5402-b309-234a3935aa70	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
0825118a-17c2-5c68-bea5-7126bb331ca6	913fbedb-c4d5-5402-b309-234a3935aa70	ded9e174-90f2-5ea7-9b35-86728f8544f7	checked_in	\N	{"status": "checked_in"}	2026-08-26 22:00:00+00
2b9d09fe-3783-5a1f-bb6c-b2441c4b5767	21429526-e9cb-5a8a-a3c4-666b47d7ed17	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
aa6099a7-6f55-50b3-8d4c-9ac2104ce299	21429526-e9cb-5a8a-a3c4-666b47d7ed17	ded9e174-90f2-5ea7-9b35-86728f8544f7	in_progress	\N	{"status": "in_progress"}	2026-08-26 22:00:00+00
89d8705b-8834-5549-8bb6-74c9955fc343	af5a8a6a-fbb5-5079-a426-6f14edd418a6	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
98ba9e12-1032-50b2-b89b-c85b4ba69029	af5a8a6a-fbb5-5079-a426-6f14edd418a6	ded9e174-90f2-5ea7-9b35-86728f8544f7	completed	\N	{"status": "completed"}	2026-08-26 23:00:00+00
2aa19d69-c8e6-5035-86fc-7e037e6e5bca	d4341c25-0d74-5b56-85cd-6e58e3e93bb4	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
427349f4-7a98-56cf-8853-22f33312d9dc	d4341c25-0d74-5b56-85cd-6e58e3e93bb4	ded9e174-90f2-5ea7-9b35-86728f8544f7	cancelled	\N	{"status": "cancelled"}	2026-08-26 23:00:00+00
531e9656-751e-5b4c-8b6c-3ee1e4924923	0cc6efe8-f98b-57de-97d2-b7eea2933fe6	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
affe1f75-4c0d-507d-86c0-5ee6776d5416	51b8c108-389b-54d4-8235-53c82c937d2e	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
1ed45e77-3c02-59de-abc4-f630cc829c34	51b8c108-389b-54d4-8235-53c82c937d2e	ded9e174-90f2-5ea7-9b35-86728f8544f7	checked_in	\N	{"status": "checked_in"}	2026-08-26 23:00:00+00
e4637716-fd6f-56c3-91ff-40d514838b87	fa59e79c-eb85-5380-b460-41e1d1329b4c	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ab35eb11-aee3-5bcb-a92b-657bd6ebbc62	fa59e79c-eb85-5380-b460-41e1d1329b4c	ded9e174-90f2-5ea7-9b35-86728f8544f7	in_progress	\N	{"status": "in_progress"}	2026-08-26 23:00:00+00
e46af9f8-2970-5130-ac3a-6148486d55ce	527a4178-db47-578d-bab2-2f3f3bffcb2f	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
e4077f65-0f61-508f-b5d0-99731350a4f4	527a4178-db47-578d-bab2-2f3f3bffcb2f	ded9e174-90f2-5ea7-9b35-86728f8544f7	completed	\N	{"status": "completed"}	2026-08-28 00:00:00+00
a90d0542-812e-5bc2-8de5-f9022470a79e	6d4b2ca5-aa5d-5009-b035-a237a34f192e	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d7ca87e6-90dd-52b6-b631-0cfffaf12f37	6d4b2ca5-aa5d-5009-b035-a237a34f192e	ded9e174-90f2-5ea7-9b35-86728f8544f7	cancelled	\N	{"status": "cancelled"}	2026-08-28 00:00:00+00
0d2bb7aa-682b-53f5-9a8f-de1107ad8277	7f4b449a-c0a0-5b65-9c9b-0737bdfa00ee	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
1ac3459e-f65f-5785-aab4-0baee6e43841	acf9525c-2a74-56a6-9baa-3df7f68cf8f5	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
60ddce40-a9cc-5eaa-8487-f3d12c331aa8	acf9525c-2a74-56a6-9baa-3df7f68cf8f5	ded9e174-90f2-5ea7-9b35-86728f8544f7	checked_in	\N	{"status": "checked_in"}	2026-08-28 00:00:00+00
ff2665bc-af87-5a6e-9e91-8ba06d85efad	74bf21e1-399b-579d-ab6f-9df4db0a5717	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
9d915fea-8c64-5bf5-94ae-c7b405d3cc10	74bf21e1-399b-579d-ab6f-9df4db0a5717	ded9e174-90f2-5ea7-9b35-86728f8544f7	in_progress	\N	{"status": "in_progress"}	2026-08-28 00:00:00+00
143b4058-8062-5998-ae9f-b318b49db4bd	b6103c5a-02b9-54fa-a10a-f5601a4816a7	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
5e12b1f3-9f85-5303-9a30-38d111bd6ea2	b6103c5a-02b9-54fa-a10a-f5601a4816a7	ded9e174-90f2-5ea7-9b35-86728f8544f7	completed	\N	{"status": "completed"}	2026-08-28 01:00:00+00
4359bdb1-965d-5f35-b578-36865fda9f66	c79f06ec-6932-5029-b0ae-687b23d87ac8	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
bc1351e0-56db-58ed-b43f-2fefa0a25954	c79f06ec-6932-5029-b0ae-687b23d87ac8	ded9e174-90f2-5ea7-9b35-86728f8544f7	cancelled	\N	{"status": "cancelled"}	2026-08-28 01:00:00+00
c60285e8-fbd0-515e-be97-c36d4dc7d859	6ad7b82b-ab35-584e-8607-df1ea988e370	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
2a96e02e-9931-51c8-a4fd-ddee7c6e109a	7c224bd3-62e4-5d29-8b36-915f08d274ab	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
719f406f-1a9f-5fd6-8d0f-b53ec94b640b	7c224bd3-62e4-5d29-8b36-915f08d274ab	ded9e174-90f2-5ea7-9b35-86728f8544f7	checked_in	\N	{"status": "checked_in"}	2026-08-28 01:00:00+00
65f7d3db-a52f-59d1-be0f-26489e74c2c1	91baae88-14a5-590d-b709-597f023bab50	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d8ff8fec-532c-5499-a301-97c18d1ebd99	91baae88-14a5-590d-b709-597f023bab50	ded9e174-90f2-5ea7-9b35-86728f8544f7	in_progress	\N	{"status": "in_progress"}	2026-08-28 01:00:00+00
8bc32a0b-f7e0-529d-9822-d31dda49a4a6	cdf40560-d303-5cd8-acf1-1cb3a80b7393	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d4b3a383-1fc5-5c09-94df-16c82e04b29c	cdf40560-d303-5cd8-acf1-1cb3a80b7393	ded9e174-90f2-5ea7-9b35-86728f8544f7	completed	\N	{"status": "completed"}	2026-09-03 02:00:00+00
ff64156b-a063-5a89-b68f-8b08d544080a	863fb2cb-726a-547e-90cc-f78a0206926b	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
82851309-20b9-5908-a82c-a3a939d58245	863fb2cb-726a-547e-90cc-f78a0206926b	ded9e174-90f2-5ea7-9b35-86728f8544f7	cancelled	\N	{"status": "cancelled"}	2026-09-03 02:00:00+00
26088e33-966b-51cb-8a7e-9d830fdc1086	ee21cea7-e328-511f-835d-f51d390755c5	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
b7bc4da3-df06-5bf2-9d48-5a0cb3d2daab	91b62df0-c992-506e-960c-ef0d5e0a10eb	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
f3e765b2-c819-5a48-b277-409ccb07bc91	91b62df0-c992-506e-960c-ef0d5e0a10eb	ded9e174-90f2-5ea7-9b35-86728f8544f7	checked_in	\N	{"status": "checked_in"}	2026-09-03 02:00:00+00
337e8387-00b1-5311-affb-950d92a6e699	ee48f155-0ea2-5c4f-8788-c72642614915	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
50b268ec-3ac1-55f0-bf88-4150b077d23b	ee48f155-0ea2-5c4f-8788-c72642614915	ded9e174-90f2-5ea7-9b35-86728f8544f7	in_progress	\N	{"status": "in_progress"}	2026-09-03 02:00:00+00
c3a75302-f184-57a8-9041-4f4472e47547	8180cd6d-95cb-5b10-bf59-a452858e2beb	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
f688c064-c05d-549c-9e6e-decd81d92150	8180cd6d-95cb-5b10-bf59-a452858e2beb	ded9e174-90f2-5ea7-9b35-86728f8544f7	completed	\N	{"status": "completed"}	2026-09-03 03:00:00+00
c2f8fc1f-d646-5fdc-99e1-7adb2bbb9976	0f2551cc-952f-5382-a5d4-13e796ad1267	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
dd687733-57b9-5899-b946-5e21b1163e78	0f2551cc-952f-5382-a5d4-13e796ad1267	ded9e174-90f2-5ea7-9b35-86728f8544f7	cancelled	\N	{"status": "cancelled"}	2026-09-03 03:00:00+00
d50310b0-bbf1-59b9-93a0-2e5e2b26ebbb	b7c5d581-9d85-59e4-96ca-88f3784eebfc	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ca424a4e-6108-5bdf-ac2a-117e81c559f3	4ac1de9a-4df8-5ff6-82a9-016c44132e74	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
471c9a34-91eb-5720-bf18-084fbbdbbac0	4ac1de9a-4df8-5ff6-82a9-016c44132e74	ded9e174-90f2-5ea7-9b35-86728f8544f7	checked_in	\N	{"status": "checked_in"}	2026-09-03 03:00:00+00
bf1cf2e7-d4e4-55e6-95e3-602c47865349	f89aaf31-3917-50dc-928a-4aac5a5bdd69	ded9e174-90f2-5ea7-9b35-86728f8544f7	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ea040374-bd8c-571c-a48b-dc6094369a6a	f89aaf31-3917-50dc-928a-4aac5a5bdd69	ded9e174-90f2-5ea7-9b35-86728f8544f7	in_progress	\N	{"status": "in_progress"}	2026-09-03 03:00:00+00
d52313e8-bab2-50aa-97d0-2b57517f805c	4b444f6b-ddf5-5197-9593-718af083c89a	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d059aa32-f840-5547-9850-133bca4091dd	4b444f6b-ddf5-5197-9593-718af083c89a	7cedc8b3-3996-52bc-a6de-5f6f2041740f	completed	\N	{"status": "completed"}	2026-08-26 21:00:00+00
e12a133f-a5fe-5984-a100-aafc95f68076	0d5617d9-0de9-5f7d-a762-d26fa80048f8	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
aefc6748-c75f-5cb7-93e3-f274b2e9015d	0d5617d9-0de9-5f7d-a762-d26fa80048f8	7cedc8b3-3996-52bc-a6de-5f6f2041740f	cancelled	\N	{"status": "cancelled"}	2026-08-26 21:00:00+00
921880b5-15e5-5d55-a67a-30f39a85a66a	79504438-8585-5412-a0e7-d5b60dafd48a	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
2e631a99-4e6e-504b-b5e2-b4a4873da0f9	9c61762c-0ee2-51b8-938a-e279049ca95c	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ff0d2f94-983d-5442-a3a9-0dd442f923c0	9c61762c-0ee2-51b8-938a-e279049ca95c	7cedc8b3-3996-52bc-a6de-5f6f2041740f	checked_in	\N	{"status": "checked_in"}	2026-08-26 21:00:00+00
4c7937e8-f40f-541d-9fa8-944e940320ec	e0dd9e5f-53b6-5c08-acfa-05a587e2ac8c	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
f889bd81-202f-55df-aaf4-0004eae39899	e0dd9e5f-53b6-5c08-acfa-05a587e2ac8c	7cedc8b3-3996-52bc-a6de-5f6f2041740f	in_progress	\N	{"status": "in_progress"}	2026-08-26 21:00:00+00
7e246b2e-303f-5c71-8714-622126651089	de360e40-e02c-5a71-acea-b80b29a40df8	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
12964bec-77b1-55bd-a963-6676de75d493	de360e40-e02c-5a71-acea-b80b29a40df8	7cedc8b3-3996-52bc-a6de-5f6f2041740f	completed	\N	{"status": "completed"}	2026-08-26 22:00:00+00
a583bc5e-cd0b-5df6-a189-3c8280dc715a	e4ca982c-fb5f-5359-b84a-ccc9ca3ef485	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
3efe7182-9b78-5b38-b0b7-cac4050bd446	e4ca982c-fb5f-5359-b84a-ccc9ca3ef485	7cedc8b3-3996-52bc-a6de-5f6f2041740f	cancelled	\N	{"status": "cancelled"}	2026-08-26 22:00:00+00
ef867cac-c129-52ab-8330-efebc6d800c4	1ee0e0ec-df9f-5a24-8596-78dc20ea5505	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
739848bd-99e0-5bac-84f0-e32cd0272045	f170be60-f842-5db8-9eef-571ef9bcb6a0	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
24e2a239-fb07-5f03-b756-f8d75a8533ca	f170be60-f842-5db8-9eef-571ef9bcb6a0	7cedc8b3-3996-52bc-a6de-5f6f2041740f	checked_in	\N	{"status": "checked_in"}	2026-08-26 22:00:00+00
d1fae846-7cd3-5e54-abc0-ff6de29a2284	62e2230e-6522-52e2-a581-854885613114	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ac53cd6a-9cfc-59a4-ae85-a91a2ce3aa41	62e2230e-6522-52e2-a581-854885613114	7cedc8b3-3996-52bc-a6de-5f6f2041740f	in_progress	\N	{"status": "in_progress"}	2026-08-26 22:00:00+00
bc57206a-0a17-5680-af82-7c5c2467314e	77554b46-a2d1-5c95-843d-d0bc4b12523f	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
9ceb3b30-4ef7-50bb-a708-98003936f2cf	77554b46-a2d1-5c95-843d-d0bc4b12523f	7cedc8b3-3996-52bc-a6de-5f6f2041740f	completed	\N	{"status": "completed"}	2026-08-27 23:00:00+00
dc062453-966b-510c-9653-0816c271ea8f	2d2fbe57-cf40-5023-b8fa-366f5c910bfd	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
5cd7d5cb-d17a-5c55-989c-593788524520	2d2fbe57-cf40-5023-b8fa-366f5c910bfd	7cedc8b3-3996-52bc-a6de-5f6f2041740f	cancelled	\N	{"status": "cancelled"}	2026-08-27 23:00:00+00
40e34e38-edaa-500a-aab8-f07ffe0f6f80	a81c1b3f-ef10-558b-b7c8-465db5e6eeed	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
f6de375a-cfa3-5032-b9e0-cf7f004ae3b0	1182656f-e6a1-5e21-a922-dddd2272efae	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
fb611f7a-1771-54ef-aa1f-caa438270ddf	1182656f-e6a1-5e21-a922-dddd2272efae	7cedc8b3-3996-52bc-a6de-5f6f2041740f	checked_in	\N	{"status": "checked_in"}	2026-08-27 23:00:00+00
257a06b5-38f7-5dc6-8d4a-9acab33d7171	30af9f27-45da-5500-b295-aab66f60aa20	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
be372f7d-91e3-584d-8f8e-c5f8d7abaf9c	30af9f27-45da-5500-b295-aab66f60aa20	7cedc8b3-3996-52bc-a6de-5f6f2041740f	in_progress	\N	{"status": "in_progress"}	2026-08-27 23:00:00+00
f5be0e30-5876-5db4-a816-7601fcbded1b	dccfa163-8f7a-571c-b752-f9d913f1ea1d	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
fa4ec292-96c6-5626-89ac-86d373e229de	dccfa163-8f7a-571c-b752-f9d913f1ea1d	7cedc8b3-3996-52bc-a6de-5f6f2041740f	completed	\N	{"status": "completed"}	2026-08-28 00:00:00+00
3a23b4a5-1906-5a4f-9323-1ce97db6e64a	1b32fb8c-3a63-55e8-ac78-19f1b0211117	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
75383c46-f0fb-5297-932d-eedec0e0421a	1b32fb8c-3a63-55e8-ac78-19f1b0211117	7cedc8b3-3996-52bc-a6de-5f6f2041740f	cancelled	\N	{"status": "cancelled"}	2026-08-28 00:00:00+00
986e98da-07d6-5298-8dbb-689cccb7bb73	e4fe3c94-eda0-5699-83bd-95e4c7df170c	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ffc19988-25f3-505f-8c55-b3f0db2ec07d	8c535195-49b7-5c90-a309-89cf65c97c16	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
7147329f-a6e4-5c71-9a06-03e9fab01c16	8c535195-49b7-5c90-a309-89cf65c97c16	7cedc8b3-3996-52bc-a6de-5f6f2041740f	checked_in	\N	{"status": "checked_in"}	2026-08-28 00:00:00+00
ede1ac1a-8f79-5429-b17b-0f3c32ae29b4	aff4d2d5-56f1-5c0c-94c0-9bb019ce56e4	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ce9ad358-0410-5ed4-82f7-f5e513469abf	aff4d2d5-56f1-5c0c-94c0-9bb019ce56e4	7cedc8b3-3996-52bc-a6de-5f6f2041740f	in_progress	\N	{"status": "in_progress"}	2026-08-28 00:00:00+00
123c9da8-a34a-5832-b874-13764b70d5c6	9a391023-01e3-5d06-a25b-742922dea10b	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ff305dd8-f9c1-5034-917f-adbc178fd105	9a391023-01e3-5d06-a25b-742922dea10b	7cedc8b3-3996-52bc-a6de-5f6f2041740f	completed	\N	{"status": "completed"}	2026-09-03 01:00:00+00
ceb2dfc9-5855-5f6f-ac6f-da8a21963f69	4e7e57e6-f7b8-5d8c-b20a-f2204a32e1a3	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
e24ca325-56df-597d-a14d-b804a6f8a3fc	4e7e57e6-f7b8-5d8c-b20a-f2204a32e1a3	7cedc8b3-3996-52bc-a6de-5f6f2041740f	cancelled	\N	{"status": "cancelled"}	2026-09-03 01:00:00+00
9a042a01-a055-5998-a65f-3bfa917a4ef1	8a4c23ed-cb76-55d6-8de2-d9255a7b35d3	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
17fe8ec7-fed8-5300-8dbb-8f51183dca76	72d47fd7-418b-54f8-b70e-47f540aa0410	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
99647f69-0f77-5a11-941a-5e95fd6b3993	72d47fd7-418b-54f8-b70e-47f540aa0410	7cedc8b3-3996-52bc-a6de-5f6f2041740f	checked_in	\N	{"status": "checked_in"}	2026-09-03 01:00:00+00
25e9c8de-7f34-556a-8035-80fa2650f1eb	459a9bd6-464c-576d-8ff2-d229c1ad32d6	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
2f47a4a8-3554-52b9-a700-303d4fe53c20	459a9bd6-464c-576d-8ff2-d229c1ad32d6	7cedc8b3-3996-52bc-a6de-5f6f2041740f	in_progress	\N	{"status": "in_progress"}	2026-09-03 01:00:00+00
b8710d1a-7569-505c-9bf8-33de8487f0f3	ee1a172a-5c0f-59bf-851b-580dbe0c69f5	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
aa82fa12-568c-56d5-85a5-93fca215f71e	ee1a172a-5c0f-59bf-851b-580dbe0c69f5	7cedc8b3-3996-52bc-a6de-5f6f2041740f	completed	\N	{"status": "completed"}	2026-09-03 02:00:00+00
63d96662-4da1-559d-a508-f9b387274621	817bb0d2-44c5-5c61-914c-17b3ac6d4995	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
088bdd90-d38d-5bea-ae94-62e864a139f6	817bb0d2-44c5-5c61-914c-17b3ac6d4995	7cedc8b3-3996-52bc-a6de-5f6f2041740f	cancelled	\N	{"status": "cancelled"}	2026-09-03 02:00:00+00
b172ad47-dc2e-5146-b28c-1f6bcc11dfe0	caa3557d-36eb-556e-b391-d9057fc59ca3	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
eb5f0aa2-5f98-5aa7-b315-f5d9a8021a63	7dc04982-934e-5a23-9153-bc402adda956	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
62c5fb48-5901-5f7c-a1f6-5ed9921f3520	7dc04982-934e-5a23-9153-bc402adda956	7cedc8b3-3996-52bc-a6de-5f6f2041740f	checked_in	\N	{"status": "checked_in"}	2026-09-03 02:00:00+00
26583c74-72ae-59a9-a24c-b4ecaeacc6af	d00534d3-40d4-5c9d-8d56-e10bdcc947d3	7cedc8b3-3996-52bc-a6de-5f6f2041740f	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
c060bbf0-6e9b-5ac3-839a-574eb612712a	d00534d3-40d4-5c9d-8d56-e10bdcc947d3	7cedc8b3-3996-52bc-a6de-5f6f2041740f	in_progress	\N	{"status": "in_progress"}	2026-09-03 02:00:00+00
15e2e89c-15bd-58ee-81c9-0cd5582f5ee0	046a62e0-c90a-56b7-a7d7-304f8be5770e	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
8a9aa3d1-cd0a-5de7-82d4-dcfed8f4b33a	046a62e0-c90a-56b7-a7d7-304f8be5770e	725e5cc4-6682-5e91-a195-973b60f26754	completed	\N	{"status": "completed"}	2026-08-27 06:00:00+00
95c3a15d-da80-5fcd-a13a-ea7ee5be32ec	11ca01c4-1317-5277-b800-2e5e6d2b8dac	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
9e4ef551-0d3b-5df7-aa68-e1cef76a3c4d	11ca01c4-1317-5277-b800-2e5e6d2b8dac	725e5cc4-6682-5e91-a195-973b60f26754	cancelled	\N	{"status": "cancelled"}	2026-08-27 06:00:00+00
1e4fc282-d6c0-5226-9319-d52cb562c707	96d525e6-6502-5c87-8088-44848f1e50ae	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
407f193f-10e4-5369-b191-82467eff9ddb	983efce1-7010-5876-8bd0-d0888d318535	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d6b20dff-9d49-51e6-8e5a-c45df4377edd	983efce1-7010-5876-8bd0-d0888d318535	725e5cc4-6682-5e91-a195-973b60f26754	checked_in	\N	{"status": "checked_in"}	2026-08-27 06:00:00+00
080139e8-4d6a-5b99-80c8-fb9a1898493d	083b4b0a-d7bf-5a80-904f-5bd7deceed55	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
74a04bfa-724d-5678-8701-9c668e5985d7	083b4b0a-d7bf-5a80-904f-5bd7deceed55	725e5cc4-6682-5e91-a195-973b60f26754	in_progress	\N	{"status": "in_progress"}	2026-08-27 06:00:00+00
5d33efd0-2b45-57a6-a325-e623802ac805	339b73b4-8cd6-5f46-b4b5-98faf11f3d3d	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
35c83937-0c8d-58df-ad57-e98cc2b0340a	339b73b4-8cd6-5f46-b4b5-98faf11f3d3d	725e5cc4-6682-5e91-a195-973b60f26754	completed	\N	{"status": "completed"}	2026-08-27 07:00:00+00
ff647672-1598-51fa-8285-8501379dfad8	01ed52c9-7e2d-5d09-9fdf-0307a94d27d8	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
a9398454-b142-570c-85b1-e4f6e3c63ba4	01ed52c9-7e2d-5d09-9fdf-0307a94d27d8	725e5cc4-6682-5e91-a195-973b60f26754	cancelled	\N	{"status": "cancelled"}	2026-08-27 07:00:00+00
0fcd10dc-b48d-5ba5-a93b-acb4704d4d0b	11e8d049-c717-5936-9e32-c9ad84bf9567	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
5664472e-4795-5611-b58b-d61a0c75c641	124f135a-4b55-51af-8289-8d03aa04ad13	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
9ab00bef-1e2e-57db-84bb-8d2fa36af8b2	124f135a-4b55-51af-8289-8d03aa04ad13	725e5cc4-6682-5e91-a195-973b60f26754	checked_in	\N	{"status": "checked_in"}	2026-08-27 07:00:00+00
f133552c-e69d-51c7-8871-2a0a399e9491	e50dd2ea-6723-5069-8e30-9abf1a3c8ebe	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
4ee78f20-a595-57f9-8036-e24d54bf2c39	e50dd2ea-6723-5069-8e30-9abf1a3c8ebe	725e5cc4-6682-5e91-a195-973b60f26754	in_progress	\N	{"status": "in_progress"}	2026-08-27 07:00:00+00
30e1fe60-5d5e-53b7-80a7-eabe1e8027ae	f640f7dc-4389-54bd-a6bc-54c54198bcaf	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d478181f-419e-5032-9910-49e94a819755	f640f7dc-4389-54bd-a6bc-54c54198bcaf	725e5cc4-6682-5e91-a195-973b60f26754	completed	\N	{"status": "completed"}	2026-08-28 08:00:00+00
34f1f39b-9712-518c-83d6-59c54cf06812	422c4871-31d1-5ba2-8874-1ecf000fe2a1	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
169c245b-73e9-5150-a5a3-77fa60d76754	422c4871-31d1-5ba2-8874-1ecf000fe2a1	725e5cc4-6682-5e91-a195-973b60f26754	cancelled	\N	{"status": "cancelled"}	2026-08-28 08:00:00+00
4889c551-416f-57b6-8449-9e707ba604e7	9a19db3b-241f-5cbc-8d27-c169038ac12b	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
527a785e-b725-5311-a22a-53dff6e6be49	a294c79d-0853-5503-bf08-5cb44daf7272	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ab0ca271-96b5-5e8a-b967-0a0a3b62d750	a294c79d-0853-5503-bf08-5cb44daf7272	725e5cc4-6682-5e91-a195-973b60f26754	checked_in	\N	{"status": "checked_in"}	2026-08-28 08:00:00+00
6768b01d-5543-5447-886e-bd7eb027ce0c	e6e89bf4-a182-5457-8d65-d63275022432	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
1b638c4f-ba68-500b-8f2c-9885614a5aa0	e6e89bf4-a182-5457-8d65-d63275022432	725e5cc4-6682-5e91-a195-973b60f26754	in_progress	\N	{"status": "in_progress"}	2026-08-28 08:00:00+00
c7abeeb2-8b3d-5761-abf5-6e16bafb992a	2858ded8-19d8-5a99-b515-1de4947ed87f	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
f7aa1fda-f9d4-5651-8ba5-83265df1bb63	2858ded8-19d8-5a99-b515-1de4947ed87f	725e5cc4-6682-5e91-a195-973b60f26754	completed	\N	{"status": "completed"}	2026-08-28 09:00:00+00
e6df4ebd-db6c-5185-a33f-d34b9445c3ad	a631ee0b-d59d-54cb-b82b-24fd0586e22f	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
e379384a-823f-5c5b-bcc2-e34e2913e651	a631ee0b-d59d-54cb-b82b-24fd0586e22f	725e5cc4-6682-5e91-a195-973b60f26754	cancelled	\N	{"status": "cancelled"}	2026-08-28 09:00:00+00
4234389a-9e74-50d2-831f-4c8afac3759e	a75143b1-eb7d-555b-a6a1-80e3e8e6b7a6	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ddf01f2a-1c5d-5f73-baa5-5c9c708dcdf6	b696b2b9-af07-5a99-adca-a0074a51b3bc	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
ea464f98-3527-54f6-80f6-e4060ba41163	b696b2b9-af07-5a99-adca-a0074a51b3bc	725e5cc4-6682-5e91-a195-973b60f26754	checked_in	\N	{"status": "checked_in"}	2026-08-28 09:00:00+00
ea19cbdd-57a1-5160-a7c1-675eb53ba0c4	0e085804-8bb3-5c65-98f9-5b1a16a23bc1	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
6762ba32-67f8-5601-9950-a439dac32693	0e085804-8bb3-5c65-98f9-5b1a16a23bc1	725e5cc4-6682-5e91-a195-973b60f26754	in_progress	\N	{"status": "in_progress"}	2026-08-28 09:00:00+00
74a6cfa2-b5c6-54c0-b7b5-dccd2d4acdeb	a632049b-5eaf-54a0-af20-0c97cfe687d9	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
a78cbc01-bc74-5372-b349-ea832097ce17	a632049b-5eaf-54a0-af20-0c97cfe687d9	725e5cc4-6682-5e91-a195-973b60f26754	completed	\N	{"status": "completed"}	2026-09-03 10:00:00+00
6a9152b0-44b0-5b22-8881-68ad2d59455a	f25259c8-3eff-5f58-8e9f-944fbfb9a7b3	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
50057129-c987-5534-bb7f-97a1018b465d	f25259c8-3eff-5f58-8e9f-944fbfb9a7b3	725e5cc4-6682-5e91-a195-973b60f26754	cancelled	\N	{"status": "cancelled"}	2026-09-03 10:00:00+00
691e4433-d33b-56ac-92b6-18c485ad90a1	a5659d7b-3b87-509e-92d7-489b8a454a9e	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d40293ea-80c6-5669-a882-c26e1fca1463	01a5daf6-126c-5ea9-8a49-ef48eaa33056	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
54c1c5fa-24a3-5e6a-9981-11e72461be44	01a5daf6-126c-5ea9-8a49-ef48eaa33056	725e5cc4-6682-5e91-a195-973b60f26754	checked_in	\N	{"status": "checked_in"}	2026-09-03 10:00:00+00
6ba49429-b31c-50ab-b17e-15efe082e138	d62e17b5-590c-53ff-bf82-35bf57ac3136	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
925a3532-ee1d-5953-8a49-47b92e7bec70	d62e17b5-590c-53ff-bf82-35bf57ac3136	725e5cc4-6682-5e91-a195-973b60f26754	in_progress	\N	{"status": "in_progress"}	2026-09-03 10:00:00+00
15d35d12-fb7b-5bf3-8c4d-cca09e041dde	0563c049-6bff-57e2-8d0a-49c9aeb2028f	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
4156f080-836a-5c53-b954-5f70b56df2a2	0563c049-6bff-57e2-8d0a-49c9aeb2028f	725e5cc4-6682-5e91-a195-973b60f26754	completed	\N	{"status": "completed"}	2026-09-03 11:00:00+00
5b742b76-1176-502b-8d32-a631c8e05e3e	47b47b9b-443c-5af4-9cc7-bbb4d18da237	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
60d34bf0-c6e0-51b2-a719-172eae531875	47b47b9b-443c-5af4-9cc7-bbb4d18da237	725e5cc4-6682-5e91-a195-973b60f26754	cancelled	\N	{"status": "cancelled"}	2026-09-03 11:00:00+00
b2320689-b761-5c68-91a5-b916fc6d9fa8	f3432f7d-dba3-5ccc-a8c3-a1e1d117fcb7	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
832ded99-88c6-5c70-bfbb-6ceb9c53be14	57f4da57-577b-5193-b437-1e02c1291e69	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
8c4d9acb-54ab-57ec-aac8-d339fe78bf24	57f4da57-577b-5193-b437-1e02c1291e69	725e5cc4-6682-5e91-a195-973b60f26754	checked_in	\N	{"status": "checked_in"}	2026-09-03 11:00:00+00
1153f848-1abd-5471-9763-97392897578a	2da0cddf-93e0-56d4-96a8-38fa23aca797	725e5cc4-6682-5e91-a195-973b60f26754	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
7e919976-416e-54dd-baef-b50e0daf56c0	2da0cddf-93e0-56d4-96a8-38fa23aca797	725e5cc4-6682-5e91-a195-973b60f26754	in_progress	\N	{"status": "in_progress"}	2026-09-03 11:00:00+00
217c63d8-a3fd-5a04-baa5-957b3f3b2621	74d19b2d-a91d-5ae4-b72c-ad18325dd2bb	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
acbf11b8-4989-5cf9-87fa-05f1bbf60d6a	74d19b2d-a91d-5ae4-b72c-ad18325dd2bb	2ad48f7a-7d9b-5503-a68d-07001e014841	completed	\N	{"status": "completed"}	2026-08-27 14:00:00+00
f2cf561d-2eab-5267-b64a-b537e4806201	957ea531-0a9e-5913-b1cc-7e36293904be	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
1063a51a-c7b3-542b-8e41-77a78a26251f	957ea531-0a9e-5913-b1cc-7e36293904be	2ad48f7a-7d9b-5503-a68d-07001e014841	cancelled	\N	{"status": "cancelled"}	2026-08-27 14:00:00+00
96232c46-f0d9-5e8b-853e-699c83d7e488	352c053c-7ce5-5c50-a16f-95b386bc8fa1	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
03f1f82c-4987-5828-89bc-f77859aab6a5	8f780028-909c-5e1f-a59b-3e126bf600af	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
df121fce-95bb-5a6a-9955-a3739cd974c4	8f780028-909c-5e1f-a59b-3e126bf600af	2ad48f7a-7d9b-5503-a68d-07001e014841	checked_in	\N	{"status": "checked_in"}	2026-08-27 14:00:00+00
fc12dab5-6de7-5ea0-89f0-c8e536343c2a	d5c03091-be46-5656-ba36-ec8f62830e91	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
38061b3f-765c-580b-9f9e-06ae0614a307	d5c03091-be46-5656-ba36-ec8f62830e91	2ad48f7a-7d9b-5503-a68d-07001e014841	in_progress	\N	{"status": "in_progress"}	2026-08-27 14:00:00+00
6398ccf3-54ba-51e5-9f82-9e6ceae66421	701ca8af-2dea-5e92-85f9-848ee5e18a2f	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
577da9a7-91fc-5ff0-9b14-f6bfc066a063	701ca8af-2dea-5e92-85f9-848ee5e18a2f	2ad48f7a-7d9b-5503-a68d-07001e014841	completed	\N	{"status": "completed"}	2026-08-27 15:00:00+00
1cd7fb50-26e5-58b3-b02a-f73ec3649883	a464346f-d4fd-5039-89b7-079107ba4709	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
a0af9b98-ba4b-56c8-8ff2-0df73c8e8e2d	a464346f-d4fd-5039-89b7-079107ba4709	2ad48f7a-7d9b-5503-a68d-07001e014841	cancelled	\N	{"status": "cancelled"}	2026-08-27 15:00:00+00
d656fed7-6329-5b7d-a28b-729a2e7d171c	ea68f82e-0a49-564e-854e-52f6a627a863	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d9b4be87-fe31-5516-93d3-3d8fa96cfcbd	1359d325-e1dd-559c-a4d0-a962c62508a7	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
95da3f78-7e9b-5489-8810-f87077a122b9	1359d325-e1dd-559c-a4d0-a962c62508a7	2ad48f7a-7d9b-5503-a68d-07001e014841	checked_in	\N	{"status": "checked_in"}	2026-08-27 15:00:00+00
8eb016d4-f9f9-5372-8e46-45b79b4ab8f1	49ee3e16-c24a-547b-b05d-6d25475f4cff	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
6c3da874-e866-544b-89ef-13b45e8296b7	49ee3e16-c24a-547b-b05d-6d25475f4cff	2ad48f7a-7d9b-5503-a68d-07001e014841	in_progress	\N	{"status": "in_progress"}	2026-08-27 15:00:00+00
4146da02-ad84-58ef-afb5-6314736b1e3f	a6f39d8e-6a95-5cd6-be05-610083ee0609	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
c558229d-26d2-53c0-8c4d-c5753d191478	a6f39d8e-6a95-5cd6-be05-610083ee0609	2ad48f7a-7d9b-5503-a68d-07001e014841	completed	\N	{"status": "completed"}	2026-08-28 16:00:00+00
885a844d-85b8-51af-a258-4f8bcebbd467	0a88e4ba-6992-576c-8d88-d4c668321f11	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
1ede892d-5447-54f1-a04d-15af860c17a7	0a88e4ba-6992-576c-8d88-d4c668321f11	2ad48f7a-7d9b-5503-a68d-07001e014841	cancelled	\N	{"status": "cancelled"}	2026-08-28 16:00:00+00
befaa833-4a1f-5232-8f99-8e005a89d89d	ec69ef24-35e8-5eec-913c-e74c29fe329a	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
c0de9fb1-2533-5b31-bd31-8b49626515e0	7ad83945-6cac-59bf-8278-67144b7b6264	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
afc08eab-a112-5395-a707-1f5b315d9469	7ad83945-6cac-59bf-8278-67144b7b6264	2ad48f7a-7d9b-5503-a68d-07001e014841	checked_in	\N	{"status": "checked_in"}	2026-08-28 16:00:00+00
182adad9-cd80-57ef-92d5-82e90b1a021a	03dd3106-c13f-5501-8900-f2553d346387	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
0a668996-bedb-5bed-9d37-e7382d616890	03dd3106-c13f-5501-8900-f2553d346387	2ad48f7a-7d9b-5503-a68d-07001e014841	in_progress	\N	{"status": "in_progress"}	2026-08-28 16:00:00+00
dd50fc6b-bf43-5f7d-932c-cd679e33eea2	38ece363-7034-5af6-b988-c5d92552e6be	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
44a43377-a771-5636-8b8c-a594509960ab	38ece363-7034-5af6-b988-c5d92552e6be	2ad48f7a-7d9b-5503-a68d-07001e014841	completed	\N	{"status": "completed"}	2026-08-28 17:00:00+00
9e822744-9670-5326-8dea-57a74ee9ec95	de7aa3a5-55dd-5635-a9a2-4c8e7d229a54	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
e389f4d3-26ca-5c84-84a3-b9091676190d	de7aa3a5-55dd-5635-a9a2-4c8e7d229a54	2ad48f7a-7d9b-5503-a68d-07001e014841	cancelled	\N	{"status": "cancelled"}	2026-08-28 17:00:00+00
a9b38f06-a744-5ddf-8df8-47a28a9c0321	e7d1574e-5124-5b1e-8715-814772a587fa	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
a3200816-7271-58cd-acd9-f1a93f62b77e	c543cda9-b2fd-559c-a757-490848fdf302	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
74876e76-ccf7-57d2-b834-3d486fc1a66c	c543cda9-b2fd-559c-a757-490848fdf302	2ad48f7a-7d9b-5503-a68d-07001e014841	checked_in	\N	{"status": "checked_in"}	2026-08-28 17:00:00+00
b61cb74c-a45d-5b66-8c3a-a9e35667b1ee	7989a5e7-e12b-5875-954b-68ffaf8d0814	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
c08d9575-149e-525b-9675-a1c6c0435ab3	7989a5e7-e12b-5875-954b-68ffaf8d0814	2ad48f7a-7d9b-5503-a68d-07001e014841	in_progress	\N	{"status": "in_progress"}	2026-08-28 17:00:00+00
a5b1ea20-0491-5a37-8138-8aec5626435e	ba820a4e-0f95-5b7d-b9a5-721a767736e3	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
890c273a-6e86-5325-ab35-af6596e9d5ea	ba820a4e-0f95-5b7d-b9a5-721a767736e3	2ad48f7a-7d9b-5503-a68d-07001e014841	completed	\N	{"status": "completed"}	2026-09-03 18:00:00+00
0a8f7f03-4a8d-5f76-aa09-e316b87d90e5	dafdef31-4855-5c70-896f-08b743bfbcd8	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
86b9c12a-6a3d-5441-b142-5ec1fabc0d5a	dafdef31-4855-5c70-896f-08b743bfbcd8	2ad48f7a-7d9b-5503-a68d-07001e014841	cancelled	\N	{"status": "cancelled"}	2026-09-03 18:00:00+00
bddd0197-f3d7-5930-9f14-f6a054893387	501adc19-bc0a-5cb2-a6d6-8af3d8185d88	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
88119fdb-a151-556b-9b52-0db634a127b7	f5c38f17-4c28-50b3-bc95-a128be000c91	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
dea115cc-2333-59c5-a10f-a2d16dbb31d0	f5c38f17-4c28-50b3-bc95-a128be000c91	2ad48f7a-7d9b-5503-a68d-07001e014841	checked_in	\N	{"status": "checked_in"}	2026-09-03 18:00:00+00
f0da67e6-fde3-5e26-a391-419237dc40cf	c284dca7-557c-5e19-b7a1-3a373f8cc6c1	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
b04ec9f8-b93e-5708-8769-868a44bf3567	c284dca7-557c-5e19-b7a1-3a373f8cc6c1	2ad48f7a-7d9b-5503-a68d-07001e014841	in_progress	\N	{"status": "in_progress"}	2026-09-03 18:00:00+00
0a0f3df9-131f-5024-b391-bd3cbde4d38d	0c4c44f9-7438-5ede-a780-f8a0d3dbbcef	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
c78c8a0b-51e4-5b53-80a2-a24972fe374e	0c4c44f9-7438-5ede-a780-f8a0d3dbbcef	2ad48f7a-7d9b-5503-a68d-07001e014841	completed	\N	{"status": "completed"}	2026-09-03 19:00:00+00
0c1d8fdb-3768-5cf5-9bf2-4676a462caae	6f5405e0-8f9f-5ddf-85b3-0a253bb19180	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
7af8c536-f883-5b18-8d59-e3326ab74565	6f5405e0-8f9f-5ddf-85b3-0a253bb19180	2ad48f7a-7d9b-5503-a68d-07001e014841	cancelled	\N	{"status": "cancelled"}	2026-09-03 19:00:00+00
ae18d2fd-fea7-5267-8787-0af5a2b79c20	817b51f8-1b7b-50dc-97ba-9dafc2be9dc2	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
84a8b25b-1d9d-55df-9b8f-8b5fdf24fe27	8e9e7fd7-904d-5242-9357-df8a2663f200	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
938d1139-0f4e-5b13-a2e9-9001a4204e8b	8e9e7fd7-904d-5242-9357-df8a2663f200	2ad48f7a-7d9b-5503-a68d-07001e014841	checked_in	\N	{"status": "checked_in"}	2026-09-03 19:00:00+00
35df74fa-6661-568c-8963-347ee1e3ea79	3c5d29ec-88b0-5f97-a6c7-5af942f91230	2ad48f7a-7d9b-5503-a68d-07001e014841	created	\N	{"status": "requested"}	2026-08-01 00:00:00+00
d6da8ec1-54f4-55be-ba84-ae63900e7b66	3c5d29ec-88b0-5f97-a6c7-5af942f91230	2ad48f7a-7d9b-5503-a68d-07001e014841	in_progress	\N	{"status": "in_progress"}	2026-09-03 19:00:00+00
ee2a7023-41e9-4325-a4cc-664d4a6bcbbf	2b01e87d-1e6a-477b-a248-6703f9b07baa	3b037fab-ef51-55de-abac-63d4f0242ed4	created	\N	{"status": "requested", "ends_at": "2026-09-01T04:00:00Z", "starts_at": "2026-09-01T02:00:00Z"}	2026-08-30 10:24:33.824784+00
0bc38925-f418-4347-8db3-7c0abf23bb7a	965ccd4c-361d-436f-9e0d-15770bc3524b	3b037fab-ef51-55de-abac-63d4f0242ed4	created	\N	{"status": "requested", "ends_at": "2026-09-01T04:00:00Z", "starts_at": "2026-09-01T02:00:00Z"}	2026-08-30 10:50:53.186967+00
2cc6a831-c8d4-42ff-ae71-465dc6d892c6	355cbc7b-4e80-4651-a8bb-98315b6db970	3b037fab-ef51-55de-abac-63d4f0242ed4	created	\N	{"status": "requested", "ends_at": "2026-09-16T04:00:00Z", "starts_at": "2026-09-16T02:00:00Z"}	2026-08-30 11:00:33.368694+00
\.


--
-- Data for Name: appointment_idempotency; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.appointment_idempotency (idempotency_key, appointment_id, created_at, deleted_at) FROM stdin;
\.


--
-- Data for Name: appointment_resource_reservations; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.appointment_resource_reservations (appointment_resource_reservation_id, appointment_id, resource_type, resource_id, reserved_starts_at, reserved_ends_at, status, assigned_at, released_at, assigned_by_user_id, reason) FROM stdin;
320e9bf7-d1fc-5493-affe-c4a16e8537d1	c1be6607-1700-5bd1-8c30-a11a772a9d39	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 01:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
1adb43b0-57ac-574d-9841-7c83f5b4fc0c	c1be6607-1700-5bd1-8c30-a11a772a9d39	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 01:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
424d9e1c-e323-5d94-b7dc-6a5fd4fa0152	51d98f33-5a44-55b5-b473-3c834876a284	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 01:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
a2dbc275-18c9-5d14-b92a-00a30b33b65b	51d98f33-5a44-55b5-b473-3c834876a284	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 01:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
53edb7f7-1746-5cc5-bbf1-75e0995245ad	c36806f7-30b8-5e1a-b19a-5de4afc3ba82	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
52597926-92c9-5a98-aaab-bdfdc03fd4b1	c36806f7-30b8-5e1a-b19a-5de4afc3ba82	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
69e0dc1c-66ab-5d3e-8a13-23b1243bbe05	512f2cc0-21f1-5582-bde7-92d1d446501a	technician	7497e944-d4ac-58cd-a8f7-b33478331e7e	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
fc4aa8b0-1676-5230-8351-fa08192fc893	512f2cc0-21f1-5582-bde7-92d1d446501a	service_bay	ff440016-8cdc-5773-a81e-2a040283208b	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
12d9faa0-55aa-58fd-8d71-df3aea741c53	70d87942-32d1-57e6-b368-8a78f441f5d4	technician	aab629e4-5965-5d14-a69f-e8d2db5df493	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
ba087855-4e7b-5bef-bfe4-6600636cbd69	70d87942-32d1-57e6-b368-8a78f441f5d4	service_bay	f924649c-3402-5659-b18a-385fdece1353	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
216c5b37-d148-54f7-a1e7-f1193614462c	32276637-d152-5de4-b70c-f479d93301a3	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 02:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
647dee27-3c6c-5320-969c-7e8829022cfa	32276637-d152-5de4-b70c-f479d93301a3	service_bay	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 02:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
1fe67216-ec83-59fd-90ca-7e98938a628c	028f3e80-dddf-5362-b6e7-9cca35ffe13a	technician	fdfee93f-949b-5a04-849c-bb943a92e4bd	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 02:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
30b42a55-e360-5cba-81d9-849b9c9da885	028f3e80-dddf-5362-b6e7-9cca35ffe13a	service_bay	ecf7be60-2540-5e7d-88f8-99cec4954edb	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 02:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
8fda212d-cc2f-5d51-9c96-e0c1ac36e718	4b5fe5f0-1672-5971-9882-360d05edf5f5	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
8cb78fb2-19b2-5a60-b4a2-bc1e5d16b818	4b5fe5f0-1672-5971-9882-360d05edf5f5	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
87f3c6ed-010e-53d9-b81b-5244bef366d1	505c41f3-ab0e-5258-9049-bde98a3211bd	technician	7497e944-d4ac-58cd-a8f7-b33478331e7e	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
c83473b7-04b9-50c1-9051-b5d554ab2dfa	505c41f3-ab0e-5258-9049-bde98a3211bd	service_bay	619ea9fa-4c9d-506e-8838-5f527f5223c2	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
1bbb9419-23dc-566a-bf00-9f984eab6cc2	c3de56e7-38d4-59b4-ac0d-72e210bdbf95	technician	aab629e4-5965-5d14-a69f-e8d2db5df493	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
f36bc1ed-2ee4-5db1-89f6-6329719ebfe3	c3de56e7-38d4-59b4-ac0d-72e210bdbf95	service_bay	0a1fae29-1e5b-5efc-b8a9-0887d4c25610	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
2fe845a8-7fb9-5e97-81f5-189e4468a8b7	68dd5464-9979-56fb-9177-c11bb97f88eb	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 03:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
9d280a24-0bbe-564b-a3ab-e10dad0ba5e1	68dd5464-9979-56fb-9177-c11bb97f88eb	service_bay	ff440016-8cdc-5773-a81e-2a040283208b	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 03:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
2f872462-477b-5866-9076-9a57162ad39a	6e8ddc03-dd54-58a1-b707-6f638c67cdc6	technician	fdfee93f-949b-5a04-849c-bb943a92e4bd	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 03:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
b937cdbd-a7eb-530a-9d21-eb609d8695bc	6e8ddc03-dd54-58a1-b707-6f638c67cdc6	service_bay	f924649c-3402-5659-b18a-385fdece1353	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 03:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
508dae90-faee-5eac-9492-f41c4583c86d	ba1eb83b-2463-5459-b573-6091d22f893e	technician	780d2c59-38da-5e9b-8b59-d3377186faab	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
252d2ce2-b085-5a81-b17a-70018fb38519	ba1eb83b-2463-5459-b573-6091d22f893e	service_bay	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
63f62428-113e-50c5-8960-c5a79bd79ed2	b42f07e6-193a-573e-83f5-8f0efb29cc9e	technician	7497e944-d4ac-58cd-a8f7-b33478331e7e	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
ef419eeb-0a76-5997-83b5-e51aed1e40a7	b42f07e6-193a-573e-83f5-8f0efb29cc9e	service_bay	ecf7be60-2540-5e7d-88f8-99cec4954edb	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
788685b5-9b94-57f9-98bb-92e1aaf90282	f7eb979a-71c5-59c7-9f6d-cc67215c0a42	technician	aab629e4-5965-5d14-a69f-e8d2db5df493	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
3a2b8495-e217-537b-9c55-dce193ee27a8	f7eb979a-71c5-59c7-9f6d-cc67215c0a42	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
505ff780-b4d3-59e1-affc-d4cd90f119e0	89cbbf80-8ed3-5794-ba37-a2bcadf57dd9	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 04:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
3a8315bf-bd4b-504d-94d2-1c189cc9c444	89cbbf80-8ed3-5794-ba37-a2bcadf57dd9	service_bay	619ea9fa-4c9d-506e-8838-5f527f5223c2	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 04:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
db66b1f3-f020-5b82-b92a-8e13fc23e096	8ee6032a-ec74-5a8a-a084-2ef75bacc8ea	technician	fdfee93f-949b-5a04-849c-bb943a92e4bd	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 04:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
c8bbc82c-22ae-51b1-8ed0-7cede0b6d0c1	8ee6032a-ec74-5a8a-a084-2ef75bacc8ea	service_bay	0a1fae29-1e5b-5efc-b8a9-0887d4c25610	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 04:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
b6a6c10b-ec83-52d6-809e-585e09306a98	8e39ab31-f7f9-53b5-9d5c-ce33ff187b07	technician	780d2c59-38da-5e9b-8b59-d3377186faab	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
0efdfdc6-eebd-5427-ac30-fb0c9cca8591	8e39ab31-f7f9-53b5-9d5c-ce33ff187b07	service_bay	ff440016-8cdc-5773-a81e-2a040283208b	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
5045e833-0397-502d-b2ad-bd86bccb9a02	fd1b3303-a5de-5e71-92ee-e18a700ff091	technician	7497e944-d4ac-58cd-a8f7-b33478331e7e	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
db47cb47-f979-5a82-9ffb-d83065776887	fd1b3303-a5de-5e71-92ee-e18a700ff091	service_bay	f924649c-3402-5659-b18a-385fdece1353	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
b061ef4f-476c-51f1-bd08-b8eb394ef2a5	508a1ec3-6d18-5080-9ea8-d288caec0e52	technician	aab629e4-5965-5d14-a69f-e8d2db5df493	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
f04135bb-f1d4-5dd6-9dad-b3957409f3be	508a1ec3-6d18-5080-9ea8-d288caec0e52	service_bay	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
4f3e0e0b-e1cf-549e-b11e-9e10de502d36	ccb0b729-659c-5948-91af-a3d00ade05b8	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 05:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
2279b342-ec04-5d19-aa83-2ddf791143f6	ccb0b729-659c-5948-91af-a3d00ade05b8	service_bay	ecf7be60-2540-5e7d-88f8-99cec4954edb	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 05:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
542c3a00-8308-528c-b939-dca76db2d931	6a047d7d-bdbf-5067-869b-69daf14ca320	technician	fdfee93f-949b-5a04-849c-bb943a92e4bd	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 05:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
165c8ee6-b049-5995-ab63-da768103164c	6a047d7d-bdbf-5067-869b-69daf14ca320	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 05:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
b0526049-edab-51a0-aab7-826f44c02873	233400f6-3b7f-5648-bb71-202b2aec854c	technician	780d2c59-38da-5e9b-8b59-d3377186faab	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
13b146d3-3d30-5ba5-94f3-4db911568380	233400f6-3b7f-5648-bb71-202b2aec854c	service_bay	619ea9fa-4c9d-506e-8838-5f527f5223c2	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
b37c398f-4ae5-50ea-863a-8a312c6e2bf0	cde45d35-f67e-5f9f-aeb2-06b49e2aad3d	technician	7497e944-d4ac-58cd-a8f7-b33478331e7e	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
0edc839d-291c-5fe3-ae94-e2600ac4bba1	cde45d35-f67e-5f9f-aeb2-06b49e2aad3d	service_bay	0a1fae29-1e5b-5efc-b8a9-0887d4c25610	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
7738a85b-015a-5095-bdaf-dd893372b986	b8453e21-1f95-5e6b-ab8e-d7a919f85dff	technician	aab629e4-5965-5d14-a69f-e8d2db5df493	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
b71a6f45-005f-5893-b1d4-3aeb1f0b0e86	b8453e21-1f95-5e6b-ab8e-d7a919f85dff	service_bay	ff440016-8cdc-5773-a81e-2a040283208b	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
4eb0659f-49e3-5be6-832f-1c3041bc7619	f8726250-0119-59ae-8c57-702615784cc1	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 06:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
25a929a5-0a2b-5e4b-9707-0d1cdba91389	f8726250-0119-59ae-8c57-702615784cc1	service_bay	f924649c-3402-5659-b18a-385fdece1353	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 06:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
f374f9c0-002f-5a73-adb2-e48d4ef42140	97cff4f4-8a65-55fc-9f01-e3d97cdb097a	technician	fdfee93f-949b-5a04-849c-bb943a92e4bd	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 06:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
f2315a69-4090-5515-ab43-1b44915fe0ca	97cff4f4-8a65-55fc-9f01-e3d97cdb097a	service_bay	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 06:00:00+00	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
8fefc4e8-7e74-5bc6-be0e-a9fb20553381	71bfbd58-db4e-5e66-be5c-7b3c8973b14e	technician	780d2c59-38da-5e9b-8b59-d3377186faab	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
8f420da1-0828-5397-998a-adbacb6a611e	71bfbd58-db4e-5e66-be5c-7b3c8973b14e	service_bay	ecf7be60-2540-5e7d-88f8-99cec4954edb	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	requested	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
f9bb9303-1a60-5026-b2ca-316685127e0e	0d1929f8-6dbd-5ec0-bed5-3bd2891793dc	technician	7497e944-d4ac-58cd-a8f7-b33478331e7e	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
09c08e55-e399-5b54-ad03-59c84446dd0c	0d1929f8-6dbd-5ec0-bed5-3bd2891793dc	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
72a7ddd0-4459-5332-b9cc-16778fee3100	5fe8bcc3-eef7-5412-9325-4799e84653d5	technician	aab629e4-5965-5d14-a69f-e8d2db5df493	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
b7fc0e4a-6da6-5cec-8573-b5eaacb92bef	5fe8bcc3-eef7-5412-9325-4799e84653d5	service_bay	619ea9fa-4c9d-506e-8838-5f527f5223c2	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	a73801eb-398a-54d0-8e82-e50c59407287	Seed fixture
7f4315e3-0732-50ee-8d59-591a6835961f	eda78781-d975-5169-ab34-444c65348509	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
ea658d11-d701-5a05-b59d-fc6a008fcf49	eda78781-d975-5169-ab34-444c65348509	service_bay	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
2f342965-2e40-52a5-a4ea-ecc7ca440968	e9a173fd-770c-5f71-911a-330de6bd6f15	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
8014eb97-e9cc-5b76-9a83-27d042dcbca1	e9a173fd-770c-5f71-911a-330de6bd6f15	service_bay	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
77196979-8882-5311-9edc-16d24a955e02	746e6df4-6a1a-5f90-a351-d465c3557099	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
6bd81440-11b6-5cd8-8669-ebf4a92d0684	746e6df4-6a1a-5f90-a351-d465c3557099	service_bay	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
cf2c9ce9-191c-5789-b4ba-9886215a6c0c	913fbedb-c4d5-5402-b309-234a3935aa70	technician	93a7232e-d474-5224-8e5b-fd7e98e60a52	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
01e6ce0e-2d2d-5a64-8db5-916098267e95	913fbedb-c4d5-5402-b309-234a3935aa70	service_bay	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
92a916e4-9b3a-5686-a80c-c7a4cc974600	21429526-e9cb-5a8a-a3c4-666b47d7ed17	technician	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
0c512dc8-796b-5efc-a0ba-96dd70a3a0dd	21429526-e9cb-5a8a-a3c4-666b47d7ed17	service_bay	dcd21ca1-995a-51e7-b954-60af0e35b8ac	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
edbe8edf-85e2-52bb-a610-746acbeda7e9	af5a8a6a-fbb5-5079-a426-6f14edd418a6	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 00:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
badac96b-1f68-5564-bb52-1fe7aee2cfcc	af5a8a6a-fbb5-5079-a426-6f14edd418a6	service_bay	42eff788-5be8-5f54-afb7-7c14606599ea	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 00:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
4d865cbc-495e-5792-adab-35d75200f537	d4341c25-0d74-5b56-85cd-6e58e3e93bb4	technician	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 00:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
853354fe-0158-5268-9624-7c96c95315a2	d4341c25-0d74-5b56-85cd-6e58e3e93bb4	service_bay	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 00:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
8dfc8937-ddb8-5981-9abd-7a987e5451ab	0cc6efe8-f98b-57de-97d2-b7eea2933fe6	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
333992b6-d8a8-51cd-89e6-e9df63338975	0cc6efe8-f98b-57de-97d2-b7eea2933fe6	service_bay	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
cc91efa1-bdce-56e6-9ba3-e01e723f61b4	51b8c108-389b-54d4-8235-53c82c937d2e	technician	93a7232e-d474-5224-8e5b-fd7e98e60a52	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
5191582b-8e05-528c-8e5c-1243be97d412	51b8c108-389b-54d4-8235-53c82c937d2e	service_bay	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
d36c1981-cef3-5f63-93cf-45921d0b5329	fa59e79c-eb85-5380-b460-41e1d1329b4c	technician	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
c942becf-ef8d-55a1-96a0-bf1ddab1a877	fa59e79c-eb85-5380-b460-41e1d1329b4c	service_bay	94e41d7e-908c-5e90-b8a2-410674183b28	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
ede22f07-48fb-543a-8e81-b61d48b44b1d	527a4178-db47-578d-bab2-2f3f3bffcb2f	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
6ca1ec64-e2a1-50b5-8edc-e7d6ecef42cb	527a4178-db47-578d-bab2-2f3f3bffcb2f	service_bay	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
0adc1ad9-a24f-5f14-937f-69c9e9466f21	6d4b2ca5-aa5d-5009-b035-a237a34f192e	technician	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
1d93fd05-4f33-5c6f-b220-d251c717e4d9	6d4b2ca5-aa5d-5009-b035-a237a34f192e	service_bay	dcd21ca1-995a-51e7-b954-60af0e35b8ac	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
b95cca52-66c9-5b6c-bff7-77d3baa58f53	7f4b449a-c0a0-5b65-9c9b-0737bdfa00ee	technician	60805ebd-cae5-57ce-aa9d-362d81cfc131	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
53ae56de-eed8-5d2a-b0e4-efce15e76e49	7f4b449a-c0a0-5b65-9c9b-0737bdfa00ee	service_bay	42eff788-5be8-5f54-afb7-7c14606599ea	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
491b0ea0-249a-559e-80d9-27b1ca0486e6	acf9525c-2a74-56a6-9baa-3df7f68cf8f5	technician	93a7232e-d474-5224-8e5b-fd7e98e60a52	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
4b36516e-8a9f-5cdc-b5f2-b4101e731fe4	acf9525c-2a74-56a6-9baa-3df7f68cf8f5	service_bay	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
564d469e-5d3f-58a8-b9bd-68102835e8f7	74bf21e1-399b-579d-ab6f-9df4db0a5717	technician	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
dfa20759-3594-5e58-937d-2556bc3a2417	74bf21e1-399b-579d-ab6f-9df4db0a5717	service_bay	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
4c7fa10c-2e84-557c-ab90-3009d361e73a	b6103c5a-02b9-54fa-a10a-f5601a4816a7	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 02:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
bb78fff8-f591-58bd-b6cf-af65208a8d55	b6103c5a-02b9-54fa-a10a-f5601a4816a7	service_bay	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 02:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
3a69498e-5622-50ae-be43-25cc63bd9b24	c79f06ec-6932-5029-b0ae-687b23d87ac8	technician	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 02:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
b22c4d70-83b5-538c-96dd-09de838b2f9a	c79f06ec-6932-5029-b0ae-687b23d87ac8	service_bay	94e41d7e-908c-5e90-b8a2-410674183b28	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 02:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
da9f044c-2568-59f8-8db7-e40c5702c66d	6ad7b82b-ab35-584e-8607-df1ea988e370	technician	60805ebd-cae5-57ce-aa9d-362d81cfc131	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
abdf2814-7bee-524d-8ee2-c5ce7df5a6e7	6ad7b82b-ab35-584e-8607-df1ea988e370	service_bay	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
dd3a0462-2a9c-571e-beec-1b37bd27335e	7c224bd3-62e4-5d29-8b36-915f08d274ab	technician	93a7232e-d474-5224-8e5b-fd7e98e60a52	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
53a2b9fa-5ace-5c99-aeec-c4eb6419714c	7c224bd3-62e4-5d29-8b36-915f08d274ab	service_bay	dcd21ca1-995a-51e7-b954-60af0e35b8ac	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
23b7a0f6-27b4-580b-ac37-c63e27b2a9b3	91baae88-14a5-590d-b709-597f023bab50	technician	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
7f05916d-e918-516c-8749-ebe9cc6046e0	91baae88-14a5-590d-b709-597f023bab50	service_bay	42eff788-5be8-5f54-afb7-7c14606599ea	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
e8577294-df92-5008-ba3a-e9d71781ea00	cdf40560-d303-5cd8-acf1-1cb3a80b7393	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
53c662fa-5d0c-5691-9183-82735813998e	cdf40560-d303-5cd8-acf1-1cb3a80b7393	service_bay	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
c27c774d-1e74-5790-ba3e-7b1ad20db89f	863fb2cb-726a-547e-90cc-f78a0206926b	technician	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
61e91e4f-1bcc-5862-9ebc-baaa100bddda	863fb2cb-726a-547e-90cc-f78a0206926b	service_bay	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
023978ca-2c3d-5d12-af55-0b9c021558db	ee21cea7-e328-511f-835d-f51d390755c5	technician	60805ebd-cae5-57ce-aa9d-362d81cfc131	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
2991ac70-1eb0-5f1d-baa0-35f252949391	ee21cea7-e328-511f-835d-f51d390755c5	service_bay	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
19bf7563-56d8-5cbd-8066-119d20d9da2a	91b62df0-c992-506e-960c-ef0d5e0a10eb	technician	93a7232e-d474-5224-8e5b-fd7e98e60a52	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
f2b7afe1-bd30-504c-b6bd-56a8acc7fc60	91b62df0-c992-506e-960c-ef0d5e0a10eb	service_bay	94e41d7e-908c-5e90-b8a2-410674183b28	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
2b0e6d51-332a-5650-a0a0-47670d73fc6d	ee48f155-0ea2-5c4f-8788-c72642614915	technician	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
d68e371c-28c5-52d4-9895-07eea93bb196	ee48f155-0ea2-5c4f-8788-c72642614915	service_bay	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
cb2bee74-ac49-5869-8cf2-9a68abb855eb	8180cd6d-95cb-5b10-bf59-a452858e2beb	technician	6e4dae43-a541-594f-980b-6f78dedfcb0d	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 04:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
7ab5f279-575b-5783-9bd7-5a9900c49b3c	8180cd6d-95cb-5b10-bf59-a452858e2beb	service_bay	dcd21ca1-995a-51e7-b954-60af0e35b8ac	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 04:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
6a3869f5-875b-58b8-8307-7018f55b0cae	0f2551cc-952f-5382-a5d4-13e796ad1267	technician	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 04:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
a00ebc7c-3d51-53f5-9f0d-e49d735a5e57	0f2551cc-952f-5382-a5d4-13e796ad1267	service_bay	42eff788-5be8-5f54-afb7-7c14606599ea	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 04:00:00+00	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
57f0ba43-8853-5c4f-95e2-574ba283d93a	b7c5d581-9d85-59e4-96ca-88f3784eebfc	technician	60805ebd-cae5-57ce-aa9d-362d81cfc131	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
aaf80e71-c22b-5f91-9de5-9e4742a03491	b7c5d581-9d85-59e4-96ca-88f3784eebfc	service_bay	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	requested	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
6253c230-edb9-59e1-be33-8daf3653dd53	4ac1de9a-4df8-5ff6-82a9-016c44132e74	technician	93a7232e-d474-5224-8e5b-fd7e98e60a52	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
fd56e2c9-2750-52e9-a242-3887ba4746bb	4ac1de9a-4df8-5ff6-82a9-016c44132e74	service_bay	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
562222b3-8438-5a2d-8203-f5791e692c3e	f89aaf31-3917-50dc-928a-4aac5a5bdd69	technician	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
1b9c1ccf-58fa-5b2d-9b6e-ff41c82e2af7	f89aaf31-3917-50dc-928a-4aac5a5bdd69	service_bay	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	ded9e174-90f2-5ea7-9b35-86728f8544f7	Seed fixture
f0fd2f57-097a-56f9-a305-6cbfa0d7d7e2	4b444f6b-ddf5-5197-9593-718af083c89a	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-26 22:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
546aa947-588f-5255-92b2-508d3483b0ad	4b444f6b-ddf5-5197-9593-718af083c89a	service_bay	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-26 22:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
715c64ee-bb34-5d51-95c5-f843ca3793f3	0d5617d9-0de9-5f7d-a762-d26fa80048f8	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-26 22:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
bf2292be-bc76-5956-bbb1-6317c8a4e01f	0d5617d9-0de9-5f7d-a762-d26fa80048f8	service_bay	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-26 22:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
c9570593-d2b1-5d84-98cd-83520ec196a7	79504438-8585-5412-a0e7-d5b60dafd48a	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
0d4c8daa-390e-5699-abc7-569a52f7e0a4	79504438-8585-5412-a0e7-d5b60dafd48a	service_bay	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
6414c747-f342-552b-97dd-a5dc8d929e24	9c61762c-0ee2-51b8-938a-e279049ca95c	technician	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
1c8bc646-1d05-5e83-ac0e-3e01bec5f890	9c61762c-0ee2-51b8-938a-e279049ca95c	service_bay	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
8bdb463d-7e3a-5301-9ff2-b4c477054b65	e0dd9e5f-53b6-5c08-acfa-05a587e2ac8c	technician	f22afce6-9be8-5d54-8493-e187e6080d3d	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
419217f0-8e3e-5ae3-a35e-e69c2d695763	e0dd9e5f-53b6-5c08-acfa-05a587e2ac8c	service_bay	42ce9d61-5263-5784-b0c8-984b6bf6aaae	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
f0bd9ea9-f3e4-58d1-8ae3-cd58c7032b29	de360e40-e02c-5a71-acea-b80b29a40df8	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
8054c424-c83a-5b46-b582-917a8b0f06eb	de360e40-e02c-5a71-acea-b80b29a40df8	service_bay	8806d3d9-7c39-511e-ab4d-8ac2880f513f	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
beac4892-7e81-542b-8b7b-61f4c4e592c6	e4ca982c-fb5f-5359-b84a-ccc9ca3ef485	technician	a710b9c6-f208-5130-a26d-8a583a0cae4e	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
ccafc7d3-2560-5c78-9e70-318623582c6f	e4ca982c-fb5f-5359-b84a-ccc9ca3ef485	service_bay	432195c4-02e8-5310-b2a3-30ac3819e62b	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
9dfe1aca-bc9b-5ce7-bc8a-7f1eefad0bbe	1ee0e0ec-df9f-5a24-8596-78dc20ea5505	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
54ac75bf-20f6-5071-969f-d8f2ed94114d	1ee0e0ec-df9f-5a24-8596-78dc20ea5505	service_bay	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
33c8d995-4690-5610-b10f-508cbb86f016	f170be60-f842-5db8-9eef-571ef9bcb6a0	technician	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
c7a5146a-931f-5b7d-9eee-56a40edba460	f170be60-f842-5db8-9eef-571ef9bcb6a0	service_bay	9df77ddf-fe56-5e6f-8979-9b70e064d232	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
5b43129b-fc8c-5da7-b21d-07bed96daf22	62e2230e-6522-52e2-a581-854885613114	technician	f22afce6-9be8-5d54-8493-e187e6080d3d	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
3a96ddd0-30c3-56af-9c12-f484b918760e	62e2230e-6522-52e2-a581-854885613114	service_bay	2e5bd34a-e96d-50b1-89e7-4ced572bdad6	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
59b21629-0ea8-515c-9cfd-7d02e7b7831f	77554b46-a2d1-5c95-843d-d0bc4b12523f	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 00:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
43131e2f-2d22-5ad1-b88b-7cd80f7e3d91	77554b46-a2d1-5c95-843d-d0bc4b12523f	service_bay	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 00:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
1db76586-2206-5d86-a08a-99d426a76682	2d2fbe57-cf40-5023-b8fa-366f5c910bfd	technician	a710b9c6-f208-5130-a26d-8a583a0cae4e	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 00:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
1c4671c5-127a-5a54-ae03-62f44bdf0e10	2d2fbe57-cf40-5023-b8fa-366f5c910bfd	service_bay	42ce9d61-5263-5784-b0c8-984b6bf6aaae	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 00:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
ea47c7af-38f5-5e76-b0f2-05b7cdc52495	a81c1b3f-ef10-558b-b7c8-465db5e6eeed	technician	a2d88a64-e213-5b97-8356-654a9acaf896	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
ce67d10e-099f-5d7a-889b-724b4a479591	a81c1b3f-ef10-558b-b7c8-465db5e6eeed	service_bay	8806d3d9-7c39-511e-ab4d-8ac2880f513f	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
48acb16a-7ff2-5604-8337-c0e06f86e725	1182656f-e6a1-5e21-a922-dddd2272efae	technician	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
8d0daee6-0784-5cb8-b253-323ad62af23e	1182656f-e6a1-5e21-a922-dddd2272efae	service_bay	432195c4-02e8-5310-b2a3-30ac3819e62b	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
08fe797c-c677-553c-841d-689b7d6af1d1	30af9f27-45da-5500-b295-aab66f60aa20	technician	f22afce6-9be8-5d54-8493-e187e6080d3d	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
3485cfd9-4aef-5b43-a6f6-13527e75d96f	30af9f27-45da-5500-b295-aab66f60aa20	service_bay	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
28da7daa-f780-55fc-93f4-d66f7b78a9ba	dccfa163-8f7a-571c-b752-f9d913f1ea1d	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
39ccf4e6-61c9-57c2-8a35-642c7c49ab18	dccfa163-8f7a-571c-b752-f9d913f1ea1d	service_bay	9df77ddf-fe56-5e6f-8979-9b70e064d232	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
f962b04c-dfde-522c-923a-522d15a69fe5	1b32fb8c-3a63-55e8-ac78-19f1b0211117	technician	a710b9c6-f208-5130-a26d-8a583a0cae4e	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
46331314-424a-5e4f-ad80-4d88ffe7bb99	1b32fb8c-3a63-55e8-ac78-19f1b0211117	service_bay	2e5bd34a-e96d-50b1-89e7-4ced572bdad6	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
b0206133-b0d2-5c33-8b91-185185e3cad9	e4fe3c94-eda0-5699-83bd-95e4c7df170c	technician	a2d88a64-e213-5b97-8356-654a9acaf896	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
9d251a28-9feb-5c4b-936d-39188506e121	e4fe3c94-eda0-5699-83bd-95e4c7df170c	service_bay	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
38797133-40c1-5bf7-abb6-f6d826169605	8c535195-49b7-5c90-a309-89cf65c97c16	technician	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
0dbea95b-2962-5778-a1a8-650368bafa18	8c535195-49b7-5c90-a309-89cf65c97c16	service_bay	42ce9d61-5263-5784-b0c8-984b6bf6aaae	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
32475921-f7bb-569a-a984-91ab828a46b8	aff4d2d5-56f1-5c0c-94c0-9bb019ce56e4	technician	f22afce6-9be8-5d54-8493-e187e6080d3d	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
ef895e31-40f3-5327-9580-13d6a7d84bbf	aff4d2d5-56f1-5c0c-94c0-9bb019ce56e4	service_bay	8806d3d9-7c39-511e-ab4d-8ac2880f513f	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
ba6bdd93-0b91-5322-9c73-80b869579b7b	9a391023-01e3-5d06-a25b-742922dea10b	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 02:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
1fba7120-b5e5-567b-b040-928c44abe0f0	9a391023-01e3-5d06-a25b-742922dea10b	service_bay	432195c4-02e8-5310-b2a3-30ac3819e62b	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 02:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
25469a3d-e5ff-5f5f-9d66-6bab1e6fc5fa	4e7e57e6-f7b8-5d8c-b20a-f2204a32e1a3	technician	a710b9c6-f208-5130-a26d-8a583a0cae4e	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 02:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
c42fad3e-e717-5c6d-85d6-15289d498539	4e7e57e6-f7b8-5d8c-b20a-f2204a32e1a3	service_bay	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 02:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
125967e1-debe-5c5c-ad2e-30011beba882	8a4c23ed-cb76-55d6-8de2-d9255a7b35d3	technician	a2d88a64-e213-5b97-8356-654a9acaf896	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
54ce7d99-899a-556e-af8e-094aac396b88	8a4c23ed-cb76-55d6-8de2-d9255a7b35d3	service_bay	9df77ddf-fe56-5e6f-8979-9b70e064d232	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
d3e48a83-e52c-532c-bcb6-ddff25d22522	72d47fd7-418b-54f8-b70e-47f540aa0410	technician	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
ff7e4fbe-03b5-58f2-8c61-72b046d502b6	72d47fd7-418b-54f8-b70e-47f540aa0410	service_bay	2e5bd34a-e96d-50b1-89e7-4ced572bdad6	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
6971b3e3-5526-5665-aa13-d1278282e237	459a9bd6-464c-576d-8ff2-d229c1ad32d6	technician	f22afce6-9be8-5d54-8493-e187e6080d3d	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
76dda1e7-3704-5653-be54-80a6da0fab1a	459a9bd6-464c-576d-8ff2-d229c1ad32d6	service_bay	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
9c04567b-e8e0-5af6-acf0-44b11b98810c	ee1a172a-5c0f-59bf-851b-580dbe0c69f5	technician	f94d6698-e5d4-544b-b734-a8672691fde0	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
8d62b1a5-ce39-5720-b002-d2fa556074af	ee1a172a-5c0f-59bf-851b-580dbe0c69f5	service_bay	42ce9d61-5263-5784-b0c8-984b6bf6aaae	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
05d2d60b-3b1b-580b-a310-faec731c18ca	817bb0d2-44c5-5c61-914c-17b3ac6d4995	technician	a710b9c6-f208-5130-a26d-8a583a0cae4e	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
fce122b4-0204-58b4-b08d-3e83daa25301	817bb0d2-44c5-5c61-914c-17b3ac6d4995	service_bay	8806d3d9-7c39-511e-ab4d-8ac2880f513f	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
a02d1da0-4fda-589a-9923-0967a23b22dd	caa3557d-36eb-556e-b391-d9057fc59ca3	technician	a2d88a64-e213-5b97-8356-654a9acaf896	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
fa9b99dc-2d24-539a-9b22-2ba15af36f33	caa3557d-36eb-556e-b391-d9057fc59ca3	service_bay	432195c4-02e8-5310-b2a3-30ac3819e62b	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	requested	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
165d12a2-2a62-5893-bfbc-c3b62236f5ab	7dc04982-934e-5a23-9153-bc402adda956	technician	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
db7d335e-1079-5be8-8bd6-4e1ff02d6092	7dc04982-934e-5a23-9153-bc402adda956	service_bay	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
81e3481f-531b-5e80-adcb-d4cf456bc178	d00534d3-40d4-5c9d-8d56-e10bdcc947d3	technician	f22afce6-9be8-5d54-8493-e187e6080d3d	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
42a746a5-0ac4-51b3-901d-91fea7b2624c	d00534d3-40d4-5c9d-8d56-e10bdcc947d3	service_bay	9df77ddf-fe56-5e6f-8979-9b70e064d232	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Seed fixture
6381db44-06a7-5d39-97ca-0946dab5b292	046a62e0-c90a-56b7-a7d7-304f8be5770e	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 07:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
43f950b3-8e7c-56b4-a623-c683952acc84	046a62e0-c90a-56b7-a7d7-304f8be5770e	service_bay	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 07:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
f3ec7780-5894-54d6-964b-e482de7750da	11ca01c4-1317-5277-b800-2e5e6d2b8dac	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 07:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
4837e6bb-b687-51de-9dc2-be40c6f7f673	11ca01c4-1317-5277-b800-2e5e6d2b8dac	service_bay	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 07:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
b4230673-a7c9-5b35-b38a-9800b5ac957b	96d525e6-6502-5c87-8088-44848f1e50ae	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
80a95342-ea9b-5624-b484-77976076bbfe	96d525e6-6502-5c87-8088-44848f1e50ae	service_bay	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
3e2fc793-8c29-5963-a12e-c73cfc6d7642	983efce1-7010-5876-8bd0-d0888d318535	technician	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
ae932434-c1f6-5c67-b608-6d11d07869aa	983efce1-7010-5876-8bd0-d0888d318535	service_bay	f98cc283-b3ce-5c13-82b5-5b343ed52d21	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
563467a5-6549-5ce0-9b39-09bea53cd4f6	083b4b0a-d7bf-5a80-904f-5bd7deceed55	technician	e98c71df-d0a6-56d0-a881-2a2c57bf5986	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
b498334f-617e-5841-8f9d-2c42e8fd33c0	083b4b0a-d7bf-5a80-904f-5bd7deceed55	service_bay	f3436b53-3c8c-5302-afa3-904ea008c446	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
af26c695-2dd1-5831-8a0d-d51694d2bb84	339b73b4-8cd6-5f46-b4b5-98faf11f3d3d	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 08:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
eafc73e5-9987-5fb3-88ef-b8beb2092611	339b73b4-8cd6-5f46-b4b5-98faf11f3d3d	service_bay	16bdd951-987c-5321-89b3-3dda5dacaec1	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 08:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
23727698-8385-5715-95e8-6d78b7421975	01ed52c9-7e2d-5d09-9fdf-0307a94d27d8	technician	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 08:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
6d02b6bc-8c20-57cc-9c76-f573198696a1	01ed52c9-7e2d-5d09-9fdf-0307a94d27d8	service_bay	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 08:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
4ea3737d-fe8a-59fd-9323-42b434e4d0de	11e8d049-c717-5936-9e32-c9ad84bf9567	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
350843d6-6410-5513-b8b0-fda58399daa2	11e8d049-c717-5936-9e32-c9ad84bf9567	service_bay	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
ca58d05a-215c-59c7-bfd3-8a43349ea212	124f135a-4b55-51af-8289-8d03aa04ad13	technician	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
a1376f8c-0741-503f-8d59-efe075887533	124f135a-4b55-51af-8289-8d03aa04ad13	service_bay	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
c6fea81d-e488-5b2f-9d8d-a58258835edb	e50dd2ea-6723-5069-8e30-9abf1a3c8ebe	technician	e98c71df-d0a6-56d0-a881-2a2c57bf5986	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
07aea94a-eafa-53d3-abd9-fe5200e58578	e50dd2ea-6723-5069-8e30-9abf1a3c8ebe	service_bay	d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
9333e65e-276e-55c8-a508-18bb9161e45e	f640f7dc-4389-54bd-a6bc-54c54198bcaf	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 09:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
3ca3ace8-8130-5881-9c7d-acad9a982f96	f640f7dc-4389-54bd-a6bc-54c54198bcaf	service_bay	f98cc283-b3ce-5c13-82b5-5b343ed52d21	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 09:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
184a148f-5a94-5d6b-a549-d739bb645c0e	422c4871-31d1-5ba2-8874-1ecf000fe2a1	technician	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 09:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
edf88063-c2a9-5bec-ab9f-afb95b69499b	422c4871-31d1-5ba2-8874-1ecf000fe2a1	service_bay	f3436b53-3c8c-5302-afa3-904ea008c446	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 09:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
b5c08365-a57c-58e1-a378-76fe48ee96c0	9a19db3b-241f-5cbc-8d27-c169038ac12b	technician	adf23604-8641-504a-be4a-f23c5d9579b6	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
8bc7b4e3-d4ae-58b6-81da-bc573b7123dd	9a19db3b-241f-5cbc-8d27-c169038ac12b	service_bay	16bdd951-987c-5321-89b3-3dda5dacaec1	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
7d114f41-b7fd-58f2-bd7a-07b9b7fc0b39	a294c79d-0853-5503-bf08-5cb44daf7272	technician	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
87cc7779-fad2-56d5-bb23-33bc09d0a84e	a294c79d-0853-5503-bf08-5cb44daf7272	service_bay	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
5040782b-34d5-5aca-89de-2b6c9831bd07	e6e89bf4-a182-5457-8d65-d63275022432	technician	e98c71df-d0a6-56d0-a881-2a2c57bf5986	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
2f7b2ecb-719b-51b7-970d-4adf615e726a	e6e89bf4-a182-5457-8d65-d63275022432	service_bay	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
e02dc11b-338e-52e4-9248-b74345031c06	2858ded8-19d8-5a99-b515-1de4947ed87f	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 10:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
77eb5d6b-1d90-52d0-800f-cd0c721f91ab	2858ded8-19d8-5a99-b515-1de4947ed87f	service_bay	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 10:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
f9d72a7a-fa0e-5a2f-88c6-baec61703b2f	a631ee0b-d59d-54cb-b82b-24fd0586e22f	technician	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 10:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
88da88b9-469e-5dd0-bc95-676830f519d0	a631ee0b-d59d-54cb-b82b-24fd0586e22f	service_bay	d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 10:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
4439bb7c-5f14-5cc4-ad7b-6af91fd635be	a75143b1-eb7d-555b-a6a1-80e3e8e6b7a6	technician	adf23604-8641-504a-be4a-f23c5d9579b6	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
ea0bce7c-7b58-55d4-a63e-a066ef3ffaf2	a75143b1-eb7d-555b-a6a1-80e3e8e6b7a6	service_bay	f98cc283-b3ce-5c13-82b5-5b343ed52d21	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
17524b7f-2967-5363-b228-a90422280595	b696b2b9-af07-5a99-adca-a0074a51b3bc	technician	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
637da9a0-71ff-574e-87ad-6e5360bf4579	b696b2b9-af07-5a99-adca-a0074a51b3bc	service_bay	f3436b53-3c8c-5302-afa3-904ea008c446	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
2bd668bd-1273-5c48-8525-1c1d45f554d0	0e085804-8bb3-5c65-98f9-5b1a16a23bc1	technician	e98c71df-d0a6-56d0-a881-2a2c57bf5986	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
f5214ca9-eed3-58b1-ba6d-db1606631cd6	0e085804-8bb3-5c65-98f9-5b1a16a23bc1	service_bay	16bdd951-987c-5321-89b3-3dda5dacaec1	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
fe3fcbe3-6676-58cf-b77a-e7546d9ab114	a632049b-5eaf-54a0-af20-0c97cfe687d9	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 11:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
487fa6f5-98d4-55ab-9e16-4cfb175d16e7	a632049b-5eaf-54a0-af20-0c97cfe687d9	service_bay	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 11:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
a654a534-003c-5013-ba64-fa6fbcded55a	f25259c8-3eff-5f58-8e9f-944fbfb9a7b3	technician	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 11:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
a8f10989-8705-5a64-b994-5cae8c9d9eee	f25259c8-3eff-5f58-8e9f-944fbfb9a7b3	service_bay	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 11:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
01367098-f2bf-5ea8-91c3-d8e9bcaba9fc	a5659d7b-3b87-509e-92d7-489b8a454a9e	technician	adf23604-8641-504a-be4a-f23c5d9579b6	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
6c816b3e-1887-54f2-83a0-e9ad656aa12a	a5659d7b-3b87-509e-92d7-489b8a454a9e	service_bay	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
b4d3ee0c-0311-54d4-a7a3-3382cb740ea5	01a5daf6-126c-5ea9-8a49-ef48eaa33056	technician	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
c92d101d-6270-58e5-8bb0-a3b853143b5f	01a5daf6-126c-5ea9-8a49-ef48eaa33056	service_bay	d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
a7c63bc6-a202-5fe8-a6df-3d36ec7b48c3	d62e17b5-590c-53ff-bf82-35bf57ac3136	technician	e98c71df-d0a6-56d0-a881-2a2c57bf5986	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
a25dbaf1-db06-5786-93bf-8139f5bd7278	d62e17b5-590c-53ff-bf82-35bf57ac3136	service_bay	f98cc283-b3ce-5c13-82b5-5b343ed52d21	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
df76b88c-15b2-5d35-b73c-d3612d9aef26	0563c049-6bff-57e2-8d0a-49c9aeb2028f	technician	9cdfb0cd-e427-5722-a838-333ba2098240	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 12:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
59f12d0e-8326-5025-bfff-fb725d958497	0563c049-6bff-57e2-8d0a-49c9aeb2028f	service_bay	f3436b53-3c8c-5302-afa3-904ea008c446	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 12:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
11d6c549-0200-51fc-8d17-411b018bf12b	47b47b9b-443c-5af4-9cc7-bbb4d18da237	technician	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 12:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
4a2c6998-5e5d-5952-9f20-81898b510a8a	47b47b9b-443c-5af4-9cc7-bbb4d18da237	service_bay	16bdd951-987c-5321-89b3-3dda5dacaec1	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 12:00:00+00	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
938280c7-396f-5f4b-a915-20995455037e	f3432f7d-dba3-5ccc-a8c3-a1e1d117fcb7	technician	adf23604-8641-504a-be4a-f23c5d9579b6	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
48e04f7c-8d6d-59bd-b11e-c7089883e7aa	f3432f7d-dba3-5ccc-a8c3-a1e1d117fcb7	service_bay	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	requested	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
81de66dc-a4e6-55dd-a812-c60abfed179c	57f4da57-577b-5193-b437-1e02c1291e69	technician	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
b7ccfa52-1a33-5fb0-a7c8-9058b2597f6f	57f4da57-577b-5193-b437-1e02c1291e69	service_bay	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
8b0cd630-2d1a-55f6-88c5-bec9c5b71ff8	2da0cddf-93e0-56d4-96a8-38fa23aca797	technician	e98c71df-d0a6-56d0-a881-2a2c57bf5986	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
fb8c05f9-26ae-5455-9c40-8c3dd430b6b6	2da0cddf-93e0-56d4-96a8-38fa23aca797	service_bay	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	725e5cc4-6682-5e91-a195-973b60f26754	Seed fixture
3bc98cfa-0bdf-5289-9764-581fdeb3352a	74d19b2d-a91d-5ae4-b72c-ad18325dd2bb	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 15:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
f8742790-dfbd-54e2-af70-2895e7a651c2	74d19b2d-a91d-5ae4-b72c-ad18325dd2bb	service_bay	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 15:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
abcdfc44-2d9e-52bc-b649-bba679470ee8	957ea531-0a9e-5913-b1cc-7e36293904be	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 15:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
b0b4aea7-f00a-56df-a6e0-d8c411a04237	957ea531-0a9e-5913-b1cc-7e36293904be	service_bay	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 15:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
9b8506d5-fa54-58d1-854e-4feaf20bec46	352c053c-7ce5-5c50-a16f-95b386bc8fa1	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
c80b4225-9ce9-5849-a61c-e8971c6d7690	352c053c-7ce5-5c50-a16f-95b386bc8fa1	service_bay	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
57b6c440-d21f-5637-bc92-abd3f62a3d68	8f780028-909c-5e1f-a59b-3e126bf600af	technician	885312b8-41b5-5011-b4d6-948cffe99df2	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
efcda574-adf9-5316-a30e-ccaf9197f825	8f780028-909c-5e1f-a59b-3e126bf600af	service_bay	baada9ae-6167-533e-ad0d-1ee0e47ef254	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
43ab1673-27de-5dd2-b16e-1524e072c80a	d5c03091-be46-5656-ba36-ec8f62830e91	technician	ed061c8d-b8b7-5356-813b-79b188f7a0ba	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
d3c1bfd9-f0d4-5e77-8bbc-db0c28bb645b	d5c03091-be46-5656-ba36-ec8f62830e91	service_bay	26ed90fd-20f8-511c-88e5-55f55772b50e	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
1bfb365d-d3cf-54f0-a961-62c898e74224	701ca8af-2dea-5e92-85f9-848ee5e18a2f	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 16:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
31fe2dbc-60de-5dd0-886c-c95bf758db0f	701ca8af-2dea-5e92-85f9-848ee5e18a2f	service_bay	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-27 16:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
5ed0d009-d76a-5b5c-921f-d9ae2119c9fe	a464346f-d4fd-5039-89b7-079107ba4709	technician	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 16:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
0076d535-c444-51f4-ad2c-3fac99dcd436	a464346f-d4fd-5039-89b7-079107ba4709	service_bay	3aabc2d5-d94e-5d21-a979-632c719fd85d	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-27 16:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
6a1b575a-1db9-53af-b9f6-1f1ffabcbfd6	ea68f82e-0a49-564e-854e-52f6a627a863	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
b97e5075-fd54-52ac-b85a-73b4bcd05ac1	ea68f82e-0a49-564e-854e-52f6a627a863	service_bay	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
b11733b4-98ea-5d48-89e2-8b592e1c0818	1359d325-e1dd-559c-a4d0-a962c62508a7	technician	885312b8-41b5-5011-b4d6-948cffe99df2	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
0c739183-319a-5535-8fa1-1b737a9dbb75	1359d325-e1dd-559c-a4d0-a962c62508a7	service_bay	b703c0bd-0601-5342-a6bd-7eee5b24f28d	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
24b77011-2dd1-5b5d-a227-1da1bb4f47f3	49ee3e16-c24a-547b-b05d-6d25475f4cff	technician	ed061c8d-b8b7-5356-813b-79b188f7a0ba	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
5cf8f0f7-a176-5f19-a850-560804d7a913	49ee3e16-c24a-547b-b05d-6d25475f4cff	service_bay	3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
5e1b90e8-575c-57e7-b453-273c33aae9d4	a6f39d8e-6a95-5cd6-be05-610083ee0609	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 17:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
eacc3c4e-3654-5fb0-8e7a-4622ebe78ed8	a6f39d8e-6a95-5cd6-be05-610083ee0609	service_bay	baada9ae-6167-533e-ad0d-1ee0e47ef254	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 17:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
240aa8ad-5de9-5d13-bdbd-8129493ac83e	0a88e4ba-6992-576c-8d88-d4c668321f11	technician	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 17:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
04ebf63d-f572-5c76-9108-880681c9257d	0a88e4ba-6992-576c-8d88-d4c668321f11	service_bay	26ed90fd-20f8-511c-88e5-55f55772b50e	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 17:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
c047bab3-7c6a-5298-9742-6eed66e2a6ee	ec69ef24-35e8-5eec-913c-e74c29fe329a	technician	4a5f4e0e-e447-519c-8f36-bb3d60802506	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
3fa3700f-7334-5227-b3d8-8aed9a6af640	ec69ef24-35e8-5eec-913c-e74c29fe329a	service_bay	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
98f49dbb-2a36-50fd-8903-ced9ad93bbf3	7ad83945-6cac-59bf-8278-67144b7b6264	technician	885312b8-41b5-5011-b4d6-948cffe99df2	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
834c421d-adc9-5575-bc3e-f57e22c544ad	7ad83945-6cac-59bf-8278-67144b7b6264	service_bay	3aabc2d5-d94e-5d21-a979-632c719fd85d	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
70f04bbb-5b1f-5d01-976a-94f038b6f09e	03dd3106-c13f-5501-8900-f2553d346387	technician	ed061c8d-b8b7-5356-813b-79b188f7a0ba	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
4cfee83e-83ac-56e7-8fea-e837530125a0	03dd3106-c13f-5501-8900-f2553d346387	service_bay	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
a8282b69-e9b9-50a0-b4da-e5e9cc643132	38ece363-7034-5af6-b988-c5d92552e6be	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 18:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
d63929f4-7ee5-50ee-aed8-d1dcf8c71a97	38ece363-7034-5af6-b988-c5d92552e6be	service_bay	b703c0bd-0601-5342-a6bd-7eee5b24f28d	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	completed	2026-08-01 00:00:00+00	2026-08-28 18:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
2cfc0644-0bbd-55e1-97a6-7d34ba3ca1e5	de7aa3a5-55dd-5635-a9a2-4c8e7d229a54	technician	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 18:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
409a8832-23ed-5597-a8f8-c67b346f1974	de7aa3a5-55dd-5635-a9a2-4c8e7d229a54	service_bay	3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-08-28 18:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
b097acdf-507c-5d10-be14-c35331634d9c	e7d1574e-5124-5b1e-8715-814772a587fa	technician	4a5f4e0e-e447-519c-8f36-bb3d60802506	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
cf92517a-8fc8-5850-afc3-9449ab567a18	e7d1574e-5124-5b1e-8715-814772a587fa	service_bay	baada9ae-6167-533e-ad0d-1ee0e47ef254	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
8a055027-acda-5e3d-9ef9-d0ebdba9837b	c543cda9-b2fd-559c-a757-490848fdf302	technician	885312b8-41b5-5011-b4d6-948cffe99df2	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
b13b7537-e7b8-5472-9a57-aa5347199d8e	c543cda9-b2fd-559c-a757-490848fdf302	service_bay	26ed90fd-20f8-511c-88e5-55f55772b50e	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
9c040166-2cc9-571f-88e5-ffbce354cb92	7989a5e7-e12b-5875-954b-68ffaf8d0814	technician	ed061c8d-b8b7-5356-813b-79b188f7a0ba	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
db545ff9-9a12-5503-8a1d-5e1ca42bd272	7989a5e7-e12b-5875-954b-68ffaf8d0814	service_bay	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
c7865521-7ee5-556e-8102-973e25dd8fa6	ba820a4e-0f95-5b7d-b9a5-721a767736e3	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 19:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
725fdbf8-2146-58b0-add1-2c372ec6594d	ba820a4e-0f95-5b7d-b9a5-721a767736e3	service_bay	3aabc2d5-d94e-5d21-a979-632c719fd85d	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 19:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
de660178-f4ef-5e2e-9065-fbd0405c87a4	dafdef31-4855-5c70-896f-08b743bfbcd8	technician	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 19:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
c5ccf1cd-242e-55ac-8665-03740d132e53	dafdef31-4855-5c70-896f-08b743bfbcd8	service_bay	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 19:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
921fd30c-b1ea-5dea-af81-39f3c64d7298	501adc19-bc0a-5cb2-a6d6-8af3d8185d88	technician	4a5f4e0e-e447-519c-8f36-bb3d60802506	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
f09b8586-069c-5dff-9225-f9fdaba3d852	501adc19-bc0a-5cb2-a6d6-8af3d8185d88	service_bay	b703c0bd-0601-5342-a6bd-7eee5b24f28d	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
4ff1925f-790b-552e-b324-0c4e0731184f	f5c38f17-4c28-50b3-bc95-a128be000c91	technician	885312b8-41b5-5011-b4d6-948cffe99df2	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
358f49e5-40c8-59ff-9ed2-2593c4889da9	f5c38f17-4c28-50b3-bc95-a128be000c91	service_bay	3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
2fd67612-0bfa-5f9d-b823-15f22fa11a95	c284dca7-557c-5e19-b7a1-3a373f8cc6c1	technician	ed061c8d-b8b7-5356-813b-79b188f7a0ba	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
0941baf0-7b42-5f72-86b1-66d1e3d76d9e	c284dca7-557c-5e19-b7a1-3a373f8cc6c1	service_bay	baada9ae-6167-533e-ad0d-1ee0e47ef254	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
5a041f9e-2fff-5beb-8851-1a0873dd1068	0c4c44f9-7438-5ede-a780-f8a0d3dbbcef	technician	f6e45079-dc94-52f1-a87f-fb82c82c6684	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 20:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
e8e6d817-74db-5590-bf35-1fae57c16355	0c4c44f9-7438-5ede-a780-f8a0d3dbbcef	service_bay	26ed90fd-20f8-511c-88e5-55f55772b50e	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	completed	2026-08-01 00:00:00+00	2026-09-03 20:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
6d174307-c8f6-530d-86a3-559679b5376a	6f5405e0-8f9f-5ddf-85b3-0a253bb19180	technician	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 20:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
b045a667-7579-5117-8561-5bd4f9ddae05	6f5405e0-8f9f-5ddf-85b3-0a253bb19180	service_bay	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	cancelled	2026-08-01 00:00:00+00	2026-09-03 20:00:00+00	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
e2ac8862-cf80-5c89-b17f-b5fad4d1f02d	817b51f8-1b7b-50dc-97ba-9dafc2be9dc2	technician	4a5f4e0e-e447-519c-8f36-bb3d60802506	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
72c48844-2fce-52a7-b381-30263c6162e0	817b51f8-1b7b-50dc-97ba-9dafc2be9dc2	service_bay	3aabc2d5-d94e-5d21-a979-632c719fd85d	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	requested	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
d3f38e34-d3a9-5f5c-b7c3-b320350d8106	8e9e7fd7-904d-5242-9357-df8a2663f200	technician	885312b8-41b5-5011-b4d6-948cffe99df2	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
924c7b5b-2dab-5fcb-a52f-55bd3cb8fa02	8e9e7fd7-904d-5242-9357-df8a2663f200	service_bay	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	checked_in	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
800035f1-6942-523b-808a-9d14ab3d58cf	3c5d29ec-88b0-5f97-a6c7-5af942f91230	technician	ed061c8d-b8b7-5356-813b-79b188f7a0ba	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
47cff76e-c77e-53a3-b4a8-84cf1da1025e	3c5d29ec-88b0-5f97-a6c7-5af942f91230	service_bay	b703c0bd-0601-5342-a6bd-7eee5b24f28d	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	in_progress	2026-08-01 00:00:00+00	\N	2ad48f7a-7d9b-5503-a68d-07001e014841	Seed fixture
4b20b46f-2e0f-4f87-9539-d2f322359f93	2b01e87d-1e6a-477b-a248-6703f9b07baa	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-09-01 02:00:00+00	2026-09-01 04:00:00+00	requested	2026-08-30 10:24:33.824784+00	\N	3b037fab-ef51-55de-abac-63d4f0242ed4	\N
14389df9-82e1-4cf4-b5c1-a342a994ed4c	2b01e87d-1e6a-477b-a248-6703f9b07baa	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-09-01 02:00:00+00	2026-09-01 04:00:00+00	requested	2026-08-30 10:24:33.824784+00	\N	3b037fab-ef51-55de-abac-63d4f0242ed4	\N
ec5c294f-9248-4192-b332-978757579d53	965ccd4c-361d-436f-9e0d-15770bc3524b	technician	aab629e4-5965-5d14-a69f-e8d2db5df493	2026-09-01 02:00:00+00	2026-09-01 04:00:00+00	requested	2026-08-30 10:50:53.186967+00	\N	3b037fab-ef51-55de-abac-63d4f0242ed4	\N
bc68b063-cc5a-43cd-9d00-531e0b19ea3d	965ccd4c-361d-436f-9e0d-15770bc3524b	service_bay	f924649c-3402-5659-b18a-385fdece1353	2026-09-01 02:00:00+00	2026-09-01 04:00:00+00	requested	2026-08-30 10:50:53.186967+00	\N	3b037fab-ef51-55de-abac-63d4f0242ed4	\N
23a93b26-22cd-49c0-a0f6-616f820944cd	355cbc7b-4e80-4651-a8bb-98315b6db970	technician	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2026-09-16 02:00:00+00	2026-09-16 04:00:00+00	requested	2026-08-30 11:00:33.368694+00	\N	3b037fab-ef51-55de-abac-63d4f0242ed4	\N
2e61af9b-1c55-4716-b88e-dc271cf6b291	355cbc7b-4e80-4651-a8bb-98315b6db970	service_bay	2118d041-b09a-541d-a9a8-034f86641286	2026-09-16 02:00:00+00	2026-09-16 04:00:00+00	requested	2026-08-30 11:00:33.368694+00	\N	3b037fab-ef51-55de-abac-63d4f0242ed4	\N
\.


--
-- Data for Name: appointments; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.appointments (appointment_id, reference_code, customer_id, vehicle_id, dealership_id, service_type_id, technician_id, service_bay_id, starts_at, ends_at, status, notes, created_by_user_id, cancelled_by_user_id, cancellation_reason, created_at, deleted_at, updated_at, cancelled_at, checked_in_at, in_progress_at, started_at, completed_at, actual_ends_at, planned_duration_minutes) FROM stdin;
c1be6607-1700-5bd1-8c30-a11a772a9d39	SEED-HCM-01	80bf95ff-9973-508b-9e4c-4448d6979561	0f777184-c71e-5c20-95bf-3ddd073781a0	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	ff658fc4-1dd0-5cca-b436-d138e9e5832a	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2118d041-b09a-541d-a9a8-034f86641286	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	completed	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-27 01:00:00+00	2026-08-27 01:00:00+00	60
51d98f33-5a44-55b5-b473-3c834876a284	SEED-HCM-02	1be2026f-a49c-5ca7-805b-aa1de3a5f349	2dc6a499-86fe-5d2a-a3cb-2d2688f9b9c9	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	40e31547-ef9d-5f42-8fe4-acdb10affee0	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2118d041-b09a-541d-a9a8-034f86641286	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	cancelled	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	a73801eb-398a-54d0-8e82-e50c59407287	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-26 23:00:00+00	\N	\N	\N	\N	\N	60
c36806f7-30b8-5e1a-b19a-5de4afc3ba82	SEED-HCM-03	8ab22659-36a2-57c9-86f3-10cd9e0134ff	3fba3706-18d3-5ab5-9a64-fb6b91e4df0b	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	47e2a50d-3111-5d97-87d1-c6f9b865cdf4	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2118d041-b09a-541d-a9a8-034f86641286	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	requested	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
512f2cc0-21f1-5582-bde7-92d1d446501a	SEED-HCM-04	4a2800af-46ff-51a1-b8fc-e1a248b97793	af030a0d-409f-5da8-a741-803299cfbc3f	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	1df02326-4e85-579f-b58f-64e4cd71b5a7	7497e944-d4ac-58cd-a8f7-b33478331e7e	ff440016-8cdc-5773-a81e-2a040283208b	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	checked_in	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 00:00:00+00	\N	\N	\N	\N	60
70d87942-32d1-57e6-b368-8a78f441f5d4	SEED-HCM-05	a9e5a060-3b39-5d45-85d4-de0566386b46	30af15ee-d6a7-54e2-b17c-5e5ba9a5d5f7	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	8a8a8dcb-c515-5c94-9b15-411fa5d3af78	aab629e4-5965-5d14-a69f-e8d2db5df493	f924649c-3402-5659-b18a-385fdece1353	2026-08-27 00:00:00+00	2026-08-27 01:00:00+00	in_progress	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 00:00:00+00	2026-08-27 00:10:00+00	2026-08-27 00:10:00+00	\N	\N	60
32276637-d152-5de4-b70c-f479d93301a3	SEED-HCM-06	078c70f3-9945-5317-b9cb-dbd70219dc4a	301c52a5-86e0-5e34-902c-ef357c1871c6	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	c3d8dbba-05fa-5785-9a04-5fbb17a80efa	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	completed	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-27 02:00:00+00	2026-08-27 02:00:00+00	60
028f3e80-dddf-5362-b6e7-9cca35ffe13a	SEED-HCM-07	95d210c0-b1d9-58b0-8aed-67b24c2646a9	00b47839-23b6-5c71-8d42-afab163ebed2	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	35dd4ceb-6a3a-569e-a49c-6ead26a5ac52	fdfee93f-949b-5a04-849c-bb943a92e4bd	ecf7be60-2540-5e7d-88f8-99cec4954edb	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	cancelled	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	a73801eb-398a-54d0-8e82-e50c59407287	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-27 00:00:00+00	\N	\N	\N	\N	\N	60
4b5fe5f0-1672-5971-9882-360d05edf5f5	SEED-HCM-08	2604f74a-6aff-598d-a9da-7974c77af22f	c7e3bf2e-baec-5fb4-8b04-f081d375e5ca	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	f8ea6f15-8a21-57c2-97ee-7b5dd0638443	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2118d041-b09a-541d-a9a8-034f86641286	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	requested	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
505c41f3-ab0e-5258-9049-bde98a3211bd	SEED-HCM-09	972997c0-3a0d-54b3-a9cc-5adeeb22e21a	48297c3b-e79f-5d5b-9626-3cfaedf3b230	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	07c9fc2e-90ba-56af-88c9-01726b22ef20	7497e944-d4ac-58cd-a8f7-b33478331e7e	619ea9fa-4c9d-506e-8838-5f527f5223c2	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	checked_in	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 01:00:00+00	\N	\N	\N	\N	60
c3de56e7-38d4-59b4-ac0d-72e210bdbf95	SEED-HCM-10	da52fc8e-70a9-57a0-bcd8-a7ff2e7a1dbc	14299018-bc8a-5198-aff0-ae5511370f58	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	0e5f7e9e-e60a-5b1b-b9ff-b0f318a4af8b	aab629e4-5965-5d14-a69f-e8d2db5df493	0a1fae29-1e5b-5efc-b8a9-0887d4c25610	2026-08-27 01:00:00+00	2026-08-27 02:00:00+00	in_progress	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 01:00:00+00	2026-08-27 01:10:00+00	2026-08-27 01:10:00+00	\N	\N	60
68dd5464-9979-56fb-9177-c11bb97f88eb	SEED-HCM-11	84ad1483-9d1f-56cc-9a77-660c9b6e5949	6b117387-5da8-5729-bdfb-ef7697fc7533	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2c198c84-2406-5891-a2b7-ded50a876ed9	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	ff440016-8cdc-5773-a81e-2a040283208b	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	completed	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 03:00:00+00	2026-08-28 03:00:00+00	60
6e8ddc03-dd54-58a1-b707-6f638c67cdc6	SEED-HCM-12	629167db-2c5c-561f-ae16-eadec3f6edae	5f97896e-ee20-5da2-a5b8-d096911e6528	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	9044baac-541e-54c9-9968-db1caa46c3b8	fdfee93f-949b-5a04-849c-bb943a92e4bd	f924649c-3402-5659-b18a-385fdece1353	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	cancelled	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	a73801eb-398a-54d0-8e82-e50c59407287	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-28 01:00:00+00	\N	\N	\N	\N	\N	60
ba1eb83b-2463-5459-b573-6091d22f893e	SEED-HCM-13	76842e11-6973-5d16-b55f-9fefb0e0fc31	22de3196-f8ac-5ab1-9eac-3f05d6b03ef7	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	1407c88c-49bb-55d3-8b37-e58b7ad90b4a	780d2c59-38da-5e9b-8b59-d3377186faab	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	requested	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
b42f07e6-193a-573e-83f5-8f0efb29cc9e	SEED-HCM-14	599b0901-cbe9-56cf-98bf-94becfa492d3	3ebcfba7-3f56-56c6-ac76-743ae03fe5f5	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	dbf26c41-98f9-5731-b0e1-291f23811d1d	7497e944-d4ac-58cd-a8f7-b33478331e7e	ecf7be60-2540-5e7d-88f8-99cec4954edb	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	checked_in	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 02:00:00+00	\N	\N	\N	\N	60
f7eb979a-71c5-59c7-9f6d-cc67215c0a42	SEED-HCM-15	92b584ed-96fc-5bf4-9403-8e20585b2609	2278457f-b267-5a94-b6b7-93b14bb292b2	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	ff658fc4-1dd0-5cca-b436-d138e9e5832a	aab629e4-5965-5d14-a69f-e8d2db5df493	2118d041-b09a-541d-a9a8-034f86641286	2026-08-28 02:00:00+00	2026-08-28 03:00:00+00	in_progress	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 02:00:00+00	2026-08-28 02:10:00+00	2026-08-28 02:10:00+00	\N	\N	60
89cbbf80-8ed3-5794-ba37-a2bcadf57dd9	SEED-HCM-16	00cbef96-40fd-532e-9d9d-989eecc0243e	1f664c14-6651-5729-9ede-47e20ddc85ac	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	40e31547-ef9d-5f42-8fe4-acdb10affee0	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	619ea9fa-4c9d-506e-8838-5f527f5223c2	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	completed	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 04:00:00+00	2026-08-28 04:00:00+00	60
8ee6032a-ec74-5a8a-a084-2ef75bacc8ea	SEED-HCM-17	11aa321e-ce72-5a0c-becb-16c5e5661a7f	7fbb55d6-2f47-59f5-bf5f-8d9e6e3799af	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	47e2a50d-3111-5d97-87d1-c6f9b865cdf4	fdfee93f-949b-5a04-849c-bb943a92e4bd	0a1fae29-1e5b-5efc-b8a9-0887d4c25610	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	cancelled	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	a73801eb-398a-54d0-8e82-e50c59407287	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-28 02:00:00+00	\N	\N	\N	\N	\N	60
8e39ab31-f7f9-53b5-9d5c-ce33ff187b07	SEED-HCM-18	12e7f7fe-2240-5c8c-a8ea-de63b66542be	eaf6f4c8-c635-5fd8-a572-7d90350cf4ca	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	1df02326-4e85-579f-b58f-64e4cd71b5a7	780d2c59-38da-5e9b-8b59-d3377186faab	ff440016-8cdc-5773-a81e-2a040283208b	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	requested	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
fd1b3303-a5de-5e71-92ee-e18a700ff091	SEED-HCM-19	a5363fc5-2a82-5462-bd3f-afd2d6cadbf1	148b68c7-8b99-5340-b1a9-5f162abce857	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	8a8a8dcb-c515-5c94-9b15-411fa5d3af78	7497e944-d4ac-58cd-a8f7-b33478331e7e	f924649c-3402-5659-b18a-385fdece1353	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	checked_in	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 03:00:00+00	\N	\N	\N	\N	60
508a1ec3-6d18-5080-9ea8-d288caec0e52	SEED-HCM-20	c429efbf-ee87-559c-8d13-059bdbdf0b96	0c99d49c-96c0-5ce7-bc52-7c2932a2f359	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	c3d8dbba-05fa-5785-9a04-5fbb17a80efa	aab629e4-5965-5d14-a69f-e8d2db5df493	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	2026-08-28 03:00:00+00	2026-08-28 04:00:00+00	in_progress	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 03:00:00+00	2026-08-28 03:10:00+00	2026-08-28 03:10:00+00	\N	\N	60
ccb0b729-659c-5948-91af-a3d00ade05b8	SEED-HCM-21	80bf95ff-9973-508b-9e4c-4448d6979561	0f777184-c71e-5c20-95bf-3ddd073781a0	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	35dd4ceb-6a3a-569e-a49c-6ead26a5ac52	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	ecf7be60-2540-5e7d-88f8-99cec4954edb	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	completed	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 05:00:00+00	2026-09-03 05:00:00+00	60
6a047d7d-bdbf-5067-869b-69daf14ca320	SEED-HCM-22	1be2026f-a49c-5ca7-805b-aa1de3a5f349	2dc6a499-86fe-5d2a-a3cb-2d2688f9b9c9	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	f8ea6f15-8a21-57c2-97ee-7b5dd0638443	fdfee93f-949b-5a04-849c-bb943a92e4bd	2118d041-b09a-541d-a9a8-034f86641286	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	cancelled	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	a73801eb-398a-54d0-8e82-e50c59407287	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 03:00:00+00	\N	\N	\N	\N	\N	60
233400f6-3b7f-5648-bb71-202b2aec854c	SEED-HCM-23	8ab22659-36a2-57c9-86f3-10cd9e0134ff	3fba3706-18d3-5ab5-9a64-fb6b91e4df0b	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	07c9fc2e-90ba-56af-88c9-01726b22ef20	780d2c59-38da-5e9b-8b59-d3377186faab	619ea9fa-4c9d-506e-8838-5f527f5223c2	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	requested	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
cde45d35-f67e-5f9f-aeb2-06b49e2aad3d	SEED-HCM-24	4a2800af-46ff-51a1-b8fc-e1a248b97793	af030a0d-409f-5da8-a741-803299cfbc3f	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	0e5f7e9e-e60a-5b1b-b9ff-b0f318a4af8b	7497e944-d4ac-58cd-a8f7-b33478331e7e	0a1fae29-1e5b-5efc-b8a9-0887d4c25610	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	checked_in	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 04:00:00+00	\N	\N	\N	\N	60
b8453e21-1f95-5e6b-ab8e-d7a919f85dff	SEED-HCM-25	a9e5a060-3b39-5d45-85d4-de0566386b46	30af15ee-d6a7-54e2-b17c-5e5ba9a5d5f7	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2c198c84-2406-5891-a2b7-ded50a876ed9	aab629e4-5965-5d14-a69f-e8d2db5df493	ff440016-8cdc-5773-a81e-2a040283208b	2026-09-03 04:00:00+00	2026-09-03 05:00:00+00	in_progress	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 04:00:00+00	2026-09-03 04:10:00+00	2026-09-03 04:10:00+00	\N	\N	60
f8726250-0119-59ae-8c57-702615784cc1	SEED-HCM-26	078c70f3-9945-5317-b9cb-dbd70219dc4a	301c52a5-86e0-5e34-902c-ef357c1871c6	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	9044baac-541e-54c9-9968-db1caa46c3b8	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	f924649c-3402-5659-b18a-385fdece1353	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	completed	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 06:00:00+00	2026-09-03 06:00:00+00	60
97cff4f4-8a65-55fc-9f01-e3d97cdb097a	SEED-HCM-27	95d210c0-b1d9-58b0-8aed-67b24c2646a9	00b47839-23b6-5c71-8d42-afab163ebed2	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	1407c88c-49bb-55d3-8b37-e58b7ad90b4a	fdfee93f-949b-5a04-849c-bb943a92e4bd	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	cancelled	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	a73801eb-398a-54d0-8e82-e50c59407287	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 04:00:00+00	\N	\N	\N	\N	\N	60
71bfbd58-db4e-5e66-be5c-7b3c8973b14e	SEED-HCM-28	2604f74a-6aff-598d-a9da-7974c77af22f	c7e3bf2e-baec-5fb4-8b04-f081d375e5ca	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	dbf26c41-98f9-5731-b0e1-291f23811d1d	780d2c59-38da-5e9b-8b59-d3377186faab	ecf7be60-2540-5e7d-88f8-99cec4954edb	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	requested	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
0d1929f8-6dbd-5ec0-bed5-3bd2891793dc	SEED-HCM-29	972997c0-3a0d-54b3-a9cc-5adeeb22e21a	48297c3b-e79f-5d5b-9626-3cfaedf3b230	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	ff658fc4-1dd0-5cca-b436-d138e9e5832a	7497e944-d4ac-58cd-a8f7-b33478331e7e	2118d041-b09a-541d-a9a8-034f86641286	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	checked_in	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 05:00:00+00	\N	\N	\N	\N	60
5fe8bcc3-eef7-5412-9325-4799e84653d5	SEED-HCM-30	da52fc8e-70a9-57a0-bcd8-a7ff2e7a1dbc	14299018-bc8a-5198-aff0-ae5511370f58	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	40e31547-ef9d-5f42-8fe4-acdb10affee0	aab629e4-5965-5d14-a69f-e8d2db5df493	619ea9fa-4c9d-506e-8838-5f527f5223c2	2026-09-03 05:00:00+00	2026-09-03 06:00:00+00	in_progress	Deterministic development fixture	a73801eb-398a-54d0-8e82-e50c59407287	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 05:00:00+00	2026-09-03 05:10:00+00	2026-09-03 05:10:00+00	\N	\N	60
eda78781-d975-5169-ab34-444c65348509	SEED-TYO-01	3a015a81-56c2-54c0-8cf4-11b84411a0ab	d0b2c927-e63b-58b2-a2a2-e48d914aadae	206c4a44-c525-5960-ad70-3a1e80f806e5	1e1aa59c-28cc-5938-810a-49ace5798ac8	6e4dae43-a541-594f-980b-6f78dedfcb0d	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	completed	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-26 23:00:00+00	2026-08-26 23:00:00+00	60
e9a173fd-770c-5f71-911a-330de6bd6f15	SEED-TYO-02	f948ab66-1616-5de0-ba37-7851129dfa44	66005aec-63ba-5f04-aa54-d612fa9d251b	206c4a44-c525-5960-ad70-3a1e80f806e5	f120f0da-0b7d-5d61-93b3-9fad0d9f3ca8	6e4dae43-a541-594f-980b-6f78dedfcb0d	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	cancelled	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	ded9e174-90f2-5ea7-9b35-86728f8544f7	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-26 21:00:00+00	\N	\N	\N	\N	\N	60
746e6df4-6a1a-5f90-a351-d465c3557099	SEED-TYO-03	9a77a403-73c0-5634-bfe1-c67323ee601b	29cbaafd-1395-5af1-a4a2-7ab7559dd636	206c4a44-c525-5960-ad70-3a1e80f806e5	3f1ebf87-e782-5c39-b5e4-983bed1ba676	6e4dae43-a541-594f-980b-6f78dedfcb0d	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	requested	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
913fbedb-c4d5-5402-b309-234a3935aa70	SEED-TYO-04	e8ecd6e0-e0fe-5722-a345-508e2e6c3b36	83e9c3ff-eb0d-593a-8850-70b3a2feeb59	206c4a44-c525-5960-ad70-3a1e80f806e5	bf648c3f-bf11-5f41-8bd8-a9320a331d2f	93a7232e-d474-5224-8e5b-fd7e98e60a52	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	checked_in	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-26 22:00:00+00	\N	\N	\N	\N	60
21429526-e9cb-5a8a-a3c4-666b47d7ed17	SEED-TYO-05	700519e2-3e29-5d26-84e0-9d9c08222d72	feb38295-f562-5b8a-9ce9-c8c81a70260d	206c4a44-c525-5960-ad70-3a1e80f806e5	1ca5b7cc-9956-5a6f-9f50-4a8afac6f4f9	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	dcd21ca1-995a-51e7-b954-60af0e35b8ac	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	in_progress	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-26 22:00:00+00	2026-08-26 22:10:00+00	2026-08-26 22:10:00+00	\N	\N	60
af5a8a6a-fbb5-5079-a426-6f14edd418a6	SEED-TYO-06	6532c83a-fb6f-517f-b6aa-aedbf45e9f58	7cf33bb6-295b-537a-858b-cb371a0dc518	206c4a44-c525-5960-ad70-3a1e80f806e5	e95d8421-11e7-553f-8fcd-448084f10d14	6e4dae43-a541-594f-980b-6f78dedfcb0d	42eff788-5be8-5f54-afb7-7c14606599ea	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	completed	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-27 00:00:00+00	2026-08-27 00:00:00+00	60
d4341c25-0d74-5b56-85cd-6e58e3e93bb4	SEED-TYO-07	c92c6a89-9abf-5c08-a177-bf51791d9f47	81ffc193-d57e-50ba-a4f5-3e0e36638d47	206c4a44-c525-5960-ad70-3a1e80f806e5	654e08cd-8bdb-5f5b-b464-fc687b217883	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	cancelled	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	ded9e174-90f2-5ea7-9b35-86728f8544f7	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-26 22:00:00+00	\N	\N	\N	\N	\N	60
0cc6efe8-f98b-57de-97d2-b7eea2933fe6	SEED-TYO-08	3612e1ca-d209-5f12-9949-ac32ce2b14af	4f0631c0-1689-5408-8023-421056d4f368	206c4a44-c525-5960-ad70-3a1e80f806e5	c817a967-78ec-5dc5-ad90-55b61f5db704	6e4dae43-a541-594f-980b-6f78dedfcb0d	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	requested	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
51b8c108-389b-54d4-8235-53c82c937d2e	SEED-TYO-09	35e47ee2-9301-542b-ae19-ad79c69769a3	82158d92-790d-56fb-9069-f19c60bd57ab	206c4a44-c525-5960-ad70-3a1e80f806e5	c13171bb-2178-5cbe-a8ae-9906af5b92b8	93a7232e-d474-5224-8e5b-fd7e98e60a52	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	checked_in	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-26 23:00:00+00	\N	\N	\N	\N	60
fa59e79c-eb85-5380-b460-41e1d1329b4c	SEED-TYO-10	1aacd4d6-1678-5444-8b29-4cc9266cab79	54c0ac6a-6530-503c-bf6b-358bf00084cb	206c4a44-c525-5960-ad70-3a1e80f806e5	5b31e150-ec54-553e-9f11-4a95aa7e9ae9	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	94e41d7e-908c-5e90-b8a2-410674183b28	2026-08-26 23:00:00+00	2026-08-27 00:00:00+00	in_progress	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-26 23:00:00+00	2026-08-26 23:10:00+00	2026-08-26 23:10:00+00	\N	\N	60
527a4178-db47-578d-bab2-2f3f3bffcb2f	SEED-TYO-11	2061498f-7daa-5e23-968f-dc57932dd828	676f2672-df96-5912-96ab-ff10a74e7599	206c4a44-c525-5960-ad70-3a1e80f806e5	03cdcb00-c17b-56c3-9134-150bffd9d9b3	6e4dae43-a541-594f-980b-6f78dedfcb0d	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	completed	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 01:00:00+00	2026-08-28 01:00:00+00	60
6d4b2ca5-aa5d-5009-b035-a237a34f192e	SEED-TYO-12	f526dd2b-f6a7-5741-b2e0-252e132ffb06	b56d529d-a1d9-561e-8fec-a7a183e5b3ae	206c4a44-c525-5960-ad70-3a1e80f806e5	b9b9f90e-0ff3-5f7a-9bd6-66f15b26f5b9	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	dcd21ca1-995a-51e7-b954-60af0e35b8ac	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	cancelled	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	ded9e174-90f2-5ea7-9b35-86728f8544f7	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-27 23:00:00+00	\N	\N	\N	\N	\N	60
7f4b449a-c0a0-5b65-9c9b-0737bdfa00ee	SEED-TYO-13	d52a0827-374c-5e82-b5a5-06e93cfcb4a2	5dc21e19-a4b9-5186-b53e-1df996df6051	206c4a44-c525-5960-ad70-3a1e80f806e5	eb7dcc4f-ab33-593e-b814-0c41ee9ff713	60805ebd-cae5-57ce-aa9d-362d81cfc131	42eff788-5be8-5f54-afb7-7c14606599ea	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	requested	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
acf9525c-2a74-56a6-9baa-3df7f68cf8f5	SEED-TYO-14	fa8615ff-9d25-5ed1-9953-cddb4f4f403b	558b2da0-1e34-5c1f-88d9-2136e4a9bd88	206c4a44-c525-5960-ad70-3a1e80f806e5	8f63bfdd-4205-5c3c-b82b-a818f235ec0e	93a7232e-d474-5224-8e5b-fd7e98e60a52	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	checked_in	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 00:00:00+00	\N	\N	\N	\N	60
74bf21e1-399b-579d-ab6f-9df4db0a5717	SEED-TYO-15	7a6e5c27-e66a-5a79-8b7e-7db17a201d72	d36036bc-e9b7-5c21-9cd2-15873c43a6bf	206c4a44-c525-5960-ad70-3a1e80f806e5	1e1aa59c-28cc-5938-810a-49ace5798ac8	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	in_progress	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 00:00:00+00	2026-08-28 00:10:00+00	2026-08-28 00:10:00+00	\N	\N	60
b6103c5a-02b9-54fa-a10a-f5601a4816a7	SEED-TYO-16	3d7248fc-9686-5392-a193-9bca6a05ef6f	48c91971-ef3a-5849-9c5a-7f02dbad52d3	206c4a44-c525-5960-ad70-3a1e80f806e5	f120f0da-0b7d-5d61-93b3-9fad0d9f3ca8	6e4dae43-a541-594f-980b-6f78dedfcb0d	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	completed	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 02:00:00+00	2026-08-28 02:00:00+00	60
c79f06ec-6932-5029-b0ae-687b23d87ac8	SEED-TYO-17	6c2ffd98-cc7d-5a51-b4f4-485e184bd927	f65534f7-0806-5880-80ab-0737f3d9a9de	206c4a44-c525-5960-ad70-3a1e80f806e5	3f1ebf87-e782-5c39-b5e4-983bed1ba676	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	94e41d7e-908c-5e90-b8a2-410674183b28	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	cancelled	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	ded9e174-90f2-5ea7-9b35-86728f8544f7	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-28 00:00:00+00	\N	\N	\N	\N	\N	60
6ad7b82b-ab35-584e-8607-df1ea988e370	SEED-TYO-18	b17fb6f1-0973-59d2-962b-5e38be69f045	474b78b1-7bbb-56f3-aebe-e3f8c9e1fe2d	206c4a44-c525-5960-ad70-3a1e80f806e5	bf648c3f-bf11-5f41-8bd8-a9320a331d2f	60805ebd-cae5-57ce-aa9d-362d81cfc131	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	requested	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
7c224bd3-62e4-5d29-8b36-915f08d274ab	SEED-TYO-19	9a0d85be-f559-5792-a2ca-9c1ebdba0e48	96cb9aee-d80c-5993-ade9-c56694ffdfd5	206c4a44-c525-5960-ad70-3a1e80f806e5	1ca5b7cc-9956-5a6f-9f50-4a8afac6f4f9	93a7232e-d474-5224-8e5b-fd7e98e60a52	dcd21ca1-995a-51e7-b954-60af0e35b8ac	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	checked_in	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 01:00:00+00	\N	\N	\N	\N	60
91baae88-14a5-590d-b709-597f023bab50	SEED-TYO-20	79f3cded-94a7-53a6-89da-cea4b658d998	c0a55eec-f234-5df9-ad1f-fca1f1078872	206c4a44-c525-5960-ad70-3a1e80f806e5	e95d8421-11e7-553f-8fcd-448084f10d14	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	42eff788-5be8-5f54-afb7-7c14606599ea	2026-08-28 01:00:00+00	2026-08-28 02:00:00+00	in_progress	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 01:00:00+00	2026-08-28 01:10:00+00	2026-08-28 01:10:00+00	\N	\N	60
cdf40560-d303-5cd8-acf1-1cb3a80b7393	SEED-TYO-21	3a015a81-56c2-54c0-8cf4-11b84411a0ab	d0b2c927-e63b-58b2-a2a2-e48d914aadae	206c4a44-c525-5960-ad70-3a1e80f806e5	654e08cd-8bdb-5f5b-b464-fc687b217883	6e4dae43-a541-594f-980b-6f78dedfcb0d	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	completed	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 03:00:00+00	2026-09-03 03:00:00+00	60
863fb2cb-726a-547e-90cc-f78a0206926b	SEED-TYO-22	f948ab66-1616-5de0-ba37-7851129dfa44	66005aec-63ba-5f04-aa54-d612fa9d251b	206c4a44-c525-5960-ad70-3a1e80f806e5	c817a967-78ec-5dc5-ad90-55b61f5db704	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	cancelled	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	ded9e174-90f2-5ea7-9b35-86728f8544f7	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 01:00:00+00	\N	\N	\N	\N	\N	60
ee21cea7-e328-511f-835d-f51d390755c5	SEED-TYO-23	9a77a403-73c0-5634-bfe1-c67323ee601b	29cbaafd-1395-5af1-a4a2-7ab7559dd636	206c4a44-c525-5960-ad70-3a1e80f806e5	c13171bb-2178-5cbe-a8ae-9906af5b92b8	60805ebd-cae5-57ce-aa9d-362d81cfc131	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	requested	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
91b62df0-c992-506e-960c-ef0d5e0a10eb	SEED-TYO-24	e8ecd6e0-e0fe-5722-a345-508e2e6c3b36	83e9c3ff-eb0d-593a-8850-70b3a2feeb59	206c4a44-c525-5960-ad70-3a1e80f806e5	5b31e150-ec54-553e-9f11-4a95aa7e9ae9	93a7232e-d474-5224-8e5b-fd7e98e60a52	94e41d7e-908c-5e90-b8a2-410674183b28	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	checked_in	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 02:00:00+00	\N	\N	\N	\N	60
ee48f155-0ea2-5c4f-8788-c72642614915	SEED-TYO-25	700519e2-3e29-5d26-84e0-9d9c08222d72	feb38295-f562-5b8a-9ce9-c8c81a70260d	206c4a44-c525-5960-ad70-3a1e80f806e5	03cdcb00-c17b-56c3-9134-150bffd9d9b3	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	in_progress	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 02:00:00+00	2026-09-03 02:10:00+00	2026-09-03 02:10:00+00	\N	\N	60
8180cd6d-95cb-5b10-bf59-a452858e2beb	SEED-TYO-26	6532c83a-fb6f-517f-b6aa-aedbf45e9f58	7cf33bb6-295b-537a-858b-cb371a0dc518	206c4a44-c525-5960-ad70-3a1e80f806e5	b9b9f90e-0ff3-5f7a-9bd6-66f15b26f5b9	6e4dae43-a541-594f-980b-6f78dedfcb0d	dcd21ca1-995a-51e7-b954-60af0e35b8ac	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	completed	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 04:00:00+00	2026-09-03 04:00:00+00	60
0f2551cc-952f-5382-a5d4-13e796ad1267	SEED-TYO-27	c92c6a89-9abf-5c08-a177-bf51791d9f47	81ffc193-d57e-50ba-a4f5-3e0e36638d47	206c4a44-c525-5960-ad70-3a1e80f806e5	eb7dcc4f-ab33-593e-b814-0c41ee9ff713	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	42eff788-5be8-5f54-afb7-7c14606599ea	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	cancelled	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	ded9e174-90f2-5ea7-9b35-86728f8544f7	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 02:00:00+00	\N	\N	\N	\N	\N	60
b7c5d581-9d85-59e4-96ca-88f3784eebfc	SEED-TYO-28	3612e1ca-d209-5f12-9949-ac32ce2b14af	4f0631c0-1689-5408-8023-421056d4f368	206c4a44-c525-5960-ad70-3a1e80f806e5	8f63bfdd-4205-5c3c-b82b-a818f235ec0e	60805ebd-cae5-57ce-aa9d-362d81cfc131	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	requested	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
4ac1de9a-4df8-5ff6-82a9-016c44132e74	SEED-TYO-29	35e47ee2-9301-542b-ae19-ad79c69769a3	82158d92-790d-56fb-9069-f19c60bd57ab	206c4a44-c525-5960-ad70-3a1e80f806e5	1e1aa59c-28cc-5938-810a-49ace5798ac8	93a7232e-d474-5224-8e5b-fd7e98e60a52	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	checked_in	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 03:00:00+00	\N	\N	\N	\N	60
f89aaf31-3917-50dc-928a-4aac5a5bdd69	SEED-TYO-30	1aacd4d6-1678-5444-8b29-4cc9266cab79	54c0ac6a-6530-503c-bf6b-358bf00084cb	206c4a44-c525-5960-ad70-3a1e80f806e5	f120f0da-0b7d-5d61-93b3-9fad0d9f3ca8	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	2026-09-03 03:00:00+00	2026-09-03 04:00:00+00	in_progress	Deterministic development fixture	ded9e174-90f2-5ea7-9b35-86728f8544f7	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 03:00:00+00	2026-09-03 03:10:00+00	2026-09-03 03:10:00+00	\N	\N	60
4b444f6b-ddf5-5197-9593-718af083c89a	SEED-SYD-01	1affb879-d86f-57f4-b3c4-c85b191c8fc9	6fa83485-cc32-5572-a0f1-907943e1b5b1	7022ed8e-d0bf-5f76-8c90-83d05b415fad	c7366e56-c082-529c-bbe1-1ebdb9f3894b	f94d6698-e5d4-544b-b734-a8672691fde0	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	completed	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-26 22:00:00+00	2026-08-26 22:00:00+00	60
0d5617d9-0de9-5f7d-a762-d26fa80048f8	SEED-SYD-02	6fcb75b2-5105-52b0-ba8e-b19767927261	4e14a2b9-7c6e-5997-b8fd-53b65a41b663	7022ed8e-d0bf-5f76-8c90-83d05b415fad	6ed744c8-ea85-58bc-9be4-0056f6ab3c6f	f94d6698-e5d4-544b-b734-a8672691fde0	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	cancelled	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-26 20:00:00+00	\N	\N	\N	\N	\N	60
79504438-8585-5412-a0e7-d5b60dafd48a	SEED-SYD-03	13f62a96-ac31-5ea6-98f0-e73edd54615d	0594263e-9ca1-578e-88f6-7555e614b620	7022ed8e-d0bf-5f76-8c90-83d05b415fad	4cff6571-1f04-58fc-8098-c3c36144c111	f94d6698-e5d4-544b-b734-a8672691fde0	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	requested	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
9c61762c-0ee2-51b8-938a-e279049ca95c	SEED-SYD-04	882cf7e7-9e39-56a2-a474-9f313bbf6097	2d53eda8-0ab5-5161-a2f5-23506c54c14f	7022ed8e-d0bf-5f76-8c90-83d05b415fad	786869e2-e980-55c3-b53d-2185a3422ea7	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	checked_in	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-26 21:00:00+00	\N	\N	\N	\N	60
e0dd9e5f-53b6-5c08-acfa-05a587e2ac8c	SEED-SYD-05	dc82f629-7f59-594f-8d92-0825a2037d75	e5eeba7f-0cd9-532c-a803-51db158829f3	7022ed8e-d0bf-5f76-8c90-83d05b415fad	d67ce61e-d7d5-5ace-9cea-e27505455b9e	f22afce6-9be8-5d54-8493-e187e6080d3d	42ce9d61-5263-5784-b0c8-984b6bf6aaae	2026-08-26 21:00:00+00	2026-08-26 22:00:00+00	in_progress	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-26 21:00:00+00	2026-08-26 21:10:00+00	2026-08-26 21:10:00+00	\N	\N	60
de360e40-e02c-5a71-acea-b80b29a40df8	SEED-SYD-06	bc529998-94f7-5058-96f3-836342680b21	d2ebaeb3-e9f9-570e-98ce-609fef4564b4	7022ed8e-d0bf-5f76-8c90-83d05b415fad	85fdbd48-c635-5eb6-b7e6-b19233d01410	f94d6698-e5d4-544b-b734-a8672691fde0	8806d3d9-7c39-511e-ab4d-8ac2880f513f	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	completed	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-26 23:00:00+00	2026-08-26 23:00:00+00	60
e4ca982c-fb5f-5359-b84a-ccc9ca3ef485	SEED-SYD-07	1fa6803d-2fa7-5eaa-b01a-d232998ded29	087c7d58-ce85-50e0-b60c-559879d69a24	7022ed8e-d0bf-5f76-8c90-83d05b415fad	883fb935-5e66-5ce6-a5dc-ac527f31c8a7	a710b9c6-f208-5130-a26d-8a583a0cae4e	432195c4-02e8-5310-b2a3-30ac3819e62b	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	cancelled	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-26 21:00:00+00	\N	\N	\N	\N	\N	60
1ee0e0ec-df9f-5a24-8596-78dc20ea5505	SEED-SYD-08	76795c68-ca60-5f1a-b0de-b94e4b9e11d0	340f8dae-4260-5801-bd45-e6c30c69648c	7022ed8e-d0bf-5f76-8c90-83d05b415fad	f9c95f62-48bd-53ed-b5bd-3a88d6aebd65	f94d6698-e5d4-544b-b734-a8672691fde0	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	requested	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
f170be60-f842-5db8-9eef-571ef9bcb6a0	SEED-SYD-09	8af7208e-c589-5aa8-927e-c0755a06cf2b	9f833944-5a95-5d2c-8c07-852b5dd2ee15	7022ed8e-d0bf-5f76-8c90-83d05b415fad	181b685e-e58b-5599-99c7-bb5eab8c8a53	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	9df77ddf-fe56-5e6f-8979-9b70e064d232	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	checked_in	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-26 22:00:00+00	\N	\N	\N	\N	60
62e2230e-6522-52e2-a581-854885613114	SEED-SYD-10	0bb1989c-8a2d-505e-ac75-39e872811b87	36980a83-396b-5c36-8796-fdd468e3f335	7022ed8e-d0bf-5f76-8c90-83d05b415fad	80b9bf14-43e6-52c3-a237-d1afa8031bab	f22afce6-9be8-5d54-8493-e187e6080d3d	2e5bd34a-e96d-50b1-89e7-4ced572bdad6	2026-08-26 22:00:00+00	2026-08-26 23:00:00+00	in_progress	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-26 22:00:00+00	2026-08-26 22:10:00+00	2026-08-26 22:10:00+00	\N	\N	60
77554b46-a2d1-5c95-843d-d0bc4b12523f	SEED-SYD-11	e79213dc-09e6-5635-b5e0-77119b6dcb34	87a4a8ff-4235-507a-b404-96be3db45254	7022ed8e-d0bf-5f76-8c90-83d05b415fad	737ee088-dc99-5ea3-adb3-d2305ce19c5a	f94d6698-e5d4-544b-b734-a8672691fde0	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	completed	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 00:00:00+00	2026-08-28 00:00:00+00	60
2d2fbe57-cf40-5023-b8fa-366f5c910bfd	SEED-SYD-12	de0d38de-4cc8-59d0-92f4-d5b7983c3ad0	b1dec991-dbd0-5ee3-a2d6-37f1e77d424e	7022ed8e-d0bf-5f76-8c90-83d05b415fad	eaa1aa5e-613c-5c1d-8915-b8b57b8f29e3	a710b9c6-f208-5130-a26d-8a583a0cae4e	42ce9d61-5263-5784-b0c8-984b6bf6aaae	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	cancelled	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-27 22:00:00+00	\N	\N	\N	\N	\N	60
a81c1b3f-ef10-558b-b7c8-465db5e6eeed	SEED-SYD-13	8c40de9f-e606-5edc-add8-b3ff331d0911	5b7e2361-00fb-57f5-87c2-e5d966b11366	7022ed8e-d0bf-5f76-8c90-83d05b415fad	241d6f87-d07a-5e17-b773-4eb7470f146f	a2d88a64-e213-5b97-8356-654a9acaf896	8806d3d9-7c39-511e-ab4d-8ac2880f513f	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	requested	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
1182656f-e6a1-5e21-a922-dddd2272efae	SEED-SYD-14	edb5fa48-3fd1-5f7b-8392-67a66c888f59	8ea53aff-d82f-5a21-9a20-44c8e13f06ef	7022ed8e-d0bf-5f76-8c90-83d05b415fad	04c18d67-1c66-5d02-a797-f03f8d94a1e9	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	432195c4-02e8-5310-b2a3-30ac3819e62b	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	checked_in	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 23:00:00+00	\N	\N	\N	\N	60
30af9f27-45da-5500-b295-aab66f60aa20	SEED-SYD-15	3ed4c6d5-75d6-50da-a013-7a85716bb392	0f2cba2f-71d0-53c7-b36f-9437ce4420e9	7022ed8e-d0bf-5f76-8c90-83d05b415fad	c7366e56-c082-529c-bbe1-1ebdb9f3894b	f22afce6-9be8-5d54-8493-e187e6080d3d	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-08-27 23:00:00+00	2026-08-28 00:00:00+00	in_progress	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 23:00:00+00	2026-08-27 23:10:00+00	2026-08-27 23:10:00+00	\N	\N	60
dccfa163-8f7a-571c-b752-f9d913f1ea1d	SEED-SYD-16	22403b61-01f2-50f3-80f7-d93eeaaad21c	4ae15891-4a9d-5f57-8538-d0af67c53a68	7022ed8e-d0bf-5f76-8c90-83d05b415fad	6ed744c8-ea85-58bc-9be4-0056f6ab3c6f	f94d6698-e5d4-544b-b734-a8672691fde0	9df77ddf-fe56-5e6f-8979-9b70e064d232	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	completed	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 01:00:00+00	2026-08-28 01:00:00+00	60
1b32fb8c-3a63-55e8-ac78-19f1b0211117	SEED-SYD-17	2b49d420-496b-59ba-9b6e-df5a807c747d	d8d75948-a3c0-56f3-8994-53f15010d4a5	7022ed8e-d0bf-5f76-8c90-83d05b415fad	4cff6571-1f04-58fc-8098-c3c36144c111	a710b9c6-f208-5130-a26d-8a583a0cae4e	2e5bd34a-e96d-50b1-89e7-4ced572bdad6	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	cancelled	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-27 23:00:00+00	\N	\N	\N	\N	\N	60
e4fe3c94-eda0-5699-83bd-95e4c7df170c	SEED-SYD-18	a95b55f0-c6a8-5e79-96e4-a16beb4c6e28	fcc32567-3ce9-51ef-9daa-e47153bbe9fa	7022ed8e-d0bf-5f76-8c90-83d05b415fad	786869e2-e980-55c3-b53d-2185a3422ea7	a2d88a64-e213-5b97-8356-654a9acaf896	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	requested	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
8c535195-49b7-5c90-a309-89cf65c97c16	SEED-SYD-19	d40ba67b-e4cf-5007-a8a6-860ba130d5b6	6a12cbf7-9f1a-55c2-b502-93a3665c046b	7022ed8e-d0bf-5f76-8c90-83d05b415fad	d67ce61e-d7d5-5ace-9cea-e27505455b9e	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	42ce9d61-5263-5784-b0c8-984b6bf6aaae	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	checked_in	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 00:00:00+00	\N	\N	\N	\N	60
aff4d2d5-56f1-5c0c-94c0-9bb019ce56e4	SEED-SYD-20	0cf297dd-f807-58ae-855e-be1fe4fa3912	6c8b0337-98d6-5aac-a5a0-19f52259f28b	7022ed8e-d0bf-5f76-8c90-83d05b415fad	85fdbd48-c635-5eb6-b7e6-b19233d01410	f22afce6-9be8-5d54-8493-e187e6080d3d	8806d3d9-7c39-511e-ab4d-8ac2880f513f	2026-08-28 00:00:00+00	2026-08-28 01:00:00+00	in_progress	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 00:00:00+00	2026-08-28 00:10:00+00	2026-08-28 00:10:00+00	\N	\N	60
9a391023-01e3-5d06-a25b-742922dea10b	SEED-SYD-21	1affb879-d86f-57f4-b3c4-c85b191c8fc9	6fa83485-cc32-5572-a0f1-907943e1b5b1	7022ed8e-d0bf-5f76-8c90-83d05b415fad	883fb935-5e66-5ce6-a5dc-ac527f31c8a7	f94d6698-e5d4-544b-b734-a8672691fde0	432195c4-02e8-5310-b2a3-30ac3819e62b	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	completed	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 02:00:00+00	2026-09-03 02:00:00+00	60
4e7e57e6-f7b8-5d8c-b20a-f2204a32e1a3	SEED-SYD-22	6fcb75b2-5105-52b0-ba8e-b19767927261	4e14a2b9-7c6e-5997-b8fd-53b65a41b663	7022ed8e-d0bf-5f76-8c90-83d05b415fad	f9c95f62-48bd-53ed-b5bd-3a88d6aebd65	a710b9c6-f208-5130-a26d-8a583a0cae4e	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	cancelled	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 00:00:00+00	\N	\N	\N	\N	\N	60
8a4c23ed-cb76-55d6-8de2-d9255a7b35d3	SEED-SYD-23	13f62a96-ac31-5ea6-98f0-e73edd54615d	0594263e-9ca1-578e-88f6-7555e614b620	7022ed8e-d0bf-5f76-8c90-83d05b415fad	181b685e-e58b-5599-99c7-bb5eab8c8a53	a2d88a64-e213-5b97-8356-654a9acaf896	9df77ddf-fe56-5e6f-8979-9b70e064d232	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	requested	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
72d47fd7-418b-54f8-b70e-47f540aa0410	SEED-SYD-24	882cf7e7-9e39-56a2-a474-9f313bbf6097	2d53eda8-0ab5-5161-a2f5-23506c54c14f	7022ed8e-d0bf-5f76-8c90-83d05b415fad	80b9bf14-43e6-52c3-a237-d1afa8031bab	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	2e5bd34a-e96d-50b1-89e7-4ced572bdad6	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	checked_in	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 01:00:00+00	\N	\N	\N	\N	60
459a9bd6-464c-576d-8ff2-d229c1ad32d6	SEED-SYD-25	dc82f629-7f59-594f-8d92-0825a2037d75	e5eeba7f-0cd9-532c-a803-51db158829f3	7022ed8e-d0bf-5f76-8c90-83d05b415fad	737ee088-dc99-5ea3-adb3-d2305ce19c5a	f22afce6-9be8-5d54-8493-e187e6080d3d	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	2026-09-03 01:00:00+00	2026-09-03 02:00:00+00	in_progress	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 01:00:00+00	2026-09-03 01:10:00+00	2026-09-03 01:10:00+00	\N	\N	60
ee1a172a-5c0f-59bf-851b-580dbe0c69f5	SEED-SYD-26	bc529998-94f7-5058-96f3-836342680b21	d2ebaeb3-e9f9-570e-98ce-609fef4564b4	7022ed8e-d0bf-5f76-8c90-83d05b415fad	eaa1aa5e-613c-5c1d-8915-b8b57b8f29e3	f94d6698-e5d4-544b-b734-a8672691fde0	42ce9d61-5263-5784-b0c8-984b6bf6aaae	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	completed	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 03:00:00+00	2026-09-03 03:00:00+00	60
817bb0d2-44c5-5c61-914c-17b3ac6d4995	SEED-SYD-27	1fa6803d-2fa7-5eaa-b01a-d232998ded29	087c7d58-ce85-50e0-b60c-559879d69a24	7022ed8e-d0bf-5f76-8c90-83d05b415fad	241d6f87-d07a-5e17-b773-4eb7470f146f	a710b9c6-f208-5130-a26d-8a583a0cae4e	8806d3d9-7c39-511e-ab4d-8ac2880f513f	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	cancelled	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	7cedc8b3-3996-52bc-a6de-5f6f2041740f	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 01:00:00+00	\N	\N	\N	\N	\N	60
caa3557d-36eb-556e-b391-d9057fc59ca3	SEED-SYD-28	76795c68-ca60-5f1a-b0de-b94e4b9e11d0	340f8dae-4260-5801-bd45-e6c30c69648c	7022ed8e-d0bf-5f76-8c90-83d05b415fad	04c18d67-1c66-5d02-a797-f03f8d94a1e9	a2d88a64-e213-5b97-8356-654a9acaf896	432195c4-02e8-5310-b2a3-30ac3819e62b	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	requested	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
7dc04982-934e-5a23-9153-bc402adda956	SEED-SYD-29	8af7208e-c589-5aa8-927e-c0755a06cf2b	9f833944-5a95-5d2c-8c07-852b5dd2ee15	7022ed8e-d0bf-5f76-8c90-83d05b415fad	c7366e56-c082-529c-bbe1-1ebdb9f3894b	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	checked_in	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 02:00:00+00	\N	\N	\N	\N	60
d00534d3-40d4-5c9d-8d56-e10bdcc947d3	SEED-SYD-30	0bb1989c-8a2d-505e-ac75-39e872811b87	36980a83-396b-5c36-8796-fdd468e3f335	7022ed8e-d0bf-5f76-8c90-83d05b415fad	6ed744c8-ea85-58bc-9be4-0056f6ab3c6f	f22afce6-9be8-5d54-8493-e187e6080d3d	9df77ddf-fe56-5e6f-8979-9b70e064d232	2026-09-03 02:00:00+00	2026-09-03 03:00:00+00	in_progress	Deterministic development fixture	7cedc8b3-3996-52bc-a6de-5f6f2041740f	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 02:00:00+00	2026-09-03 02:10:00+00	2026-09-03 02:10:00+00	\N	\N	60
046a62e0-c90a-56b7-a7d7-304f8be5770e	SEED-LDN-01	2e3822ad-e19a-5815-91f5-005547e08893	2d36bdea-bc1e-57eb-ab7c-d7c27c117c28	e47567a4-a655-5f7a-93b2-75831525fff3	22ef464c-18b0-5cfa-b612-adedbf8f4f44	9cdfb0cd-e427-5722-a838-333ba2098240	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	completed	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-27 07:00:00+00	2026-08-27 07:00:00+00	60
11ca01c4-1317-5277-b800-2e5e6d2b8dac	SEED-LDN-02	e04ad513-ee6a-5dd8-8204-59a5ac538927	ba375fa5-4acf-5d6a-b25a-47ab14af7e70	e47567a4-a655-5f7a-93b2-75831525fff3	187c196a-5662-5427-8324-702ae75a80d8	9cdfb0cd-e427-5722-a838-333ba2098240	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	cancelled	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	725e5cc4-6682-5e91-a195-973b60f26754	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-27 05:00:00+00	\N	\N	\N	\N	\N	60
96d525e6-6502-5c87-8088-44848f1e50ae	SEED-LDN-03	a329fbb9-bf4b-58ca-b306-a030c02851f7	4aabef33-da2d-50b7-8dde-2d5db2c75d9d	e47567a4-a655-5f7a-93b2-75831525fff3	2c40bc38-b50f-59ed-913b-7fe27db0907f	9cdfb0cd-e427-5722-a838-333ba2098240	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	requested	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
983efce1-7010-5876-8bd0-d0888d318535	SEED-LDN-04	068e4c89-6f3f-59fc-a41b-fdc12cdc78a2	974b06e3-4b05-580c-846a-d100734436b4	e47567a4-a655-5f7a-93b2-75831525fff3	64d7a9c8-2455-547e-ba40-99bb8893a8a9	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	f98cc283-b3ce-5c13-82b5-5b343ed52d21	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	checked_in	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 06:00:00+00	\N	\N	\N	\N	60
083b4b0a-d7bf-5a80-904f-5bd7deceed55	SEED-LDN-05	8edcec2f-bcd6-5fb5-af4a-0a3aedef34dc	874f1f28-40b8-5863-8c48-4fc59d185841	e47567a4-a655-5f7a-93b2-75831525fff3	fc30bc18-cadc-5e1d-9f5c-2a85fcd5fc0b	e98c71df-d0a6-56d0-a881-2a2c57bf5986	f3436b53-3c8c-5302-afa3-904ea008c446	2026-08-27 06:00:00+00	2026-08-27 07:00:00+00	in_progress	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 06:00:00+00	2026-08-27 06:10:00+00	2026-08-27 06:10:00+00	\N	\N	60
339b73b4-8cd6-5f46-b4b5-98faf11f3d3d	SEED-LDN-06	e1fb0fec-3da5-596a-a7c3-21abc8151bf6	c3f63e28-3b35-5d80-b14f-97a7dcb71c66	e47567a4-a655-5f7a-93b2-75831525fff3	17e7df9e-3462-5f29-96e4-d78a710aba4a	9cdfb0cd-e427-5722-a838-333ba2098240	16bdd951-987c-5321-89b3-3dda5dacaec1	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	completed	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-27 08:00:00+00	2026-08-27 08:00:00+00	60
01ed52c9-7e2d-5d09-9fdf-0307a94d27d8	SEED-LDN-07	563e0739-240c-541f-8f4d-16bbc9d2a309	2a163b40-cd5e-5feb-b341-a454c0401f42	e47567a4-a655-5f7a-93b2-75831525fff3	ff9a4d7e-bb4e-54f8-ac15-0ae6ec2d9d09	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	cancelled	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	725e5cc4-6682-5e91-a195-973b60f26754	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-27 06:00:00+00	\N	\N	\N	\N	\N	60
11e8d049-c717-5936-9e32-c9ad84bf9567	SEED-LDN-08	17892473-2b27-56d3-85b8-a199914fab70	1af48fa5-fa68-5978-be2e-ea55294447ab	e47567a4-a655-5f7a-93b2-75831525fff3	cfe112ca-e18a-5125-bdec-ad756c242104	9cdfb0cd-e427-5722-a838-333ba2098240	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	requested	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
124f135a-4b55-51af-8289-8d03aa04ad13	SEED-LDN-09	f03fd9c6-4033-5ff3-aa27-357ef26d2381	afb41f01-00cf-55c4-ae12-edfbca7837be	e47567a4-a655-5f7a-93b2-75831525fff3	095bf04c-ae81-5f7f-bc46-5fb6ba832410	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	checked_in	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 07:00:00+00	\N	\N	\N	\N	60
e50dd2ea-6723-5069-8e30-9abf1a3c8ebe	SEED-LDN-10	6d1da64a-6fe0-5a49-b86c-bbbd2955dd63	e52ae128-9a7d-57e8-aaea-e4d1d44cbd5c	e47567a4-a655-5f7a-93b2-75831525fff3	358ed023-5145-5788-aa33-162d23201a8c	e98c71df-d0a6-56d0-a881-2a2c57bf5986	d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	2026-08-27 07:00:00+00	2026-08-27 08:00:00+00	in_progress	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 07:00:00+00	2026-08-27 07:10:00+00	2026-08-27 07:10:00+00	\N	\N	60
f640f7dc-4389-54bd-a6bc-54c54198bcaf	SEED-LDN-11	949c5a87-faf0-5aba-b569-0ddb9bc6f196	076a7b41-1f59-595d-a630-cca12b415b2b	e47567a4-a655-5f7a-93b2-75831525fff3	72e9238b-b758-5b8a-9cec-4de23ea6ee05	9cdfb0cd-e427-5722-a838-333ba2098240	f98cc283-b3ce-5c13-82b5-5b343ed52d21	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	completed	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 09:00:00+00	2026-08-28 09:00:00+00	60
422c4871-31d1-5ba2-8874-1ecf000fe2a1	SEED-LDN-12	4ff52b83-4bfc-513b-858b-7ecedba09707	1c385a04-370b-518f-ba26-f6c28ee9b35b	e47567a4-a655-5f7a-93b2-75831525fff3	e777d567-9057-5874-9c0b-f31166ebe27f	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	f3436b53-3c8c-5302-afa3-904ea008c446	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	cancelled	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	725e5cc4-6682-5e91-a195-973b60f26754	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-28 07:00:00+00	\N	\N	\N	\N	\N	60
9a19db3b-241f-5cbc-8d27-c169038ac12b	SEED-LDN-13	f8f9be2b-742e-5f0a-97e8-2ba58b6019ca	46e28768-d2f1-5f87-829e-8cb38b3fbb00	e47567a4-a655-5f7a-93b2-75831525fff3	72d0a511-17f7-50f1-b31f-827269bfcdf9	adf23604-8641-504a-be4a-f23c5d9579b6	16bdd951-987c-5321-89b3-3dda5dacaec1	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	requested	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
a294c79d-0853-5503-bf08-5cb44daf7272	SEED-LDN-14	40cbdddc-db06-58ce-bfc8-fe5515f183ae	45c336a0-d3af-59be-acba-8b9908615873	e47567a4-a655-5f7a-93b2-75831525fff3	9d3532cf-7d8d-5315-80d5-ab0fc5494335	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	checked_in	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 08:00:00+00	\N	\N	\N	\N	60
e6e89bf4-a182-5457-8d65-d63275022432	SEED-LDN-15	533b924a-6fb0-5c7e-a18f-91dfc7fcc23d	b87f8bf6-3b83-5ba0-9c7a-0948ed076d74	e47567a4-a655-5f7a-93b2-75831525fff3	22ef464c-18b0-5cfa-b612-adedbf8f4f44	e98c71df-d0a6-56d0-a881-2a2c57bf5986	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-08-28 08:00:00+00	2026-08-28 09:00:00+00	in_progress	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 08:00:00+00	2026-08-28 08:10:00+00	2026-08-28 08:10:00+00	\N	\N	60
2858ded8-19d8-5a99-b515-1de4947ed87f	SEED-LDN-16	7ccbe661-de11-5483-8fd9-6990ea61b4bc	61ef70ad-bd6d-5efa-8f09-80bf6daa4d99	e47567a4-a655-5f7a-93b2-75831525fff3	187c196a-5662-5427-8324-702ae75a80d8	9cdfb0cd-e427-5722-a838-333ba2098240	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	completed	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 10:00:00+00	2026-08-28 10:00:00+00	60
a631ee0b-d59d-54cb-b82b-24fd0586e22f	SEED-LDN-17	9286c839-94d7-5698-91f5-54e62832bf0f	d3a1e256-d90a-50f1-86ad-1bfe59938cc4	e47567a4-a655-5f7a-93b2-75831525fff3	2c40bc38-b50f-59ed-913b-7fe27db0907f	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	cancelled	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	725e5cc4-6682-5e91-a195-973b60f26754	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-28 08:00:00+00	\N	\N	\N	\N	\N	60
a75143b1-eb7d-555b-a6a1-80e3e8e6b7a6	SEED-LDN-18	7b54ff2c-5266-5434-b636-2b7abe0472bd	795134c5-c0c2-5729-be3a-2f7f28667a61	e47567a4-a655-5f7a-93b2-75831525fff3	64d7a9c8-2455-547e-ba40-99bb8893a8a9	adf23604-8641-504a-be4a-f23c5d9579b6	f98cc283-b3ce-5c13-82b5-5b343ed52d21	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	requested	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
b696b2b9-af07-5a99-adca-a0074a51b3bc	SEED-LDN-19	6ac97c6d-0889-5cd5-b9ad-9daf67115e43	78efa595-b106-59fb-9e2d-458b36c1fc7a	e47567a4-a655-5f7a-93b2-75831525fff3	fc30bc18-cadc-5e1d-9f5c-2a85fcd5fc0b	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	f3436b53-3c8c-5302-afa3-904ea008c446	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	checked_in	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 09:00:00+00	\N	\N	\N	\N	60
0e085804-8bb3-5c65-98f9-5b1a16a23bc1	SEED-LDN-20	d0d32715-14ce-5fc1-9afa-4aa73a145ce1	d3d2156b-96b8-5ea5-b6ce-fb4514e19844	e47567a4-a655-5f7a-93b2-75831525fff3	17e7df9e-3462-5f29-96e4-d78a710aba4a	e98c71df-d0a6-56d0-a881-2a2c57bf5986	16bdd951-987c-5321-89b3-3dda5dacaec1	2026-08-28 09:00:00+00	2026-08-28 10:00:00+00	in_progress	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 09:00:00+00	2026-08-28 09:10:00+00	2026-08-28 09:10:00+00	\N	\N	60
a632049b-5eaf-54a0-af20-0c97cfe687d9	SEED-LDN-21	2e3822ad-e19a-5815-91f5-005547e08893	2d36bdea-bc1e-57eb-ab7c-d7c27c117c28	e47567a4-a655-5f7a-93b2-75831525fff3	ff9a4d7e-bb4e-54f8-ac15-0ae6ec2d9d09	9cdfb0cd-e427-5722-a838-333ba2098240	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	completed	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 11:00:00+00	2026-09-03 11:00:00+00	60
f25259c8-3eff-5f58-8e9f-944fbfb9a7b3	SEED-LDN-22	e04ad513-ee6a-5dd8-8204-59a5ac538927	ba375fa5-4acf-5d6a-b25a-47ab14af7e70	e47567a4-a655-5f7a-93b2-75831525fff3	cfe112ca-e18a-5125-bdec-ad756c242104	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	cancelled	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	725e5cc4-6682-5e91-a195-973b60f26754	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 09:00:00+00	\N	\N	\N	\N	\N	60
a5659d7b-3b87-509e-92d7-489b8a454a9e	SEED-LDN-23	a329fbb9-bf4b-58ca-b306-a030c02851f7	4aabef33-da2d-50b7-8dde-2d5db2c75d9d	e47567a4-a655-5f7a-93b2-75831525fff3	095bf04c-ae81-5f7f-bc46-5fb6ba832410	adf23604-8641-504a-be4a-f23c5d9579b6	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	requested	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
01a5daf6-126c-5ea9-8a49-ef48eaa33056	SEED-LDN-24	068e4c89-6f3f-59fc-a41b-fdc12cdc78a2	974b06e3-4b05-580c-846a-d100734436b4	e47567a4-a655-5f7a-93b2-75831525fff3	358ed023-5145-5788-aa33-162d23201a8c	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	checked_in	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 10:00:00+00	\N	\N	\N	\N	60
d62e17b5-590c-53ff-bf82-35bf57ac3136	SEED-LDN-25	8edcec2f-bcd6-5fb5-af4a-0a3aedef34dc	874f1f28-40b8-5863-8c48-4fc59d185841	e47567a4-a655-5f7a-93b2-75831525fff3	72e9238b-b758-5b8a-9cec-4de23ea6ee05	e98c71df-d0a6-56d0-a881-2a2c57bf5986	f98cc283-b3ce-5c13-82b5-5b343ed52d21	2026-09-03 10:00:00+00	2026-09-03 11:00:00+00	in_progress	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 10:00:00+00	2026-09-03 10:10:00+00	2026-09-03 10:10:00+00	\N	\N	60
0563c049-6bff-57e2-8d0a-49c9aeb2028f	SEED-LDN-26	e1fb0fec-3da5-596a-a7c3-21abc8151bf6	c3f63e28-3b35-5d80-b14f-97a7dcb71c66	e47567a4-a655-5f7a-93b2-75831525fff3	e777d567-9057-5874-9c0b-f31166ebe27f	9cdfb0cd-e427-5722-a838-333ba2098240	f3436b53-3c8c-5302-afa3-904ea008c446	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	completed	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 12:00:00+00	2026-09-03 12:00:00+00	60
47b47b9b-443c-5af4-9cc7-bbb4d18da237	SEED-LDN-27	563e0739-240c-541f-8f4d-16bbc9d2a309	2a163b40-cd5e-5feb-b341-a454c0401f42	e47567a4-a655-5f7a-93b2-75831525fff3	72d0a511-17f7-50f1-b31f-827269bfcdf9	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	16bdd951-987c-5321-89b3-3dda5dacaec1	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	cancelled	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	725e5cc4-6682-5e91-a195-973b60f26754	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 10:00:00+00	\N	\N	\N	\N	\N	60
f3432f7d-dba3-5ccc-a8c3-a1e1d117fcb7	SEED-LDN-28	17892473-2b27-56d3-85b8-a199914fab70	1af48fa5-fa68-5978-be2e-ea55294447ab	e47567a4-a655-5f7a-93b2-75831525fff3	9d3532cf-7d8d-5315-80d5-ab0fc5494335	adf23604-8641-504a-be4a-f23c5d9579b6	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	requested	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
57f4da57-577b-5193-b437-1e02c1291e69	SEED-LDN-29	f03fd9c6-4033-5ff3-aa27-357ef26d2381	afb41f01-00cf-55c4-ae12-edfbca7837be	e47567a4-a655-5f7a-93b2-75831525fff3	22ef464c-18b0-5cfa-b612-adedbf8f4f44	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	checked_in	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 11:00:00+00	\N	\N	\N	\N	60
2da0cddf-93e0-56d4-96a8-38fa23aca797	SEED-LDN-30	6d1da64a-6fe0-5a49-b86c-bbbd2955dd63	e52ae128-9a7d-57e8-aaea-e4d1d44cbd5c	e47567a4-a655-5f7a-93b2-75831525fff3	187c196a-5662-5427-8324-702ae75a80d8	e98c71df-d0a6-56d0-a881-2a2c57bf5986	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	2026-09-03 11:00:00+00	2026-09-03 12:00:00+00	in_progress	Deterministic development fixture	725e5cc4-6682-5e91-a195-973b60f26754	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 11:00:00+00	2026-09-03 11:10:00+00	2026-09-03 11:10:00+00	\N	\N	60
74d19b2d-a91d-5ae4-b72c-ad18325dd2bb	SEED-LAX-01	daf78796-8816-5ae3-b5b0-d327e03764d2	0576b5f1-87c7-5510-8077-0aa37958e309	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	d374adef-adf3-5b71-b525-a6c6262bf463	f6e45079-dc94-52f1-a87f-fb82c82c6684	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	completed	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-27 15:00:00+00	2026-08-27 15:00:00+00	60
957ea531-0a9e-5913-b1cc-7e36293904be	SEED-LAX-02	b155f7ca-0311-5ae2-9775-20a123db0d35	b0788dd1-91c6-5c6f-9888-07f166631c06	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	1a7a8f85-7fd9-5d31-8247-fd5e7b7dd4b9	f6e45079-dc94-52f1-a87f-fb82c82c6684	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	cancelled	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	2ad48f7a-7d9b-5503-a68d-07001e014841	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-27 13:00:00+00	\N	\N	\N	\N	\N	60
352c053c-7ce5-5c50-a16f-95b386bc8fa1	SEED-LAX-03	28ccf436-cbad-54e8-9eb8-7742302ee14e	1989b53c-d8f4-5b00-a737-50830a9ad5f7	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	786c9846-b6c6-58fa-8635-787a18701ee3	f6e45079-dc94-52f1-a87f-fb82c82c6684	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	requested	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
8f780028-909c-5e1f-a59b-3e126bf600af	SEED-LAX-04	dc5114d1-aa50-5995-a1ab-40223403a1a3	3352ba6a-3075-5c57-827c-aa6917c116a4	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	5e928f28-f117-520a-9649-833d16276213	885312b8-41b5-5011-b4d6-948cffe99df2	baada9ae-6167-533e-ad0d-1ee0e47ef254	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	checked_in	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 14:00:00+00	\N	\N	\N	\N	60
d5c03091-be46-5656-ba36-ec8f62830e91	SEED-LAX-05	475e45e4-b6bc-57cf-a63d-5481a41eb665	cb708075-7755-5b10-b9b4-1a13de5f26c8	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	46120ad3-1942-522e-84f3-3761e21d9047	ed061c8d-b8b7-5356-813b-79b188f7a0ba	26ed90fd-20f8-511c-88e5-55f55772b50e	2026-08-27 14:00:00+00	2026-08-27 15:00:00+00	in_progress	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 14:00:00+00	2026-08-27 14:10:00+00	2026-08-27 14:10:00+00	\N	\N	60
701ca8af-2dea-5e92-85f9-848ee5e18a2f	SEED-LAX-06	153416ff-4e01-5841-a7da-b205eea54021	598672b5-ddd8-558d-b476-b0cbd270d84e	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	040a1aa0-177a-5154-a4c8-2853a5ac97e1	f6e45079-dc94-52f1-a87f-fb82c82c6684	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	completed	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-27 16:00:00+00	2026-08-27 16:00:00+00	60
a464346f-d4fd-5039-89b7-079107ba4709	SEED-LAX-07	6b265c6e-a5e3-5139-be41-8852aa0fb916	b0dd34cf-637b-5591-b28d-f74efcf16c60	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	d8ec1c58-f79d-5680-9ee7-0453e2b3984b	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	3aabc2d5-d94e-5d21-a979-632c719fd85d	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	cancelled	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	2ad48f7a-7d9b-5503-a68d-07001e014841	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-27 14:00:00+00	\N	\N	\N	\N	\N	60
ea68f82e-0a49-564e-854e-52f6a627a863	SEED-LAX-08	40f39805-a8b2-5fc6-a763-891ec56d488c	9bef2180-0313-5335-9637-31f3dbbcb9c7	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	334b3b9e-8bca-53f3-bf7f-272e889fb410	f6e45079-dc94-52f1-a87f-fb82c82c6684	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	requested	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
1359d325-e1dd-559c-a4d0-a962c62508a7	SEED-LAX-09	67d51689-68ff-545e-b892-7ff948f95b18	7f7beac8-8f93-5148-8fe1-c66d41346be3	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	f56033f4-69a7-57dc-a5bd-a66944ecac34	885312b8-41b5-5011-b4d6-948cffe99df2	b703c0bd-0601-5342-a6bd-7eee5b24f28d	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	checked_in	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 15:00:00+00	\N	\N	\N	\N	60
49ee3e16-c24a-547b-b05d-6d25475f4cff	SEED-LAX-10	3e57c941-3d1b-501b-9d85-973c26c953d8	ed02ea69-eacf-5050-809a-64c251923424	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	d6d8407e-4c7d-5fd7-a2ba-3660c3de1312	ed061c8d-b8b7-5356-813b-79b188f7a0ba	3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	2026-08-27 15:00:00+00	2026-08-27 16:00:00+00	in_progress	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-27 15:00:00+00	2026-08-27 15:10:00+00	2026-08-27 15:10:00+00	\N	\N	60
a6f39d8e-6a95-5cd6-be05-610083ee0609	SEED-LAX-11	73c8ba36-5adf-5fd5-ae3b-b645f64770cc	dc404a37-8af7-5f44-9309-16e681230490	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	a512c728-7421-5f09-927c-6c742849e965	f6e45079-dc94-52f1-a87f-fb82c82c6684	baada9ae-6167-533e-ad0d-1ee0e47ef254	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	completed	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 17:00:00+00	2026-08-28 17:00:00+00	60
0a88e4ba-6992-576c-8d88-d4c668321f11	SEED-LAX-12	5ec6ad08-46dd-5b53-8491-ce236867513e	4a12993b-b498-5472-b705-cd5ce1a5d3e2	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	ffc7415f-ac53-5a76-90f8-d1701ff9c8f4	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	26ed90fd-20f8-511c-88e5-55f55772b50e	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	cancelled	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	2ad48f7a-7d9b-5503-a68d-07001e014841	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-28 15:00:00+00	\N	\N	\N	\N	\N	60
ec69ef24-35e8-5eec-913c-e74c29fe329a	SEED-LAX-13	4fe40293-bce2-5e7c-aa9d-2b67f5072cfc	82141f9f-1f07-5a8d-8fa7-96fad289d1fc	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	52e99567-b48a-50e7-b996-5f38fdc4706e	4a5f4e0e-e447-519c-8f36-bb3d60802506	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	requested	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
7ad83945-6cac-59bf-8278-67144b7b6264	SEED-LAX-14	fc67775d-f9e3-59f1-9b25-0bda20414e11	0fb2a53c-772d-5250-9e7e-bba179645d4c	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	328552e6-3212-5470-9d94-e75fe36eec6a	885312b8-41b5-5011-b4d6-948cffe99df2	3aabc2d5-d94e-5d21-a979-632c719fd85d	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	checked_in	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 16:00:00+00	\N	\N	\N	\N	60
03dd3106-c13f-5501-8900-f2553d346387	SEED-LAX-15	8f44d162-c9e2-565d-9c9e-30fa23a7b017	0af2a3e3-a67b-5498-a4cc-d15470c06377	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	d374adef-adf3-5b71-b525-a6c6262bf463	ed061c8d-b8b7-5356-813b-79b188f7a0ba	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-08-28 16:00:00+00	2026-08-28 17:00:00+00	in_progress	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 16:00:00+00	2026-08-28 16:10:00+00	2026-08-28 16:10:00+00	\N	\N	60
38ece363-7034-5af6-b988-c5d92552e6be	SEED-LAX-16	880a4007-7176-52cd-8662-bb85fc42b40f	454e4bfa-474f-5338-a48c-3e15f019bef6	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	1a7a8f85-7fd9-5d31-8247-fd5e7b7dd4b9	f6e45079-dc94-52f1-a87f-fb82c82c6684	b703c0bd-0601-5342-a6bd-7eee5b24f28d	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	completed	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-08-28 18:00:00+00	2026-08-28 18:00:00+00	60
de7aa3a5-55dd-5635-a9a2-4c8e7d229a54	SEED-LAX-17	a16bc619-6712-561b-94d3-36bbf476bacc	c41d9eb2-44b0-5b1f-87cf-f5dc6810a1c9	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	786c9846-b6c6-58fa-8635-787a18701ee3	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	cancelled	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	2ad48f7a-7d9b-5503-a68d-07001e014841	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-08-28 16:00:00+00	\N	\N	\N	\N	\N	60
e7d1574e-5124-5b1e-8715-814772a587fa	SEED-LAX-18	9bc9d562-af93-57ef-b778-c9eab3baff32	d65f06fb-9fa8-5c63-970a-eeb570bd46c7	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	5e928f28-f117-520a-9649-833d16276213	4a5f4e0e-e447-519c-8f36-bb3d60802506	baada9ae-6167-533e-ad0d-1ee0e47ef254	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	requested	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
c543cda9-b2fd-559c-a757-490848fdf302	SEED-LAX-19	ecb3409c-39d8-5b3e-9805-ce476a1de18a	bc97d4c6-6e91-542e-a5cb-c92a124258d8	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	46120ad3-1942-522e-84f3-3761e21d9047	885312b8-41b5-5011-b4d6-948cffe99df2	26ed90fd-20f8-511c-88e5-55f55772b50e	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	checked_in	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 17:00:00+00	\N	\N	\N	\N	60
7989a5e7-e12b-5875-954b-68ffaf8d0814	SEED-LAX-20	8c4fe118-3953-5fff-a4cd-c0972e62cf8a	c3660d5d-851c-5a2c-8ca5-25fa72601ccd	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	040a1aa0-177a-5154-a4c8-2853a5ac97e1	ed061c8d-b8b7-5356-813b-79b188f7a0ba	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	2026-08-28 17:00:00+00	2026-08-28 18:00:00+00	in_progress	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-08-28 17:00:00+00	2026-08-28 17:10:00+00	2026-08-28 17:10:00+00	\N	\N	60
ba820a4e-0f95-5b7d-b9a5-721a767736e3	SEED-LAX-21	daf78796-8816-5ae3-b5b0-d327e03764d2	0576b5f1-87c7-5510-8077-0aa37958e309	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	d8ec1c58-f79d-5680-9ee7-0453e2b3984b	f6e45079-dc94-52f1-a87f-fb82c82c6684	3aabc2d5-d94e-5d21-a979-632c719fd85d	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	completed	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 19:00:00+00	2026-09-03 19:00:00+00	60
dafdef31-4855-5c70-896f-08b743bfbcd8	SEED-LAX-22	b155f7ca-0311-5ae2-9775-20a123db0d35	b0788dd1-91c6-5c6f-9888-07f166631c06	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	334b3b9e-8bca-53f3-bf7f-272e889fb410	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	cancelled	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	2ad48f7a-7d9b-5503-a68d-07001e014841	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 17:00:00+00	\N	\N	\N	\N	\N	60
501adc19-bc0a-5cb2-a6d6-8af3d8185d88	SEED-LAX-23	28ccf436-cbad-54e8-9eb8-7742302ee14e	1989b53c-d8f4-5b00-a737-50830a9ad5f7	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	f56033f4-69a7-57dc-a5bd-a66944ecac34	4a5f4e0e-e447-519c-8f36-bb3d60802506	b703c0bd-0601-5342-a6bd-7eee5b24f28d	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	requested	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
f5c38f17-4c28-50b3-bc95-a128be000c91	SEED-LAX-24	dc5114d1-aa50-5995-a1ab-40223403a1a3	3352ba6a-3075-5c57-827c-aa6917c116a4	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	d6d8407e-4c7d-5fd7-a2ba-3660c3de1312	885312b8-41b5-5011-b4d6-948cffe99df2	3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	checked_in	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 18:00:00+00	\N	\N	\N	\N	60
c284dca7-557c-5e19-b7a1-3a373f8cc6c1	SEED-LAX-25	475e45e4-b6bc-57cf-a63d-5481a41eb665	cb708075-7755-5b10-b9b4-1a13de5f26c8	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	a512c728-7421-5f09-927c-6c742849e965	ed061c8d-b8b7-5356-813b-79b188f7a0ba	baada9ae-6167-533e-ad0d-1ee0e47ef254	2026-09-03 18:00:00+00	2026-09-03 19:00:00+00	in_progress	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 18:00:00+00	2026-09-03 18:10:00+00	2026-09-03 18:10:00+00	\N	\N	60
0c4c44f9-7438-5ede-a780-f8a0d3dbbcef	SEED-LAX-26	153416ff-4e01-5841-a7da-b205eea54021	598672b5-ddd8-558d-b476-b0cbd270d84e	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	ffc7415f-ac53-5a76-90f8-d1701ff9c8f4	f6e45079-dc94-52f1-a87f-fb82c82c6684	26ed90fd-20f8-511c-88e5-55f55772b50e	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	completed	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	2026-09-03 20:00:00+00	2026-09-03 20:00:00+00	60
6f5405e0-8f9f-5ddf-85b3-0a253bb19180	SEED-LAX-27	6b265c6e-a5e3-5139-be41-8852aa0fb916	b0dd34cf-637b-5591-b28d-f74efcf16c60	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	52e99567-b48a-50e7-b996-5f38fdc4706e	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	cancelled	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	2ad48f7a-7d9b-5503-a68d-07001e014841	Customer rescheduled	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	2026-09-03 18:00:00+00	\N	\N	\N	\N	\N	60
817b51f8-1b7b-50dc-97ba-9dafc2be9dc2	SEED-LAX-28	40f39805-a8b2-5fc6-a763-891ec56d488c	9bef2180-0313-5335-9637-31f3dbbcb9c7	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	328552e6-3212-5470-9d94-e75fe36eec6a	4a5f4e0e-e447-519c-8f36-bb3d60802506	3aabc2d5-d94e-5d21-a979-632c719fd85d	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	requested	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	\N	\N	\N	\N	\N	60
8e9e7fd7-904d-5242-9357-df8a2663f200	SEED-LAX-29	67d51689-68ff-545e-b892-7ff948f95b18	7f7beac8-8f93-5148-8fe1-c66d41346be3	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	d374adef-adf3-5b71-b525-a6c6262bf463	885312b8-41b5-5011-b4d6-948cffe99df2	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	checked_in	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 19:00:00+00	\N	\N	\N	\N	60
3c5d29ec-88b0-5f97-a6c7-5af942f91230	SEED-LAX-30	3e57c941-3d1b-501b-9d85-973c26c953d8	ed02ea69-eacf-5050-809a-64c251923424	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	1a7a8f85-7fd9-5d31-8247-fd5e7b7dd4b9	ed061c8d-b8b7-5356-813b-79b188f7a0ba	b703c0bd-0601-5342-a6bd-7eee5b24f28d	2026-09-03 19:00:00+00	2026-09-03 20:00:00+00	in_progress	Deterministic development fixture	2ad48f7a-7d9b-5503-a68d-07001e014841	\N	\N	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00	\N	2026-09-03 19:00:00+00	2026-09-03 19:10:00+00	2026-09-03 19:10:00+00	\N	\N	60
2b01e87d-1e6a-477b-a248-6703f9b07baa	APT-c6d66b87	80bf95ff-9973-508b-9e4c-4448d6979561	0f777184-c71e-5c20-95bf-3ddd073781a0	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	c3d8dbba-05fa-5785-9a04-5fbb17a80efa	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2118d041-b09a-541d-a9a8-034f86641286	2026-09-01 02:00:00+00	2026-09-01 04:00:00+00	requested	Manual API test	3b037fab-ef51-55de-abac-63d4f0242ed4	\N	\N	2026-08-30 10:24:33.824784+00	\N	2026-08-30 10:24:33.824784+00	\N	\N	\N	\N	\N	\N	120
965ccd4c-361d-436f-9e0d-15770bc3524b	APT-b3f3a59b	80bf95ff-9973-508b-9e4c-4448d6979561	0f777184-c71e-5c20-95bf-3ddd073781a0	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	c3d8dbba-05fa-5785-9a04-5fbb17a80efa	aab629e4-5965-5d14-a69f-e8d2db5df493	f924649c-3402-5659-b18a-385fdece1353	2026-09-01 02:00:00+00	2026-09-01 04:00:00+00	requested	Manual API test	3b037fab-ef51-55de-abac-63d4f0242ed4	\N	\N	2026-08-30 10:50:53.186967+00	\N	2026-08-30 10:50:53.186967+00	\N	\N	\N	\N	\N	\N	120
355cbc7b-4e80-4651-a8bb-98315b6db970	APT-0373e4fa	80bf95ff-9973-508b-9e4c-4448d6979561	0f777184-c71e-5c20-95bf-3ddd073781a0	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	c3d8dbba-05fa-5785-9a04-5fbb17a80efa	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2118d041-b09a-541d-a9a8-034f86641286	2026-09-16 02:00:00+00	2026-09-16 04:00:00+00	requested	Manual API test	3b037fab-ef51-55de-abac-63d4f0242ed4	\N	\N	2026-08-30 11:00:33.368694+00	\N	2026-08-30 11:00:33.368694+00	\N	\N	\N	\N	\N	\N	120
\.


--
-- Data for Name: bay_capabilities; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.bay_capabilities (bay_capability_id, code, name, description, created_at, updated_at) FROM stdin;
7b05332a-224f-51c4-b834-46796dee1ee4	general-lift	general-lift	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c3716ed3-5ddd-5ddd-903c-c17b888197bb	alignment-rack	alignment-rack	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
78643e8e-8d01-59cc-907a-018e0c39cd9b	tire-machine	tire-machine	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3bc2456c-1c0b-553e-a683-2b466ee28492	diagnostic-station	diagnostic-station	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
73f5b85c-3fdc-52e6-b359-8d4e8e076788	hvac-station	hvac-station	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	engine-hoist	engine-hoist	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2b6e1691-f6b9-5b93-a428-3a7b13f811b5	ev-isolation	ev-isolation	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	adas-target	adas-target	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f0d110be-a158-5792-aa40-15cb0aff4a0e	transmission-lift	transmission-lift	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5a556121-06b4-59f3-854a-0afb3544918f	wash-bay	wash-bay	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5116ec60-ab2c-5ff2-9f19-85abc53cd38c	brake-lathe	brake-lathe	\N	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: customer_dealerships; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.customer_dealerships (customer_id, dealership_id, created_at) FROM stdin;
80bf95ff-9973-508b-9e4c-4448d6979561	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
3a015a81-56c2-54c0-8cf4-11b84411a0ab	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
1affb879-d86f-57f4-b3c4-c85b191c8fc9	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
2e3822ad-e19a-5815-91f5-005547e08893	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
daf78796-8816-5ae3-b5b0-d327e03764d2	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
1be2026f-a49c-5ca7-805b-aa1de3a5f349	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
f948ab66-1616-5de0-ba37-7851129dfa44	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
6fcb75b2-5105-52b0-ba8e-b19767927261	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
e04ad513-ee6a-5dd8-8204-59a5ac538927	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
b155f7ca-0311-5ae2-9775-20a123db0d35	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
8ab22659-36a2-57c9-86f3-10cd9e0134ff	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
9a77a403-73c0-5634-bfe1-c67323ee601b	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
13f62a96-ac31-5ea6-98f0-e73edd54615d	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
a329fbb9-bf4b-58ca-b306-a030c02851f7	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
28ccf436-cbad-54e8-9eb8-7742302ee14e	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
4a2800af-46ff-51a1-b8fc-e1a248b97793	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
e8ecd6e0-e0fe-5722-a345-508e2e6c3b36	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
882cf7e7-9e39-56a2-a474-9f313bbf6097	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
068e4c89-6f3f-59fc-a41b-fdc12cdc78a2	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
dc5114d1-aa50-5995-a1ab-40223403a1a3	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
a9e5a060-3b39-5d45-85d4-de0566386b46	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
700519e2-3e29-5d26-84e0-9d9c08222d72	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
dc82f629-7f59-594f-8d92-0825a2037d75	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
8edcec2f-bcd6-5fb5-af4a-0a3aedef34dc	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
475e45e4-b6bc-57cf-a63d-5481a41eb665	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
078c70f3-9945-5317-b9cb-dbd70219dc4a	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
6532c83a-fb6f-517f-b6aa-aedbf45e9f58	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
bc529998-94f7-5058-96f3-836342680b21	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
e1fb0fec-3da5-596a-a7c3-21abc8151bf6	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
153416ff-4e01-5841-a7da-b205eea54021	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
95d210c0-b1d9-58b0-8aed-67b24c2646a9	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
c92c6a89-9abf-5c08-a177-bf51791d9f47	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
1fa6803d-2fa7-5eaa-b01a-d232998ded29	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
563e0739-240c-541f-8f4d-16bbc9d2a309	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
6b265c6e-a5e3-5139-be41-8852aa0fb916	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
2604f74a-6aff-598d-a9da-7974c77af22f	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
3612e1ca-d209-5f12-9949-ac32ce2b14af	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
76795c68-ca60-5f1a-b0de-b94e4b9e11d0	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
17892473-2b27-56d3-85b8-a199914fab70	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
40f39805-a8b2-5fc6-a763-891ec56d488c	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
972997c0-3a0d-54b3-a9cc-5adeeb22e21a	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
35e47ee2-9301-542b-ae19-ad79c69769a3	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
8af7208e-c589-5aa8-927e-c0755a06cf2b	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
f03fd9c6-4033-5ff3-aa27-357ef26d2381	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
67d51689-68ff-545e-b892-7ff948f95b18	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
da52fc8e-70a9-57a0-bcd8-a7ff2e7a1dbc	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
1aacd4d6-1678-5444-8b29-4cc9266cab79	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
0bb1989c-8a2d-505e-ac75-39e872811b87	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
6d1da64a-6fe0-5a49-b86c-bbbd2955dd63	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
3e57c941-3d1b-501b-9d85-973c26c953d8	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
84ad1483-9d1f-56cc-9a77-660c9b6e5949	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
2061498f-7daa-5e23-968f-dc57932dd828	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
e79213dc-09e6-5635-b5e0-77119b6dcb34	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
949c5a87-faf0-5aba-b569-0ddb9bc6f196	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
73c8ba36-5adf-5fd5-ae3b-b645f64770cc	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
629167db-2c5c-561f-ae16-eadec3f6edae	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
f526dd2b-f6a7-5741-b2e0-252e132ffb06	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
de0d38de-4cc8-59d0-92f4-d5b7983c3ad0	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
4ff52b83-4bfc-513b-858b-7ecedba09707	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
5ec6ad08-46dd-5b53-8491-ce236867513e	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
76842e11-6973-5d16-b55f-9fefb0e0fc31	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
d52a0827-374c-5e82-b5a5-06e93cfcb4a2	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
8c40de9f-e606-5edc-add8-b3ff331d0911	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
f8f9be2b-742e-5f0a-97e8-2ba58b6019ca	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
4fe40293-bce2-5e7c-aa9d-2b67f5072cfc	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
599b0901-cbe9-56cf-98bf-94becfa492d3	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
fa8615ff-9d25-5ed1-9953-cddb4f4f403b	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
edb5fa48-3fd1-5f7b-8392-67a66c888f59	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
40cbdddc-db06-58ce-bfc8-fe5515f183ae	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
fc67775d-f9e3-59f1-9b25-0bda20414e11	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
92b584ed-96fc-5bf4-9403-8e20585b2609	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
7a6e5c27-e66a-5a79-8b7e-7db17a201d72	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
3ed4c6d5-75d6-50da-a013-7a85716bb392	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
533b924a-6fb0-5c7e-a18f-91dfc7fcc23d	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
8f44d162-c9e2-565d-9c9e-30fa23a7b017	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
00cbef96-40fd-532e-9d9d-989eecc0243e	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
3d7248fc-9686-5392-a193-9bca6a05ef6f	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
22403b61-01f2-50f3-80f7-d93eeaaad21c	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
7ccbe661-de11-5483-8fd9-6990ea61b4bc	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
880a4007-7176-52cd-8662-bb85fc42b40f	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
11aa321e-ce72-5a0c-becb-16c5e5661a7f	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
6c2ffd98-cc7d-5a51-b4f4-485e184bd927	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
2b49d420-496b-59ba-9b6e-df5a807c747d	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
9286c839-94d7-5698-91f5-54e62832bf0f	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
a16bc619-6712-561b-94d3-36bbf476bacc	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
12e7f7fe-2240-5c8c-a8ea-de63b66542be	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
b17fb6f1-0973-59d2-962b-5e38be69f045	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
a95b55f0-c6a8-5e79-96e4-a16beb4c6e28	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
7b54ff2c-5266-5434-b636-2b7abe0472bd	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
9bc9d562-af93-57ef-b778-c9eab3baff32	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
a5363fc5-2a82-5462-bd3f-afd2d6cadbf1	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
9a0d85be-f559-5792-a2ca-9c1ebdba0e48	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
d40ba67b-e4cf-5007-a8a6-860ba130d5b6	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
6ac97c6d-0889-5cd5-b9ad-9daf67115e43	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
ecb3409c-39d8-5b3e-9805-ce476a1de18a	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
c429efbf-ee87-559c-8d13-059bdbdf0b96	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2026-08-01 00:00:00+00
79f3cded-94a7-53a6-89da-cea4b658d998	206c4a44-c525-5960-ad70-3a1e80f806e5	2026-08-01 00:00:00+00
0cf297dd-f807-58ae-855e-be1fe4fa3912	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2026-08-01 00:00:00+00
d0d32715-14ce-5fc1-9afa-4aa73a145ce1	e47567a4-a655-5f7a-93b2-75831525fff3	2026-08-01 00:00:00+00
8c4fe118-3953-5fff-a4cd-c0972e62cf8a	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2026-08-01 00:00:00+00
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.customers (customer_id, name, phone, email, created_at, updated_at) FROM stdin;
80bf95ff-9973-508b-9e4c-4448d6979561	Seed Customer 001	+15550000001	customer.001@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3a015a81-56c2-54c0-8cf4-11b84411a0ab	Seed Customer 002	+15550000002	customer.002@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1affb879-d86f-57f4-b3c4-c85b191c8fc9	Seed Customer 003	+15550000003	customer.003@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2e3822ad-e19a-5815-91f5-005547e08893	Seed Customer 004	+15550000004	customer.004@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
daf78796-8816-5ae3-b5b0-d327e03764d2	Seed Customer 005	+15550000005	customer.005@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1be2026f-a49c-5ca7-805b-aa1de3a5f349	Seed Customer 006	+15550000006	customer.006@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f948ab66-1616-5de0-ba37-7851129dfa44	Seed Customer 007	+15550000007	customer.007@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6fcb75b2-5105-52b0-ba8e-b19767927261	Seed Customer 008	+15550000008	customer.008@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e04ad513-ee6a-5dd8-8204-59a5ac538927	Seed Customer 009	+15550000009	customer.009@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b155f7ca-0311-5ae2-9775-20a123db0d35	Seed Customer 010	+15550000010	customer.010@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8ab22659-36a2-57c9-86f3-10cd9e0134ff	Seed Customer 011	+15550000011	customer.011@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9a77a403-73c0-5634-bfe1-c67323ee601b	Seed Customer 012	+15550000012	customer.012@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
13f62a96-ac31-5ea6-98f0-e73edd54615d	Seed Customer 013	+15550000013	customer.013@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a329fbb9-bf4b-58ca-b306-a030c02851f7	Seed Customer 014	+15550000014	customer.014@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
28ccf436-cbad-54e8-9eb8-7742302ee14e	Seed Customer 015	+15550000015	customer.015@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4a2800af-46ff-51a1-b8fc-e1a248b97793	Seed Customer 016	+15550000016	customer.016@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e8ecd6e0-e0fe-5722-a345-508e2e6c3b36	Seed Customer 017	+15550000017	customer.017@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
882cf7e7-9e39-56a2-a474-9f313bbf6097	Seed Customer 018	+15550000018	customer.018@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
068e4c89-6f3f-59fc-a41b-fdc12cdc78a2	Seed Customer 019	+15550000019	customer.019@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dc5114d1-aa50-5995-a1ab-40223403a1a3	Seed Customer 020	+15550000020	customer.020@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a9e5a060-3b39-5d45-85d4-de0566386b46	Seed Customer 021	+15550000021	customer.021@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
700519e2-3e29-5d26-84e0-9d9c08222d72	Seed Customer 022	+15550000022	customer.022@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dc82f629-7f59-594f-8d92-0825a2037d75	Seed Customer 023	+15550000023	customer.023@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8edcec2f-bcd6-5fb5-af4a-0a3aedef34dc	Seed Customer 024	+15550000024	customer.024@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
475e45e4-b6bc-57cf-a63d-5481a41eb665	Seed Customer 025	+15550000025	customer.025@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
078c70f3-9945-5317-b9cb-dbd70219dc4a	Seed Customer 026	+15550000026	customer.026@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6532c83a-fb6f-517f-b6aa-aedbf45e9f58	Seed Customer 027	+15550000027	customer.027@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bc529998-94f7-5058-96f3-836342680b21	Seed Customer 028	+15550000028	customer.028@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e1fb0fec-3da5-596a-a7c3-21abc8151bf6	Seed Customer 029	+15550000029	customer.029@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
153416ff-4e01-5841-a7da-b205eea54021	Seed Customer 030	+15550000030	customer.030@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
95d210c0-b1d9-58b0-8aed-67b24c2646a9	Seed Customer 031	+15550000031	customer.031@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c92c6a89-9abf-5c08-a177-bf51791d9f47	Seed Customer 032	+15550000032	customer.032@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1fa6803d-2fa7-5eaa-b01a-d232998ded29	Seed Customer 033	+15550000033	customer.033@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
563e0739-240c-541f-8f4d-16bbc9d2a309	Seed Customer 034	+15550000034	customer.034@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6b265c6e-a5e3-5139-be41-8852aa0fb916	Seed Customer 035	+15550000035	customer.035@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2604f74a-6aff-598d-a9da-7974c77af22f	Seed Customer 036	+15550000036	customer.036@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3612e1ca-d209-5f12-9949-ac32ce2b14af	Seed Customer 037	+15550000037	customer.037@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
76795c68-ca60-5f1a-b0de-b94e4b9e11d0	Seed Customer 038	+15550000038	customer.038@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
17892473-2b27-56d3-85b8-a199914fab70	Seed Customer 039	+15550000039	customer.039@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
40f39805-a8b2-5fc6-a763-891ec56d488c	Seed Customer 040	+15550000040	customer.040@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
972997c0-3a0d-54b3-a9cc-5adeeb22e21a	Seed Customer 041	+15550000041	customer.041@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
35e47ee2-9301-542b-ae19-ad79c69769a3	Seed Customer 042	+15550000042	customer.042@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8af7208e-c589-5aa8-927e-c0755a06cf2b	Seed Customer 043	+15550000043	customer.043@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f03fd9c6-4033-5ff3-aa27-357ef26d2381	Seed Customer 044	+15550000044	customer.044@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
67d51689-68ff-545e-b892-7ff948f95b18	Seed Customer 045	+15550000045	customer.045@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
da52fc8e-70a9-57a0-bcd8-a7ff2e7a1dbc	Seed Customer 046	+15550000046	customer.046@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1aacd4d6-1678-5444-8b29-4cc9266cab79	Seed Customer 047	+15550000047	customer.047@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0bb1989c-8a2d-505e-ac75-39e872811b87	Seed Customer 048	+15550000048	customer.048@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6d1da64a-6fe0-5a49-b86c-bbbd2955dd63	Seed Customer 049	+15550000049	customer.049@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3e57c941-3d1b-501b-9d85-973c26c953d8	Seed Customer 050	+15550000050	customer.050@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
84ad1483-9d1f-56cc-9a77-660c9b6e5949	Seed Customer 051	+15550000051	customer.051@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2061498f-7daa-5e23-968f-dc57932dd828	Seed Customer 052	+15550000052	customer.052@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e79213dc-09e6-5635-b5e0-77119b6dcb34	Seed Customer 053	+15550000053	customer.053@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
949c5a87-faf0-5aba-b569-0ddb9bc6f196	Seed Customer 054	+15550000054	customer.054@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
73c8ba36-5adf-5fd5-ae3b-b645f64770cc	Seed Customer 055	+15550000055	customer.055@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
629167db-2c5c-561f-ae16-eadec3f6edae	Seed Customer 056	+15550000056	customer.056@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f526dd2b-f6a7-5741-b2e0-252e132ffb06	Seed Customer 057	+15550000057	customer.057@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
de0d38de-4cc8-59d0-92f4-d5b7983c3ad0	Seed Customer 058	+15550000058	customer.058@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4ff52b83-4bfc-513b-858b-7ecedba09707	Seed Customer 059	+15550000059	customer.059@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5ec6ad08-46dd-5b53-8491-ce236867513e	Seed Customer 060	+15550000060	customer.060@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
76842e11-6973-5d16-b55f-9fefb0e0fc31	Seed Customer 061	+15550000061	customer.061@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d52a0827-374c-5e82-b5a5-06e93cfcb4a2	Seed Customer 062	+15550000062	customer.062@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8c40de9f-e606-5edc-add8-b3ff331d0911	Seed Customer 063	+15550000063	customer.063@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f8f9be2b-742e-5f0a-97e8-2ba58b6019ca	Seed Customer 064	+15550000064	customer.064@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4fe40293-bce2-5e7c-aa9d-2b67f5072cfc	Seed Customer 065	+15550000065	customer.065@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
599b0901-cbe9-56cf-98bf-94becfa492d3	Seed Customer 066	+15550000066	customer.066@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fa8615ff-9d25-5ed1-9953-cddb4f4f403b	Seed Customer 067	+15550000067	customer.067@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
edb5fa48-3fd1-5f7b-8392-67a66c888f59	Seed Customer 068	+15550000068	customer.068@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
40cbdddc-db06-58ce-bfc8-fe5515f183ae	Seed Customer 069	+15550000069	customer.069@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fc67775d-f9e3-59f1-9b25-0bda20414e11	Seed Customer 070	+15550000070	customer.070@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
92b584ed-96fc-5bf4-9403-8e20585b2609	Seed Customer 071	+15550000071	customer.071@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7a6e5c27-e66a-5a79-8b7e-7db17a201d72	Seed Customer 072	+15550000072	customer.072@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3ed4c6d5-75d6-50da-a013-7a85716bb392	Seed Customer 073	+15550000073	customer.073@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
533b924a-6fb0-5c7e-a18f-91dfc7fcc23d	Seed Customer 074	+15550000074	customer.074@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8f44d162-c9e2-565d-9c9e-30fa23a7b017	Seed Customer 075	+15550000075	customer.075@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
00cbef96-40fd-532e-9d9d-989eecc0243e	Seed Customer 076	+15550000076	customer.076@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3d7248fc-9686-5392-a193-9bca6a05ef6f	Seed Customer 077	+15550000077	customer.077@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
22403b61-01f2-50f3-80f7-d93eeaaad21c	Seed Customer 078	+15550000078	customer.078@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7ccbe661-de11-5483-8fd9-6990ea61b4bc	Seed Customer 079	+15550000079	customer.079@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
880a4007-7176-52cd-8662-bb85fc42b40f	Seed Customer 080	+15550000080	customer.080@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
11aa321e-ce72-5a0c-becb-16c5e5661a7f	Seed Customer 081	+15550000081	customer.081@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6c2ffd98-cc7d-5a51-b4f4-485e184bd927	Seed Customer 082	+15550000082	customer.082@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2b49d420-496b-59ba-9b6e-df5a807c747d	Seed Customer 083	+15550000083	customer.083@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9286c839-94d7-5698-91f5-54e62832bf0f	Seed Customer 084	+15550000084	customer.084@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a16bc619-6712-561b-94d3-36bbf476bacc	Seed Customer 085	+15550000085	customer.085@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
12e7f7fe-2240-5c8c-a8ea-de63b66542be	Seed Customer 086	+15550000086	customer.086@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b17fb6f1-0973-59d2-962b-5e38be69f045	Seed Customer 087	+15550000087	customer.087@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a95b55f0-c6a8-5e79-96e4-a16beb4c6e28	Seed Customer 088	+15550000088	customer.088@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7b54ff2c-5266-5434-b636-2b7abe0472bd	Seed Customer 089	+15550000089	customer.089@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9bc9d562-af93-57ef-b778-c9eab3baff32	Seed Customer 090	+15550000090	customer.090@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a5363fc5-2a82-5462-bd3f-afd2d6cadbf1	Seed Customer 091	+15550000091	customer.091@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9a0d85be-f559-5792-a2ca-9c1ebdba0e48	Seed Customer 092	+15550000092	customer.092@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d40ba67b-e4cf-5007-a8a6-860ba130d5b6	Seed Customer 093	+15550000093	customer.093@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6ac97c6d-0889-5cd5-b9ad-9daf67115e43	Seed Customer 094	+15550000094	customer.094@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ecb3409c-39d8-5b3e-9805-ce476a1de18a	Seed Customer 095	+15550000095	customer.095@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c429efbf-ee87-559c-8d13-059bdbdf0b96	Seed Customer 096	+15550000096	customer.096@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
79f3cded-94a7-53a6-89da-cea4b658d998	Seed Customer 097	+15550000097	customer.097@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0cf297dd-f807-58ae-855e-be1fe4fa3912	Seed Customer 098	+15550000098	customer.098@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d0d32715-14ce-5fc1-9afa-4aa73a145ce1	Seed Customer 099	+15550000099	customer.099@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8c4fe118-3953-5fff-a4cd-c0972e62cf8a	Seed Customer 100	+15550000100	customer.100@example.test	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: dealership_operation_time; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.dealership_operation_time (dealership_operation_time_id, dealership_id, day_of_week, opens_at, closes_at, created_at, updated_at) FROM stdin;
8fa938a9-b30d-56a6-b43b-bfa20af1a28c	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	1	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6fabd53a-62c1-52b4-a0ee-47baf1e612c3	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	2	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
af487530-a06d-5d0d-b7ff-f4a848a22cf3	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	3	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a026730d-7634-5e0e-b193-1bd635b94262	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	4	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3a956d3a-fe1b-561d-a885-8e126a7c1efe	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	5	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
63f73d4d-4186-58ba-a1ec-3f9a732164fc	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	6	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9269406c-6785-59b1-8a78-33c6ad213021	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	7	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
07595086-28bf-52e4-ad77-2fbadee5dc0c	206c4a44-c525-5960-ad70-3a1e80f806e5	1	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6750b4f8-f09f-5835-be3e-9524290e52db	206c4a44-c525-5960-ad70-3a1e80f806e5	2	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4609b251-e602-5473-be0b-11e1dd7a95f7	206c4a44-c525-5960-ad70-3a1e80f806e5	3	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2fd09a58-fa0a-5295-b61b-9a0fcb480205	206c4a44-c525-5960-ad70-3a1e80f806e5	4	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c38602ae-ce93-5317-b211-3c7dd1121e98	206c4a44-c525-5960-ad70-3a1e80f806e5	5	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d9a7dec5-8ac8-5c0d-8d2b-12e3b56710a2	206c4a44-c525-5960-ad70-3a1e80f806e5	6	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a7abf018-6d8f-57aa-8ec0-7f7039f0c412	206c4a44-c525-5960-ad70-3a1e80f806e5	7	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
80de7125-1d1c-514c-9811-764922e9267d	7022ed8e-d0bf-5f76-8c90-83d05b415fad	1	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
01ffc93b-0d52-55c1-801b-27a1f7edcf9b	7022ed8e-d0bf-5f76-8c90-83d05b415fad	2	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7f76292f-14f4-5da8-acdb-5fc61ec77703	7022ed8e-d0bf-5f76-8c90-83d05b415fad	3	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
76426eae-a43b-50c8-a625-95ed2fe9cfe9	7022ed8e-d0bf-5f76-8c90-83d05b415fad	4	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3ce97ca0-d05d-5bf5-ab94-9999061d1f88	7022ed8e-d0bf-5f76-8c90-83d05b415fad	5	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4c751a9a-d49d-5e5b-aff5-1f5a0409e11c	7022ed8e-d0bf-5f76-8c90-83d05b415fad	6	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e2ad6f96-11f0-52fb-a270-9cff90b16362	7022ed8e-d0bf-5f76-8c90-83d05b415fad	7	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
88420820-35b4-51be-9678-cb2116adcc58	e47567a4-a655-5f7a-93b2-75831525fff3	1	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ac8b917a-9ea1-5677-aa36-c4953298b6f0	e47567a4-a655-5f7a-93b2-75831525fff3	2	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a044bb70-40e6-51a8-8abd-711b01cccd4a	e47567a4-a655-5f7a-93b2-75831525fff3	3	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
648c9ed6-5974-5ead-ab08-5d8f2ec55caa	e47567a4-a655-5f7a-93b2-75831525fff3	4	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e60bbbd1-5bb1-518b-8adf-6366405ca671	e47567a4-a655-5f7a-93b2-75831525fff3	5	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
80055569-60bd-5ea9-abe9-69373640ad29	e47567a4-a655-5f7a-93b2-75831525fff3	6	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
554a0e0e-2db5-5f11-8750-27a2a3ed7ee6	e47567a4-a655-5f7a-93b2-75831525fff3	7	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3794bcd8-c012-5ea6-83b9-c4bcd3c5afc0	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	1	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
333eb5fb-56c4-5cc6-8f20-f5afaf597843	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	2	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2d7a5096-bcc9-5bb8-8fb0-930cffc17c1e	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	3	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f18d7aa3-6620-59f2-bcdb-fa6d592cb5e1	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	4	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cd7f3328-36be-57b9-9feb-8a1508d6aa82	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	5	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1e8c8af5-2b61-513f-8b72-6cdca86acfbb	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	6	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
10afea70-6a13-5fb1-acae-f9e77631969b	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	7	06:00:00	23:00:00	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: dealerships; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.dealerships (dealership_id, name, code, address, timezone, is_active, created_at, deleted_at, updated_at) FROM stdin;
c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Ho Chi Minh Motors	HCM	1 Nguyen Hue, Ho Chi Minh City	Asia/Ho_Chi_Minh	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
206c4a44-c525-5960-ad70-3a1e80f806e5	Tokyo Motors	TYO	1-1 Marunouchi, Tokyo	Asia/Tokyo	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7022ed8e-d0bf-5f76-8c90-83d05b415fad	Sydney Motors	SYD	1 George Street, Sydney	Australia/Sydney	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e47567a4-a655-5f7a-93b2-75831525fff3	London Motors	LDN	1 Piccadilly, London	Europe/London	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Los Angeles Motors	LAX	1 Sunset Boulevard, Los Angeles	America/Los_Angeles	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.roles (role_id, code, name, description, created_at, deleted_at, updated_at) FROM stdin;
00000000-0000-4000-8000-000000000001	admin	Admin	Full dealership configuration; creates users and technicians; manages all resources and schedules.	2026-08-29 10:42:52.627325+00	\N	2026-08-29 10:42:52.627325+00
00000000-0000-4000-8000-000000000002	staff	Staff	Manages technician shifts, time off, and permitted technician details.	2026-08-29 10:42:52.627325+00	\N	2026-08-29 10:42:52.627325+00
00000000-0000-4000-8000-000000000003	dealer	Dealer	Creates customers and vehicles; searches availability; creates and manages appointments.	2026-08-29 10:42:52.627325+00	\N	2026-08-29 10:42:52.627325+00
00000000-0000-4000-8000-000000000004	technician	Technician	Manages customers and vehicles for their dealership.	2026-08-29 10:42:52.627325+00	\N	2026-08-29 10:42:52.627325+00
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.schema_migrations (version, dirty) FROM stdin;
1	f
\.


--
-- Data for Name: service_bay_capabilities; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.service_bay_capabilities (service_bay_capability_id, service_bay_id, bay_capability_id, created_at, updated_at) FROM stdin;
2539c27c-39fd-5f98-b6e7-d9019185f732	2118d041-b09a-541d-a9a8-034f86641286	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3fbdd49b-04d9-568c-a6b6-f2a6632c090a	2118d041-b09a-541d-a9a8-034f86641286	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c75edcfb-9669-57f6-a5af-e5a4fe9ed2cd	2118d041-b09a-541d-a9a8-034f86641286	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
84b9c7f1-9ed7-5276-b7ed-7176bc7b7413	2118d041-b09a-541d-a9a8-034f86641286	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f79057c4-5bfa-5e51-ac87-18adfcf526e2	2118d041-b09a-541d-a9a8-034f86641286	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e978a622-bb59-582a-829e-e7648f90a3ea	2118d041-b09a-541d-a9a8-034f86641286	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3e83adcf-722b-577f-9caf-1e4de5ef5303	2118d041-b09a-541d-a9a8-034f86641286	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1b39dcf5-12ca-5ab2-932a-0c682b370a83	2118d041-b09a-541d-a9a8-034f86641286	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
550d0037-415f-5872-ae9c-bab3a8b79fa0	2118d041-b09a-541d-a9a8-034f86641286	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a58441d6-a7e7-541f-ac74-185615ebf936	2118d041-b09a-541d-a9a8-034f86641286	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cb10f401-8cdf-5f6c-b777-1f7d763a8325	2118d041-b09a-541d-a9a8-034f86641286	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
541f3b29-ab3b-5729-b1cc-35714b495227	619ea9fa-4c9d-506e-8838-5f527f5223c2	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
14b906c9-4209-5e86-9f1e-2b3ac4c2026e	619ea9fa-4c9d-506e-8838-5f527f5223c2	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0cf58b1c-4370-52b1-a270-64541fdbe793	0a1fae29-1e5b-5efc-b8a9-0887d4c25610	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4c93a260-799b-51ab-a31e-59b5c2924721	0a1fae29-1e5b-5efc-b8a9-0887d4c25610	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
15149b30-76cf-53fa-b70c-cbc0f16394a1	ff440016-8cdc-5773-a81e-2a040283208b	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1511558b-7051-5000-875d-15be6c981b3e	ff440016-8cdc-5773-a81e-2a040283208b	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5187b08a-3a11-53ca-a61e-ff8d16a0890d	f924649c-3402-5659-b18a-385fdece1353	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ef07f162-df3e-5a6b-ab5d-f09ba26b5907	42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b5449647-d148-5fca-b721-91ba7541be21	ecf7be60-2540-5e7d-88f8-99cec4954edb	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c8e54795-d85f-52b1-a899-99c7ec39d74c	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e9076992-ab7c-5da2-8e0c-089bc614b934	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d2188581-904c-50cd-b8c7-2349b60648fd	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d2612627-0207-5dd4-94ff-d7da2127c195	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3d9ca986-d99f-5f3f-828f-7a0984fb3fe7	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
42525002-d34e-532e-acea-069ad4ef947a	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d18dcc3a-7348-589f-b427-b79b634c9097	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b21e848f-ac24-5ee0-baac-aefd6515aa7f	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
eb51f616-cada-56a4-be48-6d27248c1453	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5b2aa939-e100-5731-b0a7-09811bcb243b	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e0c9a4e3-3c69-5f41-b8bd-a61c73f5b797	f4b26ea6-29d4-57c6-8846-8e31fc27acd1	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
17fd58d4-16bb-57c6-b5b3-7fc74ff7234c	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
344ecb3a-45e3-5301-aa3f-33ee15fda98d	ce6496d8-6412-50b6-8cf9-9f675e39b0ad	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9cc6f939-c535-58b4-9d85-191170af1be0	94e41d7e-908c-5e90-b8a2-410674183b28	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b67db98f-371b-57ce-a2b4-f52817ce0975	94e41d7e-908c-5e90-b8a2-410674183b28	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c1d4dff4-e365-5bb2-9482-01ca8ed34d3e	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
99ea856f-bd8b-54fd-b9b1-619256c07c80	a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3657440e-b1d6-58c3-b9b1-05b47e487b68	dcd21ca1-995a-51e7-b954-60af0e35b8ac	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
042b307d-b99b-5e30-a1c3-774effb7cfb2	42eff788-5be8-5f54-afb7-7c14606599ea	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b70c36ef-0288-5973-800c-7da9af66a601	2e370881-86bf-59de-b2ed-82dfad8bf5dd	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
88f3370f-784e-54b9-8641-75d87263849d	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6078d8af-5f92-585d-8baa-2f748a77aa27	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a4b1aa94-1e30-5f5c-a89f-d9335e26b8e9	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bdcf93c1-f431-5ae4-b7a5-6bf50d82a2c5	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
71f11fdc-d3c3-5a30-ba8e-ca5845876643	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fe1659ae-93e7-5290-b004-dda2e9787f05	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8cb2218b-c159-5544-8771-3fcd62e40d27	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c6047339-275f-5ae9-aa53-0c354382ccda	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e6427f32-561b-5d47-8b76-cdbc1a5b2f96	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
99de26c6-0f6e-503a-8b2b-ae085ea52e53	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5f99a249-4f54-5d20-aee8-9c59bf34ebda	38fc9fec-72d9-5bb4-9821-90d2701ce1ff	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7f7e63f9-f082-577b-9f3b-d0580e5b3c31	9df77ddf-fe56-5e6f-8979-9b70e064d232	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5e892faf-f70a-5ff5-8859-752b60f6d543	9df77ddf-fe56-5e6f-8979-9b70e064d232	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4a003f3b-b74e-53d1-acba-9543bf0884e8	2e5bd34a-e96d-50b1-89e7-4ced572bdad6	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
159a76aa-8667-5de1-8767-12cfcaf3a57b	2e5bd34a-e96d-50b1-89e7-4ced572bdad6	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ebe88eff-75f1-5efb-80c4-dd375f601f99	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c9015127-a1c4-5b0c-83a6-70a3475f867b	953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
075ece96-0890-533a-accd-fb7e1399e60a	42ce9d61-5263-5784-b0c8-984b6bf6aaae	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
91e16f65-740c-57bd-90e3-d14332475eaf	8806d3d9-7c39-511e-ab4d-8ac2880f513f	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4afcd587-345a-5138-8e80-8e4e31197ab3	432195c4-02e8-5310-b2a3-30ac3819e62b	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a0986409-310b-5063-8cb8-d08178cad6ac	5e5a9255-4d04-5b10-8aa1-f0e068df678e	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4a97d8dd-8c9d-5579-b7ce-59555443fbbe	5e5a9255-4d04-5b10-8aa1-f0e068df678e	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7a9d6c4e-d68a-51d5-b743-f85ce9d77653	5e5a9255-4d04-5b10-8aa1-f0e068df678e	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ea519e0f-42d0-5984-9b01-cbef336b397d	5e5a9255-4d04-5b10-8aa1-f0e068df678e	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
92abc585-1711-528e-b2c9-71d3a626f810	5e5a9255-4d04-5b10-8aa1-f0e068df678e	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6ecd68c8-d256-519d-ae5f-10f90fe88528	5e5a9255-4d04-5b10-8aa1-f0e068df678e	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
caaa958c-7719-5fff-872a-2bb8c6c3bd7c	5e5a9255-4d04-5b10-8aa1-f0e068df678e	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b557cbd0-b2c0-5e1d-8010-645de29e3885	5e5a9255-4d04-5b10-8aa1-f0e068df678e	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
56d73300-4964-5e9a-95c4-167408db17bb	5e5a9255-4d04-5b10-8aa1-f0e068df678e	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
876ac233-cda6-5a21-903f-f191166e4a86	5e5a9255-4d04-5b10-8aa1-f0e068df678e	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e7ff9ea4-9eef-57e0-8cef-859254cb55ef	5e5a9255-4d04-5b10-8aa1-f0e068df678e	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7d9572df-d8b7-59c9-81d8-ef3e3f352c4a	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cc6f4605-d019-5eba-9fae-a842dd43e1ea	42c2b95f-acc1-5694-a4ef-d54d21fb25bd	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
01fc3b79-ab79-5a93-80b2-76be4209e81e	d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bf533473-50c3-543c-b7e2-c48bc8fa207a	d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
43a8e281-5017-5b22-9470-e26d5578566f	f98cc283-b3ce-5c13-82b5-5b343ed52d21	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
67b38e1c-790a-5ee0-9729-e2d40fc8a863	f98cc283-b3ce-5c13-82b5-5b343ed52d21	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a4719ce2-d4a0-55d4-880c-43af234eb647	f3436b53-3c8c-5302-afa3-904ea008c446	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e2db1fe7-af4f-53a3-9160-f0245581fc25	16bdd951-987c-5321-89b3-3dda5dacaec1	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fd036d96-23e2-5b3b-8dca-77cc0c389b14	b37e9c5c-c4a9-5353-9763-72254c50c4c5	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f5e7202e-4c5c-5b24-a3ad-364a55be78c1	e95ee836-4dc5-5f09-a22b-1a8afb79b096	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fe082b0c-7138-5afe-a7fb-9134e3ee3c63	e95ee836-4dc5-5f09-a22b-1a8afb79b096	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f374f754-5f4a-5dda-9d64-26005b044474	e95ee836-4dc5-5f09-a22b-1a8afb79b096	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4e6573eb-5141-50a2-bada-f6a736364147	e95ee836-4dc5-5f09-a22b-1a8afb79b096	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dc4b7fb3-6c7a-5a06-b825-7be96ef834e8	e95ee836-4dc5-5f09-a22b-1a8afb79b096	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8a4fc6bd-58d7-5bb5-9c15-f668581d7975	e95ee836-4dc5-5f09-a22b-1a8afb79b096	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
253aca9c-51e9-55f7-bb3f-23017b642a3e	e95ee836-4dc5-5f09-a22b-1a8afb79b096	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
65d0ff93-217f-5877-8b2d-4e8ef7314d47	e95ee836-4dc5-5f09-a22b-1a8afb79b096	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
57fd906b-c855-526f-8100-1b478835372f	e95ee836-4dc5-5f09-a22b-1a8afb79b096	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
812b2489-14e2-50ba-9444-e740e0a4a6c2	e95ee836-4dc5-5f09-a22b-1a8afb79b096	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
84fee30f-62e5-53b0-9aef-30f4d8f657f5	e95ee836-4dc5-5f09-a22b-1a8afb79b096	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d6aefdb2-801b-5c58-9439-98570dad8161	b703c0bd-0601-5342-a6bd-7eee5b24f28d	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bdcc60e8-949e-5860-9aa0-d40d3a072fed	b703c0bd-0601-5342-a6bd-7eee5b24f28d	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
53ed4238-6c5d-5f81-b276-e72cf10973ca	3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9a15b7ac-c2d5-55a4-9401-4a66a495cafe	3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ddedee99-8fd5-5290-a89f-88eec44bc8d2	baada9ae-6167-533e-ad0d-1ee0e47ef254	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
29a84ddf-565f-5bf7-b9a0-475592d91d77	baada9ae-6167-533e-ad0d-1ee0e47ef254	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
19346fff-45f2-5f2e-a246-d13b75d79b2f	26ed90fd-20f8-511c-88e5-55f55772b50e	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
76ae0ef5-bcfd-5a61-9005-8c06e1dfe936	0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e7570954-adb2-5634-b67b-22e86979273a	3aabc2d5-d94e-5d21-a979-632c719fd85d	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: service_bays; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.service_bays (service_bay_id, dealership_id, code, name, is_active, created_at, deleted_at, updated_at) FROM stdin;
2118d041-b09a-541d-a9a8-034f86641286	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	B01	Service bay 1	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
619ea9fa-4c9d-506e-8838-5f527f5223c2	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	B02	Service bay 2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0a1fae29-1e5b-5efc-b8a9-0887d4c25610	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	B03	Service bay 3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ff440016-8cdc-5773-a81e-2a040283208b	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	B04	Service bay 4	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f924649c-3402-5659-b18a-385fdece1353	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	B05	Service bay 5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
42b21eb2-0c7a-5315-a15f-2cc6fc78e83c	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	B06	Service bay 6	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ecf7be60-2540-5e7d-88f8-99cec4954edb	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	B07	Service bay 7	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f4b26ea6-29d4-57c6-8846-8e31fc27acd1	206c4a44-c525-5960-ad70-3a1e80f806e5	B01	Service bay 1	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ce6496d8-6412-50b6-8cf9-9f675e39b0ad	206c4a44-c525-5960-ad70-3a1e80f806e5	B02	Service bay 2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
94e41d7e-908c-5e90-b8a2-410674183b28	206c4a44-c525-5960-ad70-3a1e80f806e5	B03	Service bay 3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a271c9e0-39f9-5a8b-90e9-ba08bf0c0b88	206c4a44-c525-5960-ad70-3a1e80f806e5	B04	Service bay 4	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
dcd21ca1-995a-51e7-b954-60af0e35b8ac	206c4a44-c525-5960-ad70-3a1e80f806e5	B05	Service bay 5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
42eff788-5be8-5f54-afb7-7c14606599ea	206c4a44-c525-5960-ad70-3a1e80f806e5	B06	Service bay 6	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2e370881-86bf-59de-b2ed-82dfad8bf5dd	206c4a44-c525-5960-ad70-3a1e80f806e5	B07	Service bay 7	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
38fc9fec-72d9-5bb4-9821-90d2701ce1ff	7022ed8e-d0bf-5f76-8c90-83d05b415fad	B01	Service bay 1	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9df77ddf-fe56-5e6f-8979-9b70e064d232	7022ed8e-d0bf-5f76-8c90-83d05b415fad	B02	Service bay 2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2e5bd34a-e96d-50b1-89e7-4ced572bdad6	7022ed8e-d0bf-5f76-8c90-83d05b415fad	B03	Service bay 3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
953db9f5-b99d-5c64-ad5d-5f0d6876c4bf	7022ed8e-d0bf-5f76-8c90-83d05b415fad	B04	Service bay 4	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
42ce9d61-5263-5784-b0c8-984b6bf6aaae	7022ed8e-d0bf-5f76-8c90-83d05b415fad	B05	Service bay 5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8806d3d9-7c39-511e-ab4d-8ac2880f513f	7022ed8e-d0bf-5f76-8c90-83d05b415fad	B06	Service bay 6	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
432195c4-02e8-5310-b2a3-30ac3819e62b	7022ed8e-d0bf-5f76-8c90-83d05b415fad	B07	Service bay 7	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5e5a9255-4d04-5b10-8aa1-f0e068df678e	e47567a4-a655-5f7a-93b2-75831525fff3	B01	Service bay 1	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
42c2b95f-acc1-5694-a4ef-d54d21fb25bd	e47567a4-a655-5f7a-93b2-75831525fff3	B02	Service bay 2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d3e0fa7b-03ab-58ed-8c4a-7edea3ae6420	e47567a4-a655-5f7a-93b2-75831525fff3	B03	Service bay 3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f98cc283-b3ce-5c13-82b5-5b343ed52d21	e47567a4-a655-5f7a-93b2-75831525fff3	B04	Service bay 4	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f3436b53-3c8c-5302-afa3-904ea008c446	e47567a4-a655-5f7a-93b2-75831525fff3	B05	Service bay 5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
16bdd951-987c-5321-89b3-3dda5dacaec1	e47567a4-a655-5f7a-93b2-75831525fff3	B06	Service bay 6	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b37e9c5c-c4a9-5353-9763-72254c50c4c5	e47567a4-a655-5f7a-93b2-75831525fff3	B07	Service bay 7	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e95ee836-4dc5-5f09-a22b-1a8afb79b096	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	B01	Service bay 1	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b703c0bd-0601-5342-a6bd-7eee5b24f28d	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	B02	Service bay 2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3f1ef812-c217-5b2e-ad8f-2f5a90d6f327	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	B03	Service bay 3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
baada9ae-6167-533e-ad0d-1ee0e47ef254	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	B04	Service bay 4	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
26ed90fd-20f8-511c-88e5-55f55772b50e	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	B05	Service bay 5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0ecc4a49-8d3c-5bcb-a95b-80ac3bae9226	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	B06	Service bay 6	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3aabc2d5-d94e-5d21-a979-632c719fd85d	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	B07	Service bay 7	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
\.


--
-- Data for Name: service_type_required_bay_capabilities; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.service_type_required_bay_capabilities (service_type_required_bay_capability_id, service_type_id, bay_capability_id, created_at, updated_at) FROM stdin;
e0406900-1fa5-5afe-9721-674cdfe40b2b	ff658fc4-1dd0-5cca-b436-d138e9e5832a	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5a2ed817-0bc0-5f5c-8873-5ac2b54834e3	40e31547-ef9d-5f42-8fe4-acdb10affee0	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f7e0f742-ac23-533a-b7e2-ce1eaf21a845	47e2a50d-3111-5d97-87d1-c6f9b865cdf4	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b50717a3-6552-542b-86e4-9d20f2e6f435	1df02326-4e85-579f-b58f-64e4cd71b5a7	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
823ee010-166d-5aed-b50f-e69740c7ffcb	8a8a8dcb-c515-5c94-9b15-411fa5d3af78	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7113ce2a-c26e-559b-8032-e950a0b097f8	c3d8dbba-05fa-5785-9a04-5fbb17a80efa	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
96f7836d-e35c-5165-b539-f3171d8b2c16	35dd4ceb-6a3a-569e-a49c-6ead26a5ac52	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ffbce0ba-39a7-5174-b087-4214719c51a6	f8ea6f15-8a21-57c2-97ee-7b5dd0638443	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c02189e5-6907-5464-9d05-9fe95eeaf50d	07c9fc2e-90ba-56af-88c9-01726b22ef20	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2a5a660d-79ee-5f8a-8092-27e01f676558	0e5f7e9e-e60a-5b1b-b9ff-b0f318a4af8b	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
588b9aa0-f3a6-5f53-af76-79eee7b4e33d	2c198c84-2406-5891-a2b7-ded50a876ed9	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bc6ac3a0-9d38-5eda-bf71-68975f327a95	9044baac-541e-54c9-9968-db1caa46c3b8	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
89144462-5fa2-5d8b-be0c-84ef9492fde8	1407c88c-49bb-55d3-8b37-e58b7ad90b4a	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
394595be-a872-52e9-b7ac-cd124436915f	dbf26c41-98f9-5731-b0e1-291f23811d1d	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6bb9c855-5209-57d8-a531-515031219c7f	1e1aa59c-28cc-5938-810a-49ace5798ac8	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
03925ad8-e4b1-5ec5-97c4-0640d594f2f1	f120f0da-0b7d-5d61-93b3-9fad0d9f3ca8	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
276e302b-b8d9-582d-bfc8-15681d9a9c53	3f1ebf87-e782-5c39-b5e4-983bed1ba676	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
66a7c363-6f60-57ae-9cc1-14b287baf13b	bf648c3f-bf11-5f41-8bd8-a9320a331d2f	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
44ca0d66-e2db-5bcf-bf61-3c95cd545d55	1ca5b7cc-9956-5a6f-9f50-4a8afac6f4f9	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1ccbc6ac-a7cd-5697-93f1-e7e43081009a	e95d8421-11e7-553f-8fcd-448084f10d14	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8d2e2b57-3e91-5c14-b88a-1d4fdf69f21a	654e08cd-8bdb-5f5b-b464-fc687b217883	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
49e5b2e2-2b0b-54b9-a016-8a9642290787	c817a967-78ec-5dc5-ad90-55b61f5db704	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2dac4288-f2a4-558c-bbc5-637670f9ef2f	c13171bb-2178-5cbe-a8ae-9906af5b92b8	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1b20725c-1baa-5362-80d8-c0438b26912c	5b31e150-ec54-553e-9f11-4a95aa7e9ae9	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3ffa10f3-5d6f-5c03-b717-2ab22a903381	03cdcb00-c17b-56c3-9134-150bffd9d9b3	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3f81df96-2725-5372-b98b-d7e404b44d7e	b9b9f90e-0ff3-5f7a-9bd6-66f15b26f5b9	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0cd51825-dd02-54ee-b442-d462a697f928	eb7dcc4f-ab33-593e-b814-0c41ee9ff713	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d300cb7f-f07d-54ad-98d1-60b45fb14225	8f63bfdd-4205-5c3c-b82b-a818f235ec0e	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6dcb47bc-281f-500e-bbcd-4ddbc507fc41	c7366e56-c082-529c-bbe1-1ebdb9f3894b	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ea31f25f-49da-585b-a6a3-fa5c0670b4a5	6ed744c8-ea85-58bc-9be4-0056f6ab3c6f	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3850151e-651a-5015-b43b-ec21c4fb4867	4cff6571-1f04-58fc-8098-c3c36144c111	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
25ff8adb-0f38-5476-833a-bd911270710b	786869e2-e980-55c3-b53d-2185a3422ea7	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f313e8ad-60a0-5a72-a611-039f8f805040	d67ce61e-d7d5-5ace-9cea-e27505455b9e	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3836b8c1-5691-59f0-8631-eb9c24b4002a	85fdbd48-c635-5eb6-b7e6-b19233d01410	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e9111970-1206-5634-aa65-7c5ce1f7d36f	883fb935-5e66-5ce6-a5dc-ac527f31c8a7	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f427b0a2-45b0-5ec6-b301-c36f166489c3	f9c95f62-48bd-53ed-b5bd-3a88d6aebd65	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
95da6262-03e3-5df5-a443-aff03f601f79	181b685e-e58b-5599-99c7-bb5eab8c8a53	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1a9f9f39-5ac0-50bf-9d2a-5bca5366f0b5	80b9bf14-43e6-52c3-a237-d1afa8031bab	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
43c8661f-7adb-5ea2-ad19-844968ae596b	737ee088-dc99-5ea3-adb3-d2305ce19c5a	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
51537225-abad-5db3-93d3-0f2e00fd8722	eaa1aa5e-613c-5c1d-8915-b8b57b8f29e3	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9890acec-72df-5ed2-ac43-1688757911a8	241d6f87-d07a-5e17-b773-4eb7470f146f	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
858cc1d6-43db-5f20-8a7a-d645ddfc353d	04c18d67-1c66-5d02-a797-f03f8d94a1e9	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f2b2df8c-d86e-5677-bc01-5a56fc3776f1	22ef464c-18b0-5cfa-b612-adedbf8f4f44	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4faa2b91-94b1-5376-9b17-b51972537f9d	187c196a-5662-5427-8324-702ae75a80d8	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
97f74753-4017-56d1-be21-68e8cc998e3e	2c40bc38-b50f-59ed-913b-7fe27db0907f	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8c5705a4-bee0-531b-9096-6ac9eee5391f	64d7a9c8-2455-547e-ba40-99bb8893a8a9	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
786a8b89-da6c-57a0-ad0c-e1b772373c9f	fc30bc18-cadc-5e1d-9f5c-2a85fcd5fc0b	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1b072333-7252-5956-8bf2-a6f07b683537	17e7df9e-3462-5f29-96e4-d78a710aba4a	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
afb7a3c7-4bda-5e49-97bc-5809fa19828a	ff9a4d7e-bb4e-54f8-ac15-0ae6ec2d9d09	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4cf3820e-53cf-56ec-abfb-fac61d519719	cfe112ca-e18a-5125-bdec-ad756c242104	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
affb7178-7fc2-5b9e-a5f4-54d96308d68a	095bf04c-ae81-5f7f-bc46-5fb6ba832410	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9bdb4aaf-0a7d-5bc5-b780-85f2dc5903eb	358ed023-5145-5788-aa33-162d23201a8c	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f3381899-1342-59a6-96e4-dfe652580f2b	72e9238b-b758-5b8a-9cec-4de23ea6ee05	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ca492e31-ecec-53cf-af1f-c44849a014f7	e777d567-9057-5874-9c0b-f31166ebe27f	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4a0b48de-2a27-58d7-a71a-077428adbce8	72d0a511-17f7-50f1-b31f-827269bfcdf9	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
195f8ba8-04a3-58e6-be4d-4b6c11be44f6	9d3532cf-7d8d-5315-80d5-ab0fc5494335	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
732cf661-8741-5016-a177-e1489fcc5a74	d374adef-adf3-5b71-b525-a6c6262bf463	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
74c487df-1932-50e1-b69c-c0ceb3c38dbf	1a7a8f85-7fd9-5d31-8247-fd5e7b7dd4b9	78643e8e-8d01-59cc-907a-018e0c39cd9b	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f58bec41-fdde-51a3-b6fb-61014d8cc3e7	786c9846-b6c6-58fa-8635-787a18701ee3	5116ec60-ab2c-5ff2-9f19-85abc53cd38c	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6981f1c9-2372-5369-a830-a636df9fc4b5	5e928f28-f117-520a-9649-833d16276213	c3716ed3-5ddd-5ddd-903c-c17b888197bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c7c392f7-aac9-522f-9095-e4e42ab0fd59	46120ad3-1942-522e-84f3-3761e21d9047	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
56e3834b-1641-5568-a066-23671c57d975	040a1aa0-177a-5154-a4c8-2853a5ac97e1	73f5b85c-3fdc-52e6-b359-8d4e8e076788	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7e54e60d-ac72-535a-9dac-16dc52a04a5a	d8ec1c58-f79d-5680-9ee7-0453e2b3984b	d54c2ebb-f7bb-515a-bc7c-807bf100b0bc	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
100208a0-7f96-5575-bb72-0f881932024f	334b3b9e-8bca-53f3-bf7f-272e889fb410	2b6e1691-f6b9-5b93-a428-3a7b13f811b5	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7f3f3c33-7530-5dca-9c82-0dfa8ea75809	f56033f4-69a7-57dc-a5bd-a66944ecac34	1ef5d587-aa9d-5924-a60f-b5da8c3f28f4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5ea5ed02-9714-5780-b060-d984a060e6cf	d6d8407e-4c7d-5fd7-a2ba-3660c3de1312	f0d110be-a158-5792-aa40-15cb0aff4a0e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
883bdef0-1dcb-550e-9d80-15d6057b6446	a512c728-7421-5f09-927c-6c742849e965	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
04961c07-2eec-53df-9dd3-5e29bb235f2c	ffc7415f-ac53-5a76-90f8-d1701ff9c8f4	5a556121-06b4-59f3-854a-0afb3544918f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b0cc46d1-163c-5fb1-bf33-73e114a4a763	52e99567-b48a-50e7-b996-5f38fdc4706e	3bc2456c-1c0b-553e-a683-2b466ee28492	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
906035d9-c8a2-50c1-a3ed-51fbdb24b370	328552e6-3212-5470-9d94-e75fe36eec6a	7b05332a-224f-51c4-b834-46796dee1ee4	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: service_type_required_skills; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.service_type_required_skills (service_type_required_skill_id, service_type_id, skill_id, created_at, updated_at) FROM stdin;
315c1c0f-2871-5ff5-a6cf-0f5c4904d55d	ff658fc4-1dd0-5cca-b436-d138e9e5832a	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b46b34e3-f62b-5791-9547-5f13cf8be659	40e31547-ef9d-5f42-8fe4-acdb10affee0	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f0c677e2-d2d7-5768-be8c-de2e40be25c4	47e2a50d-3111-5d97-87d1-c6f9b865cdf4	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c935f095-1e2e-581d-af16-5908f4453f89	1df02326-4e85-579f-b58f-64e4cd71b5a7	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1810368a-1d13-5551-b010-5033ac4b4dee	8a8a8dcb-c515-5c94-9b15-411fa5d3af78	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4b6f138b-fca9-5d05-a01e-86a881250299	c3d8dbba-05fa-5785-9a04-5fbb17a80efa	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f1110616-66e5-5518-a947-fa5cb7332dbf	35dd4ceb-6a3a-569e-a49c-6ead26a5ac52	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b6aeeaa6-c861-515e-812b-841dc6042bf4	f8ea6f15-8a21-57c2-97ee-7b5dd0638443	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
00155c45-d8cb-5117-ab10-e2eb59abdb18	07c9fc2e-90ba-56af-88c9-01726b22ef20	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8c1811cd-780b-5048-930e-e4dd1f3ad40c	0e5f7e9e-e60a-5b1b-b9ff-b0f318a4af8b	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e091e2a9-28b2-54b0-b990-fcc0570df84f	2c198c84-2406-5891-a2b7-ded50a876ed9	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f0575bac-f8e9-5a6f-abe6-b5f2b74b9166	9044baac-541e-54c9-9968-db1caa46c3b8	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
537d2b24-d526-51eb-8a1a-7dcf1578fa22	1407c88c-49bb-55d3-8b37-e58b7ad90b4a	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dc314957-f2b0-5c9a-b865-ed0b0231482c	dbf26c41-98f9-5731-b0e1-291f23811d1d	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
19b63bfb-98ca-5b5a-938c-e308570d4c8c	1e1aa59c-28cc-5938-810a-49ace5798ac8	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d31cb074-a18d-50c5-8f05-265bd6eeefa5	f120f0da-0b7d-5d61-93b3-9fad0d9f3ca8	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5d0d36ef-f1d9-5b9d-8ab9-e9470d3d56a6	3f1ebf87-e782-5c39-b5e4-983bed1ba676	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a20a7012-47c0-5358-92ed-f8744b2d97b5	bf648c3f-bf11-5f41-8bd8-a9320a331d2f	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7705e3cd-b109-522a-b937-fd545e00cee8	1ca5b7cc-9956-5a6f-9f50-4a8afac6f4f9	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f912ec13-f91d-5f73-9ae1-3f307a5287c2	e95d8421-11e7-553f-8fcd-448084f10d14	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bdb5b1a7-02c1-5cf0-80e7-40b34e7de695	654e08cd-8bdb-5f5b-b464-fc687b217883	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
550dbae1-08a1-56a7-950f-ad74cfe003b8	c817a967-78ec-5dc5-ad90-55b61f5db704	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b67c39e0-03f5-5faa-b8d9-d5ebaa1e884c	c13171bb-2178-5cbe-a8ae-9906af5b92b8	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5a5e3e75-f519-5e70-902f-5c9b345a26ba	5b31e150-ec54-553e-9f11-4a95aa7e9ae9	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
280714c7-d6f9-531e-a5fa-f87b0b841e4d	03cdcb00-c17b-56c3-9134-150bffd9d9b3	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4b996ae5-1c1f-5b4c-a1f8-dabc3a58df20	b9b9f90e-0ff3-5f7a-9bd6-66f15b26f5b9	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
758d6331-06f9-5f0a-a903-736f1ad62711	eb7dcc4f-ab33-593e-b814-0c41ee9ff713	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9422551a-e3fe-5b0c-acd0-a0c2bce9c807	8f63bfdd-4205-5c3c-b82b-a818f235ec0e	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f9595ae9-820d-5c9b-8af1-bf70196e8e52	c7366e56-c082-529c-bbe1-1ebdb9f3894b	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
642b8628-5ee8-562e-9bce-4ac3d8a249b4	6ed744c8-ea85-58bc-9be4-0056f6ab3c6f	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
27b6fd20-e2f6-57e9-8427-399d517b41f5	4cff6571-1f04-58fc-8098-c3c36144c111	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0cb4810f-a039-561b-8775-f3232b7b2712	786869e2-e980-55c3-b53d-2185a3422ea7	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6f70217c-dca6-545c-aaa0-147931e6a03d	d67ce61e-d7d5-5ace-9cea-e27505455b9e	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ad923781-30be-5de5-9726-4ff8192bace2	85fdbd48-c635-5eb6-b7e6-b19233d01410	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1f0f01cf-cc6a-5a91-96da-4881d8c1b03d	883fb935-5e66-5ce6-a5dc-ac527f31c8a7	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3a3800a7-2383-5bb9-96a8-da8d085e68b5	f9c95f62-48bd-53ed-b5bd-3a88d6aebd65	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
73948215-7fb9-50ee-9988-f52bc1795be9	181b685e-e58b-5599-99c7-bb5eab8c8a53	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dacdf954-b0c6-5c74-a66c-7d4fffcb869f	80b9bf14-43e6-52c3-a237-d1afa8031bab	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1f3f7159-c268-543b-9d82-f223a52976c0	737ee088-dc99-5ea3-adb3-d2305ce19c5a	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8caba8c8-927c-5969-8e10-f298cb8b4e48	eaa1aa5e-613c-5c1d-8915-b8b57b8f29e3	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d773553d-8816-51ea-8058-55b694b8b8ea	241d6f87-d07a-5e17-b773-4eb7470f146f	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fddb110c-9006-5d9f-bd88-cebe128e9239	04c18d67-1c66-5d02-a797-f03f8d94a1e9	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7447d0c3-2ff0-5f25-af7c-b8d1fb12bbc6	22ef464c-18b0-5cfa-b612-adedbf8f4f44	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
65135515-018a-5fee-8452-a307e1efb4ce	187c196a-5662-5427-8324-702ae75a80d8	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
63a4d044-9e02-5eab-abd3-505cba78be37	2c40bc38-b50f-59ed-913b-7fe27db0907f	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
20496dc4-71f3-506c-887d-4e4d516598be	64d7a9c8-2455-547e-ba40-99bb8893a8a9	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
94a71f56-976f-5ee8-97fc-fc2c8f5416c7	fc30bc18-cadc-5e1d-9f5c-2a85fcd5fc0b	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
acf34bf4-d854-5fcf-82fe-a2716e4c2664	17e7df9e-3462-5f29-96e4-d78a710aba4a	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3dbabe27-cc17-5ba3-af5b-84b4a547728b	ff9a4d7e-bb4e-54f8-ac15-0ae6ec2d9d09	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c3fe43d3-22fc-56e5-9841-2f6fd88b29c9	cfe112ca-e18a-5125-bdec-ad756c242104	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2235e49a-4da2-5087-9d3a-51c52d32f68b	095bf04c-ae81-5f7f-bc46-5fb6ba832410	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
09e711c1-ee74-52fa-a75c-a6b3040eae7e	358ed023-5145-5788-aa33-162d23201a8c	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a3693b18-e8e8-595c-8f58-ebe22d708771	72e9238b-b758-5b8a-9cec-4de23ea6ee05	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
389007ba-9760-5839-b113-07af5c71f996	e777d567-9057-5874-9c0b-f31166ebe27f	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6f2b5edf-d7b7-53e9-a31a-a2c2763739d8	72d0a511-17f7-50f1-b31f-827269bfcdf9	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6d191830-4cc1-5adc-b2a4-8db3b3afd3ed	9d3532cf-7d8d-5315-80d5-ab0fc5494335	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bd5b8ea6-7169-58c4-93ae-fde4216573e4	d374adef-adf3-5b71-b525-a6c6262bf463	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e7af4bdb-5b65-539d-ab4d-1f8cfe7910c5	1a7a8f85-7fd9-5d31-8247-fd5e7b7dd4b9	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6a911e8c-4911-58b1-abcd-8e0da8fba11d	786c9846-b6c6-58fa-8635-787a18701ee3	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
caf55549-b57e-5f27-bc4c-00d712e03c89	5e928f28-f117-520a-9649-833d16276213	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bea8a98b-a389-5596-97fb-599e50345f55	46120ad3-1942-522e-84f3-3761e21d9047	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d1608793-f7c6-54e3-a47e-44c8481c81ca	040a1aa0-177a-5154-a4c8-2853a5ac97e1	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
97339bd2-bd24-516a-9f40-9753baa5b8bf	d8ec1c58-f79d-5680-9ee7-0453e2b3984b	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6c508b7b-7c90-5a45-a4d2-4e66b7404a34	334b3b9e-8bca-53f3-bf7f-272e889fb410	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
38c1f79b-327f-5d44-99e3-4b6b9b99e428	f56033f4-69a7-57dc-a5bd-a66944ecac34	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ddb4d9bd-326b-5a62-bccc-7ad482e9508e	d6d8407e-4c7d-5fd7-a2ba-3660c3de1312	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c6037b00-07fd-5d50-9ff1-5dda28a19187	a512c728-7421-5f09-927c-6c742849e965	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0f2268cf-06ac-5268-9339-be312188b3dd	ffc7415f-ac53-5a76-90f8-d1701ff9c8f4	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
09bf6fec-1281-5706-94fa-0ff938430726	52e99567-b48a-50e7-b996-5f38fdc4706e	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
060bdd66-ec13-5233-9d2d-8875a1cd8fac	328552e6-3212-5470-9d94-e75fe36eec6a	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: service_types; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.service_types (service_type_id, dealership_id, name, default_duration_minutes, min_duration_minutes, max_duration_minutes, is_active, created_at, deleted_at, updated_at) FROM stdin;
ff658fc4-1dd0-5cca-b436-d138e9e5832a	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Oil service	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
40e31547-ef9d-5f42-8fe4-acdb10affee0	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Tire rotation	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
47e2a50d-3111-5d97-87d1-c6f9b865cdf4	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Brake inspection	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1df02326-4e85-579f-b58f-64e4cd71b5a7	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Wheel alignment	75	37	150	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8a8a8dcb-c515-5c94-9b15-411fa5d3af78	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Diagnostic assessment	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c3d8dbba-05fa-5785-9a04-5fbb17a80efa	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	AC repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
35dd4ceb-6a3a-569e-a49c-6ead26a5ac52	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Major engine repair	180	90	360	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f8ea6f15-8a21-57c2-97ee-7b5dd0638443	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	EV battery inspection	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
07c9fc2e-90ba-56af-88c9-01726b22ef20	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	ADAS calibration	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0e5f7e9e-e60a-5b1b-b9ff-b0f318a4af8b	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Transmission service	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2c198c84-2406-5891-a2b7-ded50a876ed9	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Suspension repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9044baac-541e-54c9-9968-db1caa46c3b8	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Vehicle detailing	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1407c88c-49bb-55d3-8b37-e58b7ad90b4a	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Electrical diagnosis	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
dbf26c41-98f9-5731-b0e1-291f23811d1d	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	Cooling system repair	105	52	210	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1e1aa59c-28cc-5938-810a-49ace5798ac8	206c4a44-c525-5960-ad70-3a1e80f806e5	Oil service	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f120f0da-0b7d-5d61-93b3-9fad0d9f3ca8	206c4a44-c525-5960-ad70-3a1e80f806e5	Tire rotation	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3f1ebf87-e782-5c39-b5e4-983bed1ba676	206c4a44-c525-5960-ad70-3a1e80f806e5	Brake inspection	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bf648c3f-bf11-5f41-8bd8-a9320a331d2f	206c4a44-c525-5960-ad70-3a1e80f806e5	Wheel alignment	75	37	150	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1ca5b7cc-9956-5a6f-9f50-4a8afac6f4f9	206c4a44-c525-5960-ad70-3a1e80f806e5	Diagnostic assessment	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e95d8421-11e7-553f-8fcd-448084f10d14	206c4a44-c525-5960-ad70-3a1e80f806e5	AC repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
654e08cd-8bdb-5f5b-b464-fc687b217883	206c4a44-c525-5960-ad70-3a1e80f806e5	Major engine repair	180	90	360	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c817a967-78ec-5dc5-ad90-55b61f5db704	206c4a44-c525-5960-ad70-3a1e80f806e5	EV battery inspection	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c13171bb-2178-5cbe-a8ae-9906af5b92b8	206c4a44-c525-5960-ad70-3a1e80f806e5	ADAS calibration	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5b31e150-ec54-553e-9f11-4a95aa7e9ae9	206c4a44-c525-5960-ad70-3a1e80f806e5	Transmission service	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
03cdcb00-c17b-56c3-9134-150bffd9d9b3	206c4a44-c525-5960-ad70-3a1e80f806e5	Suspension repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b9b9f90e-0ff3-5f7a-9bd6-66f15b26f5b9	206c4a44-c525-5960-ad70-3a1e80f806e5	Vehicle detailing	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
eb7dcc4f-ab33-593e-b814-0c41ee9ff713	206c4a44-c525-5960-ad70-3a1e80f806e5	Electrical diagnosis	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8f63bfdd-4205-5c3c-b82b-a818f235ec0e	206c4a44-c525-5960-ad70-3a1e80f806e5	Cooling system repair	105	52	210	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c7366e56-c082-529c-bbe1-1ebdb9f3894b	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Oil service	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6ed744c8-ea85-58bc-9be4-0056f6ab3c6f	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Tire rotation	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4cff6571-1f04-58fc-8098-c3c36144c111	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Brake inspection	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
786869e2-e980-55c3-b53d-2185a3422ea7	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Wheel alignment	75	37	150	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d67ce61e-d7d5-5ace-9cea-e27505455b9e	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Diagnostic assessment	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
85fdbd48-c635-5eb6-b7e6-b19233d01410	7022ed8e-d0bf-5f76-8c90-83d05b415fad	AC repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
883fb935-5e66-5ce6-a5dc-ac527f31c8a7	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Major engine repair	180	90	360	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f9c95f62-48bd-53ed-b5bd-3a88d6aebd65	7022ed8e-d0bf-5f76-8c90-83d05b415fad	EV battery inspection	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
181b685e-e58b-5599-99c7-bb5eab8c8a53	7022ed8e-d0bf-5f76-8c90-83d05b415fad	ADAS calibration	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
80b9bf14-43e6-52c3-a237-d1afa8031bab	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Transmission service	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
737ee088-dc99-5ea3-adb3-d2305ce19c5a	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Suspension repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
eaa1aa5e-613c-5c1d-8915-b8b57b8f29e3	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Vehicle detailing	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
241d6f87-d07a-5e17-b773-4eb7470f146f	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Electrical diagnosis	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
04c18d67-1c66-5d02-a797-f03f8d94a1e9	7022ed8e-d0bf-5f76-8c90-83d05b415fad	Cooling system repair	105	52	210	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
22ef464c-18b0-5cfa-b612-adedbf8f4f44	e47567a4-a655-5f7a-93b2-75831525fff3	Oil service	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
187c196a-5662-5427-8324-702ae75a80d8	e47567a4-a655-5f7a-93b2-75831525fff3	Tire rotation	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2c40bc38-b50f-59ed-913b-7fe27db0907f	e47567a4-a655-5f7a-93b2-75831525fff3	Brake inspection	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
64d7a9c8-2455-547e-ba40-99bb8893a8a9	e47567a4-a655-5f7a-93b2-75831525fff3	Wheel alignment	75	37	150	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fc30bc18-cadc-5e1d-9f5c-2a85fcd5fc0b	e47567a4-a655-5f7a-93b2-75831525fff3	Diagnostic assessment	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
17e7df9e-3462-5f29-96e4-d78a710aba4a	e47567a4-a655-5f7a-93b2-75831525fff3	AC repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ff9a4d7e-bb4e-54f8-ac15-0ae6ec2d9d09	e47567a4-a655-5f7a-93b2-75831525fff3	Major engine repair	180	90	360	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cfe112ca-e18a-5125-bdec-ad756c242104	e47567a4-a655-5f7a-93b2-75831525fff3	EV battery inspection	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
095bf04c-ae81-5f7f-bc46-5fb6ba832410	e47567a4-a655-5f7a-93b2-75831525fff3	ADAS calibration	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
358ed023-5145-5788-aa33-162d23201a8c	e47567a4-a655-5f7a-93b2-75831525fff3	Transmission service	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
72e9238b-b758-5b8a-9cec-4de23ea6ee05	e47567a4-a655-5f7a-93b2-75831525fff3	Suspension repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e777d567-9057-5874-9c0b-f31166ebe27f	e47567a4-a655-5f7a-93b2-75831525fff3	Vehicle detailing	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
72d0a511-17f7-50f1-b31f-827269bfcdf9	e47567a4-a655-5f7a-93b2-75831525fff3	Electrical diagnosis	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9d3532cf-7d8d-5315-80d5-ab0fc5494335	e47567a4-a655-5f7a-93b2-75831525fff3	Cooling system repair	105	52	210	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d374adef-adf3-5b71-b525-a6c6262bf463	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Oil service	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1a7a8f85-7fd9-5d31-8247-fd5e7b7dd4b9	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Tire rotation	45	22	90	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
786c9846-b6c6-58fa-8635-787a18701ee3	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Brake inspection	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5e928f28-f117-520a-9649-833d16276213	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Wheel alignment	75	37	150	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
46120ad3-1942-522e-84f3-3761e21d9047	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Diagnostic assessment	60	30	120	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
040a1aa0-177a-5154-a4c8-2853a5ac97e1	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	AC repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d8ec1c58-f79d-5680-9ee7-0453e2b3984b	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Major engine repair	180	90	360	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
334b3b9e-8bca-53f3-bf7f-272e889fb410	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	EV battery inspection	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f56033f4-69a7-57dc-a5bd-a66944ecac34	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	ADAS calibration	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d6d8407e-4c7d-5fd7-a2ba-3660c3de1312	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Transmission service	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a512c728-7421-5f09-927c-6c742849e965	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Suspension repair	120	60	240	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ffc7415f-ac53-5a76-90f8-d1701ff9c8f4	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Vehicle detailing	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
52e99567-b48a-50e7-b996-5f38fdc4706e	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Electrical diagnosis	90	45	180	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
328552e6-3212-5470-9d94-e75fe36eec6a	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	Cooling system repair	105	52	210	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
\.


--
-- Data for Name: skills; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.skills (skill_id, code, name, is_active, created_at, updated_at) FROM stdin;
1ac72710-c75b-5a3e-8ae7-7e6398648c5e	diagnostics	diagnostics	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
95cb2b49-4c5b-5c53-9568-c241db822c1f	engine-repair	engine-repair	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7c285c99-882c-51f8-88e4-360a01a8c6c3	brake-service	brake-service	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b6340703-8a90-59c5-b10f-6530b04245de	ev-high-voltage	ev-high-voltage	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e6530243-c0d6-5c53-a07b-dfab1ec20621	hvac	hvac	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	alignment	alignment	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0ebee0f7-8cbd-5499-8959-0743c0003667	tire-service	tire-service	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dc37ee6a-9a13-50d7-92ca-e41af046b5fb	adas-calibration	adas-calibration	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d94db26b-4e81-5bda-9574-edd56a8f751f	transmission	transmission	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
42ff017e-b931-52aa-81d7-b996f6486bda	suspension	suspension	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	detailing	detailing	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fd4a223b-0210-5af8-a4ae-37851e6d13bb	oil-service	oil-service	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
58362d5b-c4bf-5847-a5f2-464b8af27c6e	electrical	electrical	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1773747a-6c15-5296-856e-d9476f06d1b0	battery	battery	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
573ffe3c-57f3-532e-b401-dfcfa5959fe1	cooling	cooling	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
73477906-1bd3-5211-8bde-27e8924ecb84	exhaust	exhaust	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c0571bb0-f4b9-53e7-92c2-0896179c86be	hybrid	hybrid	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
35cdde80-4cb7-52e3-808c-4ab03fa554af	inspection	inspection	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f116abf5-5ce2-5288-87eb-8a34e27c2261	bodywork	bodywork	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2552c17a-b823-5d68-ab3d-8d198b617fba	wheels	wheels	t	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: technician_shifts; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.technician_shifts (technician_shift_id, technician_id, day_of_week, starts_at, ends_at, created_at, deleted_at, updated_at) FROM stdin;
5b3fe050-3298-5436-b6de-5de94c7318b5	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
88eabf36-5645-50bb-9ff4-862de861001d	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
367f3e66-e614-5206-ba73-32618db1e28c	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f6220373-9703-521b-9c22-521c13b99881	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
89376440-fd3a-51fd-a7a9-af26dd04ad43	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
189b65a6-18c0-599c-8ecf-2f85017ba20a	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6d903b8a-a9f6-5c11-9427-e83f44381f26	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
33fc018b-127f-5723-bd54-2bc2ff6661d0	fdfee93f-949b-5a04-849c-bb943a92e4bd	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
149762cc-a266-5c06-9bb9-ff46f9f1a399	fdfee93f-949b-5a04-849c-bb943a92e4bd	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
766a5a7f-c3bd-5e8f-82c0-33ec819a992c	fdfee93f-949b-5a04-849c-bb943a92e4bd	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a66bb24b-53ca-5ba6-abec-420d612e04b1	fdfee93f-949b-5a04-849c-bb943a92e4bd	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
592135e0-4d4c-572f-90d8-709cb75dcf4e	fdfee93f-949b-5a04-849c-bb943a92e4bd	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ee856415-12c6-5b70-9d4b-7ea3cc6d996a	fdfee93f-949b-5a04-849c-bb943a92e4bd	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
34321e94-41eb-5633-a976-db5a17fd0f8f	fdfee93f-949b-5a04-849c-bb943a92e4bd	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4b4ada8c-516d-5947-9469-060a2103f629	780d2c59-38da-5e9b-8b59-d3377186faab	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a2ffb78b-f7c0-5089-8a01-333891a3baf4	780d2c59-38da-5e9b-8b59-d3377186faab	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
28dbb20b-4d0d-506a-88c7-1f3c95dfa298	780d2c59-38da-5e9b-8b59-d3377186faab	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6684f6c3-bfec-5b57-b9ba-88eea1021738	780d2c59-38da-5e9b-8b59-d3377186faab	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
be809c94-6d21-52ad-a01e-b97ad68902a4	780d2c59-38da-5e9b-8b59-d3377186faab	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
99a096f0-40c3-5510-997b-6f18558ad4dc	780d2c59-38da-5e9b-8b59-d3377186faab	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fd6e435d-b95a-5ec6-8ef0-3faa83df10cd	780d2c59-38da-5e9b-8b59-d3377186faab	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3df576d0-5dc1-56a7-86c5-2fd62753ccae	7497e944-d4ac-58cd-a8f7-b33478331e7e	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4800b0de-4eb6-534d-bd89-690294b1abf7	7497e944-d4ac-58cd-a8f7-b33478331e7e	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9642acc9-1bc0-5345-8002-84a9b5b84b82	7497e944-d4ac-58cd-a8f7-b33478331e7e	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5ce60b64-84ee-5c6d-a06d-8d978e5f3548	7497e944-d4ac-58cd-a8f7-b33478331e7e	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7310c05d-2582-5a6e-b220-2751fd961a97	7497e944-d4ac-58cd-a8f7-b33478331e7e	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
23b8049f-8de3-55c4-ac85-949426f4710a	7497e944-d4ac-58cd-a8f7-b33478331e7e	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
60b179e0-451e-52a4-8c3c-40f7c2f7a69d	7497e944-d4ac-58cd-a8f7-b33478331e7e	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3b152cc1-f728-5b5b-ad2f-81f1cadbdc10	aab629e4-5965-5d14-a69f-e8d2db5df493	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cddc2444-7219-5864-802c-5fbb5115149f	aab629e4-5965-5d14-a69f-e8d2db5df493	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
13e5dc07-4947-5e03-acc5-ba60096f1f0e	aab629e4-5965-5d14-a69f-e8d2db5df493	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
69b287d7-7e38-57dd-a259-b647fd42c97e	aab629e4-5965-5d14-a69f-e8d2db5df493	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
438000f7-61a5-5b05-b495-38751a4a0465	aab629e4-5965-5d14-a69f-e8d2db5df493	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3cb87d9b-f916-55aa-becb-4ddc3cc19758	aab629e4-5965-5d14-a69f-e8d2db5df493	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
643a7f08-e73d-5608-8855-9d26f3303b1f	aab629e4-5965-5d14-a69f-e8d2db5df493	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
74edbdc6-c834-527a-987d-5932bc36a3fb	707dff87-bd95-5b80-995e-d50103262d38	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
31449212-81ca-535d-ae57-ee867aae465a	707dff87-bd95-5b80-995e-d50103262d38	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1649ce8d-2a44-5c33-a081-5f95cee2400a	707dff87-bd95-5b80-995e-d50103262d38	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b419c9e0-1749-5333-af39-497caa82ab94	707dff87-bd95-5b80-995e-d50103262d38	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f3bc5793-d08b-5beb-ad4b-9dd0375b2fd1	707dff87-bd95-5b80-995e-d50103262d38	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
052f9b6e-4fa6-52e8-8fb1-f2a9d78b1ee2	707dff87-bd95-5b80-995e-d50103262d38	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e11cbac4-cc55-5502-aa6e-4dad04e02d56	707dff87-bd95-5b80-995e-d50103262d38	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9869ca5e-729e-53a3-93ce-cfd06cde287c	f2198e56-6a0f-532d-9157-d476192410b6	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
42fdf16e-beb0-504f-8dd2-5d4e8b0ea49e	f2198e56-6a0f-532d-9157-d476192410b6	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8f0e9565-249d-5248-b4af-c2b00586e0fd	f2198e56-6a0f-532d-9157-d476192410b6	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
85e65980-96f3-5395-bb8f-3ac60fb38899	f2198e56-6a0f-532d-9157-d476192410b6	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7b0a6a0a-748d-5076-aabe-1dfef2e1849e	f2198e56-6a0f-532d-9157-d476192410b6	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bc3bf8ad-7ec7-5906-a04c-35c5fdeb93a4	f2198e56-6a0f-532d-9157-d476192410b6	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b944cb60-e284-52e9-9c00-c618e560e704	f2198e56-6a0f-532d-9157-d476192410b6	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
095b4e1f-cf48-5226-b12f-356cfc910254	1a23a28b-6101-544e-b435-1c5436b103b2	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
30097220-216e-50e8-9c56-c30bfeb843c5	1a23a28b-6101-544e-b435-1c5436b103b2	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
776364ef-fd58-518c-aa9f-743fc0732d33	1a23a28b-6101-544e-b435-1c5436b103b2	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
522f903c-9450-508b-aee0-37c272f28e95	1a23a28b-6101-544e-b435-1c5436b103b2	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1c1124ea-8372-5aae-8af9-988ddd84855d	1a23a28b-6101-544e-b435-1c5436b103b2	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1745d991-2aab-5aa7-bd50-3b7456d70f81	1a23a28b-6101-544e-b435-1c5436b103b2	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
edc102e4-be7f-5a07-a172-8625059b5779	1a23a28b-6101-544e-b435-1c5436b103b2	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a4d7005d-8450-5463-9750-30aa591347bf	847302c3-659b-56b6-9f76-ab212762e171	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
afcf9971-7c34-55a7-a9a4-832737faec67	847302c3-659b-56b6-9f76-ab212762e171	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1f1587dd-c36f-5bf4-817b-a53716f8b38f	847302c3-659b-56b6-9f76-ab212762e171	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f7d0feaa-9370-5b58-ae54-12aed1d0f1b8	847302c3-659b-56b6-9f76-ab212762e171	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
be2f69fa-563a-5e44-8fdc-ba5d1e06c40d	847302c3-659b-56b6-9f76-ab212762e171	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0e7272d7-727b-5fd2-8be1-0517ccf9c788	847302c3-659b-56b6-9f76-ab212762e171	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8fd61426-a3ee-5232-99d8-f73f1dd1bfc5	847302c3-659b-56b6-9f76-ab212762e171	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3a9f1a39-6e86-59b9-84cd-db6bc3695b82	010f4661-5deb-5107-8c54-5d91e8a14ae5	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
24903b3c-9025-5e45-a004-bff11af43cc0	010f4661-5deb-5107-8c54-5d91e8a14ae5	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
62810569-7596-5da9-ab9e-1e85b9446b4a	010f4661-5deb-5107-8c54-5d91e8a14ae5	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f32c06c2-5d47-58fb-9bb3-c90284e9d5fb	010f4661-5deb-5107-8c54-5d91e8a14ae5	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0bb2163e-5b6a-5980-b7bd-902aad75ad37	010f4661-5deb-5107-8c54-5d91e8a14ae5	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
46379d85-614e-57c0-9cd2-6a3fbd0f00e8	010f4661-5deb-5107-8c54-5d91e8a14ae5	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
92aa6fe3-d3a6-5ce4-9ce1-2356091ad027	010f4661-5deb-5107-8c54-5d91e8a14ae5	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
54b1d8fd-fb74-54d7-a2b2-0c923cc76002	6e4dae43-a541-594f-980b-6f78dedfcb0d	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8e6cbfb3-d7dd-5050-a6b5-3b0e9ccdd071	6e4dae43-a541-594f-980b-6f78dedfcb0d	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b2a46d06-70ca-584c-9beb-88724c345036	6e4dae43-a541-594f-980b-6f78dedfcb0d	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
eba07fd0-d7ed-5fce-9cb8-3526092f1c97	6e4dae43-a541-594f-980b-6f78dedfcb0d	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c2e399d9-699c-5b1e-928b-2b6dd90b27cd	6e4dae43-a541-594f-980b-6f78dedfcb0d	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7e9e8f25-81fc-560f-8f09-061457d096e5	6e4dae43-a541-594f-980b-6f78dedfcb0d	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4b2667b9-fa7a-5c54-92b4-3f905ec54c1b	6e4dae43-a541-594f-980b-6f78dedfcb0d	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
df047940-6300-50e2-a932-84ce22fbc45b	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
051e194b-bf69-5f95-b107-09fbc12fe6d0	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f7995f49-5299-56bf-b91c-3912f98c1e6d	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cd28da1e-2a14-5d45-8565-b2b9a52c6b2c	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ca8410cc-7916-5016-a70e-1fab87863362	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d3604f38-5d80-5d33-a539-1288739bc0c8	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d4acecd1-80f4-58ba-bee9-3d0f7916b855	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cfa14957-d89c-5d3e-a9c3-ec5719c87eb3	60805ebd-cae5-57ce-aa9d-362d81cfc131	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1954d1c3-1fe1-5bd5-8f67-64a824c5dfc4	60805ebd-cae5-57ce-aa9d-362d81cfc131	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
50dc409f-db86-587f-b407-087f53ecce2f	60805ebd-cae5-57ce-aa9d-362d81cfc131	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a567127a-5a10-5da6-b3b5-58d8ee301ff6	60805ebd-cae5-57ce-aa9d-362d81cfc131	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d97d342c-f8a3-549f-8aa7-c7d3c4550bae	60805ebd-cae5-57ce-aa9d-362d81cfc131	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ce79f04a-8e21-5a11-a1ca-ae288e072da4	60805ebd-cae5-57ce-aa9d-362d81cfc131	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bfe37110-eb6e-58ea-b7a0-970c0edc455e	60805ebd-cae5-57ce-aa9d-362d81cfc131	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d464669d-ef48-5f2b-8ef1-e752ce457f6f	93a7232e-d474-5224-8e5b-fd7e98e60a52	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bc5ae0e5-c1bc-5512-8686-208e2813f56e	93a7232e-d474-5224-8e5b-fd7e98e60a52	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cbf1b6a1-1149-5e6d-ab90-74b5a5ee8bc5	93a7232e-d474-5224-8e5b-fd7e98e60a52	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e8379453-c935-53a8-b62f-4965c833f4de	93a7232e-d474-5224-8e5b-fd7e98e60a52	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
891207d5-fbe9-5334-98fe-2195c3560737	93a7232e-d474-5224-8e5b-fd7e98e60a52	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0f8934df-5905-5765-b895-1f9a9fd7b788	93a7232e-d474-5224-8e5b-fd7e98e60a52	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
97b53112-db33-55d7-bf99-22778c2723fb	93a7232e-d474-5224-8e5b-fd7e98e60a52	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b67fc9b2-9488-5ee1-a3ad-068ffe2eb196	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
30c2914f-1821-565a-b473-c4354491e61f	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
762cd66f-92e8-5535-8e95-661be09f3cf4	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bd2ae8f1-b3ee-5b29-9f95-587b3cf49eb9	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d465c2a7-4490-5acf-91d3-915d512a0c54	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9be5c57f-8886-5000-9f1c-78e2af0be028	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a3d8e40d-36ff-558e-adb2-b3c14fc1b4b6	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fab7f2b7-0950-5b90-8d9d-1d0886cddd67	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ea306cee-075f-595b-9700-9b00f12b4a61	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
93e66711-31f4-5b57-a07d-fd90c8be2f7b	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4a749ef2-cf24-5c45-94eb-90928a904830	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5b7fd0a0-2ea0-5a39-8b5e-1844299f9227	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5a86485d-ce06-5112-a6e0-940b48cb98ae	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
265adc5e-72ec-5627-9367-8c22c7ba6b8f	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7e3f2224-9674-5b34-a40a-95c634f8bc24	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e39b026c-d1b0-580a-ae54-5abea68cb0f2	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bd6f0a3a-3019-554a-9e74-68585854a087	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
98f54347-6a00-53c3-b58f-fdb3823231aa	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bdd65be9-f4b4-5e1f-8b5e-3092d7037ed7	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
05d76dde-afe0-5b58-9a16-8730b4467c8b	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d788c177-7af5-571c-b7be-66137aa7b9f7	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f8487ff2-7a4d-584b-97f4-f80b9b2c91af	0456f052-61de-54f4-ac05-a5caba206b56	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
162576bc-f833-5f25-8e31-c0763a09718b	0456f052-61de-54f4-ac05-a5caba206b56	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2466388f-1e17-5126-a221-69fd1c7d8671	0456f052-61de-54f4-ac05-a5caba206b56	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3f8be8f9-7ee8-569f-94b2-c16c8669d90d	0456f052-61de-54f4-ac05-a5caba206b56	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5bc997bd-db94-5090-b367-5d01221e9864	0456f052-61de-54f4-ac05-a5caba206b56	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7bfb5f6d-a841-57a0-aefe-4e30daca4ca0	0456f052-61de-54f4-ac05-a5caba206b56	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e0893e4a-af13-5e80-9f0c-31d6266935fe	0456f052-61de-54f4-ac05-a5caba206b56	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
84a6194f-9d12-5fff-8911-9d8605fd1e53	21d55bed-11e7-550a-a85a-c56e01059dd7	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ddcb4127-8b9b-5151-a5ea-255025137332	21d55bed-11e7-550a-a85a-c56e01059dd7	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
524c209a-0be0-5454-92ed-5b61b434231f	21d55bed-11e7-550a-a85a-c56e01059dd7	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8d0b9fd5-942e-5c0a-942e-dd9ee0ef0b15	21d55bed-11e7-550a-a85a-c56e01059dd7	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
de6e3e61-ceba-57c7-935d-1b4808cfd96d	21d55bed-11e7-550a-a85a-c56e01059dd7	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d87d6983-dcb8-5df1-b6f5-88daeb6c3875	21d55bed-11e7-550a-a85a-c56e01059dd7	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ee70c258-bb50-5b6e-822d-062bf1b3d1dc	21d55bed-11e7-550a-a85a-c56e01059dd7	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
62d0a2be-eb10-58bd-96e8-df5a41dea244	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ffde4b70-80ad-5da1-b5ec-1375dbcf44bc	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
79bb48b4-37cf-5c7e-be1e-1fe7b1edd028	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7ef6edbe-3db3-5afb-b064-1c146936a20d	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d56bf0e6-f23d-5ab3-ab55-6a503dfc50b5	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
52bf9018-41ce-5d24-bcf2-581fbbf8ac72	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ea3e7d72-dd4c-58f6-8322-4ffd2c7c7e38	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fda2c29d-fbcb-5343-8994-b7e937ac4c8c	f94d6698-e5d4-544b-b734-a8672691fde0	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
60de2e57-af07-5800-9302-79ca73a7e78f	f94d6698-e5d4-544b-b734-a8672691fde0	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0eacc2ef-00e9-5f23-8337-b76c6c279c76	f94d6698-e5d4-544b-b734-a8672691fde0	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a70550e8-87fc-5bc3-80ba-b91236cb74b9	f94d6698-e5d4-544b-b734-a8672691fde0	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4c501ca8-d5f0-55c3-b051-dce2f3dc2b5e	f94d6698-e5d4-544b-b734-a8672691fde0	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d5756f65-689f-59c4-8514-29e7ce557544	f94d6698-e5d4-544b-b734-a8672691fde0	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b3485258-4dbc-50a6-8e0b-5c35ee436c63	f94d6698-e5d4-544b-b734-a8672691fde0	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
97620b96-1a06-5a0a-ae4d-9597e2f6a59e	a710b9c6-f208-5130-a26d-8a583a0cae4e	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1695d276-5fb7-5df0-83bf-1a695247533b	a710b9c6-f208-5130-a26d-8a583a0cae4e	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9a279f8b-9be4-58f2-b60e-1a3a7ddd1aae	a710b9c6-f208-5130-a26d-8a583a0cae4e	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
49113a2b-d309-56b8-aa7b-8e14e86e251d	a710b9c6-f208-5130-a26d-8a583a0cae4e	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d27e9163-28fc-5b03-af9f-9f5ed42dcc5c	a710b9c6-f208-5130-a26d-8a583a0cae4e	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
82b70132-bad5-5824-b2e6-4a6b59c672d5	a710b9c6-f208-5130-a26d-8a583a0cae4e	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e1f38377-a00e-5f0b-a677-c31c75e95933	a710b9c6-f208-5130-a26d-8a583a0cae4e	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8c92c971-a7c4-59ad-b410-94e4a26d0743	a2d88a64-e213-5b97-8356-654a9acaf896	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4b34d394-9d90-5d51-951d-92515f3b50f9	a2d88a64-e213-5b97-8356-654a9acaf896	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b2406fb4-ee64-570e-b7bb-f508e647ab42	a2d88a64-e213-5b97-8356-654a9acaf896	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
04a09c05-33de-54b7-b836-37a6a9a28623	a2d88a64-e213-5b97-8356-654a9acaf896	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3c03bfdb-dfec-5f03-9778-1cb8d1996035	a2d88a64-e213-5b97-8356-654a9acaf896	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9043c04d-9af0-569a-b3ba-1410103fb1cf	a2d88a64-e213-5b97-8356-654a9acaf896	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0cbe91a3-de28-56cc-a6e8-43aa2b3d6049	a2d88a64-e213-5b97-8356-654a9acaf896	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
51dab2c8-3b11-5b3c-bd18-49bdda866069	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9fbbf822-7d7f-5d1b-869b-721f0f939360	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e5258968-b9f4-5011-a51c-bd72ccff531e	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
baa5e745-c14d-599a-9140-31db2c8e6875	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ca497684-fbcf-51e5-8c6f-ec7b80f1143c	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
905537c3-89ea-5a63-b5b8-8b70a4ef2807	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7df1c163-b5df-56f2-9c7f-16a043574841	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
be24ec76-6350-5f83-b153-ca62672334bd	f22afce6-9be8-5d54-8493-e187e6080d3d	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ccd2f6ba-5940-529c-9e78-19a0eb1234bb	f22afce6-9be8-5d54-8493-e187e6080d3d	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3de64fbb-40e1-5aee-a5b2-a4b0620aab66	f22afce6-9be8-5d54-8493-e187e6080d3d	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7553db1f-6b66-57a7-b1ca-135b99b9c319	f22afce6-9be8-5d54-8493-e187e6080d3d	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
139ad0d7-983b-567c-970e-46c3a17bb7fb	f22afce6-9be8-5d54-8493-e187e6080d3d	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
95a44302-f422-5e55-bb41-548b598ff54c	f22afce6-9be8-5d54-8493-e187e6080d3d	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
27726d17-8099-5408-ae21-311bebce97d6	f22afce6-9be8-5d54-8493-e187e6080d3d	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ce4f9c41-af63-5204-b35b-6b8fc8f1e795	64e6769c-84d1-57fa-bc98-e1723e8eb08c	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
09b9e33e-2092-5a03-bdd0-ef3fc25174f2	64e6769c-84d1-57fa-bc98-e1723e8eb08c	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
597d1397-f2ce-5b08-97ab-aee81ff2f795	64e6769c-84d1-57fa-bc98-e1723e8eb08c	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
aefcdcad-2bb3-5c57-bf75-42ca255a50e3	64e6769c-84d1-57fa-bc98-e1723e8eb08c	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1b79e9b2-e559-5c40-9482-d65b0b7774c7	64e6769c-84d1-57fa-bc98-e1723e8eb08c	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c54736a7-3ac4-5c77-9e1b-d6854dbe9a86	64e6769c-84d1-57fa-bc98-e1723e8eb08c	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5a28932f-1f46-5b3e-ac7f-4213ca318480	64e6769c-84d1-57fa-bc98-e1723e8eb08c	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0bd2792c-ec86-55ec-9bac-b24f34a7bfac	d80e7bf0-ccec-5454-a816-fff69439db2b	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
38931f21-509e-5f50-ad62-4610b414752e	d80e7bf0-ccec-5454-a816-fff69439db2b	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b2bbbca5-d441-5da5-a66c-e762ad57449f	d80e7bf0-ccec-5454-a816-fff69439db2b	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
88f823a3-76c1-5d26-a6a4-9958a0e5bdd8	d80e7bf0-ccec-5454-a816-fff69439db2b	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1db6353f-8b0f-5f9f-b57a-91162b3200b4	d80e7bf0-ccec-5454-a816-fff69439db2b	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
694f3c3c-7cbd-5ee2-a5cf-1f2854f303d7	d80e7bf0-ccec-5454-a816-fff69439db2b	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
33e0042e-63eb-5a73-a3d0-4fbb93895050	d80e7bf0-ccec-5454-a816-fff69439db2b	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a88adaa5-cf3d-5dc3-aa55-fbeda11d788e	b8674841-66c5-5b49-a764-676033847ca0	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c41d04b1-9c87-584e-a2f0-a44be2327e57	b8674841-66c5-5b49-a764-676033847ca0	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
73ed0a08-c380-58fc-ac19-05e1ecb3ad44	b8674841-66c5-5b49-a764-676033847ca0	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b63a8378-da09-5a26-9543-3607d18d131e	b8674841-66c5-5b49-a764-676033847ca0	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6050f9cd-7a9b-57bd-a32f-45dd6add3264	b8674841-66c5-5b49-a764-676033847ca0	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
684cdef5-7960-5d36-a109-047c7237786c	b8674841-66c5-5b49-a764-676033847ca0	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0047f7a3-8a2f-5599-b799-d156e79e09f8	b8674841-66c5-5b49-a764-676033847ca0	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
46a03f3b-9baa-5f64-9dcc-38ff8dee541a	a11f12c8-7336-5219-b274-3f2978e6ca23	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
14157a1f-d33b-5ce1-8580-5cb376efe38d	a11f12c8-7336-5219-b274-3f2978e6ca23	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3133369c-d509-5d5b-99c3-2a5f9fd74e5f	a11f12c8-7336-5219-b274-3f2978e6ca23	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8739bc35-bb26-56cc-bedb-b8935dedf559	a11f12c8-7336-5219-b274-3f2978e6ca23	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1b15a8a3-ec38-57b9-bbf0-9650d2c14325	a11f12c8-7336-5219-b274-3f2978e6ca23	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
573285fb-7d84-58fb-a8bc-d0583d44ada4	a11f12c8-7336-5219-b274-3f2978e6ca23	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
73795f6e-78ae-5c8b-80af-af88a2c31613	a11f12c8-7336-5219-b274-3f2978e6ca23	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0dc2de85-bd15-52f3-8aea-48febdd7edae	6cca4493-621f-508f-840a-1309311acd8d	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5f3ed709-d2bb-55a4-8ae9-2c7c49cec44a	6cca4493-621f-508f-840a-1309311acd8d	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e9a12d99-08be-5842-abf5-55853646f55a	6cca4493-621f-508f-840a-1309311acd8d	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8c25ec4f-908a-546a-a98c-e8c9ff3e9f39	6cca4493-621f-508f-840a-1309311acd8d	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ee11c716-2024-5030-899b-d7e93fc75e36	6cca4493-621f-508f-840a-1309311acd8d	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2a04fe5b-4401-5b58-85a1-45d6c61e32da	6cca4493-621f-508f-840a-1309311acd8d	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
44c23ca1-1ac6-5d35-ad22-823190b1e4f3	6cca4493-621f-508f-840a-1309311acd8d	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
365af0e8-d5be-5194-a2b1-1eafbd749bca	9cdfb0cd-e427-5722-a838-333ba2098240	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a4bf1f42-1b3e-55f6-8675-8b66f46f10ee	9cdfb0cd-e427-5722-a838-333ba2098240	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0276e1ba-2f30-52fb-8d93-e77426a359c7	9cdfb0cd-e427-5722-a838-333ba2098240	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d2dc5cbc-df17-5cf4-8c10-43071db4f616	9cdfb0cd-e427-5722-a838-333ba2098240	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b44338ea-443a-55f9-b687-4202a3ade828	9cdfb0cd-e427-5722-a838-333ba2098240	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4270cea3-73cd-57f3-b7e1-1090c5a1c4b0	9cdfb0cd-e427-5722-a838-333ba2098240	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ef40353e-a38c-5626-83a5-184191f843ed	9cdfb0cd-e427-5722-a838-333ba2098240	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5ebbad36-2245-5d2e-aacb-55103aab550b	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1783b4ce-1ddb-5ccc-ab2e-599ad22148e7	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
45919cdd-9859-583c-be93-105bd0b67747	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1d505108-6fc4-557c-8e9f-0a5949417100	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bd8257c5-8f98-5d8a-a0c1-7878fe5cb33a	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5d7ea2ad-8e2b-5cce-839f-ac8af7515857	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d8644008-5c0c-549e-b1ee-bc711b05a6ec	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7f34ee10-d236-553b-bb67-cc662f2ad1b4	adf23604-8641-504a-be4a-f23c5d9579b6	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7a0f4e07-1311-5635-bc05-76c3929bc777	adf23604-8641-504a-be4a-f23c5d9579b6	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7097a27b-ab09-5553-ae7e-9cc5527357ee	adf23604-8641-504a-be4a-f23c5d9579b6	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
414dd738-e360-57fe-b35d-347a50c72f8a	adf23604-8641-504a-be4a-f23c5d9579b6	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e1126adc-7bfe-5cea-976f-80e18d37f645	adf23604-8641-504a-be4a-f23c5d9579b6	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
df3707a4-1fe9-5ead-83fc-527fdef25c09	adf23604-8641-504a-be4a-f23c5d9579b6	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0e9aa183-335d-5f49-9927-840b59948917	adf23604-8641-504a-be4a-f23c5d9579b6	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2a48ad02-5d02-537b-8afd-d4e006a2d1c8	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3dd7413a-8974-5890-9f30-9bc4eecc94b5	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2c0488cd-3e4b-540a-bd8d-0eba0851883e	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
814d5df8-db46-5f30-9355-ab84df7eb1d9	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2c7683a3-61b9-5fe3-8b02-b552374938c7	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6e544cad-dbdd-54b7-8789-b0a3276328e6	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
28b23594-9a9c-58ee-9c58-10e06c1ab0b5	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ffe23f32-79cd-5fa8-82a6-724f8720d427	e98c71df-d0a6-56d0-a881-2a2c57bf5986	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4d058380-6a82-57bc-b420-e7a59d033d0d	e98c71df-d0a6-56d0-a881-2a2c57bf5986	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2868209f-8e6a-5374-abc6-f203e65a7aa9	e98c71df-d0a6-56d0-a881-2a2c57bf5986	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a829d61b-59db-5926-9ffd-1eeb25d9901f	e98c71df-d0a6-56d0-a881-2a2c57bf5986	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b68a7f24-5991-56e3-af01-84d0cc88b243	e98c71df-d0a6-56d0-a881-2a2c57bf5986	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7c8043b4-0c18-5a46-b95c-1358dd1692fd	e98c71df-d0a6-56d0-a881-2a2c57bf5986	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2863e3fc-beb1-5aa2-b015-0f508ce5aa63	e98c71df-d0a6-56d0-a881-2a2c57bf5986	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
32838c36-e287-54cb-9807-48747b5105f0	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c84d33af-f7a2-5348-8db1-45caa4022dc2	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
807c5563-6a0a-5cfa-83cb-7b67dcf53b53	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fce898f1-f051-5c05-9991-9eb36581bd9b	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0cbabbdc-0239-57a4-8fce-ba3e61e94ce7	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
39c36fa6-bddb-56a6-875a-a1464929f7d8	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c38ed6c6-b9c9-5a88-9c0d-54ff0eb934f7	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
09d3e72e-b517-5863-897e-f0ec74fb1906	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c6f69f62-2484-5409-8de8-eb406a47652d	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
339c8f2c-1df4-5ac6-a254-50a5bfc35b44	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6e165fc6-7079-52c2-ae29-fc7e584e00bb	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cd8fcb24-189c-56dd-a8f8-c0c0b03f59f6	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
12377ce4-fe4b-50db-8178-86a04e48b59b	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a0e1d772-6924-5de5-8197-104733a9879f	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
59b77e34-ee30-5e39-bb52-ca202965ce56	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3697dc30-0b04-57f9-b108-e3cf1f632675	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d7ead402-ea07-5c48-9203-b7dffa258373	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
605661a8-d342-53c6-882d-9827774601ff	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4b960151-e422-5010-881f-3c8e3154dc0b	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d8e54efa-5380-57f1-87d2-bbca4af7a1c6	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c020d122-a00b-5363-ace1-7466a5f84482	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
23d97c1d-126c-55ac-9031-7347cd421d7f	bbeb14bc-40c8-5503-bb81-29c16b4d0712	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
40e57d4f-af38-5971-9797-c7436e310d52	bbeb14bc-40c8-5503-bb81-29c16b4d0712	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
31ef1420-cc63-5b8a-895e-984dfbb65430	bbeb14bc-40c8-5503-bb81-29c16b4d0712	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ec7562eb-61c7-5a1e-a039-33d9fc86b943	bbeb14bc-40c8-5503-bb81-29c16b4d0712	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a4476172-fe8a-58d5-9ec5-735b33200dd0	bbeb14bc-40c8-5503-bb81-29c16b4d0712	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
da9c5c14-2ad9-5e75-98e8-3d39637e997b	bbeb14bc-40c8-5503-bb81-29c16b4d0712	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
83260071-6364-58dd-9658-503b1b6be901	bbeb14bc-40c8-5503-bb81-29c16b4d0712	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
07ffbc50-6d93-5fe1-9509-282426fdd7b5	ba4a0f25-eb37-5753-9980-0dd47d153853	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0beab0b0-6912-5010-8efa-850426cb1bf5	ba4a0f25-eb37-5753-9980-0dd47d153853	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
028401ca-21e9-548d-ae9c-ecfb66841cbe	ba4a0f25-eb37-5753-9980-0dd47d153853	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1c038ee5-b505-5729-bedf-a9ee2164114a	ba4a0f25-eb37-5753-9980-0dd47d153853	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ce34afcc-2fa5-5bb7-b721-1f2669bb956f	ba4a0f25-eb37-5753-9980-0dd47d153853	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d04212c1-6e81-5a8a-851b-bc6187501ed0	ba4a0f25-eb37-5753-9980-0dd47d153853	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a7de95ba-9f3e-55ed-95ae-491403179d55	ba4a0f25-eb37-5753-9980-0dd47d153853	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
332857f3-960b-568e-9225-952eca72420f	f6e45079-dc94-52f1-a87f-fb82c82c6684	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
55a40bfc-9c6a-5d9c-836b-b381bb39f63d	f6e45079-dc94-52f1-a87f-fb82c82c6684	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ec1c2f8c-b0c1-573e-b335-a36ec6c56adc	f6e45079-dc94-52f1-a87f-fb82c82c6684	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
af38333b-1603-5728-b4e5-3815ed71af59	f6e45079-dc94-52f1-a87f-fb82c82c6684	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
be3348cc-6a99-5a86-b4b1-bb00cd977ecd	f6e45079-dc94-52f1-a87f-fb82c82c6684	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
23edc106-18c4-5eb1-872e-071a3457796c	f6e45079-dc94-52f1-a87f-fb82c82c6684	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
51d4f82a-3bf9-5975-9153-67decb7d7018	f6e45079-dc94-52f1-a87f-fb82c82c6684	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
79172cf7-bd2c-56f8-8748-1b827e04356e	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
72af329d-287a-51b1-a206-a7937662ea04	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
aaa17c97-b36f-5155-9300-d7f79c40ceb5	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
19e56741-b28e-56e5-85fb-490178a36c08	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cd3960af-0fc9-5e3b-af5e-10330c57ceb3	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
16927684-2b37-5e40-a56c-e4065aebac9d	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
dc88f522-d5f6-5bd7-9752-6c34fcb0743b	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
62b3e05d-7e1b-59cf-bdab-173c94fca3f8	4a5f4e0e-e447-519c-8f36-bb3d60802506	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
338e120f-e16e-5cc8-99e7-37702308900a	4a5f4e0e-e447-519c-8f36-bb3d60802506	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
15f7ccd6-2c20-5001-adf0-90f138396ffe	4a5f4e0e-e447-519c-8f36-bb3d60802506	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9c7b51f2-680e-5835-8332-ce781b535184	4a5f4e0e-e447-519c-8f36-bb3d60802506	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
eb8db6c1-cdc3-50fc-be88-27ebcaf45f75	4a5f4e0e-e447-519c-8f36-bb3d60802506	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2a3d3441-38ed-54e8-bc00-1a506c271a65	4a5f4e0e-e447-519c-8f36-bb3d60802506	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
436481ed-c8f3-5f0b-a6e5-069a68e9b482	4a5f4e0e-e447-519c-8f36-bb3d60802506	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
71a30fa1-5c52-580a-ad7e-8bfb084dd323	885312b8-41b5-5011-b4d6-948cffe99df2	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
311e6de2-83b0-57b6-bd3e-14b8c7c75d66	885312b8-41b5-5011-b4d6-948cffe99df2	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
440031bd-6e11-5a98-8637-2d61aed36131	885312b8-41b5-5011-b4d6-948cffe99df2	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ab43a3aa-3494-594d-adce-b25079613a6c	885312b8-41b5-5011-b4d6-948cffe99df2	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cb7f9044-268c-5a08-a819-0d023948200a	885312b8-41b5-5011-b4d6-948cffe99df2	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2a71ce0d-b25e-5d63-ac89-5a55a2e416f9	885312b8-41b5-5011-b4d6-948cffe99df2	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
894e1bb0-3eb1-5edb-826f-01dd4c032203	885312b8-41b5-5011-b4d6-948cffe99df2	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a2d32654-0042-5479-9341-0745f0924aa1	ed061c8d-b8b7-5356-813b-79b188f7a0ba	1	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
432e7c6d-6946-5755-b14a-180e4749c9fb	ed061c8d-b8b7-5356-813b-79b188f7a0ba	2	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b3968ebb-bdb2-5a1c-aec9-9a9b42078f7d	ed061c8d-b8b7-5356-813b-79b188f7a0ba	3	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
463ea416-9641-5166-bc55-c528d5a78fc7	ed061c8d-b8b7-5356-813b-79b188f7a0ba	4	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a92b3bab-c929-5ea0-a2ac-9160bca1ef8b	ed061c8d-b8b7-5356-813b-79b188f7a0ba	5	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
14d5e25a-954d-558f-9bee-de6df64c81d3	ed061c8d-b8b7-5356-813b-79b188f7a0ba	6	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
df0c73a3-1036-5e4b-94ed-5902d4ffdc6c	ed061c8d-b8b7-5356-813b-79b188f7a0ba	7	06:00:00	15:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4f95fdc4-d41f-5e9f-bf42-d7d2bef83224	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
db8b3b00-cedb-5852-89e4-b9a3c26bffa7	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
10abf1a6-f14d-5e10-b982-618b9a313506	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
410468bd-e42b-567c-86f0-ff8087d1f263	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c66afdce-bced-5867-af06-79140efe18fd	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5424f7ca-d330-5389-bde2-f9095043f224	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7fef95fc-041f-5064-b417-75ecf204507e	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1898d912-17ad-5c9a-85e7-94f9dc80e16b	e03ed121-b75d-5595-8e87-41f167c523c6	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ae6c37f4-b121-5daa-82d0-4d13b9403701	e03ed121-b75d-5595-8e87-41f167c523c6	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0a26ef8f-021e-5577-ba2a-26db5ff006ba	e03ed121-b75d-5595-8e87-41f167c523c6	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e248ac35-2929-53f7-a1ab-3f0767f6119b	e03ed121-b75d-5595-8e87-41f167c523c6	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0f88428b-496f-5b4b-96c0-e9e36f37774e	e03ed121-b75d-5595-8e87-41f167c523c6	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
dc04aa38-99e7-58b2-a93f-6a6a99d742eb	e03ed121-b75d-5595-8e87-41f167c523c6	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ab4a5963-597e-55ac-81dd-a5b0ca2685d9	e03ed121-b75d-5595-8e87-41f167c523c6	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c942bd73-f32d-5b70-aab8-be6ee785b53d	add1c01c-5847-58f9-808e-5e6f164c7f92	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
19132117-510c-55d5-993e-af974cbe7043	add1c01c-5847-58f9-808e-5e6f164c7f92	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
41ba0692-a1b5-5b2f-96e7-7e4afba1b91a	add1c01c-5847-58f9-808e-5e6f164c7f92	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0ac120b1-e851-58ec-8c4f-99ad93ed03e7	add1c01c-5847-58f9-808e-5e6f164c7f92	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bda971a2-94f9-580f-9ac6-a48c4b1fbdbf	add1c01c-5847-58f9-808e-5e6f164c7f92	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9a676d6e-8b42-542f-9b1b-76b8868d4050	add1c01c-5847-58f9-808e-5e6f164c7f92	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
24f7acbd-8b2f-51bf-99a4-2ae182710bbf	add1c01c-5847-58f9-808e-5e6f164c7f92	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
045ba8f0-62fb-5d74-bc7a-2045ccf0ee67	b08797ab-1356-52d7-9326-8c07ceacb317	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8ab8ec61-22b8-5450-8ab5-2aaa94639983	b08797ab-1356-52d7-9326-8c07ceacb317	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
186e7c45-7298-57ea-8810-badef3b4efd6	b08797ab-1356-52d7-9326-8c07ceacb317	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d7f7b638-e787-5c16-89f1-640c482ddb4c	b08797ab-1356-52d7-9326-8c07ceacb317	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f0005ab4-6da2-5831-a094-008560c2f9e3	b08797ab-1356-52d7-9326-8c07ceacb317	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
40b9a529-e3b9-567f-b394-15b9d2ee2dba	b08797ab-1356-52d7-9326-8c07ceacb317	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
11b4441f-ae6c-59d0-858f-0ee80596b9f5	b08797ab-1356-52d7-9326-8c07ceacb317	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b011f1da-5a34-5c89-9a36-695d8500f188	7c55c4a0-9710-5326-8677-9328cbb9ebbb	1	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c03bb8ea-b7f8-50a0-9faf-4dad9c6a6b2f	7c55c4a0-9710-5326-8677-9328cbb9ebbb	2	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
edf8a200-fff5-5877-9dd0-718c4bbaffae	7c55c4a0-9710-5326-8677-9328cbb9ebbb	3	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0e238e08-9166-53ab-aa00-22b62675850e	7c55c4a0-9710-5326-8677-9328cbb9ebbb	4	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
268fb475-bf0a-51c0-a108-f67e3e41142c	7c55c4a0-9710-5326-8677-9328cbb9ebbb	5	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3ef9afa6-bb6b-55b8-93b9-19fad00e3ebf	7c55c4a0-9710-5326-8677-9328cbb9ebbb	6	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
95b369c8-a919-5ac6-a3f8-209be1bf4f25	7c55c4a0-9710-5326-8677-9328cbb9ebbb	7	14:00:00	23:00:00	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
\.


--
-- Data for Name: technician_skills; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.technician_skills (technician_skill_id, technician_id, skill_id, created_at, updated_at) FROM stdin;
1c3d21a1-6c01-5bb6-9069-c4a570365978	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bb57d8ab-6c6d-5c4b-b649-7c42af52ca04	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7ae87e71-e9b3-52d7-80c4-cc88f4aded26	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
46b288b4-e682-511f-8879-154f003a5ab1	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ded96c3e-692f-595f-8673-fbdf8453dc43	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0e9c8f1b-472c-5fd2-9235-75c282d4b161	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ad592c2c-4b75-584c-8c49-8454b8988b0a	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0e2b18b5-d1dc-5f79-b07e-fc9248e479aa	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7396b1ce-cb65-5ca0-a888-87f5f7a68ae4	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1c0dad62-51d8-55a2-8910-37ce58d6d2b4	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b5b7012f-2791-57ac-acfc-41e33e12917b	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
18984f92-66e7-5c24-8985-f6f76278e939	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7306372c-8373-581c-b46c-ceeba8831085	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
99d926c4-d0d1-59b5-b095-f5c8984215a4	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fa7da662-502c-5c05-b8b3-27dcef88184a	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6a5c5d16-2669-5e7b-bf0c-d3684b6a423b	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
31a2f5e4-a13b-52bd-8de2-4d73fa85bef2	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4902a8ef-e82e-537f-b461-c0e6d97e86de	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ba77b29f-ef21-542c-8330-792b138c79ee	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0b6a9bbb-5698-558c-a1cf-de752ef1e07a	4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6a546805-dd5c-5575-a8fe-0e922f1b9938	fdfee93f-949b-5a04-849c-bb943a92e4bd	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ae72a8ca-6b20-552d-9fbd-a828f63a3135	fdfee93f-949b-5a04-849c-bb943a92e4bd	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1834a4df-1f77-5aec-9f8e-7eb04d8ce267	fdfee93f-949b-5a04-849c-bb943a92e4bd	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d6c4af09-d4c4-5b4b-a1c7-4516a8e4b269	fdfee93f-949b-5a04-849c-bb943a92e4bd	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8cfe4632-3808-5b06-bb1e-ae22e22cc592	fdfee93f-949b-5a04-849c-bb943a92e4bd	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c3a10e2b-1685-5197-a6d7-2d4c0611c176	fdfee93f-949b-5a04-849c-bb943a92e4bd	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
619768a9-1552-505c-8912-e435cc89cab9	fdfee93f-949b-5a04-849c-bb943a92e4bd	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
79d9b17d-6e46-5b2f-8ccd-163c485ab17d	fdfee93f-949b-5a04-849c-bb943a92e4bd	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d4834c48-e102-5019-8379-c08e88179f74	fdfee93f-949b-5a04-849c-bb943a92e4bd	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
10f78fe2-898f-5304-86d2-38ed33aa176f	fdfee93f-949b-5a04-849c-bb943a92e4bd	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3bff968b-51dd-5ea6-996f-b6402ea17278	780d2c59-38da-5e9b-8b59-d3377186faab	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dd57df87-3d3f-5cc8-859c-a84fa31b2b09	780d2c59-38da-5e9b-8b59-d3377186faab	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
422dce5d-4188-5f7f-8c7b-10b780966a4c	780d2c59-38da-5e9b-8b59-d3377186faab	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0fdd6b72-8696-5d39-98fe-f299ca5a8557	780d2c59-38da-5e9b-8b59-d3377186faab	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a820915e-a829-5393-9652-427e324d7910	780d2c59-38da-5e9b-8b59-d3377186faab	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
83328ccc-8524-5319-b9e0-574d00772de7	7497e944-d4ac-58cd-a8f7-b33478331e7e	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5d79e276-9a59-5c99-9911-6a325868f03b	7497e944-d4ac-58cd-a8f7-b33478331e7e	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e3eee85f-300b-5907-ada0-773027d2dc77	7497e944-d4ac-58cd-a8f7-b33478331e7e	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1d3ea6ce-e442-5e47-b020-48fa21ac783b	7497e944-d4ac-58cd-a8f7-b33478331e7e	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a4631788-5300-53dd-b0d0-495b71cee482	7497e944-d4ac-58cd-a8f7-b33478331e7e	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c5fee141-6d94-51b3-b643-10e99bf32069	aab629e4-5965-5d14-a69f-e8d2db5df493	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2c4edd8e-21d4-55c0-a02c-081b289d1f9c	aab629e4-5965-5d14-a69f-e8d2db5df493	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2fe12c46-9695-5640-9cda-2da29bd1a13a	aab629e4-5965-5d14-a69f-e8d2db5df493	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f84b4ae5-2378-5764-a7ed-3d08d8aede72	aab629e4-5965-5d14-a69f-e8d2db5df493	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4715b325-b16a-5640-83b7-188bf238b2b0	aab629e4-5965-5d14-a69f-e8d2db5df493	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b7478c24-3b50-58c2-a8c4-68e5f9d7a536	707dff87-bd95-5b80-995e-d50103262d38	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2c25f2e2-d04d-5dbb-8397-4d3898e14e89	707dff87-bd95-5b80-995e-d50103262d38	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
422b7997-53cc-5b63-abfd-8fab2e4b436b	707dff87-bd95-5b80-995e-d50103262d38	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b04d5185-86a0-561e-8782-64dcea62cb0e	707dff87-bd95-5b80-995e-d50103262d38	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1aea0a20-d116-52b1-a2da-39c56d5df641	707dff87-bd95-5b80-995e-d50103262d38	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
229900d8-4237-5cca-adf1-1f2565e064a4	f2198e56-6a0f-532d-9157-d476192410b6	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0a745864-9a81-569a-90b8-c95d9bf6753e	f2198e56-6a0f-532d-9157-d476192410b6	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8444ecdb-8d56-573f-83ed-8b7500bbe2de	f2198e56-6a0f-532d-9157-d476192410b6	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dfb35b82-5344-5024-b6f3-b9155f1534df	f2198e56-6a0f-532d-9157-d476192410b6	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fad12587-d122-58a3-8727-f1d6f120d07f	f2198e56-6a0f-532d-9157-d476192410b6	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
94647918-8213-5a10-96e8-9161b05ce1be	1a23a28b-6101-544e-b435-1c5436b103b2	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6e47ed06-e9e6-553b-88e1-e4eef286cdac	1a23a28b-6101-544e-b435-1c5436b103b2	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
57c52bb6-06ed-5a56-a6cf-13f00b50ab0d	1a23a28b-6101-544e-b435-1c5436b103b2	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
30d3fa33-9150-599b-997c-7aa6740efd53	1a23a28b-6101-544e-b435-1c5436b103b2	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
735f99ef-f4b8-52cc-9ba8-a924e0a6cffa	1a23a28b-6101-544e-b435-1c5436b103b2	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fcce3c2f-2031-529b-a2c1-ba2c5de9816d	847302c3-659b-56b6-9f76-ab212762e171	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e92edb6d-7969-5fb6-bf72-ff52eac0147c	847302c3-659b-56b6-9f76-ab212762e171	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f01b3daa-e2d7-580c-87fb-c6c85f175729	847302c3-659b-56b6-9f76-ab212762e171	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d1595572-d8a2-509b-ad8e-90c110d6bd23	847302c3-659b-56b6-9f76-ab212762e171	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
726e576e-c607-53e8-8a68-826b9dc2e17b	847302c3-659b-56b6-9f76-ab212762e171	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6268ddf5-3911-5e1e-ac26-694335a36bb1	010f4661-5deb-5107-8c54-5d91e8a14ae5	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a7e42ccf-119b-5e61-9d87-82e2be0fc353	010f4661-5deb-5107-8c54-5d91e8a14ae5	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6a8d0854-94d8-5f7c-8a48-17eab6affe58	010f4661-5deb-5107-8c54-5d91e8a14ae5	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5a3c2b32-2a42-5716-a1dd-21d87e8e04c5	010f4661-5deb-5107-8c54-5d91e8a14ae5	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
99dcab1b-59c6-5f4a-ac5d-a1ee4755c9ba	010f4661-5deb-5107-8c54-5d91e8a14ae5	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e784cbd6-6d8a-5e93-a252-631a9ed8d4bc	6e4dae43-a541-594f-980b-6f78dedfcb0d	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7bc8961e-979b-51d3-bccd-bbd9988a6e87	6e4dae43-a541-594f-980b-6f78dedfcb0d	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fe4e685c-c437-54ac-ba84-a412db19f1d4	6e4dae43-a541-594f-980b-6f78dedfcb0d	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3dc0bd51-2c23-552b-bf55-c9e2a37c4552	6e4dae43-a541-594f-980b-6f78dedfcb0d	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
63b3b873-2e1d-5af3-8366-90750a2af2f0	6e4dae43-a541-594f-980b-6f78dedfcb0d	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3782ec7a-682a-52f4-92fc-ea2f44957706	6e4dae43-a541-594f-980b-6f78dedfcb0d	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f5bd04b6-670c-5735-aa83-316d59301f9a	6e4dae43-a541-594f-980b-6f78dedfcb0d	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4a26e2bb-2b7b-5104-b0b1-c4d4e6bf384b	6e4dae43-a541-594f-980b-6f78dedfcb0d	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d6c60089-91cc-5f14-90cd-4446eeccb888	6e4dae43-a541-594f-980b-6f78dedfcb0d	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
644d0cd9-c0e8-5264-b844-8b2f9d5bed68	6e4dae43-a541-594f-980b-6f78dedfcb0d	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
619f21c1-131e-51ea-8482-c98de741a7ff	6e4dae43-a541-594f-980b-6f78dedfcb0d	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
38e3d252-71b0-5363-ad76-441d1b7eb8e5	6e4dae43-a541-594f-980b-6f78dedfcb0d	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8d30fefb-9aac-599b-9357-37d5d3bef520	6e4dae43-a541-594f-980b-6f78dedfcb0d	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7bc03574-7903-5b41-9bbc-c2a8db140346	6e4dae43-a541-594f-980b-6f78dedfcb0d	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f8795829-d1be-51ec-9510-e26f3a84cd28	6e4dae43-a541-594f-980b-6f78dedfcb0d	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
528f5c12-a6f5-5e9f-a09c-02dfb744ac49	6e4dae43-a541-594f-980b-6f78dedfcb0d	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
36f98a02-4c0c-57a9-a25c-eb7a3d45086a	6e4dae43-a541-594f-980b-6f78dedfcb0d	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a86236fd-9301-520b-9aad-e592aee2d23f	6e4dae43-a541-594f-980b-6f78dedfcb0d	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f26a35f7-eccc-5c17-9779-067a13500c0b	6e4dae43-a541-594f-980b-6f78dedfcb0d	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7456ff55-795f-5bf1-b990-8857d99a624e	6e4dae43-a541-594f-980b-6f78dedfcb0d	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
399c9e7a-25e5-5601-bad1-68d32b55bfb3	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b24d5c1a-76ac-5cad-958f-5bd9ffaad5f8	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c0319879-55ed-54ff-bf14-07d090e63d93	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9364a0b9-b371-5504-8276-260299874959	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0dfdb8d7-44e6-548a-82b5-2eb42ae933e3	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9e76b4f3-6a32-59ac-a803-df188ba2c535	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a4a3ada5-8f5b-53fc-b784-7dad9842833d	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ba0ae696-9359-5147-8c0b-139ab93a858a	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
84232d3f-80b0-5816-b454-4016937a5d8a	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3894f733-18cf-5ee0-8a7e-fb499c52fde6	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
605d13d7-7ee1-5985-bf8a-d827da9ce7f5	60805ebd-cae5-57ce-aa9d-362d81cfc131	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
13e8e604-b468-52dd-ad39-2461ff9c576f	60805ebd-cae5-57ce-aa9d-362d81cfc131	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dd04b0fb-0589-5746-93ed-0259ec61e4f3	60805ebd-cae5-57ce-aa9d-362d81cfc131	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3ac7c6cc-c8a6-52d6-95ae-ad014ca4cb8c	60805ebd-cae5-57ce-aa9d-362d81cfc131	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0e9d62c4-b31d-57d4-a716-bb95ffa461c6	60805ebd-cae5-57ce-aa9d-362d81cfc131	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d412ea21-917f-5b82-95cb-c2ab8c7a2e7f	93a7232e-d474-5224-8e5b-fd7e98e60a52	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a65e3377-8def-5bdf-a8ad-fe1cfaf69b39	93a7232e-d474-5224-8e5b-fd7e98e60a52	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cfdd5627-0946-5812-a63c-cf368aef1106	93a7232e-d474-5224-8e5b-fd7e98e60a52	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c46f02cf-48f5-5cfe-a0b5-650470c00bf7	93a7232e-d474-5224-8e5b-fd7e98e60a52	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f391352e-92de-5a8d-860d-a0241ad2edd7	93a7232e-d474-5224-8e5b-fd7e98e60a52	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4028c586-16e1-5915-b165-780fd958e04a	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f3f0c344-abcf-51fc-9a15-7faf91bb344e	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c880eb2c-a0db-5055-9528-a4bac4748107	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c313bd98-7fc2-58ca-a874-6061da254dec	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2c9c0b49-68bc-5a9f-a90d-24b04961d04d	f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a8f3e5f3-03dd-599b-bbfd-2767be615cb7	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
05e91242-19a5-54c7-9e49-f9030105ebfe	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
68996cc3-8694-546e-a001-b62c2e49a753	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5b7e49ae-d5fb-5d98-ba4d-d7bed2b18c9d	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
668d56ca-10dc-5918-a272-e04221b8ecc7	2e9b052d-7e21-57c7-bf69-79b9dad71e4e	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bc75df42-f73f-582d-abe9-27917fd9be48	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5f8cc6dc-0a3b-571c-b03e-82334d18f6ad	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
17303f4a-7dbc-564b-b056-2002dc39376c	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5f481cad-7afd-5aa2-8bd0-e5e054ea9e87	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
37d3b726-b3b8-592e-9b38-1cde09347847	b49a8dfd-668a-5e57-ba66-38b389a1d0c3	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
df5a290b-cbf6-5d09-b71b-dee5e2bf6f75	0456f052-61de-54f4-ac05-a5caba206b56	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
958a6c18-4bfb-5799-9b7f-dcc065627e03	0456f052-61de-54f4-ac05-a5caba206b56	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
20559be0-63c6-54ac-a206-b2715dc9bb18	0456f052-61de-54f4-ac05-a5caba206b56	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2b4775ba-a156-545a-af58-65b0c025388a	0456f052-61de-54f4-ac05-a5caba206b56	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5fc963db-6e6c-5222-9833-30855d4767ba	0456f052-61de-54f4-ac05-a5caba206b56	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5d2db5bc-83f8-5a21-8b01-fe4f38ed7f14	21d55bed-11e7-550a-a85a-c56e01059dd7	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1165eeeb-4f32-5e39-ae8c-ec9858bfac97	21d55bed-11e7-550a-a85a-c56e01059dd7	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
57ea07bc-5f04-5d17-817c-a9d4e183adf1	21d55bed-11e7-550a-a85a-c56e01059dd7	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e40f9be6-37a2-5750-9fbf-44824c088688	21d55bed-11e7-550a-a85a-c56e01059dd7	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
163b13e3-3938-5cac-9d9f-c3a974c66e95	21d55bed-11e7-550a-a85a-c56e01059dd7	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
48453682-1ade-52a7-b263-20899932ca03	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a5c0dc4e-1114-5181-91ed-52529cdfc9c8	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b96e52c7-c650-5087-a127-cfafabf8778e	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5ea70064-3c26-58f8-ae93-706665fd4a99	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e9b26333-ffaa-5deb-b8c0-29ad3005b9a3	f4f939a2-ef8e-5a76-816f-c17ae5dfff57	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5ba31ba2-23a9-5f29-b311-228d6195fd07	f94d6698-e5d4-544b-b734-a8672691fde0	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
76eb36f4-c281-509d-a733-eca43cf96054	f94d6698-e5d4-544b-b734-a8672691fde0	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fb85abb5-1b84-5ac3-bbbf-d9a82e932f41	f94d6698-e5d4-544b-b734-a8672691fde0	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
30517596-a048-5bab-af62-489ee3430b4a	f94d6698-e5d4-544b-b734-a8672691fde0	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
206cf6c3-8da6-55af-87cc-3144e1dd9b62	f94d6698-e5d4-544b-b734-a8672691fde0	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
12323606-58fa-56f6-b35c-204ddd4827e0	f94d6698-e5d4-544b-b734-a8672691fde0	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
98d241ba-f12f-5f08-aa6d-8d302bf41269	f94d6698-e5d4-544b-b734-a8672691fde0	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d22a18c4-1b5e-5bac-9f3c-8f0fcb042483	f94d6698-e5d4-544b-b734-a8672691fde0	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e3592927-6372-5241-9fbc-a79227cbbc34	f94d6698-e5d4-544b-b734-a8672691fde0	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8c33bf86-7af6-5217-a7b6-edb8950dbd34	f94d6698-e5d4-544b-b734-a8672691fde0	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f0db0500-ba82-5740-aadd-c23e739da529	f94d6698-e5d4-544b-b734-a8672691fde0	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a816acbc-3944-5e10-b6a4-406509411b25	f94d6698-e5d4-544b-b734-a8672691fde0	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6a2cf47c-d342-5d29-a186-bf8071a00ba3	f94d6698-e5d4-544b-b734-a8672691fde0	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c66e155a-3f9d-573c-b2df-59189212ce8b	f94d6698-e5d4-544b-b734-a8672691fde0	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4872daaa-1f81-5882-9540-036d607edb8b	f94d6698-e5d4-544b-b734-a8672691fde0	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8be5c76b-c3bd-5b67-a1b0-84f922dcbedc	f94d6698-e5d4-544b-b734-a8672691fde0	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
473e0066-72d8-5150-a730-791d316cf952	f94d6698-e5d4-544b-b734-a8672691fde0	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1ed22ec2-915a-59a8-9ef9-611d31324dda	f94d6698-e5d4-544b-b734-a8672691fde0	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
71e60040-144d-5eea-b9ee-fc888c8c23c8	f94d6698-e5d4-544b-b734-a8672691fde0	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c85b9782-bdac-5414-94ec-640851dc05ad	f94d6698-e5d4-544b-b734-a8672691fde0	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e3b0106b-da78-5588-9efa-a8117bdc34dd	a710b9c6-f208-5130-a26d-8a583a0cae4e	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c23e09f2-b4bb-5d1e-8d80-7f6827d746d2	a710b9c6-f208-5130-a26d-8a583a0cae4e	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f8ec7818-123b-578e-a71e-92c4dea57ba7	a710b9c6-f208-5130-a26d-8a583a0cae4e	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2f5c5612-8cef-5c24-b3da-2e4a262fb945	a710b9c6-f208-5130-a26d-8a583a0cae4e	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8211a7b3-86cf-57e1-a428-73aced688cc0	a710b9c6-f208-5130-a26d-8a583a0cae4e	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
17748505-b2f8-5568-b8c4-46f1e511e223	a710b9c6-f208-5130-a26d-8a583a0cae4e	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
862f9f59-a5f0-56d4-a7d9-1e2066b2bfb7	a710b9c6-f208-5130-a26d-8a583a0cae4e	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c3187f86-f6f1-53c3-836c-eadfa0a98405	a710b9c6-f208-5130-a26d-8a583a0cae4e	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
321b5417-4bc6-55a4-9557-54b21b8dda46	a710b9c6-f208-5130-a26d-8a583a0cae4e	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
295b102e-9129-593b-b7dd-f549da51fe29	a710b9c6-f208-5130-a26d-8a583a0cae4e	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
13f4dd58-165c-5e3d-b68f-a224e5e4a496	a2d88a64-e213-5b97-8356-654a9acaf896	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
37a0c9e1-08d3-59fe-b2a1-740d5e36e94d	a2d88a64-e213-5b97-8356-654a9acaf896	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f2151798-fbdf-518f-b378-d00b70b5bbb4	a2d88a64-e213-5b97-8356-654a9acaf896	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0d2d8c57-edf3-572e-8d65-228d0890461c	a2d88a64-e213-5b97-8356-654a9acaf896	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1434ffdf-1faf-5b97-907d-bca92a006e80	a2d88a64-e213-5b97-8356-654a9acaf896	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
81ee44b5-1b57-5c44-b714-4d68248ebc07	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
66a3514f-4616-552d-a43c-1678123c8260	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
830c0096-ebe0-570b-9639-47ac13c65156	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
156e8ff4-f1e5-5835-a0c9-7bb2c90a60dc	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
201aacb0-a2a7-5b7d-9222-f94d878fee72	7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e9ff1971-f777-5af0-ba28-4c507f0f50b8	f22afce6-9be8-5d54-8493-e187e6080d3d	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ef5efcac-9736-5e42-a0d0-de4d88192a01	f22afce6-9be8-5d54-8493-e187e6080d3d	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
431dbc68-91c4-52d7-9142-35fbda3726e7	f22afce6-9be8-5d54-8493-e187e6080d3d	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1960b02e-684d-5af4-8a11-0fa39c3d299d	f22afce6-9be8-5d54-8493-e187e6080d3d	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9a1322e4-1838-508f-bb44-295039d64c92	f22afce6-9be8-5d54-8493-e187e6080d3d	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
62ece278-b464-5a83-9510-5fc9fa96ff6a	64e6769c-84d1-57fa-bc98-e1723e8eb08c	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d7aaeed7-c1ff-5d26-a39a-8078bd3fed1d	64e6769c-84d1-57fa-bc98-e1723e8eb08c	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fff3e7cc-6ec2-54c0-b758-a3f2cefb16eb	64e6769c-84d1-57fa-bc98-e1723e8eb08c	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2292e6ec-d219-5c78-92e3-769ccc6bfe7e	64e6769c-84d1-57fa-bc98-e1723e8eb08c	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
23286326-9bff-56c0-9d9e-2277676361f9	64e6769c-84d1-57fa-bc98-e1723e8eb08c	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bff9007b-0943-535c-89c9-0d895700e782	d80e7bf0-ccec-5454-a816-fff69439db2b	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
65b82903-7ab2-5116-af03-e0fdebff3db5	d80e7bf0-ccec-5454-a816-fff69439db2b	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
178c3b92-e81b-564b-86e1-c64334f2d234	d80e7bf0-ccec-5454-a816-fff69439db2b	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
99ca0f57-9ae5-549f-adb0-388617bebf66	d80e7bf0-ccec-5454-a816-fff69439db2b	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1e79bf91-3152-5d25-9b95-2b7a448d65ef	d80e7bf0-ccec-5454-a816-fff69439db2b	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
34807436-bf24-5c72-99fe-4aebbd724a1b	b8674841-66c5-5b49-a764-676033847ca0	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3d472037-879f-5d97-bd00-dbd8004fc639	b8674841-66c5-5b49-a764-676033847ca0	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
53913aec-4543-5b72-a1df-722d9d7a2643	b8674841-66c5-5b49-a764-676033847ca0	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
690e1139-904c-5d26-80ca-6614ae3cf3f3	b8674841-66c5-5b49-a764-676033847ca0	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
21a494f4-22ea-5cd5-b770-d48e42444680	b8674841-66c5-5b49-a764-676033847ca0	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a4231cd4-b1d5-5478-8c19-121065f96b6f	a11f12c8-7336-5219-b274-3f2978e6ca23	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
20c8539f-34e6-5faa-aa11-5c5156f07383	a11f12c8-7336-5219-b274-3f2978e6ca23	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2b5c2c04-5201-5c7d-b939-a0d986909e3d	a11f12c8-7336-5219-b274-3f2978e6ca23	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
19c733a5-584a-5c10-be7e-44f58d4be6d9	a11f12c8-7336-5219-b274-3f2978e6ca23	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
59fcbf85-c2fe-5eb8-a20e-43a941e058ca	a11f12c8-7336-5219-b274-3f2978e6ca23	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
13eb6cf3-0ec2-5436-8a13-9b70d28cb2c2	6cca4493-621f-508f-840a-1309311acd8d	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cf3ebd19-4393-5535-b268-b8a2d9be9950	6cca4493-621f-508f-840a-1309311acd8d	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
403296e7-a3ca-520b-8980-1817a3b267e5	6cca4493-621f-508f-840a-1309311acd8d	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2a86c792-a975-5d12-9da9-d8fd99564a15	6cca4493-621f-508f-840a-1309311acd8d	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
54407259-9084-56ec-8b7e-40292ad80398	6cca4493-621f-508f-840a-1309311acd8d	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8b4e3943-0c68-51f9-8475-a42415e372d1	9cdfb0cd-e427-5722-a838-333ba2098240	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7d83dccc-1c5a-5aaf-bdff-8f1075e2b837	9cdfb0cd-e427-5722-a838-333ba2098240	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1c97bf07-ebd5-5c10-a5b4-9b3290aaf0a8	9cdfb0cd-e427-5722-a838-333ba2098240	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8e712283-9e16-53c4-a770-6bb01c44e584	9cdfb0cd-e427-5722-a838-333ba2098240	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2c328ac4-4567-5575-af7e-babfdd78c300	9cdfb0cd-e427-5722-a838-333ba2098240	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a7a8c291-3abd-5329-8491-e1a8669d1f3b	9cdfb0cd-e427-5722-a838-333ba2098240	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
208fb32a-25d1-54cc-8443-11e6f9503baa	9cdfb0cd-e427-5722-a838-333ba2098240	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
222e714e-4f46-56ad-8cb7-3f71539bcf22	9cdfb0cd-e427-5722-a838-333ba2098240	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dd3c8e66-d9e8-502e-9d07-7201db85ef03	9cdfb0cd-e427-5722-a838-333ba2098240	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bf486857-0cd1-58c1-a303-4a3af72e0832	9cdfb0cd-e427-5722-a838-333ba2098240	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6c807131-036c-50c2-b9e6-bd56f266b11c	9cdfb0cd-e427-5722-a838-333ba2098240	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4496ded0-2461-5a21-9225-6bb8ae779bf1	9cdfb0cd-e427-5722-a838-333ba2098240	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
acd1b729-db6d-5695-aec4-39fc0b0d783c	9cdfb0cd-e427-5722-a838-333ba2098240	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ac6ac213-2b99-5228-8863-e4cc6c1ab2ca	9cdfb0cd-e427-5722-a838-333ba2098240	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ba3f8d2c-3010-54e0-9f0c-66b9c4e09ed4	9cdfb0cd-e427-5722-a838-333ba2098240	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0cd2c455-3877-5009-aebb-8fcc2a288902	9cdfb0cd-e427-5722-a838-333ba2098240	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
83738956-c9cc-58ea-96b7-6bbfad1e02c4	9cdfb0cd-e427-5722-a838-333ba2098240	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3fbe8098-f080-55f4-ae43-5feac1a3f6ec	9cdfb0cd-e427-5722-a838-333ba2098240	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f05f0c3d-1f74-5554-a3c2-35f37ef10dc2	9cdfb0cd-e427-5722-a838-333ba2098240	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
41c109cd-1f0b-5c5e-bb3c-a458e938189f	9cdfb0cd-e427-5722-a838-333ba2098240	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
67a723e9-c710-53e5-a480-6b8c00be05ed	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
99ecdb6c-87ef-5a12-b387-5c431aca8650	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7dd5e91d-dc95-5b3d-bf56-06dc7a8ff0aa	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2c798c69-b151-5e9b-a7cf-fb86c3ee8128	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
093fc578-4ec8-5cfb-b219-15d9e376ebce	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6e066283-f216-5d45-93d1-8b4ac5a19e55	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
11b57b3d-e25c-5d3a-8d1c-8af01fc5e625	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9200f392-ef3d-551d-b83b-e0acc070be71	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e4fc03d3-6a13-550f-8c75-b2798ff318f3	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f1bdd75a-cdfb-5f6f-913c-495fd4fc64b0	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9c46d853-7435-571a-9235-ed297763f040	adf23604-8641-504a-be4a-f23c5d9579b6	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9a7fdd23-9e1a-5c4e-be89-975e1b60ed38	adf23604-8641-504a-be4a-f23c5d9579b6	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7afb5846-87ea-5da5-962c-20df1f947ccd	adf23604-8641-504a-be4a-f23c5d9579b6	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
683dae08-37eb-5654-b73d-6fb2a7768c12	adf23604-8641-504a-be4a-f23c5d9579b6	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
67f4eaac-3526-5f0a-9507-ff3485cd698f	adf23604-8641-504a-be4a-f23c5d9579b6	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f74a7b77-abb6-5218-b932-232f096d0c8d	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5317e1c5-4a39-5874-be25-5f9a216d735b	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7360b64f-6d2e-54e6-8712-5a43d244f04e	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0e38ca2c-53d0-5c1e-abf3-007fa1a98627	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4cc32483-497a-5603-8c41-027132fac2a9	4706e5c2-a633-5be0-a58c-1ad8951ce7e2	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
33a34870-0440-536c-aa6d-2b14fd157928	e98c71df-d0a6-56d0-a881-2a2c57bf5986	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8f82e6f4-26c6-5976-81ac-14d954209992	e98c71df-d0a6-56d0-a881-2a2c57bf5986	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b94fdd06-a2c4-5e81-a9f7-9a46569a5677	e98c71df-d0a6-56d0-a881-2a2c57bf5986	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
623e877e-16b1-56c2-98a8-d5c24511f8bf	e98c71df-d0a6-56d0-a881-2a2c57bf5986	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
de2fc125-77ed-58a1-9bc3-c764f5ab3760	e98c71df-d0a6-56d0-a881-2a2c57bf5986	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d3a2c55c-5bae-50ed-9db4-c012a236673d	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8ab05b1a-d387-5968-a417-37dbd7dfa2b2	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d8c2660b-8444-5c53-99c5-b9383ad7af89	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c49b7952-09d9-5668-87f9-8af8ba3d0f8f	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f29e03c5-53af-5806-a22f-b3aa55361023	bbe74eeb-5ce4-55a0-adf6-9607daec1a65	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bfc5572f-7d6a-519a-b13e-166d98fb7213	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8f2c5392-f89c-5e5a-9ed9-7e00c3ed2b74	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9d55be70-49af-59c5-803c-21338c721e19	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0bbc7e7b-a3e7-56fe-aee0-74b2d2007d6f	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f6db715a-c830-5ec6-bc15-05273ffe6ba5	fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c039765d-6280-53df-8da6-f177cc4521af	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
66e8cc12-7424-5f90-89b0-cfaf141eaf90	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
92c18cfc-178e-5cac-9fd0-a3c821533824	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
674a8e8e-2b94-54bd-8a40-7e3560266ba1	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5c3c4f86-9c52-5aa9-a6eb-6bc0c1ed2c9a	8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3a67214f-fb9c-599f-aeda-ecef73f4528c	bbeb14bc-40c8-5503-bb81-29c16b4d0712	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0a1e93a4-520a-5e39-ab4b-5ddfd7d666be	bbeb14bc-40c8-5503-bb81-29c16b4d0712	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
702944e5-9e5e-532f-83a9-c07d725c3948	bbeb14bc-40c8-5503-bb81-29c16b4d0712	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4ba9adf4-9a27-5c7f-93a2-bd1aaf17bcef	bbeb14bc-40c8-5503-bb81-29c16b4d0712	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1bd21225-30e0-5db9-bcdd-042f5cf62237	bbeb14bc-40c8-5503-bb81-29c16b4d0712	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b0394727-e493-5a24-949d-bfe6bc56d231	ba4a0f25-eb37-5753-9980-0dd47d153853	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7045367d-2591-5fc2-b6d5-4bffbe552c5e	ba4a0f25-eb37-5753-9980-0dd47d153853	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c95e931d-66b9-5ba9-bde7-a65f76590dac	ba4a0f25-eb37-5753-9980-0dd47d153853	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
95b2235b-eb71-5262-8f9e-c3c7e3e9daab	ba4a0f25-eb37-5753-9980-0dd47d153853	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
20935ccc-85b7-558e-8ee4-24f45fb66079	ba4a0f25-eb37-5753-9980-0dd47d153853	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5bb19cbb-7444-59ac-8f3f-6e7914aea729	f6e45079-dc94-52f1-a87f-fb82c82c6684	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
30ae64c5-757d-5126-9857-a2c8593402d6	f6e45079-dc94-52f1-a87f-fb82c82c6684	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1fa82d4b-7f19-55de-b98f-6813733d3554	f6e45079-dc94-52f1-a87f-fb82c82c6684	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5cb1d85b-f484-5a62-9c18-9818d3587310	f6e45079-dc94-52f1-a87f-fb82c82c6684	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
35670f5b-8c57-5f04-a4be-d14ffbc04423	f6e45079-dc94-52f1-a87f-fb82c82c6684	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8690606f-126e-58f4-9a5a-3e120ca4da5a	f6e45079-dc94-52f1-a87f-fb82c82c6684	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d116ca3b-80e4-58e8-ba4c-4bcce6816b5e	f6e45079-dc94-52f1-a87f-fb82c82c6684	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8e72a6e8-57a8-52bd-a56f-81c7df224db0	f6e45079-dc94-52f1-a87f-fb82c82c6684	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fea0668e-149a-5d59-8939-723db17ca329	f6e45079-dc94-52f1-a87f-fb82c82c6684	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
68f975ef-aba8-5288-8f3c-d936a457a65b	f6e45079-dc94-52f1-a87f-fb82c82c6684	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d470a1ab-9c61-5e7f-8045-de2c2371fc24	f6e45079-dc94-52f1-a87f-fb82c82c6684	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d57dab3e-c61e-514c-8998-9b5737b1a635	f6e45079-dc94-52f1-a87f-fb82c82c6684	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8714bd1e-7631-53a6-85f3-7eddbe438e1c	f6e45079-dc94-52f1-a87f-fb82c82c6684	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7c65cc21-e86e-52a4-bebf-e3892e2caa84	f6e45079-dc94-52f1-a87f-fb82c82c6684	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cd46d04f-8720-5c8c-9aa6-572eb604d6fa	f6e45079-dc94-52f1-a87f-fb82c82c6684	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0e726681-31dc-5062-b225-57a199f3fb86	f6e45079-dc94-52f1-a87f-fb82c82c6684	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d1aa8445-c8ac-5a13-8560-eaa77e8fac7e	f6e45079-dc94-52f1-a87f-fb82c82c6684	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9bf51445-e68e-5a35-9c1f-9818b8cc2319	f6e45079-dc94-52f1-a87f-fb82c82c6684	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3246102f-dd16-558a-b798-938bdda9664b	f6e45079-dc94-52f1-a87f-fb82c82c6684	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
789d7702-b1a1-5f34-bc67-58b91f1947fe	f6e45079-dc94-52f1-a87f-fb82c82c6684	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a4bfebd4-862f-5207-879d-5a0a7a5c0d2c	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4308af53-748f-560e-8439-b2442b288063	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8b08c1d9-51ec-5bd4-8b46-506d3cc82da0	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
fd719109-7a1b-5fb7-b3ee-11f57790981f	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4417b29c-e05e-51e2-892f-48d91eea4e41	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cd7424c4-167f-55a7-a7cd-c8ec0b5f6cba	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2486fd82-f657-5f9d-85ba-699dfddab30d	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dd311c27-9219-5c32-9a3c-f9bd31c97d78	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
34d242ce-4c5f-5497-8237-2bbf1160b8f7	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f6129e9d-a75a-5dc3-8b44-78067a301666	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0eb84251-719f-5541-8c00-0e8e6ee20a48	4a5f4e0e-e447-519c-8f36-bb3d60802506	7c285c99-882c-51f8-88e4-360a01a8c6c3	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8fb8fc0f-fe22-53c4-8c40-da386fee4836	4a5f4e0e-e447-519c-8f36-bb3d60802506	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cef8bd52-1263-5a15-8f09-e7ad98a6f6f1	4a5f4e0e-e447-519c-8f36-bb3d60802506	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a60b75a1-381f-56e3-a23a-6c6be68ad6dc	4a5f4e0e-e447-519c-8f36-bb3d60802506	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
06ff7f23-2b02-53d7-ae80-7a5909430904	4a5f4e0e-e447-519c-8f36-bb3d60802506	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
db28ae34-d8bb-56ea-a200-429fcaffef31	885312b8-41b5-5011-b4d6-948cffe99df2	b6340703-8a90-59c5-b10f-6530b04245de	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7e4ec0f6-6135-5a55-98d3-370d38e25112	885312b8-41b5-5011-b4d6-948cffe99df2	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
24cb2265-7012-5d11-a1b2-74269f273a06	885312b8-41b5-5011-b4d6-948cffe99df2	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
16f85562-7bd1-5b38-885c-3dd76f11faa1	885312b8-41b5-5011-b4d6-948cffe99df2	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b966251c-8093-56d7-9fc4-0f5a13889897	885312b8-41b5-5011-b4d6-948cffe99df2	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
41486b59-da4f-5bdb-b398-87fe355f91d0	ed061c8d-b8b7-5356-813b-79b188f7a0ba	e6530243-c0d6-5c53-a07b-dfab1ec20621	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
9c371653-4ef7-5305-9ca4-c704c16d5a24	ed061c8d-b8b7-5356-813b-79b188f7a0ba	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
34aef3a0-e199-5a46-8521-f69fdc53d4c9	ed061c8d-b8b7-5356-813b-79b188f7a0ba	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
44a6eb5a-45aa-50fe-92b6-4de9d437da28	ed061c8d-b8b7-5356-813b-79b188f7a0ba	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3bf4664f-8a42-5906-b226-a2fa3bd545a9	ed061c8d-b8b7-5356-813b-79b188f7a0ba	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
faf553f0-7132-56cb-83f4-6663a03a9df7	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	8499ca68-f5b9-5ed7-8f4a-ea3e8de355ec	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
6f1dc5a0-9c6f-580e-9bac-e6cf90cf9ea1	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e6399ef4-376e-518a-92d6-d1cb382a976f	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b6c9c46f-d1ee-5709-ba8d-ed3addf133fb	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e6240cb9-52c6-52ac-b3a0-9ce5ab24bcf0	6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
46870cb2-3dee-5da4-8618-c18573d007b6	e03ed121-b75d-5595-8e87-41f167c523c6	0ebee0f7-8cbd-5499-8959-0743c0003667	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
540489d4-cebf-5e7f-8c2e-a5ba70d63fe2	e03ed121-b75d-5595-8e87-41f167c523c6	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d6b91ddd-614c-55e6-a2e2-692942ea0b45	e03ed121-b75d-5595-8e87-41f167c523c6	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d491fe63-3970-509f-8104-3f8269565bcc	e03ed121-b75d-5595-8e87-41f167c523c6	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5d443a37-9e5b-5779-aea4-208a4378e5f1	e03ed121-b75d-5595-8e87-41f167c523c6	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
89e5aa36-4b83-518b-bb08-3fe37b8626fe	add1c01c-5847-58f9-808e-5e6f164c7f92	dc37ee6a-9a13-50d7-92ca-e41af046b5fb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1e1948ce-a616-5db2-a059-f8ea240301fb	add1c01c-5847-58f9-808e-5e6f164c7f92	16fb8c8d-b9aa-5ff3-80b8-5e4991e8b135	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
69330369-2a78-55e3-b6a3-31d8f568b5a0	add1c01c-5847-58f9-808e-5e6f164c7f92	1773747a-6c15-5296-856e-d9476f06d1b0	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
187ba087-ecdd-571a-b08d-da3d74bc7fd2	add1c01c-5847-58f9-808e-5e6f164c7f92	c0571bb0-f4b9-53e7-92c2-0896179c86be	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
47238eab-12b2-57c8-b449-3222dc0a2c16	add1c01c-5847-58f9-808e-5e6f164c7f92	2552c17a-b823-5d68-ab3d-8d198b617fba	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
06c144e3-ff10-559a-a30a-6e43401db545	b08797ab-1356-52d7-9326-8c07ceacb317	d94db26b-4e81-5bda-9574-edd56a8f751f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
45492d1d-9642-5411-9ef0-d01c0691e87a	b08797ab-1356-52d7-9326-8c07ceacb317	fd4a223b-0210-5af8-a4ae-37851e6d13bb	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8d2476f0-9caf-574e-8465-60a182b0da23	b08797ab-1356-52d7-9326-8c07ceacb317	573ffe3c-57f3-532e-b401-dfcfa5959fe1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d8c76542-67bb-5434-9c4a-03a0fae32d62	b08797ab-1356-52d7-9326-8c07ceacb317	35cdde80-4cb7-52e3-808c-4ab03fa554af	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
516857df-fefc-5aa6-b555-28499234bf5c	b08797ab-1356-52d7-9326-8c07ceacb317	1ac72710-c75b-5a3e-8ae7-7e6398648c5e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d8fafd66-4508-5989-8d6e-8dc36b37f1aa	7c55c4a0-9710-5326-8677-9328cbb9ebbb	42ff017e-b931-52aa-81d7-b996f6486bda	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5cb1d106-480a-598a-86fd-67cd9fd2ca96	7c55c4a0-9710-5326-8677-9328cbb9ebbb	58362d5b-c4bf-5847-a5f2-464b8af27c6e	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
eadcbfbc-b01d-5715-89cd-3665d77ff433	7c55c4a0-9710-5326-8677-9328cbb9ebbb	73477906-1bd3-5211-8bde-27e8924ecb84	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7fae9cce-7593-5d84-9e68-af056cebcbf3	7c55c4a0-9710-5326-8677-9328cbb9ebbb	f116abf5-5ce2-5288-87eb-8a34e27c2261	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
130f6831-d1f8-5274-a9a1-f3d55f5198bf	7c55c4a0-9710-5326-8677-9328cbb9ebbb	95cb2b49-4c5b-5c53-9568-c241db822c1f	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: technician_time_off; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.technician_time_off (technician_time_off_id, technician_id, starts_at, ends_at, reason, created_by_user_id, created_at, deleted_at, updated_at) FROM stdin;
e70291c4-cce5-53d6-9ba9-3fedd5d8ffdf	fdfee93f-949b-5a04-849c-bb943a92e4bd	2026-09-03 05:00:00+00	2026-09-03 07:00:00+00	Seed availability-blocking training	d818cd10-0148-5c15-bfd7-597e856951a6	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
963d2979-fffb-55b1-9092-30f506626575	c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	2026-09-03 03:00:00+00	2026-09-03 05:00:00+00	Seed availability-blocking training	bd80cc2a-b071-5a5a-8150-5a24d1b35c90	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
63fd96d0-f348-5b53-a91b-962555807335	a710b9c6-f208-5130-a26d-8a583a0cae4e	2026-09-03 02:00:00+00	2026-09-03 04:00:00+00	Seed availability-blocking training	e53f0c1c-3ce4-5c92-97b8-36ddd59364e7	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a7fc998e-ee87-5b39-9412-3f2fa75afb51	47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	2026-09-03 11:00:00+00	2026-09-03 13:00:00+00	Seed availability-blocking training	fb0eefa5-e688-581e-9d41-fc7bc1a3b406	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f2c7af7f-55a9-59ad-89d3-4659fd146200	6f79bcb9-caba-5e4f-a0da-f2a832862a6a	2026-09-03 19:00:00+00	2026-09-03 21:00:00+00	Seed availability-blocking training	1f1aecf8-3abc-550e-9557-1ef8f9cc87aa	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
\.


--
-- Data for Name: technicians; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.technicians (technician_id, user_id, is_active, created_at, deleted_at, updated_at) FROM stdin;
4e2253e4-33a2-5cf0-b7a3-7df6e4dcaea4	bd73733f-4309-51bf-8627-e35af33083a8	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fdfee93f-949b-5a04-849c-bb943a92e4bd	1c567e37-66e1-5522-b160-3fa7480ccce8	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
780d2c59-38da-5e9b-8b59-d3377186faab	aa8ba7a6-95e0-5f13-8a94-e9525df6d194	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7497e944-d4ac-58cd-a8f7-b33478331e7e	3570aac3-1bd0-5c57-ba7b-cf01cbbecf67	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
aab629e4-5965-5d14-a69f-e8d2db5df493	65c6e163-5396-5fc1-858f-d59685a0bdd3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
707dff87-bd95-5b80-995e-d50103262d38	f3959a3f-930a-5c7e-8d8a-8f4e57f1c420	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f2198e56-6a0f-532d-9157-d476192410b6	b4ce8ac1-cbbd-5662-9658-a9009c057f1e	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1a23a28b-6101-544e-b435-1c5436b103b2	07b45b76-564b-50be-aa1a-3e53974e8d38	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
847302c3-659b-56b6-9f76-ab212762e171	ae8b1779-0f98-55ce-bbaa-6de941023266	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
010f4661-5deb-5107-8c54-5d91e8a14ae5	e79b5213-af45-5218-9e0d-a66b578ba8f3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6e4dae43-a541-594f-980b-6f78dedfcb0d	ba9e53d2-37b9-5ae6-9732-718b0eedcfa9	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c5bafe2f-9ceb-5df6-98b2-aad2c89c89b4	ae8703f7-6c6f-5b0c-bb71-b62ca767eef6	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
60805ebd-cae5-57ce-aa9d-362d81cfc131	6e5c3cf6-6ce5-5052-ae08-fa2564924ae8	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
93a7232e-d474-5224-8e5b-fd7e98e60a52	a639d156-b086-59d8-a68d-9b1118928a5b	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f86854b3-cbc8-5bf0-88b1-c3eda9ac5598	8320a64d-b1a9-5ecb-8748-2b6636638dbc	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2e9b052d-7e21-57c7-bf69-79b9dad71e4e	fb7fb295-01d2-52a1-9f03-5ea588c90db0	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b49a8dfd-668a-5e57-ba66-38b389a1d0c3	9cffdf42-4c07-583f-8041-42808b483d2d	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0456f052-61de-54f4-ac05-a5caba206b56	a2d49664-d546-51d4-afbb-af954ca7b1b4	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
21d55bed-11e7-550a-a85a-c56e01059dd7	e5b82ee9-1d94-5d89-8902-cf3f78a08e71	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f4f939a2-ef8e-5a76-816f-c17ae5dfff57	4d3d3928-3fc9-5223-99ec-60f2e50bfa45	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f94d6698-e5d4-544b-b734-a8672691fde0	b72b4b0c-a4b6-5e8d-a397-cc637a202de0	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a710b9c6-f208-5130-a26d-8a583a0cae4e	41cd1221-8950-50cd-aaeb-097f897a5ead	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a2d88a64-e213-5b97-8356-654a9acaf896	a9e702fe-85bf-50fc-9341-7cbcb984cb00	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7d83cb9f-1db6-54a0-9c93-8b5f0a245d16	d38448fd-37bd-54b0-9958-9577f1b58350	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f22afce6-9be8-5d54-8493-e187e6080d3d	5fa6e0af-db48-5eb9-b4ce-7023faf1c51a	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
64e6769c-84d1-57fa-bc98-e1723e8eb08c	98059ccc-820a-5437-b764-3faf5ef1d893	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d80e7bf0-ccec-5454-a816-fff69439db2b	9e12be67-45a3-5d86-8cd2-94ead8086a57	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b8674841-66c5-5b49-a764-676033847ca0	a7195547-281d-56a2-af8c-e7b0781fff8a	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a11f12c8-7336-5219-b274-3f2978e6ca23	b4131867-be7b-5a92-b920-3de5659297b8	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6cca4493-621f-508f-840a-1309311acd8d	a3d09d17-3ffb-56a7-bc41-4914ac5e9d52	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9cdfb0cd-e427-5722-a838-333ba2098240	db801577-97e0-5c5c-9091-26e0d664ee58	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
47bb1406-dd07-5aa7-8f1d-c12201c5fa2d	e96f87f4-9757-5d36-a60b-ab5caa69ff73	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
adf23604-8641-504a-be4a-f23c5d9579b6	6c05bb61-1f5a-5efc-a216-9b044c10b4a3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4706e5c2-a633-5be0-a58c-1ad8951ce7e2	386952a2-53c2-5300-b887-7514e323b6e3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e98c71df-d0a6-56d0-a881-2a2c57bf5986	9a3f1205-5892-5046-aaac-2c2d3f61d09a	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bbe74eeb-5ce4-55a0-adf6-9607daec1a65	376f006d-bade-5ca5-9ebd-4957c0c3a97e	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fc5b4977-0d1d-58b3-a4b7-8fd8929bad8f	85f794c7-c578-5a22-b784-50bd28511769	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8eea8bfd-f4fc-5fef-8706-73fa3fa14a4c	e54a6054-9a5b-5d41-aa30-2299991e6acd	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bbeb14bc-40c8-5503-bb81-29c16b4d0712	ef48adb9-9ffa-56cf-bd2b-74f0570db1cd	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ba4a0f25-eb37-5753-9980-0dd47d153853	21cc7172-f9e7-5433-83e3-7ed51e53fed0	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f6e45079-dc94-52f1-a87f-fb82c82c6684	8c2e9113-f626-5264-b07b-4a8cdd6edc5d	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6f79bcb9-caba-5e4f-a0da-f2a832862a6a	8a6c84a9-e818-5736-89b5-87afe99c118f	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4a5f4e0e-e447-519c-8f36-bb3d60802506	66bd4d0a-36ec-5c6f-a8b5-9be88055e332	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
885312b8-41b5-5011-b4d6-948cffe99df2	def65ac9-e8eb-5581-92a2-f98c879f94a2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ed061c8d-b8b7-5356-813b-79b188f7a0ba	94462eaa-4c20-58b7-9fb2-82e0f093ecc4	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6d09eba6-5468-5f1b-9f88-3e7f6dd4dd86	535c26bf-0366-5be1-bae4-40a4fbfde1bd	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e03ed121-b75d-5595-8e87-41f167c523c6	ec801993-faf3-5071-9433-6265e206c58e	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
add1c01c-5847-58f9-808e-5e6f164c7f92	b5a8d7ae-60e1-591b-adb2-d6c8ef9c5a4b	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b08797ab-1356-52d7-9326-8c07ceacb317	54877f58-2328-51ac-a283-5e1f72226f7d	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7c55c4a0-9710-5326-8677-9328cbb9ebbb	14b6f40d-3735-5233-ba31-df2c119d1b0c	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
\.


--
-- Data for Name: user_roles; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.user_roles (user_role_id, user_id, role_id, created_at, deleted_at) FROM stdin;
07e366b5-17bb-5965-b2bd-0ac32561448f	3b037fab-ef51-55de-abac-63d4f0242ed4	00000000-0000-4000-8000-000000000001	2026-08-01 00:00:00+00	\N
c527589b-683c-5c02-981f-a306a4685f8a	d818cd10-0148-5c15-bfd7-597e856951a6	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
f4b63826-5a8d-530f-b46c-f4927904a322	4724b2ea-d26e-595b-a998-ce2ecc8a98dd	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
027ccf4f-60b2-581f-9261-b696f3a0cc21	a73801eb-398a-54d0-8e82-e50c59407287	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
5d5b67a9-7e29-5cc2-8f71-31849edd8dfe	6ba3cbde-00de-5241-b4ee-3a234dcacb3a	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
d0927388-dddf-5ee3-9ff0-2fd2f4bee8de	bd73733f-4309-51bf-8627-e35af33083a8	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
5c6b0861-8e53-59fc-8793-86868120c860	1c567e37-66e1-5522-b160-3fa7480ccce8	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
372538de-9211-5c93-bca2-d23e269ba7c5	aa8ba7a6-95e0-5f13-8a94-e9525df6d194	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
77d774ae-3908-52d8-afca-4f3f18940ef3	3570aac3-1bd0-5c57-ba7b-cf01cbbecf67	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
3c0ca36b-bb22-55f1-ab41-65d467844c4a	65c6e163-5396-5fc1-858f-d59685a0bdd3	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
096c9ed5-b284-5b86-9a80-6c3144fefb16	f3959a3f-930a-5c7e-8d8a-8f4e57f1c420	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
73765e30-f29b-544c-bac9-94b5fa59bfc8	b4ce8ac1-cbbd-5662-9658-a9009c057f1e	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
e2944c94-3665-597c-96d4-ae758008572f	07b45b76-564b-50be-aa1a-3e53974e8d38	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
0e256284-22ca-56d0-9886-f5b0a2e90e99	ae8b1779-0f98-55ce-bbaa-6de941023266	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
1604c0c6-e591-5aa2-a385-397306a816cb	e79b5213-af45-5218-9e0d-a66b578ba8f3	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
db5a05dd-d782-597d-a85b-92e36fdfd112	707b4e3a-ae41-5493-ae98-2bea11b31672	00000000-0000-4000-8000-000000000001	2026-08-01 00:00:00+00	\N
310b1c58-a2da-58c8-8a5d-72e48685304e	bd80cc2a-b071-5a5a-8150-5a24d1b35c90	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
712baeb0-4842-597b-b20f-0510641022a0	75c2ad8e-a45c-5e36-8a83-577381f344fe	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
6cea5a24-45f3-5413-89ba-a623bf5b2a77	ded9e174-90f2-5ea7-9b35-86728f8544f7	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
50c9e96b-db92-5552-8eb6-35ca49425e29	71fc0983-58f6-5fa7-898b-a5364d868bb2	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
1988e89d-48f1-5777-976b-c8931f467c7c	ba9e53d2-37b9-5ae6-9732-718b0eedcfa9	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
3d001818-3807-583f-bd82-970652f6453e	ae8703f7-6c6f-5b0c-bb71-b62ca767eef6	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
94b9bca5-e155-537a-9e9b-c4ad00836e71	6e5c3cf6-6ce5-5052-ae08-fa2564924ae8	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
4aa69d8f-973d-5b3e-a261-b04a768eb792	a639d156-b086-59d8-a68d-9b1118928a5b	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
056a0ab4-b336-5809-941d-66793bc0bcb3	8320a64d-b1a9-5ecb-8748-2b6636638dbc	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
add0cae1-a20f-52af-849b-bc9b630fbb82	fb7fb295-01d2-52a1-9f03-5ea588c90db0	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
e2a33978-23a5-514b-a19c-b3038e32ec96	9cffdf42-4c07-583f-8041-42808b483d2d	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
12b96d73-f614-5a40-a106-cb1053a645ca	a2d49664-d546-51d4-afbb-af954ca7b1b4	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
0086688a-cce1-5154-b4c5-4e61102a6863	e5b82ee9-1d94-5d89-8902-cf3f78a08e71	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
904a8524-2a8c-529e-a96e-bdc62b218855	4d3d3928-3fc9-5223-99ec-60f2e50bfa45	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
b6a6a427-8815-55f0-a796-8ad7d675e968	584015f1-f050-5d84-b6ae-08ce073a9756	00000000-0000-4000-8000-000000000001	2026-08-01 00:00:00+00	\N
ba28706d-d6f0-5f3c-814d-99f16b5b113f	e53f0c1c-3ce4-5c92-97b8-36ddd59364e7	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
8bbfa3e4-c37f-5772-8932-eed7861b443c	1a87e15f-cc38-5003-8362-d0d7ba88c0f2	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
bcd061b7-0c44-589d-b9e8-de184e6f40fb	7cedc8b3-3996-52bc-a6de-5f6f2041740f	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
51735f03-16eb-559f-86c5-018dd4641399	e3072459-5304-5663-b190-d18a4d0c4cb6	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
91562a1a-2a12-5836-92ca-3f8f8a7e2d5d	b72b4b0c-a4b6-5e8d-a397-cc637a202de0	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
ce0b588f-beee-5619-8d03-5a17113e8f62	41cd1221-8950-50cd-aaeb-097f897a5ead	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
22c352f6-5fa6-597f-b4c0-cd3acddb7735	a9e702fe-85bf-50fc-9341-7cbcb984cb00	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
548e775b-059c-5f75-adcd-cbb7f92044ec	d38448fd-37bd-54b0-9958-9577f1b58350	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
b09e9984-07bb-50af-a835-c4fc42471c12	5fa6e0af-db48-5eb9-b4ce-7023faf1c51a	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
74380241-01d2-5d84-ad0e-0978582fd75c	98059ccc-820a-5437-b764-3faf5ef1d893	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
c64eacab-c626-53bc-a4c2-c7501cd3112b	9e12be67-45a3-5d86-8cd2-94ead8086a57	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
807f528b-fef6-5b73-b205-2e5063a11c71	a7195547-281d-56a2-af8c-e7b0781fff8a	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
c870eabf-fcc9-55ef-997c-16fa93fd34ac	b4131867-be7b-5a92-b920-3de5659297b8	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
8df72ff8-4aa7-5640-b88a-9a1d49328c90	a3d09d17-3ffb-56a7-bc41-4914ac5e9d52	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
028d195b-f8d6-5c05-9bee-8cd213825d60	eaec58ed-74cb-590a-a7f9-b18ff99acb07	00000000-0000-4000-8000-000000000001	2026-08-01 00:00:00+00	\N
7b98520e-226a-541b-bfa5-8a11e61ccb56	fb0eefa5-e688-581e-9d41-fc7bc1a3b406	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
44f150dc-4a63-5ca5-b5cf-282e3804a1b1	0c03b529-c1f5-5c23-9758-8e5fac3cc84c	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
adc53767-8070-5160-a045-a6eeba9742aa	725e5cc4-6682-5e91-a195-973b60f26754	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
73c74867-aa21-517b-be55-ef9b14c30adb	dc9ae689-3df8-5bee-9a02-6b416d1761d0	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
f7994b0e-8a7c-5ab2-8dc1-461b7e5d7dd8	db801577-97e0-5c5c-9091-26e0d664ee58	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
414c472f-8d1f-5e33-9a1a-4e430658db15	e96f87f4-9757-5d36-a60b-ab5caa69ff73	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
d2329e96-8c16-5c71-a2e6-d2c5c949fc7d	6c05bb61-1f5a-5efc-a216-9b044c10b4a3	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
1507439d-5cc1-5c53-a876-5800aabc987b	386952a2-53c2-5300-b887-7514e323b6e3	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
41de05d8-dd43-53c5-983c-3001eec1b1d5	9a3f1205-5892-5046-aaac-2c2d3f61d09a	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
5976c2a0-f6c4-5507-ac21-291a597dec3d	376f006d-bade-5ca5-9ebd-4957c0c3a97e	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
8ad5a69e-d9e0-5c30-88c3-db002d480240	85f794c7-c578-5a22-b784-50bd28511769	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
e7a4eda2-7f52-55fb-974e-3b2b015add3a	e54a6054-9a5b-5d41-aa30-2299991e6acd	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
3b5e7e78-3511-55f2-9bb7-be20d7ad71b4	ef48adb9-9ffa-56cf-bd2b-74f0570db1cd	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
7bbacdf9-875c-5833-95d6-74f1cae48fe1	21cc7172-f9e7-5433-83e3-7ed51e53fed0	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
56639d03-c133-517e-9f28-0a6f5d5d547f	a1468c7d-a647-5ffe-aea7-9129ad4c5b37	00000000-0000-4000-8000-000000000001	2026-08-01 00:00:00+00	\N
b26f1b1b-651b-5db8-91fe-4eda3c8e30f8	1f1aecf8-3abc-550e-9557-1ef8f9cc87aa	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
a9478326-25cb-56a1-94b8-93f11d6c32a0	7bdfaa66-9d0d-53e1-b216-2f9f37084703	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	\N
2c75d90f-ad61-5044-a152-a88414a07d20	2ad48f7a-7d9b-5503-a68d-07001e014841	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
03548ffe-04e8-50b4-b29d-908c04e8604c	02a75670-78b9-5714-a449-16b547343692	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	\N
92016d39-457e-50e7-bedf-1de628e4df12	8c2e9113-f626-5264-b07b-4a8cdd6edc5d	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
af661262-efce-51da-b806-18074ad6fc09	8a6c84a9-e818-5736-89b5-87afe99c118f	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
0ecb817e-9331-51a5-8803-7da7dd55bf99	66bd4d0a-36ec-5c6f-a8b5-9be88055e332	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
30a8eda4-396e-5bee-b2e3-873d3231b919	def65ac9-e8eb-5581-92a2-f98c879f94a2	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
9ea6791d-e33e-5966-a8f0-92a760859279	94462eaa-4c20-58b7-9fb2-82e0f093ecc4	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
cd87a05c-c78a-5faa-b4e6-db2ce52189ee	535c26bf-0366-5be1-bae4-40a4fbfde1bd	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
d4fef909-0b0c-566b-b0cf-cc030c7f9a5b	ec801993-faf3-5071-9433-6265e206c58e	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
810c2347-d2c2-5309-8d02-26d279c0f0db	b5a8d7ae-60e1-591b-adb2-d6c8ef9c5a4b	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
a4861858-f6b3-5682-ac1b-33fa0804bb78	54877f58-2328-51ac-a283-5e1f72226f7d	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
d9934db9-4e48-5457-953d-49e3cb178c62	14b6f40d-3735-5233-ba31-df2c119d1b0c	00000000-0000-4000-8000-000000000004	2026-08-01 00:00:00+00	\N
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.users (user_id, auth_user_id, name, phone, email, dealership_id, is_active, created_at, deleted_at, updated_at) FROM stdin;
3b037fab-ef51-55de-abac-63d4f0242ed4	ed13e8e3-7703-5989-98bd-610dd497c246	HCM employee 01	+1555000000001	employee.1.1@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d818cd10-0148-5c15-bfd7-597e856951a6	f85b4a3e-8c11-519f-afcd-a1c41bb4adb7	HCM employee 02	+1555000000002	employee.1.2@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4724b2ea-d26e-595b-a998-ce2ecc8a98dd	0f10864d-3c5d-5ffe-b46c-e52b088234f9	HCM employee 03	+1555000000003	employee.1.3@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a73801eb-398a-54d0-8e82-e50c59407287	47b464d0-f951-51c4-9be7-52839e6b8ac1	HCM employee 04	+1555000000004	employee.1.4@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6ba3cbde-00de-5241-b4ee-3a234dcacb3a	ad31ce73-53b4-59f3-9de2-1665bc9dde64	HCM employee 05	+1555000000005	employee.1.5@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bd73733f-4309-51bf-8627-e35af33083a8	a9a2456a-8d3c-5ba7-b057-10e92e727fd4	HCM employee 06	+1555000000006	employee.1.6@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1c567e37-66e1-5522-b160-3fa7480ccce8	f5f434cf-0e86-5c1b-a095-3a305cfaa506	HCM employee 07	+1555000000007	employee.1.7@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
aa8ba7a6-95e0-5f13-8a94-e9525df6d194	c9bf0ee0-8be9-5f59-95c4-0ef3fa3a6c00	HCM employee 08	+1555000000008	employee.1.8@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3570aac3-1bd0-5c57-ba7b-cf01cbbecf67	1a754f12-9ac9-59c0-8d3d-9b7471e2ecaa	HCM employee 09	+1555000000009	employee.1.9@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
65c6e163-5396-5fc1-858f-d59685a0bdd3	b37baa2d-b1b1-5701-aef4-fafcd4ef9d02	HCM employee 10	+1555000000010	employee.1.10@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f3959a3f-930a-5c7e-8d8a-8f4e57f1c420	5756905c-68a6-57a4-9479-da4b99044bf7	HCM employee 11	+1555000000011	employee.1.11@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b4ce8ac1-cbbd-5662-9658-a9009c057f1e	e56f779d-6c24-5365-af11-87916cadee0d	HCM employee 12	+1555000000012	employee.1.12@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
07b45b76-564b-50be-aa1a-3e53974e8d38	f50679c8-e072-5a01-a83d-cccd1001a47e	HCM employee 13	+1555000000013	employee.1.13@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ae8b1779-0f98-55ce-bbaa-6de941023266	09fe0421-b613-5972-9a02-375121cd2eb0	HCM employee 14	+1555000000014	employee.1.14@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e79b5213-af45-5218-9e0d-a66b578ba8f3	d93d7258-0326-526b-95dd-221400877201	HCM employee 15	+1555000000015	employee.1.15@example.test	c0a5818b-26ce-52eb-a07d-fc091ee18bf2	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
707b4e3a-ae41-5493-ae98-2bea11b31672	a3ca678a-d322-5dd9-8e1e-1519a770a274	TYO employee 01	+1555010000001	employee.2.1@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bd80cc2a-b071-5a5a-8150-5a24d1b35c90	106008b1-93dd-5e9d-9c54-859a203d7618	TYO employee 02	+1555010000002	employee.2.2@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
75c2ad8e-a45c-5e36-8a83-577381f344fe	caa71961-224a-5f01-bb65-78ed8fc80398	TYO employee 03	+1555010000003	employee.2.3@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ded9e174-90f2-5ea7-9b35-86728f8544f7	08940432-709c-5295-a2d7-b5e35c738f29	TYO employee 04	+1555010000004	employee.2.4@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
71fc0983-58f6-5fa7-898b-a5364d868bb2	7eb58973-c7b4-578c-9266-4128162fceed	TYO employee 05	+1555010000005	employee.2.5@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ba9e53d2-37b9-5ae6-9732-718b0eedcfa9	72a92aef-fb11-5df1-b776-4559b0403e65	TYO employee 06	+1555010000006	employee.2.6@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ae8703f7-6c6f-5b0c-bb71-b62ca767eef6	5db5f3cf-4a66-5358-887b-7352b8486559	TYO employee 07	+1555010000007	employee.2.7@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6e5c3cf6-6ce5-5052-ae08-fa2564924ae8	22b1b4c5-8080-59ab-8c72-0e6754f9fd0c	TYO employee 08	+1555010000008	employee.2.8@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a639d156-b086-59d8-a68d-9b1118928a5b	c9818417-23b0-5824-a9fe-2424d9dca93c	TYO employee 09	+1555010000009	employee.2.9@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8320a64d-b1a9-5ecb-8748-2b6636638dbc	1ad786ba-141b-5426-8548-9c08d2ed8cca	TYO employee 10	+1555010000010	employee.2.10@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fb7fb295-01d2-52a1-9f03-5ea588c90db0	100eb798-0e4f-59df-9eb7-8dd8a539396a	TYO employee 11	+1555010000011	employee.2.11@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9cffdf42-4c07-583f-8041-42808b483d2d	5e556e92-b7e0-51ce-90fb-71cb14d5f7ad	TYO employee 12	+1555010000012	employee.2.12@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a2d49664-d546-51d4-afbb-af954ca7b1b4	4dba136f-ca11-5746-b71f-5206f01382c1	TYO employee 13	+1555010000013	employee.2.13@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e5b82ee9-1d94-5d89-8902-cf3f78a08e71	dcecdc95-00f7-51fa-af11-4c47b3e977e0	TYO employee 14	+1555010000014	employee.2.14@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4d3d3928-3fc9-5223-99ec-60f2e50bfa45	52f6ac89-8849-5d74-8205-815d7571e25d	TYO employee 15	+1555010000015	employee.2.15@example.test	206c4a44-c525-5960-ad70-3a1e80f806e5	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
584015f1-f050-5d84-b6ae-08ce073a9756	f473874f-a60a-51a3-99e2-0f8502640ba0	SYD employee 01	+1555020000001	employee.3.1@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e53f0c1c-3ce4-5c92-97b8-36ddd59364e7	c45cfb57-49b6-50be-8bd3-b523c6c24cfe	SYD employee 02	+1555020000002	employee.3.2@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1a87e15f-cc38-5003-8362-d0d7ba88c0f2	a83f5d58-18ee-5bd3-8672-b552ae57e554	SYD employee 03	+1555020000003	employee.3.3@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7cedc8b3-3996-52bc-a6de-5f6f2041740f	e4cc80c4-7ffa-5040-9b94-0ecb109f7215	SYD employee 04	+1555020000004	employee.3.4@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e3072459-5304-5663-b190-d18a4d0c4cb6	dd122c26-5379-564d-89ec-8a750946d464	SYD employee 05	+1555020000005	employee.3.5@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b72b4b0c-a4b6-5e8d-a397-cc637a202de0	f455e858-2d88-5deb-a0dc-3b6ba9c0d912	SYD employee 06	+1555020000006	employee.3.6@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
41cd1221-8950-50cd-aaeb-097f897a5ead	da9d869a-114c-5dd4-b73a-4750cf55e7f0	SYD employee 07	+1555020000007	employee.3.7@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a9e702fe-85bf-50fc-9341-7cbcb984cb00	cdf01099-5c7f-5671-85a1-04fab47c361e	SYD employee 08	+1555020000008	employee.3.8@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d38448fd-37bd-54b0-9958-9577f1b58350	f9b4676e-3cdd-5ffb-8e66-a0e550c27f2f	SYD employee 09	+1555020000009	employee.3.9@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5fa6e0af-db48-5eb9-b4ce-7023faf1c51a	b51556d8-a2d4-5587-9d54-18b68389f2a4	SYD employee 10	+1555020000010	employee.3.10@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
98059ccc-820a-5437-b764-3faf5ef1d893	bf147955-4682-5721-a7cf-1fe10af7d033	SYD employee 11	+1555020000011	employee.3.11@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9e12be67-45a3-5d86-8cd2-94ead8086a57	dcc2db75-b19f-595a-8029-c877fa908e8a	SYD employee 12	+1555020000012	employee.3.12@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a7195547-281d-56a2-af8c-e7b0781fff8a	8739fbcd-95b3-5bc2-9258-ab217b9e3bbc	SYD employee 13	+1555020000013	employee.3.13@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b4131867-be7b-5a92-b920-3de5659297b8	2e8f4dfc-78d9-55c2-85b6-beb955113f73	SYD employee 14	+1555020000014	employee.3.14@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a3d09d17-3ffb-56a7-bc41-4914ac5e9d52	2ec9567a-0bc8-5b46-ab01-f62f38a1be62	SYD employee 15	+1555020000015	employee.3.15@example.test	7022ed8e-d0bf-5f76-8c90-83d05b415fad	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
eaec58ed-74cb-590a-a7f9-b18ff99acb07	3ae0ec68-7085-58d2-8f8f-7d7c20adf12d	LDN employee 01	+1555030000001	employee.4.1@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fb0eefa5-e688-581e-9d41-fc7bc1a3b406	ddf58e35-4fa3-5e81-81dc-70baaaa7ee21	LDN employee 02	+1555030000002	employee.4.2@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0c03b529-c1f5-5c23-9758-8e5fac3cc84c	b0daea7a-227b-5429-ad13-595e937835a4	LDN employee 03	+1555030000003	employee.4.3@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
725e5cc4-6682-5e91-a195-973b60f26754	85384d9f-b3a6-57e1-a0d2-830e377cd2a4	LDN employee 04	+1555030000004	employee.4.4@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
dc9ae689-3df8-5bee-9a02-6b416d1761d0	57cd5649-9664-5509-879c-6b7706527c98	LDN employee 05	+1555030000005	employee.4.5@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
db801577-97e0-5c5c-9091-26e0d664ee58	00982e78-df72-5461-b547-6b1cf267e21a	LDN employee 06	+1555030000006	employee.4.6@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e96f87f4-9757-5d36-a60b-ab5caa69ff73	821a4660-9ef5-541c-b390-884a0fe6e419	LDN employee 07	+1555030000007	employee.4.7@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6c05bb61-1f5a-5efc-a216-9b044c10b4a3	e4d6a0e4-b2ff-50d3-8aa9-b7179b9de310	LDN employee 08	+1555030000008	employee.4.8@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
386952a2-53c2-5300-b887-7514e323b6e3	cec08e97-8ca6-5e2c-87f6-f1af809b4d46	LDN employee 09	+1555030000009	employee.4.9@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9a3f1205-5892-5046-aaac-2c2d3f61d09a	acafcd06-d332-5699-bfe1-0e96fa0a9f8b	LDN employee 10	+1555030000010	employee.4.10@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
376f006d-bade-5ca5-9ebd-4957c0c3a97e	0020b47c-0af6-54af-9af7-c8fdf58759f4	LDN employee 11	+1555030000011	employee.4.11@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
85f794c7-c578-5a22-b784-50bd28511769	de6f81e7-7225-5637-9286-d8f4474d7785	LDN employee 12	+1555030000012	employee.4.12@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e54a6054-9a5b-5d41-aa30-2299991e6acd	a5a11267-a3e3-5de1-92e5-468c1c060b31	LDN employee 13	+1555030000013	employee.4.13@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ef48adb9-9ffa-56cf-bd2b-74f0570db1cd	423721b6-4a46-517b-adee-0b777c04cea9	LDN employee 14	+1555030000014	employee.4.14@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
21cc7172-f9e7-5433-83e3-7ed51e53fed0	eb360fca-eb96-5e3b-8930-72b395834212	LDN employee 15	+1555030000015	employee.4.15@example.test	e47567a4-a655-5f7a-93b2-75831525fff3	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a1468c7d-a647-5ffe-aea7-9129ad4c5b37	7bdb7d40-e721-53be-991c-408b90e62b4f	LAX employee 01	+1555040000001	employee.5.1@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1f1aecf8-3abc-550e-9557-1ef8f9cc87aa	afaac000-3f8c-5cc7-81c0-7dd3b33b5322	LAX employee 02	+1555040000002	employee.5.2@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7bdfaa66-9d0d-53e1-b216-2f9f37084703	86082c6d-f6ce-5691-b46c-16c8f4ce3003	LAX employee 03	+1555040000003	employee.5.3@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2ad48f7a-7d9b-5503-a68d-07001e014841	5062875c-b0d1-56f9-a950-fd0ba0766204	LAX employee 04	+1555040000004	employee.5.4@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
02a75670-78b9-5714-a449-16b547343692	cef17b64-2d8b-5f68-8cb3-2e4f23535f72	LAX employee 05	+1555040000005	employee.5.5@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8c2e9113-f626-5264-b07b-4a8cdd6edc5d	79d049ea-c4f8-5c15-9b9d-73fd28f1699d	LAX employee 06	+1555040000006	employee.5.6@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8a6c84a9-e818-5736-89b5-87afe99c118f	eac738c9-85a9-58ba-ac93-3a884bbb5a12	LAX employee 07	+1555040000007	employee.5.7@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
66bd4d0a-36ec-5c6f-a8b5-9be88055e332	0c50b446-f2ea-54d7-9ea2-bb42d78c175b	LAX employee 08	+1555040000008	employee.5.8@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
def65ac9-e8eb-5581-92a2-f98c879f94a2	c3299ed5-eca3-598e-a27d-6995a26850c4	LAX employee 09	+1555040000009	employee.5.9@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
94462eaa-4c20-58b7-9fb2-82e0f093ecc4	7a7f6ea5-eae0-56a7-8170-19f63df36eac	LAX employee 10	+1555040000010	employee.5.10@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
535c26bf-0366-5be1-bae4-40a4fbfde1bd	767fed37-59e2-566e-9176-b86eb3f9e6a1	LAX employee 11	+1555040000011	employee.5.11@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ec801993-faf3-5071-9433-6265e206c58e	557f77f1-0005-5160-aeec-844e74cb1d48	LAX employee 12	+1555040000012	employee.5.12@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b5a8d7ae-60e1-591b-adb2-d6c8ef9c5a4b	57442b8e-30fa-5be7-a8d2-97a430faf00e	LAX employee 13	+1555040000013	employee.5.13@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
54877f58-2328-51ac-a283-5e1f72226f7d	56aebc4f-4fa9-5285-978f-535055a22403	LAX employee 14	+1555040000014	employee.5.14@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
14b6f40d-3735-5233-ba31-df2c119d1b0c	c410c3fb-090d-54d0-b028-266594143b70	LAX employee 15	+1555040000015	employee.5.15@example.test	3bd40f39-dc6f-5ea6-ab81-2d1e305d42ae	t	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
\.


--
-- Data for Name: vehicles; Type: TABLE DATA; Schema: appointment_scheduler; Owner: postgres
--

COPY appointment_scheduler.vehicles (vehicle_id, customer_id, vin, registration_plate, make, model, model_year, created_at, deleted_at, updated_at) FROM stdin;
0f777184-c71e-5c20-95bf-3ddd073781a0	80bf95ff-9973-508b-9e4c-4448d6979561	S0000000000000001	SEED0001	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d0b2c927-e63b-58b2-a2a2-e48d914aadae	3a015a81-56c2-54c0-8cf4-11b84411a0ab	S0000000000000002	SEED0002	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6fa83485-cc32-5572-a0f1-907943e1b5b1	1affb879-d86f-57f4-b3c4-c85b191c8fc9	S0000000000000003	SEED0003	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2d36bdea-bc1e-57eb-ab7c-d7c27c117c28	2e3822ad-e19a-5815-91f5-005547e08893	S0000000000000004	SEED0004	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0576b5f1-87c7-5510-8077-0aa37958e309	daf78796-8816-5ae3-b5b0-d327e03764d2	S0000000000000005	SEED0005	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2dc6a499-86fe-5d2a-a3cb-2d2688f9b9c9	1be2026f-a49c-5ca7-805b-aa1de3a5f349	S0000000000000006	SEED0006	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
66005aec-63ba-5f04-aa54-d612fa9d251b	f948ab66-1616-5de0-ba37-7851129dfa44	S0000000000000007	SEED0007	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4e14a2b9-7c6e-5997-b8fd-53b65a41b663	6fcb75b2-5105-52b0-ba8e-b19767927261	S0000000000000008	SEED0008	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ba375fa5-4acf-5d6a-b25a-47ab14af7e70	e04ad513-ee6a-5dd8-8204-59a5ac538927	S0000000000000009	SEED0009	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b0788dd1-91c6-5c6f-9888-07f166631c06	b155f7ca-0311-5ae2-9775-20a123db0d35	S0000000000000010	SEED0010	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3fba3706-18d3-5ab5-9a64-fb6b91e4df0b	8ab22659-36a2-57c9-86f3-10cd9e0134ff	S0000000000000011	SEED0011	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
29cbaafd-1395-5af1-a4a2-7ab7559dd636	9a77a403-73c0-5634-bfe1-c67323ee601b	S0000000000000012	SEED0012	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0594263e-9ca1-578e-88f6-7555e614b620	13f62a96-ac31-5ea6-98f0-e73edd54615d	S0000000000000013	SEED0013	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4aabef33-da2d-50b7-8dde-2d5db2c75d9d	a329fbb9-bf4b-58ca-b306-a030c02851f7	S0000000000000014	SEED0014	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1989b53c-d8f4-5b00-a737-50830a9ad5f7	28ccf436-cbad-54e8-9eb8-7742302ee14e	S0000000000000015	SEED0015	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
af030a0d-409f-5da8-a741-803299cfbc3f	4a2800af-46ff-51a1-b8fc-e1a248b97793	S0000000000000016	SEED0016	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
83e9c3ff-eb0d-593a-8850-70b3a2feeb59	e8ecd6e0-e0fe-5722-a345-508e2e6c3b36	S0000000000000017	SEED0017	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2d53eda8-0ab5-5161-a2f5-23506c54c14f	882cf7e7-9e39-56a2-a474-9f313bbf6097	S0000000000000018	SEED0018	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
974b06e3-4b05-580c-846a-d100734436b4	068e4c89-6f3f-59fc-a41b-fdc12cdc78a2	S0000000000000019	SEED0019	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3352ba6a-3075-5c57-827c-aa6917c116a4	dc5114d1-aa50-5995-a1ab-40223403a1a3	S0000000000000020	SEED0020	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
30af15ee-d6a7-54e2-b17c-5e5ba9a5d5f7	a9e5a060-3b39-5d45-85d4-de0566386b46	S0000000000000021	SEED0021	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
feb38295-f562-5b8a-9ce9-c8c81a70260d	700519e2-3e29-5d26-84e0-9d9c08222d72	S0000000000000022	SEED0022	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e5eeba7f-0cd9-532c-a803-51db158829f3	dc82f629-7f59-594f-8d92-0825a2037d75	S0000000000000023	SEED0023	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
874f1f28-40b8-5863-8c48-4fc59d185841	8edcec2f-bcd6-5fb5-af4a-0a3aedef34dc	S0000000000000024	SEED0024	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
cb708075-7755-5b10-b9b4-1a13de5f26c8	475e45e4-b6bc-57cf-a63d-5481a41eb665	S0000000000000025	SEED0025	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
301c52a5-86e0-5e34-902c-ef357c1871c6	078c70f3-9945-5317-b9cb-dbd70219dc4a	S0000000000000026	SEED0026	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7cf33bb6-295b-537a-858b-cb371a0dc518	6532c83a-fb6f-517f-b6aa-aedbf45e9f58	S0000000000000027	SEED0027	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d2ebaeb3-e9f9-570e-98ce-609fef4564b4	bc529998-94f7-5058-96f3-836342680b21	S0000000000000028	SEED0028	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c3f63e28-3b35-5d80-b14f-97a7dcb71c66	e1fb0fec-3da5-596a-a7c3-21abc8151bf6	S0000000000000029	SEED0029	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
598672b5-ddd8-558d-b476-b0cbd270d84e	153416ff-4e01-5841-a7da-b205eea54021	S0000000000000030	SEED0030	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
00b47839-23b6-5c71-8d42-afab163ebed2	95d210c0-b1d9-58b0-8aed-67b24c2646a9	S0000000000000031	SEED0031	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
81ffc193-d57e-50ba-a4f5-3e0e36638d47	c92c6a89-9abf-5c08-a177-bf51791d9f47	S0000000000000032	SEED0032	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
087c7d58-ce85-50e0-b60c-559879d69a24	1fa6803d-2fa7-5eaa-b01a-d232998ded29	S0000000000000033	SEED0033	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2a163b40-cd5e-5feb-b341-a454c0401f42	563e0739-240c-541f-8f4d-16bbc9d2a309	S0000000000000034	SEED0034	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b0dd34cf-637b-5591-b28d-f74efcf16c60	6b265c6e-a5e3-5139-be41-8852aa0fb916	S0000000000000035	SEED0035	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c7e3bf2e-baec-5fb4-8b04-f081d375e5ca	2604f74a-6aff-598d-a9da-7974c77af22f	S0000000000000036	SEED0036	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4f0631c0-1689-5408-8023-421056d4f368	3612e1ca-d209-5f12-9949-ac32ce2b14af	S0000000000000037	SEED0037	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
340f8dae-4260-5801-bd45-e6c30c69648c	76795c68-ca60-5f1a-b0de-b94e4b9e11d0	S0000000000000038	SEED0038	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1af48fa5-fa68-5978-be2e-ea55294447ab	17892473-2b27-56d3-85b8-a199914fab70	S0000000000000039	SEED0039	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9bef2180-0313-5335-9637-31f3dbbcb9c7	40f39805-a8b2-5fc6-a763-891ec56d488c	S0000000000000040	SEED0040	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
48297c3b-e79f-5d5b-9626-3cfaedf3b230	972997c0-3a0d-54b3-a9cc-5adeeb22e21a	S0000000000000041	SEED0041	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
82158d92-790d-56fb-9069-f19c60bd57ab	35e47ee2-9301-542b-ae19-ad79c69769a3	S0000000000000042	SEED0042	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
9f833944-5a95-5d2c-8c07-852b5dd2ee15	8af7208e-c589-5aa8-927e-c0755a06cf2b	S0000000000000043	SEED0043	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
afb41f01-00cf-55c4-ae12-edfbca7837be	f03fd9c6-4033-5ff3-aa27-357ef26d2381	S0000000000000044	SEED0044	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7f7beac8-8f93-5148-8fe1-c66d41346be3	67d51689-68ff-545e-b892-7ff948f95b18	S0000000000000045	SEED0045	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
14299018-bc8a-5198-aff0-ae5511370f58	da52fc8e-70a9-57a0-bcd8-a7ff2e7a1dbc	S0000000000000046	SEED0046	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
54c0ac6a-6530-503c-bf6b-358bf00084cb	1aacd4d6-1678-5444-8b29-4cc9266cab79	S0000000000000047	SEED0047	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
36980a83-396b-5c36-8796-fdd468e3f335	0bb1989c-8a2d-505e-ac75-39e872811b87	S0000000000000048	SEED0048	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e52ae128-9a7d-57e8-aaea-e4d1d44cbd5c	6d1da64a-6fe0-5a49-b86c-bbbd2955dd63	S0000000000000049	SEED0049	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ed02ea69-eacf-5050-809a-64c251923424	3e57c941-3d1b-501b-9d85-973c26c953d8	S0000000000000050	SEED0050	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6b117387-5da8-5729-bdfb-ef7697fc7533	84ad1483-9d1f-56cc-9a77-660c9b6e5949	S0000000000000051	SEED0051	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
676f2672-df96-5912-96ab-ff10a74e7599	2061498f-7daa-5e23-968f-dc57932dd828	S0000000000000052	SEED0052	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
87a4a8ff-4235-507a-b404-96be3db45254	e79213dc-09e6-5635-b5e0-77119b6dcb34	S0000000000000053	SEED0053	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
076a7b41-1f59-595d-a630-cca12b415b2b	949c5a87-faf0-5aba-b569-0ddb9bc6f196	S0000000000000054	SEED0054	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
dc404a37-8af7-5f44-9309-16e681230490	73c8ba36-5adf-5fd5-ae3b-b645f64770cc	S0000000000000055	SEED0055	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5f97896e-ee20-5da2-a5b8-d096911e6528	629167db-2c5c-561f-ae16-eadec3f6edae	S0000000000000056	SEED0056	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b56d529d-a1d9-561e-8fec-a7a183e5b3ae	f526dd2b-f6a7-5741-b2e0-252e132ffb06	S0000000000000057	SEED0057	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b1dec991-dbd0-5ee3-a2d6-37f1e77d424e	de0d38de-4cc8-59d0-92f4-d5b7983c3ad0	S0000000000000058	SEED0058	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1c385a04-370b-518f-ba26-f6c28ee9b35b	4ff52b83-4bfc-513b-858b-7ecedba09707	S0000000000000059	SEED0059	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4a12993b-b498-5472-b705-cd5ce1a5d3e2	5ec6ad08-46dd-5b53-8491-ce236867513e	S0000000000000060	SEED0060	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
22de3196-f8ac-5ab1-9eac-3f05d6b03ef7	76842e11-6973-5d16-b55f-9fefb0e0fc31	S0000000000000061	SEED0061	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5dc21e19-a4b9-5186-b53e-1df996df6051	d52a0827-374c-5e82-b5a5-06e93cfcb4a2	S0000000000000062	SEED0062	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5b7e2361-00fb-57f5-87c2-e5d966b11366	8c40de9f-e606-5edc-add8-b3ff331d0911	S0000000000000063	SEED0063	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
46e28768-d2f1-5f87-829e-8cb38b3fbb00	f8f9be2b-742e-5f0a-97e8-2ba58b6019ca	S0000000000000064	SEED0064	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
82141f9f-1f07-5a8d-8fa7-96fad289d1fc	4fe40293-bce2-5e7c-aa9d-2b67f5072cfc	S0000000000000065	SEED0065	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
3ebcfba7-3f56-56c6-ac76-743ae03fe5f5	599b0901-cbe9-56cf-98bf-94becfa492d3	S0000000000000066	SEED0066	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
558b2da0-1e34-5c1f-88d9-2136e4a9bd88	fa8615ff-9d25-5ed1-9953-cddb4f4f403b	S0000000000000067	SEED0067	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8ea53aff-d82f-5a21-9a20-44c8e13f06ef	edb5fa48-3fd1-5f7b-8392-67a66c888f59	S0000000000000068	SEED0068	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
45c336a0-d3af-59be-acba-8b9908615873	40cbdddc-db06-58ce-bfc8-fe5515f183ae	S0000000000000069	SEED0069	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0fb2a53c-772d-5250-9e7e-bba179645d4c	fc67775d-f9e3-59f1-9b25-0bda20414e11	S0000000000000070	SEED0070	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2278457f-b267-5a94-b6b7-93b14bb292b2	92b584ed-96fc-5bf4-9403-8e20585b2609	S0000000000000071	SEED0071	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d36036bc-e9b7-5c21-9cd2-15873c43a6bf	7a6e5c27-e66a-5a79-8b7e-7db17a201d72	S0000000000000072	SEED0072	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0f2cba2f-71d0-53c7-b36f-9437ce4420e9	3ed4c6d5-75d6-50da-a013-7a85716bb392	S0000000000000073	SEED0073	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
b87f8bf6-3b83-5ba0-9c7a-0948ed076d74	533b924a-6fb0-5c7e-a18f-91dfc7fcc23d	S0000000000000074	SEED0074	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0af2a3e3-a67b-5498-a4cc-d15470c06377	8f44d162-c9e2-565d-9c9e-30fa23a7b017	S0000000000000075	SEED0075	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
1f664c14-6651-5729-9ede-47e20ddc85ac	00cbef96-40fd-532e-9d9d-989eecc0243e	S0000000000000076	SEED0076	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
48c91971-ef3a-5849-9c5a-7f02dbad52d3	3d7248fc-9686-5392-a193-9bca6a05ef6f	S0000000000000077	SEED0077	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
4ae15891-4a9d-5f57-8538-d0af67c53a68	22403b61-01f2-50f3-80f7-d93eeaaad21c	S0000000000000078	SEED0078	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
61ef70ad-bd6d-5efa-8f09-80bf6daa4d99	7ccbe661-de11-5483-8fd9-6990ea61b4bc	S0000000000000079	SEED0079	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
454e4bfa-474f-5338-a48c-3e15f019bef6	880a4007-7176-52cd-8662-bb85fc42b40f	S0000000000000080	SEED0080	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
7fbb55d6-2f47-59f5-bf5f-8d9e6e3799af	11aa321e-ce72-5a0c-becb-16c5e5661a7f	S0000000000000081	SEED0081	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f65534f7-0806-5880-80ab-0737f3d9a9de	6c2ffd98-cc7d-5a51-b4f4-485e184bd927	S0000000000000082	SEED0082	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d8d75948-a3c0-56f3-8994-53f15010d4a5	2b49d420-496b-59ba-9b6e-df5a807c747d	S0000000000000083	SEED0083	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d3a1e256-d90a-50f1-86ad-1bfe59938cc4	9286c839-94d7-5698-91f5-54e62832bf0f	S0000000000000084	SEED0084	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c41d9eb2-44b0-5b1f-87cf-f5dc6810a1c9	a16bc619-6712-561b-94d3-36bbf476bacc	S0000000000000085	SEED0085	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
eaf6f4c8-c635-5fd8-a572-7d90350cf4ca	12e7f7fe-2240-5c8c-a8ea-de63b66542be	S0000000000000086	SEED0086	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
474b78b1-7bbb-56f3-aebe-e3f8c9e1fe2d	b17fb6f1-0973-59d2-962b-5e38be69f045	S0000000000000087	SEED0087	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fcc32567-3ce9-51ef-9daa-e47153bbe9fa	a95b55f0-c6a8-5e79-96e4-a16beb4c6e28	S0000000000000088	SEED0088	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
795134c5-c0c2-5729-be3a-2f7f28667a61	7b54ff2c-5266-5434-b636-2b7abe0472bd	S0000000000000089	SEED0089	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d65f06fb-9fa8-5c63-970a-eeb570bd46c7	9bc9d562-af93-57ef-b778-c9eab3baff32	S0000000000000090	SEED0090	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
148b68c7-8b99-5340-b1a9-5f162abce857	a5363fc5-2a82-5462-bd3f-afd2d6cadbf1	S0000000000000091	SEED0091	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
96cb9aee-d80c-5993-ade9-c56694ffdfd5	9a0d85be-f559-5792-a2ca-9c1ebdba0e48	S0000000000000092	SEED0092	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6a12cbf7-9f1a-55c2-b502-93a3665c046b	d40ba67b-e4cf-5007-a8a6-860ba130d5b6	S0000000000000093	SEED0093	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
78efa595-b106-59fb-9e2d-458b36c1fc7a	6ac97c6d-0889-5cd5-b9ad-9daf67115e43	S0000000000000094	SEED0094	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bc97d4c6-6e91-542e-a5cb-c92a124258d8	ecb3409c-39d8-5b3e-9805-ce476a1de18a	S0000000000000095	SEED0095	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0c99d49c-96c0-5ce7-bc52-7c2932a2f359	c429efbf-ee87-559c-8d13-059bdbdf0b96	S0000000000000096	SEED0096	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c0a55eec-f234-5df9-ad1f-fca1f1078872	79f3cded-94a7-53a6-89da-cea4b658d998	S0000000000000097	SEED0097	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6c8b0337-98d6-5aac-a5a0-19f52259f28b	0cf297dd-f807-58ae-855e-be1fe4fa3912	S0000000000000098	SEED0098	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
d3d2156b-96b8-5ea5-b6ce-fb4514e19844	d0d32715-14ce-5fc1-9afa-4aa73a145ce1	S0000000000000099	SEED0099	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c3660d5d-851c-5a2c-8ca5-25fa72601ccd	8c4fe118-3953-5fff-a4cd-c0972e62cf8a	S0000000000000100	SEED0100	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c908ffeb-0750-5c41-a740-2c2ea8bdf4ad	80bf95ff-9973-508b-9e4c-4448d6979561	S0000000000000101	SEED0101	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5983b50b-85d6-52c9-93fe-9b08dd96a84b	3a015a81-56c2-54c0-8cf4-11b84411a0ab	S0000000000000102	SEED0102	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
e1eec2d0-bab3-5587-b831-47660f8e581c	1affb879-d86f-57f4-b3c4-c85b191c8fc9	S0000000000000103	SEED0103	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
baeea6b6-c8ed-5a69-ab38-632d9cec1216	2e3822ad-e19a-5815-91f5-005547e08893	S0000000000000104	SEED0104	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
749e5a28-8fe7-5f72-964c-b6e44b5dcb4b	daf78796-8816-5ae3-b5b0-d327e03764d2	S0000000000000105	SEED0105	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
f83dbf5f-280e-5c88-8f7f-eec54375cd8b	1be2026f-a49c-5ca7-805b-aa1de3a5f349	S0000000000000106	SEED0106	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6956b195-3c3e-56df-b3ac-e79fa36f801d	f948ab66-1616-5de0-ba37-7851129dfa44	S0000000000000107	SEED0107	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
fb9b495e-f72f-50a3-9ca9-0cbe3855e8ef	6fcb75b2-5105-52b0-ba8e-b19767927261	S0000000000000108	SEED0108	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
19bbf5d8-18da-51ab-8f09-02e6d473579d	e04ad513-ee6a-5dd8-8204-59a5ac538927	S0000000000000109	SEED0109	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
48633a3c-7d06-5ada-8784-b523079496ab	b155f7ca-0311-5ae2-9775-20a123db0d35	S0000000000000110	SEED0110	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
c022c054-ef90-54f8-bba8-08693f4e96c2	8ab22659-36a2-57c9-86f3-10cd9e0134ff	S0000000000000111	SEED0111	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
73002e50-f50a-53aa-9191-0bb4eb444b02	9a77a403-73c0-5634-bfe1-c67323ee601b	S0000000000000112	SEED0112	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
72c51ed6-2cd1-5fa8-a9ea-d860b9b0a22a	13f62a96-ac31-5ea6-98f0-e73edd54615d	S0000000000000113	SEED0113	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
8ffd2db9-9bd8-5efe-9691-8284d825510f	a329fbb9-bf4b-58ca-b306-a030c02851f7	S0000000000000114	SEED0114	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
0c8f8169-bfdf-54fb-8575-a700f29ab2d7	28ccf436-cbad-54e8-9eb8-7742302ee14e	S0000000000000115	SEED0115	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
bdcccf42-d731-5cf0-96b1-6ed59d8921ac	4a2800af-46ff-51a1-b8fc-e1a248b97793	S0000000000000116	SEED0116	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ecadb2f5-ed1a-57fb-8289-75c49be85e6e	e8ecd6e0-e0fe-5722-a345-508e2e6c3b36	S0000000000000117	SEED0117	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
396835bf-0cf7-5b79-a700-be4d40a266e8	882cf7e7-9e39-56a2-a474-9f313bbf6097	S0000000000000118	SEED0118	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5cede4d3-3e59-5655-9c97-6c2d79b21344	068e4c89-6f3f-59fc-a41b-fdc12cdc78a2	S0000000000000119	SEED0119	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
27ba957a-7da4-5def-b341-1b7515afca1e	dc5114d1-aa50-5995-a1ab-40223403a1a3	S0000000000000120	SEED0120	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2e6771ac-6ad8-58a5-ad82-c93c868afafd	a9e5a060-3b39-5d45-85d4-de0566386b46	S0000000000000121	SEED0121	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
98880eea-bce1-5616-941e-46e9563e4f37	700519e2-3e29-5d26-84e0-9d9c08222d72	S0000000000000122	SEED0122	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
6b7ab6c0-60ed-5db2-8cde-22a29b459a30	dc82f629-7f59-594f-8d92-0825a2037d75	S0000000000000123	SEED0123	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
a5dab888-eb34-5f5a-a41f-ac6e4a1d54d0	8edcec2f-bcd6-5fb5-af4a-0a3aedef34dc	S0000000000000124	SEED0124	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
be0f160e-4c98-5f87-bba0-cf1000635670	475e45e4-b6bc-57cf-a63d-5481a41eb665	S0000000000000125	SEED0125	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2c52f3f3-2218-5ef9-a0d9-85cd904a1b37	078c70f3-9945-5317-b9cb-dbd70219dc4a	S0000000000000126	SEED0126	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
5dd576a4-66c6-5be5-a7d8-cc349ad3a88c	6532c83a-fb6f-517f-b6aa-aedbf45e9f58	S0000000000000127	SEED0127	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2a794b09-5d1a-5703-8179-47a6c2713e94	bc529998-94f7-5058-96f3-836342680b21	S0000000000000128	SEED0128	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
ea16a435-78c3-587c-aacf-e03596a2a5d7	e1fb0fec-3da5-596a-a7c3-21abc8151bf6	S0000000000000129	SEED0129	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
2e5dda75-0cab-52ff-a79f-a03102c0d0a4	153416ff-4e01-5841-a7da-b205eea54021	S0000000000000130	SEED0130	Seed	Fixture	2024	2026-08-01 00:00:00+00	\N	2026-08-01 00:00:00+00
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.roles (role_id, name) FROM stdin;
00000000-0000-4000-8000-000000000001	superadmin
00000000-0000-4000-8000-000000000002	admin
00000000-0000-4000-8000-000000000003	user
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.schema_migrations (version, dirty) FROM stdin;
1	f
\.


--
-- Data for Name: user_roles; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.user_roles (user_id, role_id, created_at, updated_at) FROM stdin;
f958c7ac-a1fd-591f-af9e-101982236962	00000000-0000-4000-8000-000000000001	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
de3fc427-7abd-5d51-abe4-90fc696ff338	00000000-0000-4000-8000-000000000001	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
03c81075-da30-53bc-8ae7-51c4548432bb	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1af5a5f8-9757-56b0-ba95-0c8643f0e43a	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
677d2eb3-d9bf-5993-8d37-37841aa36441	00000000-0000-4000-8000-000000000002	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ed13e8e3-7703-5989-98bd-610dd497c246	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f85b4a3e-8c11-519f-afcd-a1c41bb4adb7	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0f10864d-3c5d-5ffe-b46c-e52b088234f9	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
47b464d0-f951-51c4-9be7-52839e6b8ac1	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ad31ce73-53b4-59f3-9de2-1665bc9dde64	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a3ca678a-d322-5dd9-8e1e-1519a770a274	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
106008b1-93dd-5e9d-9c54-859a203d7618	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
caa71961-224a-5f01-bb65-78ed8fc80398	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
08940432-709c-5295-a2d7-b5e35c738f29	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7eb58973-c7b4-578c-9266-4128162fceed	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f473874f-a60a-51a3-99e2-0f8502640ba0	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c45cfb57-49b6-50be-8bd3-b523c6c24cfe	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a83f5d58-18ee-5bd3-8672-b552ae57e554	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e4cc80c4-7ffa-5040-9b94-0ecb109f7215	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dd122c26-5379-564d-89ec-8a750946d464	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
3ae0ec68-7085-58d2-8f8f-7d7c20adf12d	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
ddf58e35-4fa3-5e81-81dc-70baaaa7ee21	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b0daea7a-227b-5429-ad13-595e937835a4	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
85384d9f-b3a6-57e1-a0d2-830e377cd2a4	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
57cd5649-9664-5509-879c-6b7706527c98	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7bdb7d40-e721-53be-991c-408b90e62b4f	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
afaac000-3f8c-5cc7-81c0-7dd3b33b5322	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
86082c6d-f6ce-5691-b46c-16c8f4ce3003	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5062875c-b0d1-56f9-a950-fd0ba0766204	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cef17b64-2d8b-5f68-8cb3-2e4f23535f72	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a9a2456a-8d3c-5ba7-b057-10e92e727fd4	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f5f434cf-0e86-5c1b-a095-3a305cfaa506	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c9bf0ee0-8be9-5f59-95c4-0ef3fa3a6c00	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1a754f12-9ac9-59c0-8d3d-9b7471e2ecaa	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b37baa2d-b1b1-5701-aef4-fafcd4ef9d02	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5756905c-68a6-57a4-9479-da4b99044bf7	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e56f779d-6c24-5365-af11-87916cadee0d	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f50679c8-e072-5a01-a83d-cccd1001a47e	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
09fe0421-b613-5972-9a02-375121cd2eb0	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
d93d7258-0326-526b-95dd-221400877201	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
72a92aef-fb11-5df1-b776-4559b0403e65	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5db5f3cf-4a66-5358-887b-7352b8486559	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
22b1b4c5-8080-59ab-8c72-0e6754f9fd0c	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c9818417-23b0-5824-a9fe-2424d9dca93c	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
1ad786ba-141b-5426-8548-9c08d2ed8cca	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
100eb798-0e4f-59df-9eb7-8dd8a539396a	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
5e556e92-b7e0-51ce-90fb-71cb14d5f7ad	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
4dba136f-ca11-5746-b71f-5206f01382c1	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dcecdc95-00f7-51fa-af11-4c47b3e977e0	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
52f6ac89-8849-5d74-8205-815d7571e25d	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f455e858-2d88-5deb-a0dc-3b6ba9c0d912	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
da9d869a-114c-5dd4-b73a-4750cf55e7f0	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cdf01099-5c7f-5671-85a1-04fab47c361e	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
f9b4676e-3cdd-5ffb-8e66-a0e550c27f2f	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
b51556d8-a2d4-5587-9d54-18b68389f2a4	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
bf147955-4682-5721-a7cf-1fe10af7d033	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
dcc2db75-b19f-595a-8029-c877fa908e8a	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
8739fbcd-95b3-5bc2-9258-ab217b9e3bbc	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2e8f4dfc-78d9-55c2-85b6-beb955113f73	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
2ec9567a-0bc8-5b46-ab01-f62f38a1be62	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
00982e78-df72-5461-b547-6b1cf267e21a	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
821a4660-9ef5-541c-b390-884a0fe6e419	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
e4d6a0e4-b2ff-50d3-8aa9-b7179b9de310	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
cec08e97-8ca6-5e2c-87f6-f1af809b4d46	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
acafcd06-d332-5699-bfe1-0e96fa0a9f8b	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0020b47c-0af6-54af-9af7-c8fdf58759f4	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
de6f81e7-7225-5637-9286-d8f4474d7785	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
a5a11267-a3e3-5de1-92e5-468c1c060b31	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
423721b6-4a46-517b-adee-0b777c04cea9	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
eb360fca-eb96-5e3b-8930-72b395834212	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
79d049ea-c4f8-5c15-9b9d-73fd28f1699d	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
eac738c9-85a9-58ba-ac93-3a884bbb5a12	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
0c50b446-f2ea-54d7-9ea2-bb42d78c175b	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c3299ed5-eca3-598e-a27d-6995a26850c4	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
7a7f6ea5-eae0-56a7-8170-19f63df36eac	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
767fed37-59e2-566e-9176-b86eb3f9e6a1	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
557f77f1-0005-5160-aeec-844e74cb1d48	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
57442b8e-30fa-5be7-a8d2-97a430faf00e	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
56aebc4f-4fa9-5285-978f-535055a22403	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
c410c3fb-090d-54d0-b028-266594143b70	00000000-0000-4000-8000-000000000003	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.users (user_id, full_name, email, email_lookup, email_to, hashed_password, hashed_password_1, hashed_password_2, token_ver, created_at, updated_at, status) FROM stdin;
f958c7ac-a1fd-591f-af9e-101982236962	Seed superadmin 01	\\x6726e3e212a6c32b49bff9b369a720ba3f50efb40a7adfdc806543abeedcd639950a1807c632a3553ae6	\\xc7b4b6a83429bcf95918c6dbef3a35f0d3b65f9ac5f84fa5cc68985d378b3647	abc1@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
de3fc427-7abd-5d51-abe4-90fc696ff338	Seed superadmin 02	\\xf408203832c452321f0f63da4b03ac6b8f108272b1d075a3ed26e31c3b7dd6ab34940c13545a3283cb1b	\\xeb6c8e3b3a1569d0f262049005fc90e0c3fe0fcc3e8736fe3e43813d2aeff3d5	abc2@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
03c81075-da30-53bc-8ae7-51c4548432bb	Seed admin 03	\\x7b1f4244b68d26e21aa9d23a968d9d0752487734728bf94513551c33d08bb67a90d86f3f01db78b8ad6a	\\x95f0f36aecdf6a4c99fdff14fc8491778ee8532b6e04e022f946c4f91a91fbdc	abc3@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
1af5a5f8-9757-56b0-ba95-0c8643f0e43a	Seed admin 04	\\x7536d6a3f4afe6f72d52968664d4c4b08efaf75ccc9f358cf01dfb646063757d91fb12f0e67307fdd0ac	\\xc63aff5b7c55d8d676e46d5f78d2ed2133fde7de7519702a0143c0b1edcb960d	abc4@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
677d2eb3-d9bf-5993-8d37-37841aa36441	Seed admin 05	\\x062e3bdfae37ef4457c78be3c5627b5f2320962f0de61554977e6f27b3395b3c9e517fca00d8083a227a	\\x746e50556f58bf281a703b87c7134228b8cb43a28d08e30f191a59b7616b88c3	abc5@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
ed13e8e3-7703-5989-98bd-610dd497c246	Seed user 06	\\xc6e83bad9ea89aea7672bc7c3764c8254d380594d2df2cf119ecfc45664a7623588d43bdeb5a4ef24b8b	\\x38004643914044ffcd18c11b8c3849b495c306c77adc1200779d959c1dcf7f41	abc6@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
f85b4a3e-8c11-519f-afcd-a1c41bb4adb7	Seed user 07	\\x92af8cd82ab3fb60a113bf5c6139a00c3e0c44cd04e9434ad343bda97bc4adf39a6f39692e7ee6910a4d	\\x84d30b8066de19e277656b6d11f6324aa4477d7b2b289cf9a889f185bbe5bacf	abc7@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
0f10864d-3c5d-5ffe-b46c-e52b088234f9	Seed user 08	\\x28da0e94b9d00ce2562b763e714eea47af913d94e5b2eff59a37edefe9d90e891335d60aab5bf982dcd4	\\x8be3cbfde10e42f94cfcc7cad74a9aec441684bb3ac4aa987e7c8fe9afe76bf4	abc8@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
47b464d0-f951-51c4-9be7-52839e6b8ac1	Seed user 09	\\x1869ab0be3d10b539870f49838947e853109fe646f3952d7a0352dada4cf86849b5275c020c94fc4ccb2	\\x9494a91d1d970af96d92c7d270d5cf3e7d4fb24b0ca512d6914c79c09b707aba	abc9@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
ad31ce73-53b4-59f3-9de2-1665bc9dde64	Seed user 10	\\xbc9b7ee3d5f9815530e1666d46dba0941ac82e49c0441938dfcd5427cd9843e816681a6864f045b9cb98d0	\\xe4b31e321298bb7c79b42c40274c91c933e899de2e5e89ed35c9229102c713bf	abc10@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
a3ca678a-d322-5dd9-8e1e-1519a770a274	Seed user 11	\\x6123af256363868d83d833b64398bba5367e80d9790195c96f4146668f47ea67fa0d5e8432605a67f80e59	\\xe1529d5a6f17a165ec5b953123f81c5b4d3a5ecd345edd71ed146138a0888ff8	abc11@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
106008b1-93dd-5e9d-9c54-859a203d7618	Seed user 12	\\xfca6bf672fd399ef00b646a0720caae12d4e2ec3af1968e2c6a9083ff88b3ee49135138044950da0672a89	\\xfbe7968e363d5ff0b748a2d4708df9af92a98384a4997ace09142abb8fffcc35	abc12@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
caa71961-224a-5f01-bb65-78ed8fc80398	Seed user 13	\\x4e9e10f4a6ebe9b7b569740df16816f8b3a943a4cbf5c32064918be92f78473ec0925091d61b506baf075d	\\xe4def7e406445d646cfd1d8b4c1379ced187ae141fce04ea55c804ffef617e72	abc13@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
08940432-709c-5295-a2d7-b5e35c738f29	Seed user 14	\\xacfbb255060641dce95fba49ba989a1a166cf40445ce3c39f04d6b8d73c139405910879a77e95580a9f311	\\xd84fa2c15b8bab3f2581044338ba7ffff5995d90c40db1d3b71b88d4daabb6e4	abc14@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
7eb58973-c7b4-578c-9266-4128162fceed	Seed user 15	\\x47a0fbd77f94d576900e32735fdfc1b52e1f33d4ded6d740780043e908a7f8c707ad0aadae86ad4df750b7	\\x96a71a8041b34d1ea0c500fef2cf40195cff14551aa80c93c614ffb318ff0394	abc15@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
f473874f-a60a-51a3-99e2-0f8502640ba0	Seed user 16	\\x5e26e866b7b4993a869550b476acd5d77df4a5af1cf295b82af39c402a636b084e3774c9ca06b9b9b4bfeb	\\x51c96a1181c7b447110027318f0ab033502923b25f7b0f6b72a6e55234d94571	abc16@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
c45cfb57-49b6-50be-8bd3-b523c6c24cfe	Seed user 17	\\xe68e3b344b1d7ad9785dce69b6632458c9a88b8a5d2cf7b39ecea8b0d03a038847cef0b63884475eefc13e	\\x229e4f452e50432ba307a83b932378d969d2638f07e145fa0969334c80dd9304	abc17@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
a83f5d58-18ee-5bd3-8672-b552ae57e554	Seed user 18	\\x4f74a4d70427b509ff0ba0a272a2febdd182270aaa34f109fdcb11347118afdc94cc60a42a5efda38bff12	\\x19c98f7b74d4abb56eb7811d87dac4cd17d02685cddb96ddb08dff2b4d5d8ed6	abc18@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
e4cc80c4-7ffa-5040-9b94-0ecb109f7215	Seed user 19	\\x9016fe7ed9090da240b0e099ab3bda7d4acd73da5a590d43c3e9877f6a2a0f1b64302354b4ec187c80423b	\\xbadf0af4aec19186edcc68ec3889e53036b2ba145bc89e984eb59f61e604784d	abc19@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
dd122c26-5379-564d-89ec-8a750946d464	Seed user 20	\\x625f7a7e70b90be287d982639f6d77c56c6ecdd9525dfc2d112d7ea8c7f780b841c62960c391a226527070	\\x9073a9879eb4d7e57203183b875bad24f8e9a85824b16560fea2ad48fcd6adde	abc20@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
3ae0ec68-7085-58d2-8f8f-7d7c20adf12d	Seed user 21	\\xf8caa21372b921e3bab35f314b8aa5981d15ad8da0c3caa6ab368484c80deb8be2aeba7b70e080945725eb	\\x0c35883912298c89daab3f56a4981b402344819c741f125c78053d0fcad4b950	abc21@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
ddf58e35-4fa3-5e81-81dc-70baaaa7ee21	Seed user 22	\\xb3405fe047064e04a82b83a64863eada73c96a8d79607a08fd21e86e0c0b4d48657069f26e8d5380519adf	\\x5153bcd533f993df55f9a03d444d338d9a4c25608b50a36a5bd08fbd64b6275d	abc22@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
b0daea7a-227b-5429-ad13-595e937835a4	Seed user 23	\\x91802a34a7e8fbabcc49dd84bdda7a83892a0d83a741fc896b7492d52ee295007219430853e8b3d68ccf85	\\xc857fd95046bfc76e5b4a06c0068a619144a550c2ea70d770da4301ae0b96959	abc23@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
85384d9f-b3a6-57e1-a0d2-830e377cd2a4	Seed user 24	\\x0c7e048d2c71c4251bbe053584709c8e7b054c5ab6761fdd43546a53b399e01c9745d361b98e019a448a88	\\x29e06ca689461d9ec2a8073619cc0c95e25ccdf500dfc5144b974928a8fe2743	abc24@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
57cd5649-9664-5509-879c-6b7706527c98	Seed user 25	\\xdbeba5d9c856c51eb8be5c245e347261662d747809b8d49523a324355a2eb66ecda95f47ea18ae319e7452	\\x8f1b528ffe35d34542300faeedfbbc06bdd814edccda0064706b031dbc78bb8b	abc25@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
7bdb7d40-e721-53be-991c-408b90e62b4f	Seed user 26	\\xc7fc447b37f774d4aa38a3901bd9d84990a2c84557d17293641dec919c06fd41f794c1aabd1932014aec08	\\xcdfcc6dfd33192eba892dfa23038933a158acd961032f8cf0167afeabc7c5cad	abc26@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
afaac000-3f8c-5cc7-81c0-7dd3b33b5322	Seed user 27	\\xd1560d091b4bb2e13469643c7725765adc2b0bacbf962a436ff717fcdbd4487ca12b622fc57cbc0785cd81	\\x0bbe176f455234d33e8aa5eb30b6c798db33686f6d6947e919897074264b5952	abc27@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
86082c6d-f6ce-5691-b46c-16c8f4ce3003	Seed user 28	\\xc81e54c6106fdfff4ec9389b5a5e77dc5d3696f8342d655418efff14557d91e0d5e80cddc5e4df9b825f1e	\\xb72c27d58a0adcf49f982b56c95150b6631a075789f0da50113d043b221ae721	abc28@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
5062875c-b0d1-56f9-a950-fd0ba0766204	Seed user 29	\\x7d1cea799a8c85a16feac44efc4b72bd818dc4b4ae5fb14687432e886a6ccf5188e75690f3434b6aa346b9	\\x762be21780398150767afcbc7fd224b1ed13294fce7a494f98fdd0c804cacd18	abc29@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
cef17b64-2d8b-5f68-8cb3-2e4f23535f72	Seed user 30	\\x96019ecae74d52e3e42d46e54a15f31eb262a735884b88427bb72ed56d6ef1961873d3c3a8375f18833d2b	\\x3b0a59330c0e384625d185befe163b62f17c5ddb41e479f09da07d24c3c3c239	abc30@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
a9a2456a-8d3c-5ba7-b057-10e92e727fd4	Seed user 31	\\x7a5756873fd3862ba74a30fc0262a465eb7da1528480c8c6ba13b9583d2331e19f969e583943fba0f0b2cf	\\xb9a57f6d66f2534b3552774e90c1ca87f712f8c3190dc6f30d4e23bd5be25826	abc31@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
f5f434cf-0e86-5c1b-a095-3a305cfaa506	Seed user 32	\\xeedae1039e9aa200c5ad44d8395836f572644f8f5e87af93f0e8f813654eff90c9b1036ead15c7ebdb696c	\\x4d6e16610a5d932e45e882b3df610f39f0d01822b2e4d9e6357718072917e280	abc32@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
c9bf0ee0-8be9-5f59-95c4-0ef3fa3a6c00	Seed user 33	\\x95e9519cbfd7c3bcc2ceee4c5c6936547b6072506b8457ce3889914e8ce1b82c301aef33d09f6ac1425752	\\x8f5b00c5964973b072f920b5474eaad89d3446b6831affe673c7f7532a8d362c	abc33@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
1a754f12-9ac9-59c0-8d3d-9b7471e2ecaa	Seed user 34	\\x060c7799f7a7d8a2bdee885fe5b94dd81032600d1d45565e18e198ed30aa984eb4818bb9aa0cbbda69fe28	\\xa8d5fde3f28fa36f8ef0e91984f5353656e0309852f07f5bba7bcb8136f797ae	abc34@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
b37baa2d-b1b1-5701-aef4-fafcd4ef9d02	Seed user 35	\\x6a03201e2cbc60d12aea33f3a771cf0798bd536e8325524a437b55e9cdc8047b42974c1b49944ad4de672f	\\xe820a459141dc3c8cdaef1702803bc70ff3c709ead90eeb8c49e55bcfbc4d0e6	abc35@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
5756905c-68a6-57a4-9479-da4b99044bf7	Seed user 36	\\x3847b26f675528bc6027a2c2512723b5f9ad536cc3e51764c9410655e0bad4f6e123e2022efc8f08b3e569	\\xaa0567f3b2e4e25ef29666a25e3d33b0b7b67f3517151557cf239f226583e4ff	abc36@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
e56f779d-6c24-5365-af11-87916cadee0d	Seed user 37	\\x2fd90926926d71e18c9e5f32debf759c1de686d4e2b997172c0b8f4f7efc9ae36f26ed9af7c744a64b434f	\\xa710e959f8ef83357dd39e534a890aae729c035c1de5508a1a5c83c6c969af68	abc37@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
f50679c8-e072-5a01-a83d-cccd1001a47e	Seed user 38	\\x871ec302f192df408a34e4f78b21d889e1b50f547e571abe35f2da982a1b93746854feb2dc54693e055b5e	\\xfca783ed962277beb1d762a2be1562afcc74966b6d0153b5f03c1c14cf32b42f	abc38@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
09fe0421-b613-5972-9a02-375121cd2eb0	Seed user 39	\\x42ef57a27ca225e5e39aac818873e72cd016878a98acbc18f7a1d09d97c756a475f5f19367be3312478698	\\x09466cc0157a4ee4ea88a8af73879173154840f63fec0cc3cb15d827fe76a903	abc39@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
d93d7258-0326-526b-95dd-221400877201	Seed user 40	\\xc5b763869f8639604b4707af3f1b219d5687530b4cbab00c1d1eaa5c8637c20338ea796b4aa2f41446be09	\\x358a097eaa1eac4e2f3c63e705e16f024ffbb330fe3b4ca294d1d72d55f79eb5	abc40@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
72a92aef-fb11-5df1-b776-4559b0403e65	Seed user 41	\\x7bb17c7cd3d706a65274a69f9f8a36cf4ff2181f415a0c278a16216e44a025d30c09e96d3c5d710cde2c2f	\\x0390bbae4810cc3ead8d48538c56a9db1834ee8cdc4e8a6b4566bc1c6eccc4e2	abc41@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
5db5f3cf-4a66-5358-887b-7352b8486559	Seed user 42	\\x45c7285bbd44e72c092df1b8fa4dd2f42c78d60397f7f28e45344474c40aa0c4c42288923fd2d8921269eb	\\xf2aebbd9aa6b5a47afab319507b46bcb219359b47bd31feab397859a332f4fb0	abc42@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
22b1b4c5-8080-59ab-8c72-0e6754f9fd0c	Seed user 43	\\x520531745f6dd568548f6753d4ef49b75b9641858ba418ae1a225571dd62f0787cb17ac8dfcc7324e9275c	\\xcea4b601654d2ad7d8f53e22048e4461d6d3eb29dac3d19c380f452e3d304b60	abc43@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
c9818417-23b0-5824-a9fe-2424d9dca93c	Seed user 44	\\xee5c98c0950dadc2a9e0eecaebf665daac9d601a6cdc1de9cc761332f05caa9f173f7dc056b6290572d865	\\xe84050a618d25b6fa1dee4eb910ce4eed9153ebea12126c02196315e0a86d470	abc44@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
1ad786ba-141b-5426-8548-9c08d2ed8cca	Seed user 45	\\xf279e76e06276633c32024453985334017cab19b4e1e171d5bda973b1eb0d5be2061368bf2a89c74f7c63c	\\x96b024c131078277e5f136fa3434ced6e460b31adc6619987882dee203ff25c9	abc45@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
100eb798-0e4f-59df-9eb7-8dd8a539396a	Seed user 46	\\x60b171afc68ed5554b0cbc6b177a687ce8c9e85dff5077a8d3dd57117009c90b22325a9f6c0d8adaf8bddb	\\xad8c7f8a604d7e030b10bb0c18233d4b2603a38934ff58b73c49861530a60c77	abc46@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
5e556e92-b7e0-51ce-90fb-71cb14d5f7ad	Seed user 47	\\x276940322166dd221f4ab011e818fd9d47ea707165cc81db204d7fdf178cf5ccc9b115eb71780528f91778	\\x7b52f0f666aa534c51df7a3cc2435d133827c055c53640dd5922305de39fb21b	abc47@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
4dba136f-ca11-5746-b71f-5206f01382c1	Seed user 48	\\xb9e3b1e5b044e2f9359ad5f2ade4d9a4b85b20117dc135c43566d864302b6fbea475493cc4b7a62413bf00	\\x665a573505740c538342039ab5d66b239199225517c6d494d10e2c4e65998d29	abc48@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
dcecdc95-00f7-51fa-af11-4c47b3e977e0	Seed user 49	\\x0632209990e7087cab6b19c8b4454bbb30156e59ee9cd29046f9baecf004632d4339d786c2ef19c08ad7a7	\\x238d4d576b739d57243c79c4473d7dc5a002423720b588857dbe8d5c7b153f1e	abc49@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
52f6ac89-8849-5d74-8205-815d7571e25d	Seed user 50	\\xcbf3d01ffb38288fcda0cbc8915683f147567e30408918d1fbb28ab7bb1698ea8c27bcced5e2541ec7b1a7	\\x89dc3571de54f1d9ba0b9eeb29ecdc858e2e973bdab2c515d18fb0fe1c913a87	abc50@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
f455e858-2d88-5deb-a0dc-3b6ba9c0d912	Seed user 51	\\x35f0067ed06e84924a1470ad30f58f72be049c0414e3d362b4ed8350e6b4711124a12e5b3d87275e739563	\\xa943b18aebc61ee1dd0df159559090beb6b13bcd1a350eecc65afe1d9a4e7bb7	abc51@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
da9d869a-114c-5dd4-b73a-4750cf55e7f0	Seed user 52	\\xa6acc07c7b6305eaedabc0dc40921d34185c228f27570dd1fb90a93633183a37af1fb93f7e23e66d8eb099	\\xbebe23041e90404e4823e2a61c849dd70551bfc3e136165b8806e0472089c641	abc52@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
cdf01099-5c7f-5671-85a1-04fab47c361e	Seed user 53	\\x91b85ff4c6c92aff5e2530f4dd031593680978e730a9fc47fe8c65148cd43f3cfcf30614f3de5cc3b3ef33	\\xb529e0109972a8a10dcd78bd4e90b0c229542d058cd42c2f4eebf70fee3301c0	abc53@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
f9b4676e-3cdd-5ffb-8e66-a0e550c27f2f	Seed user 54	\\x9a30f763242a5cda21bf309d3100fe270b477e47bfe1e5fdcf07301e0f2347813bf9b782cd7eacf467dfce	\\x79ae11d418c413d00b8c69e62e4620c8b12e85110f9bc385c992bd51839318a2	abc54@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
b51556d8-a2d4-5587-9d54-18b68389f2a4	Seed user 55	\\xd6801a84af82decd16823f43c722de920eaa693f014e971d44988aa79d9dcc5f2f5aba958dc093fab12533	\\x9b316c666a8490040787b494893a70abce9246b6091870417572a6f20cb7d2dc	abc55@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
bf147955-4682-5721-a7cf-1fe10af7d033	Seed user 56	\\x09610603bc5e47130def8325f89687992c8088ad1637260238c0f793b45829d669ec61e624ee260a166007	\\x314545aefcf899779398e92911add7bc045f6460f8f954dc4d04aab12097310a	abc56@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
dcc2db75-b19f-595a-8029-c877fa908e8a	Seed user 57	\\x8127cd6f7ee0192a332667e1199e3070182646787622d64808fd4cccbef32f8e632d7bca46ce06110e6d79	\\x9590182cd1f7813aac9416d521d7010e18aa62b1a02419c3c545a305407578f5	abc57@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
8739fbcd-95b3-5bc2-9258-ab217b9e3bbc	Seed user 58	\\x3c0e40b2bbe525fc30320002748a8ea0b0f92e76f271495ad5677ceb103a6ae0e25172d93e43013ddbef12	\\x3c3377533a658091b9a1619592a73752d238315e7520879994b656f4eea08473	abc58@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
2e8f4dfc-78d9-55c2-85b6-beb955113f73	Seed user 59	\\xf09416100d7a33d5eb8ba9792a6ebaf1857d1804fd63db331af0939bafc5a80ea53500f37a91be7498c5c2	\\x82bdab253cc42ca4683b28856ed75bf0b2dd78c32950513ad1f5d50a0bb49d87	abc59@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
2ec9567a-0bc8-5b46-ab01-f62f38a1be62	Seed user 60	\\xb7f9acda114fe5a2e0fa8298583d7b81c2c324e1d49f394a151a53de2b06d282bcac7bf699c7017bbe8aa2	\\x753be71769cc0a27160ad00582011b7886487ab2b31bede87bf5335f6f3ff8ab	abc60@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
00982e78-df72-5461-b547-6b1cf267e21a	Seed user 61	\\x1f9ceb47bc4000041e1e18d850e0b1b349f28fcdfb9ccba147020960d7626fea990a25ac7c5d4aa08ab67f	\\xaa02d3ae47fad970f97bb545d2a591cfac9ba31556108b429d3b073994f8a1ab	abc61@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
821a4660-9ef5-541c-b390-884a0fe6e419	Seed user 62	\\xd5c0508c666081aaba77346582cf9f5871fead60ac9d18e5910c0f411e7865243d437409a2327662451ea4	\\xd87edee4828255e282bb114f71af322b6009ac3a90e4972c995bd8e7d22bb80a	abc62@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
e4d6a0e4-b2ff-50d3-8aa9-b7179b9de310	Seed user 63	\\xf2914815bfc44e41914f78dee3ad0823140859bb461de8b96afeee903871b5558a2a56f5969850a63544c5	\\x7f5c4a510e2914b2984d74b31d81d4fc508311eb43949e92e6227cc081c8eb49	abc63@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
cec08e97-8ca6-5e2c-87f6-f1af809b4d46	Seed user 64	\\x441c2c0d3b76bf2642f22135e0aa952e41b54adfed9080827f9d48fdbf7082d4cc0110771abc4bf00a1f0b	\\x2066f4bc881f8de50029cd77c2918637d34df15b9570fcfc1104990c91956bd5	abc64@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
acafcd06-d332-5699-bfe1-0e96fa0a9f8b	Seed user 65	\\x04dff3fd9eed1f5d5a9743036dd937b90003f2b7c8d50b6f8776f5cd5c8c4c327712af47d9e92cedb4d692	\\xce5dfe3fa348eb5f549b1046e474a090223c470a345b5e0bb88146014a55fcfb	abc65@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
0020b47c-0af6-54af-9af7-c8fdf58759f4	Seed user 66	\\xc211cece22137de3789fe6f765b79da4d45f5afdf3a36865c4d4ab08d5b188e1edd083b8fc714904af59d9	\\xc5f2cf38c81f2e77614ae6a4e3a8cf141efec7f4902f995241e3bde7d9786bc5	abc66@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
de6f81e7-7225-5637-9286-d8f4474d7785	Seed user 67	\\xebe39d70ad087fa36f0aeaf477f153708cc0d472563615cc6c877867b080e0b88e36b74a06bdca6176bee7	\\x7c4fbb8d60e5cb17cdb2ca8b15f308237bc45364d4e1963fd5a805d51e2bb7d7	abc67@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
a5a11267-a3e3-5de1-92e5-468c1c060b31	Seed user 68	\\x07b34f004938c46073b7b4fb7f9f4087dc83fc1b78d4aed2b156967738e21bae445ef10bea8b906c05be98	\\xd7044d5a538302598bd1e2ac5c2c7c981b042780673a7ddaa4739f6e2db1b642	abc68@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
423721b6-4a46-517b-adee-0b777c04cea9	Seed user 69	\\xcc1c76d0b442c9a0c93d2d4680bec4a108f2926f4bcfad733ab8ea885fcb0f38dcb9408038248b57faec9c	\\x16938cdc06865481d66336f8f91459326f793488cea98030eaca5705b3e20b7f	abc69@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
eb360fca-eb96-5e3b-8930-72b395834212	Seed user 70	\\x5cd082b88cf65e4e89162ccd051272b0b68f69d050a79404739956b01f2940bee9617b4c3986fbc1d7f2c4	\\x53335b5da793541a019c5735941dae30017b14f0c2aa9b3dc47a689b110cb669	abc70@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
79d049ea-c4f8-5c15-9b9d-73fd28f1699d	Seed user 71	\\x59809a761131613218501fb340f963a2c6ad0b28624a7a752d30097690a3105fe3e91007de1be3e5b501fa	\\x603bc18d28a589ca92e2f464ee419a11ea6a910410529af4a3d619738aefb593	abc71@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
eac738c9-85a9-58ba-ac93-3a884bbb5a12	Seed user 72	\\x0fd875ce1ee22269ae0782f41e5a4e463930aed774964af86b915537f47a93bc18ea2afa325f0640928150	\\x2c4e0b9d78d6d818ca44e8a926990fb141ce82188c22c4f0698d1666f255b071	abc72@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
0c50b446-f2ea-54d7-9ea2-bb42d78c175b	Seed user 73	\\x58c2703ab1697335088e6c3e837b648da494e05c4a8215c89724710d3108780b82eda1cd61e4f0ddf1be4f	\\x20c43e7160104d8d5a6ceb22804369895786388c12777a593cb155f994bde2ef	abc73@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
c3299ed5-eca3-598e-a27d-6995a26850c4	Seed user 74	\\xa2e45e4978426c2b9dcc52b661849ff00ef5c91a2cc5f89de36022dfcc5b8d65c63684db87a2c923da5f40	\\xdc3342d441fd05942a0bc713ec53ddb9b54f546acf4da8165e72c0c2c0fe3ae5	abc74@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
7a7f6ea5-eae0-56a7-8170-19f63df36eac	Seed user 75	\\xb5ed67cd3febe9ce3b9c0ef8a10a3de4a5768affff8aeaf0166e5dcb3f27cef869c2eb20377d9726632b2c	\\x4502c1cd9367aa2470af66193227a64bbe7a6956b0337e871961040dc3491131	abc75@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
767fed37-59e2-566e-9176-b86eb3f9e6a1	Seed user 76	\\x78b310053e867dd43255d0f285d65196268434e23f44849de5a8673e16bba066e9d3f86d1f403c0499a277	\\xca622d6d47a4dba87ce35c1a06569e20e216927e77359ca4f4de515b70278628	abc76@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
557f77f1-0005-5160-aeec-844e74cb1d48	Seed user 77	\\x17ec1fdc281e682dfa32b34c3b9a6aa038e325917c3aa71dc7fbfcd70245def74ca7a73c4219b2f9cbcb5d	\\x9c3a27d1994d57f59e5996d4fb6d56626ec9083e222d2c595da19de457176878	abc77@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
57442b8e-30fa-5be7-a8d2-97a430faf00e	Seed user 78	\\x5bd11fac38bdc36096bd977c7e8f408129b97486bd9664fe58ba02e9d5b7385791bb6af77ee69af6f2024d	\\xb7e6ff65e8933d6bd739fe8d5e43ec1ca5b69f4676c3ae59db648f8ce4e59858	abc78@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
56aebc4f-4fa9-5285-978f-535055a22403	Seed user 79	\\xab6bfd0ad2cd2aff440a9ac236197e56d14d581a1d74acf1e44a8b087fa8dfc856efd247ba9a22d7d7f03e	\\xb62082e7cfb9bbc8c0f1c26f8dba011336c82567df91f115ad6eb91b07e2f405	abc79@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
c410c3fb-090d-54d0-b028-266594143b70	Seed user 80	\\x40fe1e0ea3da383eaa078817b97293814258fddd4d1c0ef93e3126741f8979dfa4a439f1fb53a028e1600e	\\xea3e117222939fc6fe42162f9647db4e90f9f106edb0d25d6b3b6ee17b6dc061	abc80@email.com	$2a$10$3SvVxvHGHyIML5nO58QnDuW5PPwW3ZQBnJ6009g9HzOPbdjdDykmG			1	2026-08-01 00:00:00+00	2026-08-01 00:00:00+00	active
\.


--
-- Name: appointment_audit_events appointment_audit_events_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_audit_events
    ADD CONSTRAINT appointment_audit_events_pkey PRIMARY KEY (appointment_audit_event_id);


--
-- Name: appointment_idempotency appointment_idempotency_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_idempotency
    ADD CONSTRAINT appointment_idempotency_pkey PRIMARY KEY (idempotency_key);


--
-- Name: appointment_resource_reservations appointment_resource_reservations_no_overlap; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_resource_reservations
    ADD CONSTRAINT appointment_resource_reservations_no_overlap EXCLUDE USING gist (resource_type WITH =, resource_id WITH =, tstzrange(reserved_starts_at, reserved_ends_at, '[)'::text) WITH &&) WHERE (((released_at IS NULL) AND ((status)::text = ANY ((ARRAY['requested'::character varying, 'checked_in'::character varying, 'in_progress'::character varying])::text[]))));


--
-- Name: appointment_resource_reservations appointment_resource_reservations_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_resource_reservations
    ADD CONSTRAINT appointment_resource_reservations_pkey PRIMARY KEY (appointment_resource_reservation_id);


--
-- Name: appointments appointments_no_service_bay_overlap; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_no_service_bay_overlap EXCLUDE USING gist (service_bay_id WITH =, tstzrange(starts_at, ends_at, '[)'::text) WITH &&) WHERE (((status)::text = ANY ((ARRAY['requested'::character varying, 'checked_in'::character varying, 'in_progress'::character varying])::text[])));


--
-- Name: appointments appointments_no_technician_overlap; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_no_technician_overlap EXCLUDE USING gist (technician_id WITH =, tstzrange(starts_at, ends_at, '[)'::text) WITH &&) WHERE (((status)::text = ANY ((ARRAY['requested'::character varying, 'checked_in'::character varying, 'in_progress'::character varying])::text[])));


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (appointment_id);


--
-- Name: appointments appointments_reference_code_key; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_reference_code_key UNIQUE (reference_code);


--
-- Name: bay_capabilities bay_capabilities_code_key; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.bay_capabilities
    ADD CONSTRAINT bay_capabilities_code_key UNIQUE (code);


--
-- Name: bay_capabilities bay_capabilities_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.bay_capabilities
    ADD CONSTRAINT bay_capabilities_pkey PRIMARY KEY (bay_capability_id);


--
-- Name: customer_dealerships customer_dealerships_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.customer_dealerships
    ADD CONSTRAINT customer_dealerships_pkey PRIMARY KEY (customer_id);


--
-- Name: customers customers_phone_key; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.customers
    ADD CONSTRAINT customers_phone_key UNIQUE (phone);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- Name: dealership_operation_time dealership_operation_time_no_overlap; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.dealership_operation_time
    ADD CONSTRAINT dealership_operation_time_no_overlap EXCLUDE USING gist (dealership_id WITH =, day_of_week WITH =, tsrange(('2000-01-01'::date + opens_at), ('2000-01-01'::date + closes_at), '[)'::text) WITH &&);


--
-- Name: dealership_operation_time dealership_operation_time_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.dealership_operation_time
    ADD CONSTRAINT dealership_operation_time_pkey PRIMARY KEY (dealership_operation_time_id);


--
-- Name: dealerships dealerships_code_key; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.dealerships
    ADD CONSTRAINT dealerships_code_key UNIQUE (code);


--
-- Name: dealerships dealerships_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.dealerships
    ADD CONSTRAINT dealerships_pkey PRIMARY KEY (dealership_id);


--
-- Name: roles roles_code_key; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.roles
    ADD CONSTRAINT roles_code_key UNIQUE (code);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: service_bay_capabilities service_bay_capabilities_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_bay_capabilities
    ADD CONSTRAINT service_bay_capabilities_pkey PRIMARY KEY (service_bay_capability_id);


--
-- Name: service_bay_capabilities service_bay_capabilities_service_bay_bay_capability_unique; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_bay_capabilities
    ADD CONSTRAINT service_bay_capabilities_service_bay_bay_capability_unique UNIQUE (service_bay_id, bay_capability_id);


--
-- Name: service_bays service_bays_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_bays
    ADD CONSTRAINT service_bays_pkey PRIMARY KEY (service_bay_id);


--
-- Name: service_type_required_bay_capabilities service_type_required_bay_capabilities_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_type_required_bay_capabilities
    ADD CONSTRAINT service_type_required_bay_capabilities_pkey PRIMARY KEY (service_type_required_bay_capability_id);


--
-- Name: service_type_required_bay_capabilities service_type_required_bay_capabilities_service_type_bay_capabil; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_type_required_bay_capabilities
    ADD CONSTRAINT service_type_required_bay_capabilities_service_type_bay_capabil UNIQUE (service_type_id, bay_capability_id);


--
-- Name: service_type_required_skills service_type_required_skills_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_type_required_skills
    ADD CONSTRAINT service_type_required_skills_pkey PRIMARY KEY (service_type_required_skill_id);


--
-- Name: service_type_required_skills service_type_required_skills_service_type_skill_unique; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_type_required_skills
    ADD CONSTRAINT service_type_required_skills_service_type_skill_unique UNIQUE (service_type_id, skill_id);


--
-- Name: service_types service_types_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_types
    ADD CONSTRAINT service_types_pkey PRIMARY KEY (service_type_id);


--
-- Name: skills skills_code_key; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.skills
    ADD CONSTRAINT skills_code_key UNIQUE (code);


--
-- Name: skills skills_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.skills
    ADD CONSTRAINT skills_pkey PRIMARY KEY (skill_id);


--
-- Name: technician_shifts technician_shifts_no_overlap; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_shifts
    ADD CONSTRAINT technician_shifts_no_overlap EXCLUDE USING gist (technician_id WITH =, day_of_week WITH =, tsrange(('2000-01-01 00:00:00'::timestamp without time zone + (starts_at)::interval), ('2000-01-01 00:00:00'::timestamp without time zone + (ends_at)::interval), '[)'::text) WITH &&) WHERE ((deleted_at IS NULL));


--
-- Name: technician_shifts technician_shifts_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_shifts
    ADD CONSTRAINT technician_shifts_pkey PRIMARY KEY (technician_shift_id);


--
-- Name: technician_skills technician_skills_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_skills
    ADD CONSTRAINT technician_skills_pkey PRIMARY KEY (technician_skill_id);


--
-- Name: technician_skills technician_skills_technician_skill_unique; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_skills
    ADD CONSTRAINT technician_skills_technician_skill_unique UNIQUE (technician_id, skill_id);


--
-- Name: technician_time_off technician_time_off_no_overlap; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_time_off
    ADD CONSTRAINT technician_time_off_no_overlap EXCLUDE USING gist (technician_id WITH =, tstzrange(starts_at, ends_at, '[)'::text) WITH &&) WHERE ((deleted_at IS NULL));


--
-- Name: technician_time_off technician_time_off_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_time_off
    ADD CONSTRAINT technician_time_off_pkey PRIMARY KEY (technician_time_off_id);


--
-- Name: technicians technicians_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technicians
    ADD CONSTRAINT technicians_pkey PRIMARY KEY (technician_id);


--
-- Name: technicians technicians_user_id_key; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technicians
    ADD CONSTRAINT technicians_user_id_key UNIQUE (user_id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_role_id);


--
-- Name: user_roles user_roles_user_role_unique; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.user_roles
    ADD CONSTRAINT user_roles_user_role_unique UNIQUE (user_id, role_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: vehicles vehicles_pkey; Type: CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.vehicles
    ADD CONSTRAINT vehicles_pkey PRIMARY KEY (vehicle_id);


--
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id);


--
-- Name: users users_email_lookup_uq; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_email_lookup_uq UNIQUE (email_lookup);


--
-- Name: users users_email_to_uq; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_email_to_uq UNIQUE (email_to);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: appointment_resource_reservations_appointment_id_idx; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE INDEX appointment_resource_reservations_appointment_id_idx ON appointment_scheduler.appointment_resource_reservations USING btree (appointment_id, assigned_at);


--
-- Name: appointments_active_future_technician_idx; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE INDEX appointments_active_future_technician_idx ON appointment_scheduler.appointments USING btree (technician_id, ends_at) WHERE ((deleted_at IS NULL) AND ((status)::text = ANY ((ARRAY['requested'::character varying, 'checked_in'::character varying, 'in_progress'::character varying])::text[])));


--
-- Name: appointments_dealership_starts_at_idx; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE INDEX appointments_dealership_starts_at_idx ON appointment_scheduler.appointments USING btree (dealership_id, starts_at);


--
-- Name: bay_capabilities_code_lower_unique; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE UNIQUE INDEX bay_capabilities_code_lower_unique ON appointment_scheduler.bay_capabilities USING btree (lower((code)::text));


--
-- Name: customer_dealerships_dealership_id_idx; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE INDEX customer_dealerships_dealership_id_idx ON appointment_scheduler.customer_dealerships USING btree (dealership_id);


--
-- Name: customers_email_unique_when_present; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE UNIQUE INDEX customers_email_unique_when_present ON appointment_scheduler.customers USING btree (lower((email)::text)) WHERE (email IS NOT NULL);


--
-- Name: dealership_operation_time_dealership_day_opens_at_idx; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE INDEX dealership_operation_time_dealership_day_opens_at_idx ON appointment_scheduler.dealership_operation_time USING btree (dealership_id, day_of_week, opens_at);


--
-- Name: service_bays_dealership_code_lower_unique; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE UNIQUE INDEX service_bays_dealership_code_lower_unique ON appointment_scheduler.service_bays USING btree (dealership_id, lower((code)::text)) WHERE (deleted_at IS NULL);


--
-- Name: service_types_dealership_name_unique; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE UNIQUE INDEX service_types_dealership_name_unique ON appointment_scheduler.service_types USING btree (dealership_id, lower((name)::text)) WHERE (deleted_at IS NULL);


--
-- Name: technician_shifts_active_technician_day_starts_at_idx; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE INDEX technician_shifts_active_technician_day_starts_at_idx ON appointment_scheduler.technician_shifts USING btree (technician_id, day_of_week, starts_at) WHERE (deleted_at IS NULL);


--
-- Name: technician_skills_technician_id_idx; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE INDEX technician_skills_technician_id_idx ON appointment_scheduler.technician_skills USING btree (technician_id);


--
-- Name: technician_time_off_active_technician_starts_at_idx; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE INDEX technician_time_off_active_technician_starts_at_idx ON appointment_scheduler.technician_time_off USING btree (technician_id, starts_at) WHERE (deleted_at IS NULL);


--
-- Name: users_auth_user_id_unique_when_present; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE UNIQUE INDEX users_auth_user_id_unique_when_present ON appointment_scheduler.users USING btree (auth_user_id) WHERE ((auth_user_id <> '00000000-0000-0000-0000-000000000000'::uuid) AND (deleted_at IS NULL));


--
-- Name: vehicles_vin_unique_when_present; Type: INDEX; Schema: appointment_scheduler; Owner: postgres
--

CREATE UNIQUE INDEX vehicles_vin_unique_when_present ON appointment_scheduler.vehicles USING btree (vin) WHERE (vin IS NOT NULL);


--
-- Name: appointment_audit_events appointment_audit_events_append_only; Type: TRIGGER; Schema: appointment_scheduler; Owner: postgres
--

CREATE TRIGGER appointment_audit_events_append_only BEFORE DELETE OR UPDATE ON appointment_scheduler.appointment_audit_events FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.prevent_appointment_audit_mutation();


--
-- Name: appointments appointments_reject_technician_time_off; Type: TRIGGER; Schema: appointment_scheduler; Owner: postgres
--

CREATE TRIGGER appointments_reject_technician_time_off BEFORE INSERT OR UPDATE OF technician_id, starts_at, ends_at, status, deleted_at ON appointment_scheduler.appointments FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.reject_appointment_during_time_off();


--
-- Name: appointment_audit_events appointment_audit_events_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_audit_events
    ADD CONSTRAINT appointment_audit_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES appointment_scheduler.users(user_id);


--
-- Name: appointment_audit_events appointment_audit_events_appointment_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_audit_events
    ADD CONSTRAINT appointment_audit_events_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES appointment_scheduler.appointments(appointment_id) ON DELETE CASCADE;


--
-- Name: appointment_idempotency appointment_idempotency_appointment_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_idempotency
    ADD CONSTRAINT appointment_idempotency_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES appointment_scheduler.appointments(appointment_id);


--
-- Name: appointment_resource_reservations appointment_resource_reservations_appointment_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_resource_reservations
    ADD CONSTRAINT appointment_resource_reservations_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES appointment_scheduler.appointments(appointment_id);


--
-- Name: appointment_resource_reservations appointment_resource_reservations_assigned_by_user_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointment_resource_reservations
    ADD CONSTRAINT appointment_resource_reservations_assigned_by_user_id_fkey FOREIGN KEY (assigned_by_user_id) REFERENCES appointment_scheduler.users(user_id);


--
-- Name: appointments appointments_cancelled_by_user_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_cancelled_by_user_id_fkey FOREIGN KEY (cancelled_by_user_id) REFERENCES appointment_scheduler.users(user_id);


--
-- Name: appointments appointments_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES appointment_scheduler.users(user_id);


--
-- Name: appointments appointments_customer_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES appointment_scheduler.customers(customer_id);


--
-- Name: appointments appointments_dealership_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_dealership_id_fkey FOREIGN KEY (dealership_id) REFERENCES appointment_scheduler.dealerships(dealership_id);


--
-- Name: appointments appointments_service_bay_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_service_bay_id_fkey FOREIGN KEY (service_bay_id) REFERENCES appointment_scheduler.service_bays(service_bay_id);


--
-- Name: appointments appointments_service_type_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_service_type_id_fkey FOREIGN KEY (service_type_id) REFERENCES appointment_scheduler.service_types(service_type_id);


--
-- Name: appointments appointments_technician_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES appointment_scheduler.technicians(technician_id);


--
-- Name: appointments appointments_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.appointments
    ADD CONSTRAINT appointments_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES appointment_scheduler.vehicles(vehicle_id);


--
-- Name: customer_dealerships customer_dealerships_customer_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.customer_dealerships
    ADD CONSTRAINT customer_dealerships_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES appointment_scheduler.customers(customer_id);


--
-- Name: customer_dealerships customer_dealerships_dealership_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.customer_dealerships
    ADD CONSTRAINT customer_dealerships_dealership_id_fkey FOREIGN KEY (dealership_id) REFERENCES appointment_scheduler.dealerships(dealership_id);


--
-- Name: dealership_operation_time dealership_operation_time_dealership_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.dealership_operation_time
    ADD CONSTRAINT dealership_operation_time_dealership_id_fkey FOREIGN KEY (dealership_id) REFERENCES appointment_scheduler.dealerships(dealership_id);


--
-- Name: service_bay_capabilities service_bay_capabilities_bay_capability_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_bay_capabilities
    ADD CONSTRAINT service_bay_capabilities_bay_capability_id_fkey FOREIGN KEY (bay_capability_id) REFERENCES appointment_scheduler.bay_capabilities(bay_capability_id);


--
-- Name: service_bay_capabilities service_bay_capabilities_service_bay_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_bay_capabilities
    ADD CONSTRAINT service_bay_capabilities_service_bay_id_fkey FOREIGN KEY (service_bay_id) REFERENCES appointment_scheduler.service_bays(service_bay_id) ON DELETE CASCADE;


--
-- Name: service_bays service_bays_dealership_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_bays
    ADD CONSTRAINT service_bays_dealership_id_fkey FOREIGN KEY (dealership_id) REFERENCES appointment_scheduler.dealerships(dealership_id);


--
-- Name: service_type_required_bay_capabilities service_type_required_bay_capabilities_bay_capability_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_type_required_bay_capabilities
    ADD CONSTRAINT service_type_required_bay_capabilities_bay_capability_id_fkey FOREIGN KEY (bay_capability_id) REFERENCES appointment_scheduler.bay_capabilities(bay_capability_id);


--
-- Name: service_type_required_bay_capabilities service_type_required_bay_capabilities_service_type_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_type_required_bay_capabilities
    ADD CONSTRAINT service_type_required_bay_capabilities_service_type_id_fkey FOREIGN KEY (service_type_id) REFERENCES appointment_scheduler.service_types(service_type_id) ON DELETE CASCADE;


--
-- Name: service_type_required_skills service_type_required_skills_service_type_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_type_required_skills
    ADD CONSTRAINT service_type_required_skills_service_type_id_fkey FOREIGN KEY (service_type_id) REFERENCES appointment_scheduler.service_types(service_type_id) ON DELETE CASCADE;


--
-- Name: service_type_required_skills service_type_required_skills_skill_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_type_required_skills
    ADD CONSTRAINT service_type_required_skills_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES appointment_scheduler.skills(skill_id);


--
-- Name: service_types service_types_dealership_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.service_types
    ADD CONSTRAINT service_types_dealership_id_fkey FOREIGN KEY (dealership_id) REFERENCES appointment_scheduler.dealerships(dealership_id);


--
-- Name: technician_shifts technician_shifts_technician_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_shifts
    ADD CONSTRAINT technician_shifts_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES appointment_scheduler.technicians(technician_id) ON DELETE CASCADE;


--
-- Name: technician_skills technician_skills_skill_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_skills
    ADD CONSTRAINT technician_skills_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES appointment_scheduler.skills(skill_id);


--
-- Name: technician_skills technician_skills_technician_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_skills
    ADD CONSTRAINT technician_skills_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES appointment_scheduler.technicians(technician_id) ON DELETE CASCADE;


--
-- Name: technician_time_off technician_time_off_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_time_off
    ADD CONSTRAINT technician_time_off_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES appointment_scheduler.users(user_id);


--
-- Name: technician_time_off technician_time_off_technician_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technician_time_off
    ADD CONSTRAINT technician_time_off_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES appointment_scheduler.technicians(technician_id) ON DELETE CASCADE;


--
-- Name: technicians technicians_user_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.technicians
    ADD CONSTRAINT technicians_user_id_fkey FOREIGN KEY (user_id) REFERENCES appointment_scheduler.users(user_id);


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES appointment_scheduler.roles(role_id);


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES appointment_scheduler.users(user_id) ON DELETE CASCADE;


--
-- Name: users users_dealership_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.users
    ADD CONSTRAINT users_dealership_id_fkey FOREIGN KEY (dealership_id) REFERENCES appointment_scheduler.dealerships(dealership_id);


--
-- Name: vehicles vehicles_customer_id_fkey; Type: FK CONSTRAINT; Schema: appointment_scheduler; Owner: postgres
--

ALTER TABLE ONLY appointment_scheduler.vehicles
    ADD CONSTRAINT vehicles_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES appointment_scheduler.customers(customer_id);


--
-- Name: user_roles user_roles_role_fk; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.user_roles
    ADD CONSTRAINT user_roles_role_fk FOREIGN KEY (role_id) REFERENCES auth.roles(role_id);


--
-- Name: user_roles user_roles_user_fk; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.user_roles
    ADD CONSTRAINT user_roles_user_fk FOREIGN KEY (user_id) REFERENCES auth.users(user_id);


--
-- PostgreSQL database dump complete
--

\unrestrict ry91l2fm4zZSkBdVJpvXMLqUH4xTekKp8j0ovt7QbDIJMfMdaNTuHOhW0XVRV1e

