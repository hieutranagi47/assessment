-- A global customer is claimed by the dealership that first manages a vehicle
-- for it. This creates an enforceable ownership boundary without changing the
-- existing global customer APIs.
CREATE TABLE appointment_scheduler.customer_dealerships (
  customer_id UUID PRIMARY KEY REFERENCES appointment_scheduler.customers(customer_id),
  dealership_id UUID NOT NULL REFERENCES appointment_scheduler.dealerships(dealership_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX customer_dealerships_dealership_id_idx
  ON appointment_scheduler.customer_dealerships (dealership_id);
