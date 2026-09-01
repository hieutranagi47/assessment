#!/usr/bin/env bash
# Creates one appointment using the deterministic development fixtures and
# prints the daily appointment list afterwards.
#
# Prerequisites: docker compose services are running, fixtures have been loaded
# (`task -d dealership seed`), and curl, jq, and python3 are installed.
#
# Optional overrides:
#   DEALERSHIP_CODE=DAL APPOINTMENT_DATE=2026-09-01 \
#   APPOINTMENT_LOCAL_TIME=09:00 CORRELATION_ID=manual-appointment-001 \
#   IDEMPOTENCY_KEY=manual-appointment-001 \
#   ./dealership/scripts/create-appointment-manual-test.sh

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:9999}"
DEALERSHIP_CODE="${DEALERSHIP_CODE:-}"
APPOINTMENT_DATE="${APPOINTMENT_DATE:-2026-09-01}"
APPOINTMENT_LOCAL_TIME="${APPOINTMENT_LOCAL_TIME:-09:00}"
CORRELATION_ID="${CORRELATION_ID:-manual-appointment-${APPOINTMENT_DATE}-${APPOINTMENT_LOCAL_TIME//:/}}"
IDEMPOTENCY_KEY="${IDEMPOTENCY_KEY:-manual-appointment-${APPOINTMENT_DATE}-${APPOINTMENT_LOCAL_TIME//:/}}"
SEED_PASSWORD="${SEED_PASSWORD:-Abc@6789}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-ht47}"
# Escape the one SQL literal supplied by the operator. The remaining IDs are
# read from PostgreSQL and are UUIDs.
DEALERSHIP_CODE_SQL="${DEALERSHIP_CODE//\'/\'\'}"

