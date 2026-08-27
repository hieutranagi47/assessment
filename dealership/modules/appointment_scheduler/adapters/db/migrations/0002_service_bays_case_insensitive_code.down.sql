DROP INDEX appointment_scheduler.service_bays_dealership_code_lower_unique;

ALTER TABLE appointment_scheduler.service_bays
  ADD CONSTRAINT service_bays_dealership_code_unique UNIQUE (dealership_id, code);
