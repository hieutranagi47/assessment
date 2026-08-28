-- Customer accounts are retained permanently; removal is not a supported operation.
ALTER TABLE appointment_scheduler.customers
  DROP COLUMN deleted_at;
