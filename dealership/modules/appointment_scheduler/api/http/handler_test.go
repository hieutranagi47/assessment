package http

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	stdhttp "net/http"
	"net/http/httptest"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/app"
	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"
	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type repositoryStub struct {
	err                    error
	isActiveSchedulerAdmin bool
}

func TestServiceBayHTTPAuthorizationOwnershipValidationAndConflict(t *testing.T) {
	actor := uuid.New()
	dealershipID := uuid.New()
	otherDealershipID := uuid.New()
	serviceBay, err := domain.NewServiceBay(uuid.New(), dealershipID, "B-01", "Main bay", true, time.Now())
	require.NoError(t, err)

	tests := []struct {
		name       string
		auth       authStub
		repository *serviceBayHTTPRepositoryStub
		method     string
		path       string
		body       string
		wantStatus int
		wantSlug   string
	}{
		{name: "admin may create", auth: authStub{identity: client.Identity{UserID: actor}}, repository: &serviceBayHTTPRepositoryStub{repositoryStub: repositoryStub{isActiveSchedulerAdmin: true}}, method: stdhttp.MethodPost, path: "/v1/dealerships/" + dealershipID.String() + "/service-bays", body: `{"code":" B-01 ","name":" Main bay "}`, wantStatus: stdhttp.StatusCreated},
		{name: "non admin is forbidden", auth: authStub{identity: client.Identity{UserID: actor}}, repository: &serviceBayHTTPRepositoryStub{}, method: stdhttp.MethodPost, path: "/v1/dealerships/" + dealershipID.String() + "/service-bays", body: `{"code":"B-01","name":"Main bay"}`, wantStatus: stdhttp.StatusForbidden, wantSlug: "service_bay_access_forbidden"},
		{name: "blank code is invalid", auth: authStub{identity: client.Identity{UserID: actor}}, repository: &serviceBayHTTPRepositoryStub{repositoryStub: repositoryStub{isActiveSchedulerAdmin: true}}, method: stdhttp.MethodPost, path: "/v1/dealerships/" + dealershipID.String() + "/service-bays", body: `{"code":" ","name":"Main bay"}`, wantStatus: stdhttp.StatusBadRequest, wantSlug: "invalid_service_bay"},
		{name: "outside dealership is scoped not found", auth: authStub{identity: client.Identity{UserID: actor}}, repository: &serviceBayHTTPRepositoryStub{repositoryStub: repositoryStub{isActiveSchedulerAdmin: true}, serviceBay: serviceBay}, method: stdhttp.MethodGet, path: "/v1/dealerships/" + otherDealershipID.String() + "/service-bays/" + serviceBay.ID().String(), wantStatus: stdhttp.StatusNotFound, wantSlug: "service_bay_not_found"},
		{name: "assigned bay delete conflicts", auth: authStub{identity: client.Identity{UserID: actor}}, repository: &serviceBayHTTPRepositoryStub{repositoryStub: repositoryStub{isActiveSchedulerAdmin: true}, deleteErr: app.ErrServiceBayInUse}, method: stdhttp.MethodDelete, path: "/v1/dealerships/" + dealershipID.String() + "/service-bays/" + serviceBay.ID().String(), wantStatus: stdhttp.StatusConflict, wantSlug: "service_bay_in_use"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := app.NewService(test.repository, test.auth)
			router := common.NewEcho(common.EchoConfig{})
			Register(context.Background(), router, NewHandler(service, test.auth))
			request := httptest.NewRequest(test.method, test.path, bytes.NewBufferString(test.body))
			request.Header.Set("Authorization", "Bearer access-token")
			request.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			require.Equal(t, test.wantStatus, recorder.Code, recorder.Body.String())
			if test.wantSlug != "" {
				require.Contains(t, recorder.Body.String(), `"slug":"`+test.wantSlug+`"`)
			}
		})
	}
}

func (r repositoryStub) Create(context.Context, domain.Dealership) error { return r.err }

func (r repositoryStub) IsActiveSchedulerAdmin(context.Context, uuid.UUID) (bool, error) {
	return r.isActiveSchedulerAdmin, nil
}

type adminRepositoryStub struct {
	repositoryStub
	created domain.DealershipAdmin
	err     error
}

type dealershipUserHTTPRepositoryStub struct {
	repositoryStub
	err error
}

type serviceBayHTTPRepositoryStub struct {
	repositoryStub
	serviceBay domain.ServiceBay
	createErr  error
	deleteErr  error
}

