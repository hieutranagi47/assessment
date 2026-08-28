// Package seed contains the explicit database-level fixture path used only by
// cmd/seed. It intentionally does not participate in application startup.
package seed

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

const defaultPassword = "Abc@6789"

type fixtureCrypto struct {
	block     cipher.AEAD
	lookupKey []byte
}

func Run(ctx context.Context, database *pgxpool.Pool, encryptionKey, lookupKey, password string) error {
	if database == nil {
		return errors.New("PostgreSQL database is required")
	}
	if err := requireMigrations(ctx, database); err != nil {
		return err
	}
	if password == "" {
		password = defaultPassword
	}
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash seed password: %w", err)
	}
	crypto, err := newFixtureCrypto(encryptionKey, lookupKey)
	if err != nil {
		return err
	}
	tx, err := database.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("begin seed transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := seedAuth(ctx, tx, crypto, string(passwordHash)); err != nil {
		return err
	}
	if err := seedScheduler(ctx, tx); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit seed transaction: %w", err)
	}
	return nil
}

func requireMigrations(ctx context.Context, database *pgxpool.Pool) error {
	for _, schema := range []string{"auth", "appointment_scheduler"} {
		var exists *string
		if err := database.QueryRow(ctx, "SELECT to_regclass($1)::text", schema+".schema_migrations").Scan(&exists); err != nil || exists == nil {
			return fmt.Errorf("required migrations have not been applied for %s", schema)
		}
		var dirty bool
		err := database.QueryRow(ctx, "SELECT dirty FROM "+schema+".schema_migrations LIMIT 1").Scan(&dirty)
		if err != nil || dirty {
			return fmt.Errorf("required migrations have not been applied cleanly for %s", schema)
		}
	}
	for _, table := range []string{
		"auth.users",
		"appointment_scheduler.skills",
		"appointment_scheduler.bay_capabilities",
		"appointment_scheduler.customer_dealerships",
		"appointment_scheduler.appointment_resource_reservations",
	} {
		var exists *string
		if err := database.QueryRow(ctx, "SELECT to_regclass($1)::text", table).Scan(&exists); err != nil || exists == nil {
			return fmt.Errorf("required migrations have not been applied: missing %s", table)
		}
	}
	return nil
}

func newFixtureCrypto(encryptionKey, lookupKey string) (fixtureCrypto, error) {
	if encryptionKey == "" || lookupKey == "" {
		return fixtureCrypto{}, errors.New("email encryption and lookup keys are required")
	}
	key := sha256.Sum256([]byte(encryptionKey))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return fixtureCrypto{}, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return fixtureCrypto{}, err
	}
	return fixtureCrypto{block: aead, lookupKey: []byte(lookupKey)}, nil
}
func (c fixtureCrypto) encrypt(email string) ([]byte, error) {
	nonce := make([]byte, c.block.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return c.block.Seal(nonce, nonce, []byte(email), nil), nil
}
func (c fixtureCrypto) lookup(email string) []byte {
	mac := hmac.New(sha256.New, c.lookupKey)
	_, _ = mac.Write([]byte(email))
	return mac.Sum(nil)
}
func fixtureID(parts ...string) uuid.UUID {
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte(fmt.Sprint(parts)))
}
func exec(ctx context.Context, tx pgx.Tx, sql string, args ...any) error {
	_, err := tx.Exec(ctx, sql, args...)
	return err
}

func seedAuth(ctx context.Context, tx pgx.Tx, crypto fixtureCrypto, hash string) error {
	roles := []string{"superadmin", "superadmin", "admin", "admin", "admin"}
	for index := 0; index < 80; index++ {
		role := "user"
		if index < len(roles) {
			role = roles[index]
		}
		id := fixtureID("auth-user", fmt.Sprint(index))
		email := fmt.Sprintf("abc%d@email.com", index+1)
		encrypted, err := crypto.encrypt(email)
		if err != nil {
			return fmt.Errorf("encrypt seed email: %w", err)
		}
		if err := exec(ctx, tx, `INSERT INTO auth.users (user_id, full_name, email, email_lookup, email_to, hashed_password, token_ver, created_at, updated_at, status) VALUES ($1,$2,$3,$4,$5,$6,1,$7,$7,'active') ON CONFLICT (user_id) DO UPDATE SET email = EXCLUDED.email, email_lookup = EXCLUDED.email_lookup, email_to = EXCLUDED.email_to, hashed_password = EXCLUDED.hashed_password, updated_at = EXCLUDED.updated_at WHERE auth.users.email_to IS DISTINCT FROM EXCLUDED.email_to`, id.String(), fmt.Sprintf("Seed %s %02d", role, index+1), encrypted, crypto.lookup(email), email, hash, seedTime); err != nil {
			return err
		}
		if err := exec(ctx, tx, `INSERT INTO auth.user_roles (user_id, role_id, created_at, updated_at) VALUES ($1, (SELECT role_id FROM auth.roles WHERE name=$2), $3, $3) ON CONFLICT (user_id) DO NOTHING`, id.String(), role, seedTime); err != nil {
			return err
		}
	}
	return nil
}

