ALTER TABLE auth.users
  ALTER COLUMN email DROP NOT NULL,
  ALTER COLUMN email TYPE VARCHAR(255) USING NULL::VARCHAR(255);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'auth'
      AND table_name = 'users'
      AND column_name = 'email_to'
  ) THEN
    UPDATE auth.users
    SET email = email_to
    WHERE email_to IS NOT NULL;
  END IF;
END $$;

ALTER TABLE auth.users
  DROP CONSTRAINT IF EXISTS users_email_to_uq,
  DROP COLUMN IF EXISTS email_to;