type operationTimeHTTPRepositoryStub struct {
	repositoryStub
	active    bool
	item      domain.DealershipOperationTime
	createErr error
}

type vehicleHTTPRepositoryStub struct {
	repositoryStub
	dealershipID uuid.UUID
	customerID   uuid.UUID
	vehicle      domain.Vehicle
}

func (r vehicleHTTPRepositoryStub) GetActiveVehicleManagerDealership(context.Context, uuid.UUID) (uuid.UUID, error) {
	if r.dealershipID == uuid.Nil {
		return uuid.Nil, app.ErrVehicleCustomerForbidden
	}
	return r.dealershipID, nil
}

func (r vehicleHTTPRepositoryStub) GetCustomer(_ context.Context, customerID uuid.UUID) (domain.Customer, error) {
	if customerID != r.customerID {
		return domain.Customer{}, app.ErrCustomerNotFound
	}
	return domain.RestoreCustomer(customerID, "Jane Doe", "+84901234567", nil, time.Now(), time.Now()), nil
}

func (r *vehicleHTTPRepositoryStub) CreateVehicle(_ context.Context, _ uuid.UUID, vehicle domain.Vehicle) error {
	r.vehicle = vehicle
	return nil
}

func (r vehicleHTTPRepositoryStub) GetVehicle(context.Context, uuid.UUID) (domain.Vehicle, error) {
	if r.vehicle.ID() == uuid.Nil {
		return domain.Vehicle{}, app.ErrVehicleNotFound
	}
	return r.vehicle, nil
}

func (r vehicleHTTPRepositoryStub) ListCustomerVehicles(context.Context, uuid.UUID) ([]domain.Vehicle, error) {
	return nil, nil
}

func (r vehicleHTTPRepositoryStub) CustomerBelongsToDealership(_ context.Context, customerID, dealershipID uuid.UUID) (bool, error) {
	return customerID == r.customerID && dealershipID == r.dealershipID, nil
}

func (r *vehicleHTTPRepositoryStub) UpdateVehicle(context.Context, domain.Vehicle) error { return nil }
func (r *vehicleHTTPRepositoryStub) DeleteVehicle(context.Context, uuid.UUID, time.Time) error {
	return nil
}

func TestVehicleCreateHTTPAuthorizationAndNormalization(t *testing.T) {
	actorID := uuid.New()
	customerID := uuid.New()
	tests := []struct {
		name       string
		repository *vehicleHTTPRepositoryStub
		wantStatus int
		wantSlug   string
	}{
		{name: "authorized employee", repository: &vehicleHTTPRepositoryStub{dealershipID: uuid.New(), customerID: customerID}, wantStatus: stdhttp.StatusCreated},
		{name: "role forbidden", repository: &vehicleHTTPRepositoryStub{customerID: customerID}, wantStatus: stdhttp.StatusForbidden, wantSlug: "vehicle_access_forbidden"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			auth := authStub{identity: client.Identity{UserID: actorID}}
			service := app.NewService(test.repository, auth)
			router := common.NewEcho(common.EchoConfig{})
			Register(context.Background(), router, NewHandler(service, auth))
			request := httptest.NewRequest(stdhttp.MethodPost, "/v1/customers/"+customerID.String()+"/vehicles", bytes.NewBufferString(`{"vin":" 1hgcm82633a004352 ","make":"Toyota","model":"Camry"}`))
			request.Header.Set("Authorization", "Bearer access-token")
			request.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			require.Equal(t, test.wantStatus, recorder.Code, recorder.Body.String())
			if test.wantSlug != "" {
				require.Contains(t, recorder.Body.String(), `"slug":"`+test.wantSlug+`"`)
			}
			if test.wantStatus == stdhttp.StatusCreated {
				require.Equal(t, "1HGCM82633A004352", *test.repository.vehicle.VIN())
			}
		})
	}
}

