ALTER TABLE auth.users
  ADD COLUMN email_password BYTEA NULL,
  ADD COLUMN email_password_salt BYTEA NULL;