var seedTime = time.Date(2026, time.August, 1, 0, 0, 0, 0, time.UTC)
var dealershipSpecs = []struct{ code, name, address, timezone string }{
	{"HCM", "Ho Chi Minh Motors", "1 Nguyen Hue, Ho Chi Minh City", "Asia/Ho_Chi_Minh"}, {"TYO", "Tokyo Motors", "1-1 Marunouchi, Tokyo", "Asia/Tokyo"}, {"SYD", "Sydney Motors", "1 George Street, Sydney", "Australia/Sydney"}, {"LDN", "London Motors", "1 Piccadilly, London", "Europe/London"}, {"LAX", "Los Angeles Motors", "1 Sunset Boulevard, Los Angeles", "America/Los_Angeles"},
}
var skills = []string{"diagnostics", "engine-repair", "brake-service", "ev-high-voltage", "hvac", "alignment", "tire-service", "adas-calibration", "transmission", "suspension", "detailing", "oil-service", "electrical", "battery", "cooling", "exhaust", "hybrid", "inspection", "bodywork", "wheels"}
var capabilities = []string{"general-lift", "alignment-rack", "tire-machine", "diagnostic-station", "hvac-station", "engine-hoist", "ev-isolation", "adas-target", "transmission-lift", "wash-bay", "brake-lathe"}
var services = []struct {
	name, skill, capability string
	duration                int
}{
	{"Oil service", "oil-service", "general-lift", 45}, {"Tire rotation", "tire-service", "tire-machine", 45}, {"Brake inspection", "brake-service", "brake-lathe", 60}, {"Wheel alignment", "alignment", "alignment-rack", 75}, {"Diagnostic assessment", "diagnostics", "diagnostic-station", 60}, {"AC repair", "hvac", "hvac-station", 120}, {"Major engine repair", "engine-repair", "engine-hoist", 180}, {"EV battery inspection", "ev-high-voltage", "ev-isolation", 90}, {"ADAS calibration", "adas-calibration", "adas-target", 120}, {"Transmission service", "transmission", "transmission-lift", 120}, {"Suspension repair", "suspension", "general-lift", 120}, {"Vehicle detailing", "detailing", "wash-bay", 90}, {"Electrical diagnosis", "electrical", "diagnostic-station", 90}, {"Cooling system repair", "cooling", "general-lift", 105},
}