func (r operationTimeHTTPRepositoryStub) IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.isActiveSchedulerAdmin, nil
}
func (r operationTimeHTTPRepositoryStub) IsActiveDealership(context.Context, uuid.UUID) (bool, error) {
	return r.active, nil
}
func (r *operationTimeHTTPRepositoryStub) CreateDealershipOperationTime(_ context.Context, item domain.DealershipOperationTime) error {
	if r.createErr != nil {
		return r.createErr
	}
	r.item = item
	return nil
}
func (r operationTimeHTTPRepositoryStub) GetDealershipOperationTime(_ context.Context, dealershipID, itemID uuid.UUID) (domain.DealershipOperationTime, error) {
	if r.item.ID() == uuid.Nil || r.item.ID() != itemID || r.item.DealershipID() != dealershipID {
		return domain.DealershipOperationTime{}, app.ErrDealershipOperationTimeNotFound
	}
	return r.item, nil
}
func (r operationTimeHTTPRepositoryStub) ListDealershipOperationTimes(_ context.Context, dealershipID uuid.UUID) ([]domain.DealershipOperationTime, error) {
	if r.item.ID() == uuid.Nil || r.item.DealershipID() != dealershipID {
		return []domain.DealershipOperationTime{}, nil
	}
	return []domain.DealershipOperationTime{r.item}, nil
}
func (r *operationTimeHTTPRepositoryStub) UpdateDealershipOperationTime(_ context.Context, item domain.DealershipOperationTime) error {
	r.item = item
	return nil
}
func (r *operationTimeHTTPRepositoryStub) DeleteDealershipOperationTime(_ context.Context, dealershipID, itemID uuid.UUID) error {
	if r.item.ID() == uuid.Nil || r.item.ID() != itemID || r.item.DealershipID() != dealershipID {
		return app.ErrDealershipOperationTimeNotFound
	}
	r.item = domain.DealershipOperationTime{}
	return nil
}

func TestDealershipOperationTimeHTTPAuthorizationAndValidation(t *testing.T) {
	actor, dealershipID := uuid.New(), uuid.New()
	tests := []struct {
		name, body string
		auth       authStub
		repository *operationTimeHTTPRepositoryStub
		wantStatus int
		wantSlug   string
	}{
		{"admin may create", `{"dayOfWeek":1,"opensAt":"08:00","closesAt":"12:00"}`, authStub{identity: client.Identity{UserID: actor}}, &operationTimeHTTPRepositoryStub{repositoryStub: repositoryStub{isActiveSchedulerAdmin: true}, active: true}, stdhttp.StatusCreated, ""},
		{"staff is denied", `{"dayOfWeek":1,"opensAt":"08:00","closesAt":"12:00"}`, authStub{identity: client.Identity{UserID: actor}}, &operationTimeHTTPRepositoryStub{active: true}, stdhttp.StatusForbidden, "operation_time_access_forbidden"},
		{"unauthenticated is denied", `{"dayOfWeek":1,"opensAt":"08:00","closesAt":"12:00"}`, authStub{authErr: errors.New("bad token")}, &operationTimeHTTPRepositoryStub{active: true}, stdhttp.StatusUnauthorized, "authentication_required"},
		{"invalid clock is rejected", `{"dayOfWeek":1,"opensAt":"8:00","closesAt":"12:00"}`, authStub{identity: client.Identity{UserID: actor}}, &operationTimeHTTPRepositoryStub{repositoryStub: repositoryStub{isActiveSchedulerAdmin: true}, active: true}, stdhttp.StatusBadRequest, "invalid_operation_time"},
		{"equal clock values are rejected", `{"dayOfWeek":1,"opensAt":"08:00","closesAt":"08:00"}`, authStub{identity: client.Identity{UserID: actor}}, &operationTimeHTTPRepositoryStub{repositoryStub: repositoryStub{isActiveSchedulerAdmin: true}, active: true}, 422, "invalid_operation_time"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := app.NewService(test.repository, test.auth)
			router := common.NewEcho(common.EchoConfig{})
			Register(context.Background(), router, NewHandler(service, test.auth))
			request := httptest.NewRequest(stdhttp.MethodPost, "/v1/dealerships/"+dealershipID.String()+"/operation-times", bytes.NewBufferString(test.body))
			request.Header.Set("Authorization", "Bearer access-token")
			request.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			require.Equal(t, test.wantStatus, recorder.Code, recorder.Body.String())
			if test.wantSlug != "" {
				require.Contains(t, recorder.Body.String(), `"slug":"`+test.wantSlug+`"`)
			}
		})
	}
}

func (r serviceBayHTTPRepositoryStub) IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.isActiveSchedulerAdmin, nil
}

func (r *serviceBayHTTPRepositoryStub) CreateServiceBay(_ context.Context, serviceBay domain.ServiceBay) error {
	r.serviceBay = serviceBay
	return r.createErr
}

