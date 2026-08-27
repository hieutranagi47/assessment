ALTER TABLE appointment_scheduler.service_bays
  DROP CONSTRAINT service_bays_dealership_code_unique;

CREATE UNIQUE INDEX service_bays_dealership_code_lower_unique
  ON appointment_scheduler.service_bays (dealership_id, LOWER(code))
  WHERE deleted_at IS NULL;