func seedScheduler(ctx context.Context, tx pgx.Tx) error {
	if err := seedCatalog(ctx, tx); err != nil {
		return err
	}
	for dealerIndex, spec := range dealershipSpecs {
		if err := seedDealership(ctx, tx, dealerIndex, spec); err != nil {
			return err
		}
	}
	if err := seedCustomersAndVehicles(ctx, tx); err != nil {
		return err
	}
	for dealerIndex := range dealershipSpecs {
		if err := seedAppointments(ctx, tx, dealerIndex); err != nil {
			return err
		}
	}
	return nil
}
func seedCatalog(ctx context.Context, tx pgx.Tx) error {
	for _, skill := range skills {
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.skills (skill_id,code,name,is_active,created_at,updated_at) VALUES ($1,$2,$3,true,$4,$4) ON CONFLICT (skill_id) DO NOTHING`, fixtureID("skill", skill), skill, skill, seedTime); err != nil {
			return err
		}
	}
	for _, capability := range capabilities {
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.bay_capabilities (bay_capability_id,code,name,created_at,updated_at) VALUES ($1,$2,$3,$4,$4) ON CONFLICT (bay_capability_id) DO NOTHING`, fixtureID("capability", capability), capability, capability, seedTime); err != nil {
			return err
		}
	}
	return nil
}
func seedDealership(ctx context.Context, tx pgx.Tx, d int, spec struct{ code, name, address, timezone string }) error {
	did := fixtureID("dealership", spec.code)
	if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.dealerships (dealership_id,name,code,address,timezone,is_active,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,true,$6,$6) ON CONFLICT (dealership_id) DO NOTHING`, did, spec.name, spec.code, spec.address, spec.timezone, seedTime); err != nil {
		return err
	}
	for day := 1; day <= 7; day++ {
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.dealership_operation_time (dealership_operation_time_id,dealership_id,day_of_week,opens_at,closes_at,created_at,updated_at) VALUES ($1,$2,$3,'06:00','23:00',$4,$4) ON CONFLICT (dealership_operation_time_id) DO NOTHING`, fixtureID("hours", fmt.Sprint(d), fmt.Sprint(day)), did, day, seedTime); err != nil {
			return err
		}
	}
	for employee := 0; employee < 15; employee++ {
		if err := seedEmployee(ctx, tx, d, employee, did); err != nil {
			return err
		}
	}
	for bay := 0; bay < 7; bay++ {
		bid := fixtureID("bay", fmt.Sprint(d), fmt.Sprint(bay))
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.service_bays (service_bay_id,dealership_id,code,name,is_active,created_at,updated_at) VALUES ($1,$2,$3,$4,true,$5,$5) ON CONFLICT (service_bay_id) DO NOTHING`, bid, did, fmt.Sprintf("B%02d", bay+1), fmt.Sprintf("Service bay %d", bay+1), seedTime); err != nil {
			return err
		}
		for ci, capability := range capabilities {
			if bay == 0 || ci%7 == bay {
				if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.service_bay_capabilities (service_bay_capability_id,service_bay_id,bay_capability_id,created_at,updated_at) VALUES ($1,$2,$3,$4,$4) ON CONFLICT (service_bay_capability_id) DO NOTHING`, fixtureID("bay-cap", fmt.Sprint(d), fmt.Sprint(bay), capability), bid, fixtureID("capability", capability), seedTime); err != nil {
					return err
				}
			}
		}
	}
	for si, service := range services {
		sid := fixtureID("service", fmt.Sprint(d), fmt.Sprint(si))
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.service_types (service_type_id,dealership_id,name,default_duration_minutes,min_duration_minutes,max_duration_minutes,is_active,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,true,$7,$7) ON CONFLICT (service_type_id) DO NOTHING`, sid, did, service.name, service.duration, service.duration/2, service.duration*2, seedTime); err != nil {
			return err
		}
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.service_type_required_skills (service_type_required_skill_id,service_type_id,skill_id,created_at,updated_at) VALUES ($1,$2,$3,$4,$4) ON CONFLICT (service_type_required_skill_id) DO NOTHING`, fixtureID("service-skill", fmt.Sprint(d), fmt.Sprint(si)), sid, fixtureID("skill", service.skill), seedTime); err != nil {
			return err
		}
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.service_type_required_bay_capabilities (service_type_required_bay_capability_id,service_type_id,bay_capability_id,created_at,updated_at) VALUES ($1,$2,$3,$4,$4) ON CONFLICT (service_type_required_bay_capability_id) DO NOTHING`, fixtureID("service-cap", fmt.Sprint(d), fmt.Sprint(si)), sid, fixtureID("capability", service.capability), seedTime); err != nil {
			return err
		}
	}
	return nil
}
func seedEmployee(ctx context.Context, tx pgx.Tx, d, e int, dealershipID uuid.UUID) error {
	uid := fixtureID("scheduler-user", fmt.Sprint(d), fmt.Sprint(e))
	role := "technician"
	authIndex := 30 + d*10 + (e - 5)
	if e < 5 {
		authIndex = 5 + d*5 + e
		role = []string{"admin", "staff", "staff", "dealer", "dealer"}[e]
	}
	authID := fixtureID("auth-user", fmt.Sprint(authIndex))
	if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.users (user_id,auth_user_id,name,phone,email,dealership_id,is_active,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,true,$7,$7) ON CONFLICT (user_id) DO UPDATE SET auth_user_id = EXCLUDED.auth_user_id, name = EXCLUDED.name, phone = EXCLUDED.phone, email = EXCLUDED.email, dealership_id = EXCLUDED.dealership_id, is_active = EXCLUDED.is_active, deleted_at = NULL, updated_at = EXCLUDED.updated_at`, uid, authID, fmt.Sprintf("%s employee %02d", dealershipSpecs[d].code, e+1), fmt.Sprintf("+1555%02d%07d", d, e+1), fmt.Sprintf("employee.%d.%d@example.test", d+1, e+1), dealershipID, seedTime); err != nil {
		return err
	}
	if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.user_roles (user_role_id,user_id,role_id,created_at) VALUES ($1,$2,(SELECT role_id FROM appointment_scheduler.roles WHERE code=$3),$4) ON CONFLICT (user_role_id) DO UPDATE SET role_id = EXCLUDED.role_id, deleted_at = NULL`, fixtureID("user-role", fmt.Sprint(d), fmt.Sprint(e)), uid, role, seedTime); err != nil {
		return err
	}
	if e < 5 {
		return nil
	}
	tid := fixtureID("technician", fmt.Sprint(d), fmt.Sprint(e-5))
	if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.technicians (technician_id,user_id,is_active,created_at,updated_at) VALUES ($1,$2,true,$3,$3) ON CONFLICT (technician_id) DO NOTHING`, tid, uid, seedTime); err != nil {
		return err
	}
	for j := 0; j < 5; j++ {
		skill := skills[(e-5+j*3)%len(skills)]
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.technician_skills (technician_skill_id,technician_id,skill_id,created_at,updated_at) VALUES ($1,$2,$3,$4,$4) ON CONFLICT (technician_skill_id) DO NOTHING`, fixtureID("tech-skill", fmt.Sprint(d), fmt.Sprint(e), skill), tid, fixtureID("skill", skill), seedTime); err != nil {
			return err
		}
	}
	// Five broadly qualified technicians ensure every service is feasible while
	// the remaining technicians retain varied skill combinations.
	if e < 10 {
		for _, skill := range skills {
			if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.technician_skills (technician_skill_id,technician_id,skill_id,created_at,updated_at) VALUES ($1,$2,$3,$4,$4) ON CONFLICT DO NOTHING`, fixtureID("tech-skill-all", fmt.Sprint(d), skill), tid, fixtureID("skill", skill), seedTime); err != nil {
				return err
			}
		}
	}
	for day := 1; day <= 7; day++ {
		start, end := "06:00", "15:00"
		if e >= 10 {
			start, end = "14:00", "23:00"
		}
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.technician_shifts (technician_shift_id,technician_id,day_of_week,starts_at,ends_at,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,$6) ON CONFLICT (technician_shift_id) DO NOTHING`, fixtureID("shift", fmt.Sprint(d), fmt.Sprint(e), fmt.Sprint(day)), tid, day, start, end, seedTime); err != nil {
			return err
		}
	}
	if e == 6 {
		start, end := localUTC(dealershipSpecs[d].timezone, 2026, time.September, 3, 12, 0), localUTC(dealershipSpecs[d].timezone, 2026, time.September, 3, 14, 0)
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.technician_time_off (technician_time_off_id,technician_id,starts_at,ends_at,reason,created_by_user_id,created_at,updated_at) VALUES ($1,$2,$3,$4,'Seed availability-blocking training',$5,$6,$6) ON CONFLICT (technician_time_off_id) DO NOTHING`, fixtureID("time-off", fmt.Sprint(d)), tid, start, end, fixtureID("scheduler-user", fmt.Sprint(d), "1"), seedTime); err != nil {
			return err
		}
	}
	return nil
}
func seedCustomersAndVehicles(ctx context.Context, tx pgx.Tx) error {
	for customer := 0; customer < 100; customer++ {
		cid := fixtureID("customer", fmt.Sprint(customer))
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.customers (customer_id,name,phone,email,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$5) ON CONFLICT (customer_id) DO NOTHING`, cid, fmt.Sprintf("Seed Customer %03d", customer+1), fmt.Sprintf("+1555000%04d", customer+1), fmt.Sprintf("customer.%03d@example.test", customer+1), seedTime); err != nil {
			return err
		}
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.customer_dealerships (customer_id,dealership_id,created_at) VALUES ($1,$2,$3) ON CONFLICT (customer_id) DO NOTHING`, cid, fixtureID("dealership", dealershipSpecs[customer%5].code), seedTime); err != nil {
			return err
		}
	}
	for vehicle := 0; vehicle < 130; vehicle++ {
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.vehicles (vehicle_id,customer_id,vin,registration_plate,make,model,model_year,created_at,updated_at) VALUES ($1,$2,$3,$4,'Seed','Fixture',2024,$5,$5) ON CONFLICT (vehicle_id) DO NOTHING`, fixtureID("vehicle", fmt.Sprint(vehicle)), fixtureID("customer", fmt.Sprint(vehicle%100)), fmt.Sprintf("S%016d", vehicle+1), fmt.Sprintf("SEED%04d", vehicle+1), seedTime); err != nil {
			return err
		}
	}
	return nil
}
func seedAppointments(ctx context.Context, tx pgx.Tx, d int) error {
	for n := 0; n < 30; n++ {
		if err := seedAppointment(ctx, tx, d, n); err != nil {
			return err
		}
	}
	return nil
}
func seedAppointment(ctx context.Context, tx pgx.Tx, d, n int) error {
	month, day := time.August, 27
	if n >= 10 {
		day = 28
	}
	if n >= 20 {
		month, day = time.September, 3
	}
	hour := 7 + n/5
	technician := n % 5
	bay := n % 7
	if n == 1 || n == 2 || n == 7 {
		technician, bay = 0, 0
	}
	status := []string{"completed", "cancelled", "requested", "checked_in", "in_progress"}[n%5]
	start := localUTC(dealershipSpecs[d].timezone, 2026, month, day, hour, 0)
	end := start.Add(time.Hour)
	aid := fixtureID("appointment", fmt.Sprint(d), fmt.Sprint(n))
	customer := (d + n*5) % 100
	vehicle := customer
	creator := fixtureID("scheduler-user", fmt.Sprint(d), "3")
	var cancelledBy any
	var reason any
	var cancelledAt any
	if status == "cancelled" {
		cancelledBy, reason, cancelledAt = creator, "Customer rescheduled", start.Add(-time.Hour)
	}
	if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.appointments (appointment_id,reference_code,customer_id,vehicle_id,dealership_id,service_type_id,technician_id,service_bay_id,starts_at,ends_at,status,notes,created_by_user_id,cancelled_by_user_id,cancellation_reason,created_at,updated_at,cancelled_at,checked_in_at,in_progress_at,started_at,completed_at,actual_ends_at,planned_duration_minutes) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'Deterministic development fixture',$12,$13,$14,$15,$15,$16,$17,$18,$19,$20,$21,60) ON CONFLICT (appointment_id) DO NOTHING`, aid, fmt.Sprintf("SEED-%s-%02d", dealershipSpecs[d].code, n+1), fixtureID("customer", fmt.Sprint(customer)), fixtureID("vehicle", fmt.Sprint(vehicle)), fixtureID("dealership", dealershipSpecs[d].code), fixtureID("service", fmt.Sprint(d), fmt.Sprint(n%len(services))), fixtureID("technician", fmt.Sprint(d), fmt.Sprint(technician)), fixtureID("bay", fmt.Sprint(d), fmt.Sprint(bay)), start, end, status, creator, cancelledBy, reason, seedTime, cancelledAt, nullableTime(status, "checked_in", start), nullableTime(status, "in_progress", start.Add(10*time.Minute)), nullableTime(status, "in_progress", start.Add(10*time.Minute)), nullableTime(status, "completed", end), nullableTime(status, "completed", end)); err != nil {
		return err
	}
	if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.appointment_audit_events (appointment_audit_event_id,appointment_id,actor_user_id,event_type,after_data,occurred_at) VALUES ($1,$2,$3,'created',jsonb_build_object('status','requested'),$4) ON CONFLICT (appointment_audit_event_id) DO NOTHING`, fixtureID("audit-created", fmt.Sprint(d), fmt.Sprint(n)), aid, creator, seedTime); err != nil {
		return err
	}
	if status != "requested" {
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.appointment_audit_events (appointment_audit_event_id,appointment_id,actor_user_id,event_type,after_data,occurred_at) VALUES ($1,$2,$3,$4,jsonb_build_object('status',$5::text),$6) ON CONFLICT (appointment_audit_event_id) DO NOTHING`, fixtureID("audit-status", fmt.Sprint(d), fmt.Sprint(n)), aid, creator, status, status, start); err != nil {
			return err
		}
	}
	for _, resource := range []struct {
		typ string
		id  uuid.UUID
	}{{"technician", fixtureID("technician", fmt.Sprint(d), fmt.Sprint(technician))}, {"service_bay", fixtureID("bay", fmt.Sprint(d), fmt.Sprint(bay))}} {
		var released any
		if status == "completed" || status == "cancelled" {
			released = end
		}
		if err := exec(ctx, tx, `INSERT INTO appointment_scheduler.appointment_resource_reservations (appointment_resource_reservation_id,appointment_id,resource_type,resource_id,reserved_starts_at,reserved_ends_at,status,assigned_at,released_at,assigned_by_user_id,reason) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'Seed fixture') ON CONFLICT (appointment_resource_reservation_id) DO NOTHING`, fixtureID("reservation", fmt.Sprint(d), fmt.Sprint(n), resource.typ), aid, resource.typ, resource.id, start, end, status, seedTime, released, creator); err != nil {
			return err
		}
	}
	return nil
}
func nullableTime(status, wanted string, value time.Time) any {
	if status == wanted || (wanted == "checked_in" && status == "in_progress") {
		return value
	}
	return nil
}
func localUTC(zone string, year int, month time.Month, day, hour, minute int) time.Time {
	location, err := time.LoadLocation(zone)
	if err != nil {
		panic(err)
	}
	return time.Date(year, month, day, hour, minute, 0, 0, location).UTC()
}