func (r serviceBayHTTPRepositoryStub) GetServiceBay(_ context.Context, dealershipID, _ uuid.UUID) (domain.ServiceBay, error) {
	if r.serviceBay.ID() == uuid.Nil || r.serviceBay.DealershipID() != dealershipID {
		return domain.ServiceBay{}, app.ErrServiceBayNotFound
	}
	return r.serviceBay, nil
}

func (r serviceBayHTTPRepositoryStub) ListServiceBays(context.Context, uuid.UUID, *bool, int, int) ([]domain.ServiceBay, error) {
	return []domain.ServiceBay{r.serviceBay}, nil
}

func (r *serviceBayHTTPRepositoryStub) UpdateServiceBay(_ context.Context, serviceBay domain.ServiceBay) error {
	r.serviceBay = serviceBay
	return r.createErr
}

func (r serviceBayHTTPRepositoryStub) DeleteServiceBay(context.Context, uuid.UUID, uuid.UUID, time.Time) error {
	return r.deleteErr
}

func (r dealershipUserHTTPRepositoryStub) CreateDealershipUser(context.Context, domain.DealershipUser) error {
	return r.err
}

func (r dealershipUserHTTPRepositoryStub) IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.isActiveSchedulerAdmin, nil
}

func (r *adminRepositoryStub) CreateDealershipAdmin(_ context.Context, admin domain.DealershipAdmin) error {
	if r.err != nil {
		return r.err
	}
	r.created = admin
	return nil
}

type authStub struct {
	identity client.Identity
	authErr  error
	info     client.UserInfo
	infoErr  error
}

func (a authStub) AuthenticateAccessToken(string) (client.Identity, error) {
	return a.identity, a.authErr
}
func (a authStub) GetUserInfo(context.Context, uuid.UUID) (client.UserInfo, error) {
	return a.info, a.infoErr
}
func (a authStub) GetUserInfoByEmail(context.Context, string) (client.UserInfo, error) {
	return a.info, a.infoErr
}

func TestCreateDealershipHTTPErrorMapping(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	body := `{"name":"Downtown Motors","code":"dtm","address":"1 Main Street","timezone":"Asia/Ho_Chi_Minh"}`
	tests := []struct {
		name       string
		auth       authStub
		repository repositoryStub
		body       string
		wantStatus int
		wantSlug   string
	}{
		{name: "missing authentication", auth: authStub{authErr: errors.New("invalid token")}, body: body, wantStatus: stdhttp.StatusUnauthorized, wantSlug: "authentication_required"},
		{name: "ordinary user", auth: authStub{identity: client.Identity{UserID: actor}, info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "user"}}, body: body, wantStatus: stdhttp.StatusForbidden, wantSlug: "dealership_create_forbidden"},
		{name: "invalid timezone", auth: authStub{identity: client.Identity{UserID: actor}, info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}}, body: `{"name":"Downtown Motors","code":"dtm","address":"1 Main Street","timezone":"Mars/Olympus"}`, wantStatus: stdhttp.StatusBadRequest, wantSlug: "invalid_dealership"},
		{name: "duplicate code", auth: authStub{identity: client.Identity{UserID: actor}, info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}}, repository: repositoryStub{err: app.ErrDealershipCodeTaken}, body: body, wantStatus: stdhttp.StatusConflict, wantSlug: "dealership_code_taken"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := app.NewService(test.repository, test.auth)
			router := common.NewEcho(common.EchoConfig{})
			Register(context.Background(), router, NewHandler(service, test.auth))
			request := httptest.NewRequest(stdhttp.MethodPost, "/dealerships", bytes.NewBufferString(test.body))
			request.Header.Set("Authorization", "Bearer access-token")
			request.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			require.Equal(t, test.wantStatus, recorder.Code, recorder.Body.String())
			require.Contains(t, recorder.Body.String(), `"slug":"`+test.wantSlug+`"`)
		})
	}
}

