package tests_test

import (
	"net/http"
	"testing"
)

func TestComponent_ProtectedEndpointsRequireAuthentication(t *testing.T) {
	requireComponentTest(t)

	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/customers", "", map[string]string{
		"name":  "Unauthenticated Customer",
		"phone": "+84901234567",
	})
	requireStatus(t, response, http.StatusUnauthorized)
}

func TestComponent_AppointmentLifecycle(t *testing.T) {
	requireComponentTest(t)

	superadminToken := superadminToken(t)
	dealership := createDealership(t, superadminToken)
	admin := createDealershipAdmin(t, superadminToken, dealership.DealershipID)
	adminToken := signIn(t, admin.Email, admin.Password)

	createOperationTime(t, adminToken, dealership.DealershipID)
	serviceType := createServiceType(t, adminToken, dealership.DealershipID)
	serviceBay := createServiceBay(t, adminToken, dealership.DealershipID)
	customer := createCustomer(t, adminToken)
	vehicle := createVehicle(t, adminToken, customer.CustomerID)
	technician := createTechnician(t, adminToken)
	createTechnicianShift(t, adminToken, technician.TechnicianID)

	appointment := scheduleAppointment(t, adminToken, customer.CustomerID, vehicle.VehicleID, serviceType.ServiceTypeID, technician.TechnicianID, serviceBay.ServiceBayID)
	transitionAppointment(t, adminToken, appointment.AppointmentID, "check-in", map[string]string{"note": "Vehicle received"})
	transitionAppointment(t, adminToken, appointment.AppointmentID, "start", map[string]string{"note": "Work started"})
	transitionAppointment(t, adminToken, appointment.AppointmentID, "complete", map[string]string{"note": "Work completed"})
}

type dealershipResponse struct {
	DealershipID string `json:"dealership_id"`
}

func createDealership(t *testing.T, token string) dealershipResponse {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/dealerships", token, map[string]string{
		"name":     uniqueValue("Component Motors"),
		"code":     uniqueValue("CMP"),
		"address":  "1 Component Test Street",
		"timezone": "UTC",
	})
	requireStatus(t, response, http.StatusCreated)
	return decodeBody[dealershipResponse](t, response)
}

type componentAdmin struct {
	Email    string
	Password string
}

type userCreatedResponse struct {
	ID string `json:"id"`
}

func createDealershipAdmin(t *testing.T, superadminToken, dealershipID string) componentAdmin {
	t.Helper()
	admin := componentAdmin{
		Email:    uniqueValue("component-admin") + "@example.test",
		Password: "ComponentPass1@",
	}
	response := requestJSON(t, http.MethodPost, "/auth/v1/sign-up", "", map[string]string{
		"email":     admin.Email,
		"password":  admin.Password,
		"full_name": "Component Administrator",
	})
	requireStatus(t, response, http.StatusCreated)
	user := decodeBody[userCreatedResponse](t, response)

	response = requestJSON(t, http.MethodPatch, "/auth/v1/users/"+user.ID+"/role", superadminToken, map[string]string{"role": "admin"})
	requireStatus(t, response, http.StatusNoContent)

	response = requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/dealership-users/admins", superadminToken, map[string]string{
		"dealership_id": dealershipID,
		"email":         admin.Email,
		"name":          "Component Administrator",
		"phone":         "+84901234568",
	})
	requireStatus(t, response, http.StatusCreated)
	return admin
}

func signIn(t *testing.T, email, password string) string {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/auth/v1/sign-in", "", map[string]string{
		"email":    email,
		"password": password,
	})
	requireStatus(t, response, http.StatusOK)
	return decodeBody[tokens](t, response).AccessToken
}

func createOperationTime(t *testing.T, token, dealershipID string) {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/dealerships/"+dealershipID+"/operation-times", token, map[string]any{
		"day_of_week": 1,
		"opens_at":    "08:00",
		"closes_at":   "18:00",
	})
	requireStatus(t, response, http.StatusCreated)
}

type serviceTypeResponse struct {
	ServiceTypeID string `json:"service_type_id"`
}

func createServiceType(t *testing.T, token, dealershipID string) serviceTypeResponse {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/dealerships/"+dealershipID+"/service-types", token, map[string]any{
		"name":                     uniqueValue("Oil change"),
		"default_duration_minutes": 60,
		"min_duration_minutes":     30,
		"max_duration_minutes":     90,
	})
	requireStatus(t, response, http.StatusCreated)
	return decodeBody[serviceTypeResponse](t, response)
}

type serviceBayResponse struct {
	ServiceBayID string `json:"service_bay_id"`
}

func createServiceBay(t *testing.T, token, dealershipID string) serviceBayResponse {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/dealerships/"+dealershipID+"/service-bays", token, map[string]string{
		"code": uniqueValue("BAY"),
		"name": "Component Test Bay",
	})
	requireStatus(t, response, http.StatusCreated)
	return decodeBody[serviceBayResponse](t, response)
}

type customerResponse struct {
	CustomerID string `json:"customer_id"`
}

func createCustomer(t *testing.T, token string) customerResponse {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/customers", token, map[string]string{
		"name":  "Component Customer",
		"phone": uniquePhone(),
	})
	requireStatus(t, response, http.StatusCreated)
	return decodeBody[customerResponse](t, response)
}

type vehicleResponse struct {
	VehicleID string `json:"vehicle_id"`
}

func createVehicle(t *testing.T, token, customerID string) vehicleResponse {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/customers/"+customerID+"/vehicles", token, map[string]string{
		"vin":   uniqueIdentifier("VIN", 17),
		"make":  "Component",
		"model": "Test Vehicle",
	})
	requireStatus(t, response, http.StatusCreated)
	return decodeBody[vehicleResponse](t, response)
}

type technicianResponse struct {
	TechnicianID string `json:"technician_id"`
}

func createTechnician(t *testing.T, token string) technicianResponse {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/technicians", token, map[string]string{
		"name":  "Component Technician",
		"phone": uniquePhone(),
	})
	requireStatus(t, response, http.StatusCreated)
	return decodeBody[technicianResponse](t, response)
}

func createTechnicianShift(t *testing.T, token, technicianID string) {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/technicians/"+technicianID+"/shifts", token, map[string]any{
		"day_of_week": 1,
		"starts_at":   "08:00",
		"ends_at":     "18:00",
	})
	requireStatus(t, response, http.StatusCreated)
}

type appointmentResponse struct {
	AppointmentID string `json:"appointment_id"`
}

func scheduleAppointment(t *testing.T, token, customerID, vehicleID, serviceTypeID, technicianID, serviceBayID string) appointmentResponse {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/appointments", token, map[string]any{
		"customer_id":              customerID,
		"vehicle_id":               vehicleID,
		"service_type_id":          serviceTypeID,
		"technician_id":            technicianID,
		"service_bay_id":           serviceBayID,
		"starts_at":                "2030-01-07T09:00:00Z",
		"planned_duration_minutes": 60,
	})
	requireStatus(t, response, http.StatusCreated)
	return decodeBody[appointmentResponse](t, response)
}

func transitionAppointment(t *testing.T, token, appointmentID, action string, body map[string]string) {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/appointment-scheduler/v1/appointments/"+appointmentID+"/"+action, token, body)
	requireStatus(t, response, http.StatusNoContent)
}
