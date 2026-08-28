ALTER TABLE appointment_scheduler.dealership_operation_time
  DROP CONSTRAINT dealership_operation_time_day_unique,
  DROP COLUMN deleted_at;

ALTER TABLE appointment_scheduler.dealership_operation_time
  ADD CONSTRAINT dealership_operation_time_no_overlap
  EXCLUDE USING gist (
    dealership_id WITH =,
    day_of_week WITH =,
    tsrange(
      DATE '2000-01-01' + opens_at,
      DATE '2000-01-01' + closes_at,
      '[)'
    ) WITH &&
  );

CREATE INDEX dealership_operation_time_dealership_day_opens_at_idx
  ON appointment_scheduler.dealership_operation_time (dealership_id, day_of_week, opens_at);
