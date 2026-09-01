CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE auth.roles (
  role_id VARCHAR(36) PRIMARY KEY,
  name VARCHAR(16) NOT NULL UNIQUE CHECK (name IN ('superadmin', 'admin', 'user'))
);

INSERT INTO auth.roles (role_id, name) VALUES
  ('00000000-0000-4000-8000-000000000001', 'superadmin'),
  ('00000000-0000-4000-8000-000000000002', 'admin'),
  ('00000000-0000-4000-8000-000000000003', 'user');

CREATE TABLE auth.users (
  user_id VARCHAR(36) PRIMARY KEY,
  full_name VARCHAR(255) NOT NULL DEFAULT '',
  email VARCHAR(255) NULL,
  email_lookup BYTEA NOT NULL,
  hashed_password VARCHAR(255) NOT NULL,
  hashed_password_1 VARCHAR(255) NOT NULL DEFAULT '',
  hashed_password_2 VARCHAR(255) NOT NULL DEFAULT '',
  token_ver INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'deleted')),
  CONSTRAINT users_token_ver_positive CHECK (token_ver > 0),
  CONSTRAINT users_email_lookup_uq UNIQUE (email_lookup)
);

CREATE TABLE auth.user_roles (
  user_id VARCHAR(36) PRIMARY KEY,
  role_id VARCHAR(36) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT user_roles_user_fk FOREIGN KEY (user_id) REFERENCES auth.users (user_id),
  CONSTRAINT user_roles_role_fk FOREIGN KEY (role_id) REFERENCES auth.roles (role_id)
);