func TestCreateDealershipAdminResponseSerialization(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	target := uuid.New()
	dealershipID := uuid.New()
	repository := &adminRepositoryStub{}
	auth := adminAuthStub{actor: actor, target: target}
	service := app.NewService(repository, auth)
	router := common.NewEcho(common.EchoConfig{})
	Register(context.Background(), router, NewHandler(service, auth))
	body := `{"dealershipId":"` + dealershipID.String() + `","name":" Jane Doe ","phone":" +84901234567 ","email":" Jane@Example.com "}`
	request := httptest.NewRequest(stdhttp.MethodPost, "/dealership-users/admins", bytes.NewBufferString(body))
	request.Header.Set("Authorization", "Bearer access-token")
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)

	require.Equal(t, stdhttp.StatusCreated, recorder.Code, recorder.Body.String())
	var response map[string]any
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &response))
	require.Equal(t, target.String(), response["authUserId"])
	require.Equal(t, dealershipID.String(), response["dealershipId"])
	require.Equal(t, "Jane Doe", response["name"])
	require.Equal(t, "+84901234567", response["phone"])
	require.Equal(t, "jane@example.com", response["email"])
	require.Equal(t, true, response["isActive"])
	require.Equal(t, "admin", response["role"])
	require.NotEmpty(t, response["userId"])
	require.NotEmpty(t, response["createdAt"])
	require.NotEmpty(t, response["updatedAt"])
	require.NotEqual(t, uuid.Nil, repository.created.ID())
}

func TestCreateDealershipUserHTTPErrorMapping(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	target := uuid.New()
	dealershipID := uuid.New()
	body := `{"dealershipId":"` + dealershipID.String() + `","email":"target@example.com","role":"staff"}`
	tests := []struct {
		name       string
		auth       dealershipUserAuthStub
		repository dealershipUserHTTPRepositoryStub
		body       string
		wantStatus int
		wantSlug   string
	}{
		{name: "created", auth: dealershipUserAuthStub{actor: actor, target: target}, body: body, wantStatus: stdhttp.StatusCreated},
		{name: "technician role is created", auth: dealershipUserAuthStub{actor: actor, target: target}, body: `{"dealershipId":"` + dealershipID.String() + `","email":"target@example.com","role":"technician"}`, wantStatus: stdhttp.StatusCreated},
		{name: "invalid role", auth: dealershipUserAuthStub{actor: actor, target: target}, body: `{"dealershipId":"` + dealershipID.String() + `","email":"target@example.com","role":"owner"}`, wantStatus: stdhttp.StatusBadRequest, wantSlug: "invalid_dealership_user"},
		{name: "forbidden", auth: dealershipUserAuthStub{actor: actor, target: target, role: "user"}, body: body, wantStatus: stdhttp.StatusForbidden, wantSlug: "dealership_user_create_forbidden"},
		{name: "not found", auth: dealershipUserAuthStub{actor: actor, target: target}, repository: dealershipUserHTTPRepositoryStub{err: app.ErrDealershipNotFound}, body: body, wantStatus: stdhttp.StatusNotFound, wantSlug: "dealership_not_found"},
		{name: "conflict", auth: dealershipUserAuthStub{actor: actor, target: target}, repository: dealershipUserHTTPRepositoryStub{err: app.ErrAuthUserAlreadyAssigned}, body: body, wantStatus: stdhttp.StatusConflict, wantSlug: "auth_user_already_assigned"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := app.NewService(test.repository, test.auth)
			router := common.NewEcho(common.EchoConfig{})
			Register(context.Background(), router, NewHandler(service, test.auth))
			request := httptest.NewRequest(stdhttp.MethodPost, "/dealership-users", bytes.NewBufferString(test.body))
			request.Header.Set("Authorization", "Bearer access-token")
			request.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			require.Equal(t, test.wantStatus, recorder.Code, recorder.Body.String())
			if test.wantSlug != "" {
				require.Contains(t, recorder.Body.String(), `"slug":"`+test.wantSlug+`"`)
			}
		})
	}
}

func TestSearchAuthUserByEmailResponseSerialization(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	target := uuid.New()
	auth := searchAuthStub{actor: actor, target: target}
	service := app.NewService(repositoryStub{}, auth)
	router := common.NewEcho(common.EchoConfig{})
	Register(context.Background(), router, NewHandler(service, auth))
	request := httptest.NewRequest(stdhttp.MethodGet, "/dealership-users/search?email=jane@example.com", nil)
	request.Header.Set("Authorization", "Bearer access-token")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)

	require.Equal(t, stdhttp.StatusOK, recorder.Code, recorder.Body.String())
	var response map[string]any
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &response))
	require.Equal(t, target.String(), response["userId"])
	require.Equal(t, "jane@example.com", response["email"])
	require.Equal(t, "Jane Doe", response["fullName"])
	require.Equal(t, "active", response["status"])
	require.Equal(t, "user", response["role"])
}

