ALTER TABLE appointment_scheduler.technician_shifts
  ADD CONSTRAINT technician_shifts_no_overlap
  EXCLUDE USING gist (
    technician_id WITH =,
    day_of_week WITH =,
    tsrange(TIMESTAMP '2000-01-01' + starts_at, TIMESTAMP '2000-01-01' + ends_at, '[)') WITH &&
  )
  WHERE (deleted_at IS NULL);