require_command() {
  command -v "$1" >/dev/null || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

for command in curl docker jq python3; do
  require_command "$command"
done

db_query() {
  docker compose exec -T postgres \
    psql -v ON_ERROR_STOP=1 -At -F $'\t' \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"
}

api() {
  curl --fail-with-body --silent --show-error \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Accept: application/json' \
    -H "Correlation-ID: ${CORRELATION_ID}" \
    "$@"
}

printf 'Selecting an active dealership, its scheduler admin, and timezone from PostgreSQL...\n'
dealership_row="$(db_query -c "
  SELECT d.dealership_id, d.code, d.timezone, au.email_to
  FROM appointment_scheduler.dealerships AS d
  JOIN appointment_scheduler.users AS u
    ON u.dealership_id = d.dealership_id
   AND u.deleted_at IS NULL
   AND u.is_active
  JOIN appointment_scheduler.user_roles AS ur
    ON ur.user_id = u.user_id
   AND ur.deleted_at IS NULL
  JOIN appointment_scheduler.roles AS r
    ON r.role_id = ur.role_id
   AND r.deleted_at IS NULL
   AND r.code = 'admin'
  JOIN auth.users AS au
    ON au.user_id = u.auth_user_id::text
   AND au.status = 'active'
  WHERE d.deleted_at IS NULL
    AND d.is_active
    AND ('${DEALERSHIP_CODE_SQL}' = '' OR d.code = '${DEALERSHIP_CODE_SQL}')
  ORDER BY d.code, u.name
  LIMIT 1;")"

if [[ -z "$dealership_row" ]]; then
  printf 'No active dealership with an active scheduler admin was found. DEALERSHIP_CODE=%q\n' "$DEALERSHIP_CODE" >&2
  exit 1
fi

IFS=$'\t' read -r DEALERSHIP_ID SELECTED_DEALERSHIP_CODE DEALERSHIP_TIMEZONE ADMIN_EMAIL <<<"$dealership_row"
printf 'Using dealership %s (%s), timezone %s, admin %s.\n' \
  "$SELECTED_DEALERSHIP_CODE" "$DEALERSHIP_ID" "$DEALERSHIP_TIMEZONE" "$ADMIN_EMAIL"
printf 'Using Correlation-ID: %s\n' "$CORRELATION_ID"
printf 'Using Idempotency-Id: %s\n' "$IDEMPOTENCY_KEY"

printf 'Signing in...\n'
sign_in_body="$(jq -nc --arg email "$ADMIN_EMAIL" --arg password "$SEED_PASSWORD" \
  '{email: $email, password: $password}')"
sign_in_response="$(curl --fail-with-body --silent --show-error \
  -H 'Content-Type: application/json' \
  -H "Correlation-ID: ${CORRELATION_ID}" \
  -H "Idempotency-Id: ${IDEMPOTENCY_KEY}" \
  -X POST "$BASE_URL/auth/v1/sign-in" \
  --data "$sign_in_body")"
ACCESS_TOKEN="$(jq -er '.access_token' <<<"$sign_in_response")"
expires_in="$(jq -er '.expires_in' <<<"$sign_in_response")"
printf 'Signed in; access token expires in %s seconds.\n' "$expires_in"

# Convert the local appointment time to the UTC timestamps required by the API.
utc_times="$(python3 - "$APPOINTMENT_DATE" "$APPOINTMENT_LOCAL_TIME" "$DEALERSHIP_TIMEZONE" <<'PY'
from datetime import datetime
from zoneinfo import ZoneInfo
import sys

local = datetime.strptime(f"{sys.argv[1]}T{sys.argv[2]}", "%Y-%m-%dT%H:%M")
local = local.replace(tzinfo=ZoneInfo(sys.argv[3]))
print(local.astimezone(ZoneInfo("UTC")).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
STARTS_AT="$utc_times"

printf 'Selecting a service, its duration, and a customer/vehicle from PostgreSQL...\n'
booking_row="$(db_query -c "
  SELECT st.service_type_id,
         st.default_duration_minutes,
         c.customer_id,
         v.vehicle_id
  FROM appointment_scheduler.service_types AS st
  JOIN appointment_scheduler.customer_dealerships AS cd
    ON cd.dealership_id = st.dealership_id
  JOIN appointment_scheduler.customers AS c
    ON c.customer_id = cd.customer_id
  JOIN appointment_scheduler.vehicles AS v
    ON v.customer_id = c.customer_id
  WHERE st.dealership_id = '${DEALERSHIP_ID}'
    AND st.deleted_at IS NULL
    AND st.is_active
  ORDER BY st.name, c.name, v.vin
  LIMIT 1;")"

if [[ -z "$booking_row" ]]; then
  printf 'No active service type with a customer and vehicle is available for dealership %s.\n' "$DEALERSHIP_ID" >&2
  exit 1
fi

IFS=$'\t' read -r SERVICE_TYPE_ID PLANNED_DURATION_MINUTES CUSTOMER_ID VEHICLE_ID <<<"$booking_row"
ENDS_AT="$(python3 - "$STARTS_AT" "$PLANNED_DURATION_MINUTES" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

starts_at = datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
ends_at = starts_at + timedelta(minutes=int(sys.argv[2]))
print(ends_at.strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"

printf 'Getting all technician schedules for %s...\n' "$APPOINTMENT_DATE"
schedule_response="$(api --get \
  "$BASE_URL/appointment-scheduler/v1/dealerships/$DEALERSHIP_ID/technician-schedules" \
  --data-urlencode "date=$APPOINTMENT_DATE")"
printf '%s\n' "$schedule_response" | jq .

printf 'Selecting a qualified, unoccupied technician from PostgreSQL...\n'
technician_id="$(db_query -c "
  SELECT t.technician_id
  FROM appointment_scheduler.technicians AS t
  JOIN appointment_scheduler.users AS u
    ON u.user_id = t.user_id
   AND u.deleted_at IS NULL
   AND u.is_active
  JOIN appointment_scheduler.dealerships AS d
    ON d.dealership_id = u.dealership_id
  WHERE u.dealership_id = '${DEALERSHIP_ID}'
    AND t.deleted_at IS NULL
    AND t.is_active
    AND NOT EXISTS (
      SELECT 1
      FROM appointment_scheduler.service_type_required_skills AS required_skill
      WHERE required_skill.service_type_id = '${SERVICE_TYPE_ID}'
        AND NOT EXISTS (
          SELECT 1
          FROM appointment_scheduler.technician_skills AS technician_skill
          WHERE technician_skill.technician_id = t.technician_id
            AND technician_skill.skill_id = required_skill.skill_id
        )
    )
    AND EXISTS (
      SELECT 1
      FROM appointment_scheduler.technician_shifts AS shift
      WHERE shift.technician_id = t.technician_id
        AND shift.deleted_at IS NULL
        AND shift.day_of_week = EXTRACT(ISODOW FROM ('${STARTS_AT}'::timestamptz AT TIME ZONE d.timezone))
        AND shift.starts_at <= ('${STARTS_AT}'::timestamptz AT TIME ZONE d.timezone)::time
        AND shift.ends_at >= ('${ENDS_AT}'::timestamptz AT TIME ZONE d.timezone)::time
    )
    AND NOT EXISTS (
      SELECT 1
      FROM appointment_scheduler.appointments AS a
      WHERE a.technician_id = t.technician_id
        AND a.deleted_at IS NULL
        AND a.status IN ('requested', 'checked_in', 'in_progress')
        AND a.starts_at < '${ENDS_AT}'::timestamptz
        AND a.ends_at > '${STARTS_AT}'::timestamptz
    )
    AND NOT EXISTS (
      SELECT 1
      FROM appointment_scheduler.technician_time_off AS time_off
      WHERE time_off.technician_id = t.technician_id
        AND time_off.deleted_at IS NULL
        AND time_off.starts_at < '${ENDS_AT}'::timestamptz
        AND time_off.ends_at > '${STARTS_AT}'::timestamptz
    )
  ORDER BY t.technician_id
  LIMIT 1;")"

if [[ -z "$technician_id" ]]; then
  printf 'No qualified technician is free from %s to %s. Choose another date/time.\n' "$STARTS_AT" "$ENDS_AT" >&2
  exit 1
fi

printf 'Getting available service bays from %s to %s...\n' "$STARTS_AT" "$ENDS_AT"
available_bays_response="$(api --get \
  "$BASE_URL/appointment-scheduler/v1/dealerships/$DEALERSHIP_ID/service-bays/available" \
  --data-urlencode "service_type_id=$SERVICE_TYPE_ID" \
  --data-urlencode "starts_at=$STARTS_AT" \
  --data-urlencode "ends_at=$ENDS_AT")"
printf '%s\n' "$available_bays_response" | jq .
SERVICE_BAY_ID="$(jq -er '.items[0].service_bay_id' <<<"$available_bays_response")"

printf 'Creating the appointment...\n'
appointment_body="$(jq -nc \
  --arg customer_id "$CUSTOMER_ID" \
  --arg vehicle_id "$VEHICLE_ID" \
  --arg service_type_id "$SERVICE_TYPE_ID" \
  --arg starts_at "$STARTS_AT" \
  --arg technician_id "$technician_id" \
  --arg service_bay_id "$SERVICE_BAY_ID" \
  --argjson planned_duration_minutes "$PLANNED_DURATION_MINUTES" \
  '{customer_id: $customer_id, vehicle_id: $vehicle_id, service_type_id: $service_type_id, starts_at: $starts_at, technician_id: $technician_id, service_bay_id: $service_bay_id, planned_duration_minutes: $planned_duration_minutes, notes: "Manual API test"}')"
appointment_response="$(api -H 'Content-Type: application/json' \
  -H "Idempotency-Id: ${IDEMPOTENCY_KEY}" \
  -X POST "$BASE_URL/appointment-scheduler/v1/appointments" \
  --data "$appointment_body")"
printf '%s\n' "$appointment_response" | jq .

printf 'Listing all appointments for dealership %s on %s...\n' "$DEALERSHIP_ID" "$APPOINTMENT_DATE"
api --get "$BASE_URL/appointment-scheduler/v1/dealerships/$DEALERSHIP_ID/appointments" \
  --data-urlencode "date=$APPOINTMENT_DATE" | jq .