func TestSearchAuthUserByEmailAuthorization(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	target := uuid.New()
	tests := []struct {
		name       string
		auth       searchAuthStub
		repository repositoryStub
		wantStatus int
		wantSlug   string
	}{
		{name: "missing authentication", auth: searchAuthStub{authErr: errors.New("invalid token")}, wantStatus: stdhttp.StatusUnauthorized, wantSlug: "authentication_required"},
		{name: "ordinary user", auth: searchAuthStub{actor: actor, target: target, actorRole: "user"}, wantStatus: stdhttp.StatusForbidden, wantSlug: "auth_user_search_forbidden"},
		{name: "scheduler admin", auth: searchAuthStub{actor: actor, target: target, actorRole: "user"}, repository: repositoryStub{isActiveSchedulerAdmin: true}, wantStatus: stdhttp.StatusOK},
		{name: "missing auth user", auth: searchAuthStub{actor: actor, target: target, targetErr: errors.New("not found")}, wantStatus: stdhttp.StatusNotFound, wantSlug: "auth_user_not_found"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := app.NewService(test.repository, test.auth)
			router := common.NewEcho(common.EchoConfig{})
			Register(context.Background(), router, NewHandler(service, test.auth))
			request := httptest.NewRequest(stdhttp.MethodGet, "/dealership-users/search?email=jane@example.com", nil)
			request.Header.Set("Authorization", "Bearer access-token")
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			require.Equal(t, test.wantStatus, recorder.Code, recorder.Body.String())
			if test.wantSlug != "" {
				require.Contains(t, recorder.Body.String(), `"slug":"`+test.wantSlug+`"`)
			}
		})
	}
}

type searchAuthStub struct {
	actor     uuid.UUID
	target    uuid.UUID
	actorRole string
	authErr   error
	targetErr error
}

func (a searchAuthStub) AuthenticateAccessToken(string) (client.Identity, error) {
	return client.Identity{UserID: a.actor}, a.authErr
}

func (a searchAuthStub) GetUserInfo(_ context.Context, id uuid.UUID) (client.UserInfo, error) {
	if id != a.actor {
		return client.UserInfo{}, errors.New("not found")
	}
	role := a.actorRole
	if role == "" {
		role = "admin"
	}
	return client.UserInfo{UserID: a.actor.String(), Status: "active", Role: role}, nil
}

func (a searchAuthStub) GetUserInfoByEmail(context.Context, string) (client.UserInfo, error) {
	if a.targetErr != nil {
		return client.UserInfo{}, a.targetErr
	}
	return client.UserInfo{UserID: a.target.String(), Email: "jane@example.com", FullName: "Jane Doe", Status: "active", Role: "user"}, nil
}

type adminAuthStub struct {
	actor  uuid.UUID
	target uuid.UUID
}

type dealershipUserAuthStub struct {
	actor, target uuid.UUID
	role          string
}

func (a dealershipUserAuthStub) AuthenticateAccessToken(string) (client.Identity, error) {
	return client.Identity{UserID: a.actor}, nil
}

func (a dealershipUserAuthStub) GetUserInfo(_ context.Context, id uuid.UUID) (client.UserInfo, error) {
	if id != a.actor {
		return client.UserInfo{}, errors.New("not found")
	}
	role := a.role
	if role == "" {
		role = "admin"
	}
	return client.UserInfo{UserID: a.actor.String(), Status: "active", Role: role}, nil
}

func (a dealershipUserAuthStub) GetUserInfoByEmail(context.Context, string) (client.UserInfo, error) {
	return client.UserInfo{UserID: a.target.String(), Email: "target@example.com", FullName: "Target User", Status: "active"}, nil
}

func (a adminAuthStub) AuthenticateAccessToken(string) (client.Identity, error) {
	return client.Identity{UserID: a.actor}, nil
}

func (a adminAuthStub) GetUserInfo(_ context.Context, id uuid.UUID) (client.UserInfo, error) {
	switch id {
	case a.actor:
		return client.UserInfo{UserID: a.actor.String(), Status: "active", Role: "admin"}, nil
	case a.target:
		return client.UserInfo{UserID: a.target.String(), Status: "active"}, nil
	default:
		return client.UserInfo{}, errors.New("not found")
	}
}

func (a adminAuthStub) GetUserInfoByEmail(_ context.Context, email string) (client.UserInfo, error) {
	if email != "" {
		return client.UserInfo{UserID: a.target.String(), Email: "jane@example.com", Status: "active"}, nil
	}
	return client.UserInfo{}, errors.New("not found")
}
