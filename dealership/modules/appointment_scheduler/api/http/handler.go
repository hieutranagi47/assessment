// Package http exposes the dealership OpenAPI surface through Echo.
package http

import (
	"context"
	"errors"
	stdhttp "net/http"
	"strings"
	"time"

	"assessment/modules/appointment_scheduler/app"
	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"
	"assessment/modules/common"

	"github.com/google/uuid"
	echo "github.com/labstack/echo/v5"
	openapi_types "github.com/oapi-codegen/runtime/types"
)

type identityKey struct{}

type Handler struct {
	service      *app.Service
	auth         client.Authenticator
	schedules    TechnicianScheduleLister
	available    AvailableServiceBayLister
	appointments DealershipAppointmentsLister
	dealerships  DealershipLister
}

type TechnicianScheduleLister interface {
	List(context.Context, app.ListTechnicianSchedulesInput) (app.TechnicianScheduleResult, error)
}

type AvailableServiceBayLister interface {
	List(context.Context, app.ListAvailableServiceBaysInput) ([]domain.ServiceBay, error)
}

type DealershipLister interface {
	List(context.Context, uuid.UUID) ([]domain.Dealership, error)
}

type DealershipAppointmentsLister interface {
	List(context.Context, app.ListDealershipAppointmentsInput) (app.DealershipAppointmentsResult, error)
}

func NewHandler(service *app.Service, auth client.Authenticator, schedules ...TechnicianScheduleLister) *Handler {
	if service == nil || auth == nil {
		panic("dealership HTTP dependencies are required")
	}
	handler := &Handler{service: service, auth: auth}
	if len(schedules) > 0 {
		handler.schedules = schedules[0]
	}
	return handler
}

func (h *Handler) SetAvailableServiceBayLister(available AvailableServiceBayLister) {
	h.available = available
}

func (h *Handler) SetDealershipAppointmentsLister(appointments DealershipAppointmentsLister) {
	h.appointments = appointments
}

func (h *Handler) SetDealershipLister(dealerships DealershipLister) {
	h.dealerships = dealerships
}

func Register(_ context.Context, router common.EchoRouter, handler *Handler) error {
	options := RegisterHandlersOptions{
		OperationMiddlewares: map[string][]echo.MiddlewareFunc{
			"listDealerships":                        {handler.requireIdentity},
			"listAvailableServiceBays":               {handler.requireIdentity},
			"listTechnicianSchedules":                {handler.requireIdentity},
			"listDealershipAppointments":             {handler.requireIdentity},
			"scheduleAppointment":                    {handler.requireIdentity},
			"checkInAppointment":                     {handler.requireIdentity},
			"startAppointment":                       {handler.requireIdentity},
			"completeAppointment":                    {handler.requireIdentity},
			"cancelAppointment":                      {handler.requireIdentity},
			"createDealershipOperationTime":          {handler.requireIdentity},
			"listDealershipOperationTimes":           {handler.requireIdentity},
			"updateDealershipOperationTime":          {handler.requireIdentity},
			"deleteDealershipOperationTime":          {handler.requireIdentity},
			"createServiceBayCapability":             {handler.requireIdentity},
			"listServiceBayCapabilities":             {handler.requireIdentity},
			"updateServiceBayCapability":             {handler.requireIdentity},
			"deleteServiceBayCapability":             {handler.requireIdentity},
			"createServiceBay":                       {handler.requireIdentity},
			"listServiceBays":                        {handler.requireIdentity},
			"getServiceBay":                          {handler.requireIdentity},
			"updateServiceBay":                       {handler.requireIdentity},
			"deleteServiceBay":                       {handler.requireIdentity},
			"createServiceType":                      {handler.requireIdentity},
			"listServiceTypes":                       {handler.requireIdentity},
			"getServiceType":                         {handler.requireIdentity},
			"updateServiceType":                      {handler.requireIdentity},
			"deleteServiceType":                      {handler.requireIdentity},
			"createServiceTypeRequiredSkill":         {handler.requireIdentity},
			"listServiceTypeRequiredSkills":          {handler.requireIdentity},
			"updateServiceTypeRequiredSkill":         {handler.requireIdentity},
			"deleteServiceTypeRequiredSkill":         {handler.requireIdentity},
			"createServiceTypeRequiredBayCapability": {handler.requireIdentity},
			"listServiceTypeRequiredBayCapabilities": {handler.requireIdentity},
			"updateServiceTypeRequiredBayCapability": {handler.requireIdentity},
			"deleteServiceTypeRequiredBayCapability": {handler.requireIdentity},
			"createDealershipUser":                   {handler.requireIdentity},
			"createDealership":                       {handler.requireIdentity},
			"createDealershipAdmin":                  {handler.requireIdentity},
			"searchAuthUserByEmail":                  {handler.requireIdentity},
			"createCustomer":                         {handler.requireIdentity},
			"getCustomer":                            {handler.requireIdentity},
			"updateCustomer":                         {handler.requireIdentity},
			"searchCustomers":                        {handler.requireIdentity},
			"createVehicle":                          {handler.requireIdentity},
			"getVehicle":                             {handler.requireIdentity},
			"listCustomerVehicles":                   {handler.requireIdentity},
			"updateVehicle":                          {handler.requireIdentity},
			"deleteVehicle":                          {handler.requireIdentity},
			"createTechnician":                       {handler.requireIdentity},
			"listTechnicians":                        {handler.requireIdentity},
			"getTechnician":                          {handler.requireIdentity},
			"updateTechnician":                       {handler.requireIdentity},
			"deleteTechnician":                       {handler.requireIdentity},
			"createTechnicianSkill":                  {handler.requireIdentity},
			"listTechnicianSkills":                   {handler.requireIdentity},
			"updateTechnicianSkill":                  {handler.requireIdentity},
			"deleteTechnicianSkill":                  {handler.requireIdentity},
			"createTechnicianShift":                  {handler.requireIdentity},
			"listTechnicianShifts":                   {handler.requireIdentity},
			"updateTechnicianShift":                  {handler.requireIdentity},
			"deleteTechnicianShift":                  {handler.requireIdentity},
			"createTechnicianTimeOff":                {handler.requireIdentity},
			"listTechnicianTimeOff":                  {handler.requireIdentity},
			"getTechnicianTimeOff":                   {handler.requireIdentity},
			"updateTechnicianTimeOff":                {handler.requireIdentity},
			"deleteTechnicianTimeOff":                {handler.requireIdentity},
		},
	}
	strictHandler := NewStrictHandler(handler, nil)
	options.BaseURL = "/appointment-scheduler/v1"
	RegisterHandlersWithOptions(router, strictHandler, options)
	RegisterDocs(router)
	return nil
}

func (h *Handler) ListDealershipAppointments(ctx context.Context, request ListDealershipAppointmentsRequestObject) (ListDealershipAppointmentsResponseObject, error) {
	if h.appointments == nil {
		return listDealershipAppointmentsErrorResponse(common.Error{PublicError: "internal server error", ErrorSlug: "internal_server_error"})
	}
	result, err := h.appointments.List(ctx, app.ListDealershipAppointmentsInput{
		ActorUserID:  identityFrom(ctx),
		DealershipID: uuid.UUID(request.DealershipId),
		Date:         request.Params.Date.String(),
	})
	if err != nil {
		return listDealershipAppointmentsErrorResponse(err)
	}
	items := make([]Appointment, 0, len(result.Appointments))
	for _, appointment := range result.Appointments {
		items = append(items, Appointment{
			AppointmentId:          appointment.AppointmentID,
			ReferenceCode:          appointment.ReferenceCode,
			CustomerId:             &appointment.CustomerID,
			VehicleId:              &appointment.VehicleID,
			DealershipId:           appointment.DealershipID,
			ServiceTypeId:          &appointment.ServiceTypeID,
			TechnicianId:           &appointment.TechnicianID,
			ServiceBayId:           &appointment.ServiceBayID,
			StartsAt:               appointment.StartsAt,
			EndsAt:                 appointment.EndsAt,
			ActualEndsAt:           appointment.ActualEndsAt,
			PlannedDurationMinutes: appointment.PlannedDurationMinutes,
			Status:                 AppointmentStatus(appointment.Status),
			Notes:                  appointment.Notes,
			CreatedAt:              appointment.CreatedAt,
			UpdatedAt:              appointment.UpdatedAt,
		})
	}
	return ListDealershipAppointments200JSONResponse{
		DealershipAppointmentsListedJSONResponse: DealershipAppointmentsListedJSONResponse{
			Date:     openapi_types.Date{Time: result.Date},
			Timezone: result.Timezone,
			Items:    items,
		},
	}, nil
}

func listDealershipAppointmentsErrorResponse(err error) (ListDealershipAppointmentsResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return ListDealershipAppointments400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return ListDealershipAppointments401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListDealershipAppointments403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ListDealershipAppointments404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListDealershipAppointments500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func (h *Handler) ListDealerships(ctx context.Context, _ ListDealershipsRequestObject) (ListDealershipsResponseObject, error) {
	if h.dealerships == nil {
		return listDealershipsErrorResponse(common.Error{PublicError: "internal server error", ErrorSlug: "internal_server_error"})
	}
	dealerships, err := h.dealerships.List(ctx, identityFrom(ctx))
	if err != nil {
		return listDealershipsErrorResponse(err)
	}
	items := make([]Dealership, 0, len(dealerships))
	for _, dealership := range dealerships {
		items = append(items, dealershipResponse(dealership))
	}
	return ListDealerships200JSONResponse{DealershipsListedJSONResponse: items}, nil
}

func dealershipResponse(dealership domain.Dealership) Dealership {
	return Dealership{
		DealershipId: dealership.ID(),
		Name:         dealership.Name(),
		Code:         dealership.Code(),
		Address:      dealership.Address(),
		Timezone:     dealership.Timezone(),
		IsActive:     dealership.IsActive(),
		CreatedAt:    dealership.CreatedAt(),
		UpdatedAt:    dealership.UpdatedAt(),
	}
}

func listDealershipsErrorResponse(err error) (ListDealershipsResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return ListDealerships401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListDealerships403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	default:
		return ListDealerships500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func (h *Handler) ListAvailableServiceBays(ctx context.Context, request ListAvailableServiceBaysRequestObject) (ListAvailableServiceBaysResponseObject, error) {
	if h.available == nil {
		return listAvailableServiceBaysErrorResponse(common.Error{PublicError: "internal server error", ErrorSlug: "internal_server_error"})
	}
	serviceBays, err := h.available.List(ctx, app.ListAvailableServiceBaysInput{
		ActorUserID:   identityFrom(ctx),
		DealershipID:  uuid.UUID(request.DealershipId),
		ServiceTypeID: uuid.UUID(request.Params.ServiceTypeId),
		StartsAt:      request.Params.StartsAt,
		EndsAt:        request.Params.EndsAt,
	})
	if err != nil {
		return listAvailableServiceBaysErrorResponse(err)
	}
	items := make([]ServiceBay, 0, len(serviceBays))
	for _, serviceBay := range serviceBays {
		items = append(items, serviceBayResponse(serviceBay))
	}
	return ListAvailableServiceBays200JSONResponse{
		AvailableServiceBaysListedJSONResponse: AvailableServiceBaysListedJSONResponse{
			StartsAt: request.Params.StartsAt.UTC(),
			EndsAt:   request.Params.EndsAt.UTC(),
			Items:    items,
		},
	}, nil
}

func listAvailableServiceBaysErrorResponse(err error) (ListAvailableServiceBaysResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return ListAvailableServiceBays400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return ListAvailableServiceBays401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListAvailableServiceBays403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ListAvailableServiceBays404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListAvailableServiceBays500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func (h *Handler) ListTechnicianSchedules(ctx context.Context, request ListTechnicianSchedulesRequestObject) (ListTechnicianSchedulesResponseObject, error) {
	if h.schedules == nil {
		return listTechnicianSchedulesErrorResponse(common.Error{PublicError: "internal server error", ErrorSlug: "internal_server_error"})
	}
	var technicianID *uuid.UUID
	if request.Params.TechnicianId != nil {
		parsed, err := uuid.Parse(*request.Params.TechnicianId)
		if err != nil {
			return listTechnicianSchedulesErrorResponse(common.NewInvalidInputError("invalid_technician_id", "technician_id must be a valid UUID"))
		}
		technicianID = &parsed
	}
	includes := make([]string, 0)
	if request.Params.Include != nil {
		includes = make([]string, 0, len(*request.Params.Include))
		for _, include := range *request.Params.Include {
			includes = append(includes, string(include))
		}
	}
	result, err := h.schedules.List(ctx, app.ListTechnicianSchedulesInput{
		ActorUserID:  identityFrom(ctx),
		DealershipID: uuid.UUID(request.DealershipId),
		Date:         request.Params.Date.String(),
		TechnicianID: technicianID,
		Include:      includes,
	})
	if err != nil {
		return listTechnicianSchedulesErrorResponse(err)
	}
	return ListTechnicianSchedules200JSONResponse{TechnicianSchedulesListedJSONResponse: TechnicianSchedulesListedJSONResponse(technicianScheduleResponse(result))}, nil
}

func technicianScheduleResponse(result app.TechnicianScheduleResult) TechnicianScheduleResponse {
	technicians := make([]TechnicianSchedule, 0, len(result.Technicians))
	for _, technician := range result.Technicians {
		shifts := make([]TechnicianScheduleShift, 0, len(technician.Shifts))
		for _, shift := range technician.Shifts {
			shifts = append(shifts, TechnicianScheduleShift{StartsAt: shift.StartsAt.UTC(), EndsAt: shift.EndsAt.UTC()})
		}
		occupiedSlots := make([]TechnicianOccupiedSlot, 0, len(technician.OccupiedSlots))
		for _, slot := range technician.OccupiedSlots {
			occupiedSlots = append(occupiedSlots, technicianOccupiedSlotResponse(slot))
		}
		technicians = append(technicians, TechnicianSchedule{TechnicianId: openapi_types.UUID(technician.TechnicianID), UserId: openapi_types.UUID(technician.UserID), Name: technician.Name, Shifts: shifts, OccupiedSlots: occupiedSlots})
	}
	return TechnicianScheduleResponse{DealershipId: openapi_types.UUID(result.DealershipID), Timezone: result.Timezone, Date: openapi_types.Date{Time: result.Date}, PeriodStartsAt: result.PeriodStartsAt.UTC(), PeriodEndsAt: result.PeriodEndsAt.UTC(), Technicians: technicians}
}

func technicianOccupiedSlotResponse(slot app.TechnicianScheduleResultOccupiedSlot) TechnicianOccupiedSlot {
	response := TechnicianOccupiedSlot{Kind: TechnicianOccupiedSlotKind(slot.Kind), StartsAt: slot.StartsAt.UTC(), EndsAt: slot.EndsAt.UTC()}
	if slot.AppointmentID != nil {
		value := openapi_types.UUID(*slot.AppointmentID)
		response.AppointmentId = &value
	}
	if slot.ReferenceCode != nil {
		response.ReferenceCode = slot.ReferenceCode
	}
	if slot.Status != nil {
		value := TechnicianOccupiedSlotStatus(*slot.Status)
		response.Status = &value
	}
	if slot.ServiceTypeName != nil {
		response.ServiceTypeName = slot.ServiceTypeName
	}
	if slot.ServiceBayID != nil {
		value := openapi_types.UUID(*slot.ServiceBayID)
		response.ServiceBayId = &value
	}
	if slot.ServiceBayCode != nil {
		response.ServiceBayCode = slot.ServiceBayCode
	}
	return response
}

func listTechnicianSchedulesErrorResponse(err error) (ListTechnicianSchedulesResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return ListTechnicianSchedules400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return ListTechnicianSchedules401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListTechnicianSchedules403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ListTechnicianSchedules404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListTechnicianSchedules500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func (h *Handler) ScheduleAppointment(ctx context.Context, request ScheduleAppointmentRequestObject) (ScheduleAppointmentResponseObject, error) {
	if request.Body == nil {
		response := errorResponse(common.NewInvalidInputError("validation_error", "request body is required"))
		return ScheduleAppointment400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	record, err := h.service.ScheduleAppointment(ctx, identityFrom(ctx), app.ScheduleAppointmentInput{
		CustomerID:             uuid.UUID(request.Body.CustomerId),
		VehicleID:              uuid.UUID(request.Body.VehicleId),
		ServiceTypeID:          uuid.UUID(request.Body.ServiceTypeId),
		StartsAt:               request.Body.StartsAt,
		TechnicianID:           uuid.UUID(request.Body.TechnicianId),
		ServiceBayID:           uuid.UUID(request.Body.ServiceBayId),
		PlannedDurationMinutes: request.Body.PlannedDurationMinutes,
		Notes:                  request.Body.Notes,
	})
	if err != nil {
		return scheduleAppointmentErrorResponse(err)
	}
	return ScheduleAppointment201JSONResponse{AppointmentScheduledJSONResponse: AppointmentScheduledJSONResponse(Appointment{
		AppointmentId: record.AppointmentID, ReferenceCode: record.ReferenceCode,
		DealershipId: record.DealershipID, CustomerId: &record.CustomerID, VehicleId: &record.VehicleID,
		ServiceTypeId: &record.ServiceTypeID, TechnicianId: &record.TechnicianID, ServiceBayId: &record.ServiceBayID,
		StartsAt: record.StartsAt, EndsAt: record.EndsAt, PlannedDurationMinutes: record.PlannedDurationMinutes,
		Status: "requested", Notes: record.Notes, CreatedAt: record.CreatedAt, UpdatedAt: record.UpdatedAt,
	})}, nil
}

func scheduleAppointmentErrorResponse(err error) (ScheduleAppointmentResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return ScheduleAppointment400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return ScheduleAppointment401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ScheduleAppointment403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ScheduleAppointment404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return ScheduleAppointment409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	case 422:
		return ScheduleAppointment422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	default:
		return ScheduleAppointment500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func (h *Handler) CheckInAppointment(ctx context.Context, request CheckInAppointmentRequestObject) (CheckInAppointmentResponseObject, error) {
	var note *string
	if request.Body != nil {
		note = request.Body.Note
	}
	err := h.service.ChangeAppointmentStatus(ctx, identityFrom(ctx), uuid.UUID(request.AppointmentId), domain.AppointmentRequested, domain.AppointmentCheckedIn, nil, nil, note)
	if err == nil {
		return CheckInAppointment204Response{}, nil
	}
	status, response := appointmentStatusProblem(err)
	if status == 400 {
		return CheckInAppointment400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	if status == 403 {
		return CheckInAppointment403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	}
	if status == 404 {
		return CheckInAppointment404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	}
	if status == 409 {
		return CheckInAppointment409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	}
	return CheckInAppointment500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
}

func (h *Handler) StartAppointment(ctx context.Context, request StartAppointmentRequestObject) (StartAppointmentResponseObject, error) {
	var note *string
	if request.Body != nil {
		note = request.Body.Note
	}
	err := h.service.ChangeAppointmentStatus(ctx, identityFrom(ctx), uuid.UUID(request.AppointmentId), domain.AppointmentCheckedIn, domain.AppointmentInProgress, nil, nil, note)
	if err == nil {
		return StartAppointment204Response{}, nil
	}
	status, response := appointmentStatusProblem(err)
	if status == 400 {
		return StartAppointment400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	if status == 403 {
		return StartAppointment403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	}
	if status == 404 {
		return StartAppointment404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	}
	if status == 409 {
		return StartAppointment409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	}
	return StartAppointment500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
}

func (h *Handler) CompleteAppointment(ctx context.Context, request CompleteAppointmentRequestObject) (CompleteAppointmentResponseObject, error) {
	var actualEndsAt *time.Time
	var note *string
	if request.Body != nil {
		actualEndsAt, note = request.Body.ActualEndsAt, request.Body.Note
	}
	err := h.service.ChangeAppointmentStatus(ctx, identityFrom(ctx), uuid.UUID(request.AppointmentId), domain.AppointmentInProgress, domain.AppointmentCompleted, actualEndsAt, nil, note)
	if err == nil {
		return CompleteAppointment204Response{}, nil
	}
	status, response := appointmentStatusProblem(err)
	if status == 400 {
		return CompleteAppointment400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	if status == 403 {
		return CompleteAppointment403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	}
	if status == 404 {
		return CompleteAppointment404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	}
	if status == 409 {
		return CompleteAppointment409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	}
	return CompleteAppointment500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
}

func (h *Handler) CancelAppointment(ctx context.Context, request CancelAppointmentRequestObject) (CancelAppointmentResponseObject, error) {
	if request.Body == nil {
		return CancelAppointment400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("validation_error", "request body is required")))}, nil
	}
	err := h.service.ChangeAppointmentStatus(ctx, identityFrom(ctx), uuid.UUID(request.AppointmentId), "", domain.AppointmentCancelled, nil, &request.Body.CancellationReason, request.Body.Note)
	if err == nil {
		return CancelAppointment204Response{}, nil
	}
	status, response := appointmentStatusProblem(err)
	if status == 400 {
		return CancelAppointment400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	if status == 403 {
		return CancelAppointment403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	}
	if status == 404 {
		return CancelAppointment404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	}
	if status == 409 {
		return CancelAppointment409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	}
	return CancelAppointment500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
}

func appointmentStatusProblem(err error) (int, ErrorResponse) {
	structured := operationTimeProblem(err)
	return structured.HttpErrorCode, errorResponse(structured)
}

func (h *Handler) CreateDealershipOperationTime(ctx context.Context, request CreateDealershipOperationTimeRequestObject) (CreateDealershipOperationTimeResponseObject, error) {
	if request.Body == nil {
		return CreateDealershipOperationTime400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	opensAt, err := parseOperationTime(request.Body.OpensAt)
	if err != nil {
		return createOperationTimeErrorResponse(err)
	}
	closesAt, err := parseOperationTime(request.Body.ClosesAt)
	if err != nil {
		return createOperationTimeErrorResponse(err)
	}
	operationTime, err := h.service.CreateDealershipOperationTime(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), app.CreateDealershipOperationTimeInput{DayOfWeek: request.Body.DayOfWeek, OpensAt: opensAt, ClosesAt: closesAt})
	if err != nil {
		return createOperationTimeErrorResponse(err)
	}
	return CreateDealershipOperationTime201JSONResponse{OperationTimeCreatedJSONResponse: OperationTimeCreatedJSONResponse(operationTimeResponse(operationTime))}, nil
}

func (h *Handler) ListDealershipOperationTimes(ctx context.Context, request ListDealershipOperationTimesRequestObject) (ListDealershipOperationTimesResponseObject, error) {
	operationTimes, err := h.service.ListDealershipOperationTimes(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId))
	if err != nil {
		return listOperationTimeErrorResponse(err)
	}
	response := make(OperationTimesListedJSONResponse, 0, len(operationTimes))
	for _, operationTime := range operationTimes {
		response = append(response, operationTimeResponse(operationTime))
	}
	return ListDealershipOperationTimes200JSONResponse{OperationTimesListedJSONResponse: response}, nil
}

func (h *Handler) UpdateDealershipOperationTime(ctx context.Context, request UpdateDealershipOperationTimeRequestObject) (UpdateDealershipOperationTimeResponseObject, error) {
	if request.Body == nil || (request.Body.DayOfWeek == nil && request.Body.OpensAt == nil && request.Body.ClosesAt == nil) {
		return UpdateDealershipOperationTime400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "at least one field is required")))}, nil
	}
	input := app.UpdateDealershipOperationTimeInput{DayOfWeek: request.Body.DayOfWeek}
	if request.Body.OpensAt != nil {
		parsed, err := parseOperationTime(*request.Body.OpensAt)
		if err != nil {
			return updateOperationTimeErrorResponse(err)
		}
		input.OpensAt = &parsed
	}
	if request.Body.ClosesAt != nil {
		parsed, err := parseOperationTime(*request.Body.ClosesAt)
		if err != nil {
			return updateOperationTimeErrorResponse(err)
		}
		input.ClosesAt = &parsed
	}
	operationTime, err := h.service.UpdateDealershipOperationTime(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.OperationTimeId), input)
	if err != nil {
		return updateOperationTimeErrorResponse(err)
	}
	return UpdateDealershipOperationTime200JSONResponse{OperationTimeUpdatedJSONResponse: OperationTimeUpdatedJSONResponse(operationTimeResponse(operationTime))}, nil
}

func (h *Handler) DeleteDealershipOperationTime(ctx context.Context, request DeleteDealershipOperationTimeRequestObject) (DeleteDealershipOperationTimeResponseObject, error) {
	err := h.service.DeleteDealershipOperationTime(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.OperationTimeId))
	if err != nil {
		return deleteOperationTimeErrorResponse(err)
	}
	return DeleteDealershipOperationTime204Response{}, nil
}

func parseOperationTime(value string) (time.Duration, error) {
	parsed, err := time.Parse("15:04", value)
	if err != nil || len(value) != 5 || parsed.Format("15:04") != value {
		return 0, common.NewInvalidInputError("invalid_operation_time", "time must use HH:MM format")
	}
	return time.Duration(parsed.Hour())*time.Hour + time.Duration(parsed.Minute())*time.Minute, nil
}

func operationTimeResponse(operationTime domain.DealershipOperationTime) DealershipOperationTime {
	return DealershipOperationTime{OperationTimeId: operationTime.ID(), DealershipId: operationTime.DealershipID(), DayOfWeek: operationTime.DayOfWeek(), OpensAt: formatOperationTime(operationTime.OpensAt()), ClosesAt: formatOperationTime(operationTime.ClosesAt()), CreatedAt: operationTime.CreatedAt(), UpdatedAt: operationTime.UpdatedAt()}
}

func formatOperationTime(value time.Duration) string {
	return time.Date(0, 1, 1, 0, 0, 0, 0, time.UTC).Add(value).Format("15:04")
}

func (h *Handler) CreateServiceBay(ctx context.Context, request CreateServiceBayRequestObject) (CreateServiceBayResponseObject, error) {
	if request.Body == nil {
		return CreateServiceBay400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	isActive := true
	if request.Body.IsActive != nil {
		isActive = *request.Body.IsActive
	}
	serviceBay, err := h.service.CreateServiceBay(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), app.CreateServiceBayInput{Code: request.Body.Code, Name: request.Body.Name, IsActive: isActive})
	if err != nil {
		return createServiceBayErrorResponse(err)
	}
	return CreateServiceBay201JSONResponse{ServiceBayCreatedJSONResponse: ServiceBayCreatedJSONResponse(serviceBayResponse(serviceBay))}, nil
}

func (h *Handler) ListServiceBays(ctx context.Context, request ListServiceBaysRequestObject) (ListServiceBaysResponseObject, error) {
	limit := 25
	if request.Params.Limit != nil {
		limit = *request.Params.Limit
	}
	offset := 0
	if request.Params.Offset != nil {
		offset = *request.Params.Offset
	}
	serviceBays, err := h.service.ListServiceBays(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), request.Params.IsActive, limit, offset)
	if err != nil {
		return listServiceBaysErrorResponse(err)
	}
	items := make([]ServiceBay, 0, len(serviceBays))
	for _, serviceBay := range serviceBays {
		items = append(items, serviceBayResponse(serviceBay))
	}
	return ListServiceBays200JSONResponse{ServiceBaysListedJSONResponse: ServiceBaysListedJSONResponse(ServiceBayPage{Items: items, Limit: limit, Offset: offset})}, nil
}

func (h *Handler) GetServiceBay(ctx context.Context, request GetServiceBayRequestObject) (GetServiceBayResponseObject, error) {
	serviceBay, err := h.service.GetServiceBay(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceBayId))
	if err != nil {
		return getServiceBayErrorResponse(err)
	}
	return GetServiceBay200JSONResponse{ServiceBayFoundJSONResponse: ServiceBayFoundJSONResponse(serviceBayResponse(serviceBay))}, nil
}

func (h *Handler) UpdateServiceBay(ctx context.Context, request UpdateServiceBayRequestObject) (UpdateServiceBayResponseObject, error) {
	if request.Body == nil {
		return UpdateServiceBay400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	if request.Body.Code == nil && request.Body.Name == nil && request.Body.IsActive == nil {
		return UpdateServiceBay400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "at least one field is required")))}, nil
	}
	serviceBay, err := h.service.UpdateServiceBay(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceBayId), app.UpdateServiceBayInput{Code: request.Body.Code, Name: request.Body.Name, IsActive: request.Body.IsActive})
	if err != nil {
		return updateServiceBayErrorResponse(err)
	}
	return UpdateServiceBay200JSONResponse{ServiceBayUpdatedJSONResponse: ServiceBayUpdatedJSONResponse(serviceBayResponse(serviceBay))}, nil
}

func (h *Handler) DeleteServiceBay(ctx context.Context, request DeleteServiceBayRequestObject) (DeleteServiceBayResponseObject, error) {
	err := h.service.DeleteServiceBay(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceBayId))
	if err != nil {
		return deleteServiceBayErrorResponse(err)
	}
	return DeleteServiceBay204Response{}, nil
}

func serviceBayResponse(serviceBay domain.ServiceBay) ServiceBay {
	return ServiceBay{ServiceBayId: serviceBay.ID(), DealershipId: serviceBay.DealershipID(), Code: serviceBay.Code(), Name: serviceBay.Name(), IsActive: serviceBay.IsActive(), CreatedAt: serviceBay.CreatedAt(), UpdatedAt: serviceBay.UpdatedAt()}
}

func (h *Handler) CreateServiceBayCapability(ctx context.Context, request CreateServiceBayCapabilityRequestObject) (CreateServiceBayCapabilityResponseObject, error) {
	if request.Body == nil {
		return CreateServiceBayCapability400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	capability, err := h.service.CreateServiceBayCapability(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceBayId), app.CreateServiceBayCapabilityInput{BayCapabilityID: uuid.UUID(request.Body.BayCapabilityId)})
	if err != nil {
		return createServiceBayCapabilityErrorResponse(err)
	}
	return CreateServiceBayCapability201JSONResponse{ServiceBayCapabilityCreatedJSONResponse: ServiceBayCapabilityCreatedJSONResponse(serviceBayCapabilityResponse(capability))}, nil
}

func (h *Handler) ListServiceBayCapabilities(ctx context.Context, request ListServiceBayCapabilitiesRequestObject) (ListServiceBayCapabilitiesResponseObject, error) {
	capabilities, err := h.service.ListServiceBayCapabilities(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceBayId))
	if err != nil {
		return listServiceBayCapabilitiesErrorResponse(err)
	}
	response := make(ServiceBayCapabilitiesListedJSONResponse, 0, len(capabilities))
	for _, capability := range capabilities {
		response = append(response, serviceBayCapabilityResponse(capability))
	}
	return ListServiceBayCapabilities200JSONResponse{ServiceBayCapabilitiesListedJSONResponse: response}, nil
}

func (h *Handler) UpdateServiceBayCapability(ctx context.Context, request UpdateServiceBayCapabilityRequestObject) (UpdateServiceBayCapabilityResponseObject, error) {
	if request.Body == nil {
		return UpdateServiceBayCapability400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	bayCapabilityID := uuid.UUID(request.Body.BayCapabilityId)
	capability, err := h.service.UpdateServiceBayCapability(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceBayId), uuid.UUID(request.ServiceBayCapabilityId), app.UpdateServiceBayCapabilityInput{BayCapabilityID: &bayCapabilityID})
	if err != nil {
		return updateServiceBayCapabilityErrorResponse(err)
	}
	return UpdateServiceBayCapability200JSONResponse{ServiceBayCapabilityUpdatedJSONResponse: ServiceBayCapabilityUpdatedJSONResponse(serviceBayCapabilityResponse(capability))}, nil
}

func (h *Handler) DeleteServiceBayCapability(ctx context.Context, request DeleteServiceBayCapabilityRequestObject) (DeleteServiceBayCapabilityResponseObject, error) {
	err := h.service.DeleteServiceBayCapability(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceBayId), uuid.UUID(request.ServiceBayCapabilityId))
	if err != nil {
		return deleteServiceBayCapabilityErrorResponse(err)
	}
	return DeleteServiceBayCapability204Response{}, nil
}

func serviceBayCapabilityResponse(capability domain.ServiceBayCapability) ServiceBayCapability {
	return ServiceBayCapability{
		ServiceBayCapabilityId: capability.ID(),
		ServiceBayId:           capability.ServiceBayID(),
		BayCapability: BayCapability{
			BayCapabilityId: capability.BayCapabilityID(),
			Code:            capability.CapabilityCode(),
			Name:            capability.CapabilityName(),
		},
		CreatedAt: capability.CreatedAt(),
		UpdatedAt: capability.UpdatedAt(),
	}
}

func (h *Handler) CreateServiceType(ctx context.Context, request CreateServiceTypeRequestObject) (CreateServiceTypeResponseObject, error) {
	if request.Body == nil {
		response := errorResponse(common.NewInvalidInputError("request_body_required", "request body is required"))
		return CreateServiceType400JSONResponse{
			BadRequestJSONResponse: BadRequestJSONResponse(response),
		}, nil
	}
	isActive := true
	if request.Body.IsActive != nil {
		isActive = *request.Body.IsActive
	}
	serviceType, err := h.service.CreateServiceType(
		ctx,
		identityFrom(ctx),
		uuid.UUID(request.DealershipId),
		app.CreateServiceTypeInput{
			Name:                   request.Body.Name,
			DefaultDurationMinutes: request.Body.DefaultDurationMinutes,
			MinDurationMinutes:     request.Body.MinDurationMinutes,
			MaxDurationMinutes:     request.Body.MaxDurationMinutes,
			IsActive:               isActive,
		},
	)
	if err != nil {
		return createServiceTypeErrorResponse(err)
	}
	return CreateServiceType201JSONResponse{
		ServiceTypeCreatedJSONResponse: ServiceTypeCreatedJSONResponse(serviceTypeResponse(serviceType)),
	}, nil
}

func (h *Handler) ListServiceTypes(ctx context.Context, request ListServiceTypesRequestObject) (ListServiceTypesResponseObject, error) {
	serviceTypes, err := h.service.ListServiceTypes(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId))
	if err != nil {
		return listServiceTypesErrorResponse(err)
	}
	response := make(ServiceTypesListedJSONResponse, 0, len(serviceTypes))
	for _, serviceType := range serviceTypes {
		response = append(response, serviceTypeResponse(serviceType))
	}
	return ListServiceTypes200JSONResponse{ServiceTypesListedJSONResponse: response}, nil
}

func (h *Handler) GetServiceType(ctx context.Context, request GetServiceTypeRequestObject) (GetServiceTypeResponseObject, error) {
	serviceType, err := h.service.GetServiceType(
		ctx,
		identityFrom(ctx),
		uuid.UUID(request.DealershipId),
		uuid.UUID(request.ServiceTypeId),
	)
	if err != nil {
		return getServiceTypeErrorResponse(err)
	}
	return GetServiceType200JSONResponse{
		ServiceTypeFoundJSONResponse: ServiceTypeFoundJSONResponse(serviceTypeResponse(serviceType)),
	}, nil
}

func (h *Handler) UpdateServiceType(ctx context.Context, request UpdateServiceTypeRequestObject) (UpdateServiceTypeResponseObject, error) {
	if request.Body == nil {
		response := errorResponse(common.NewInvalidInputError("request_body_required", "request body is required"))
		return UpdateServiceType400JSONResponse{
			BadRequestJSONResponse: BadRequestJSONResponse(response),
		}, nil
	}
	if request.Body.Name == nil && request.Body.DefaultDurationMinutes == nil && request.Body.MinDurationMinutes == nil && request.Body.MaxDurationMinutes == nil && request.Body.IsActive == nil {
		response := errorResponse(common.NewInvalidInputError("request_body_required", "at least one field is required"))
		return UpdateServiceType400JSONResponse{
			BadRequestJSONResponse: BadRequestJSONResponse(response),
		}, nil
	}
	serviceType, err := h.service.UpdateServiceType(
		ctx,
		identityFrom(ctx),
		uuid.UUID(request.DealershipId),
		uuid.UUID(request.ServiceTypeId),
		app.UpdateServiceTypeInput{
			Name:                   request.Body.Name,
			DefaultDurationMinutes: request.Body.DefaultDurationMinutes,
			MinDurationMinutes:     request.Body.MinDurationMinutes,
			MaxDurationMinutes:     request.Body.MaxDurationMinutes,
			IsActive:               request.Body.IsActive,
		},
	)
	if err != nil {
		return updateServiceTypeErrorResponse(err)
	}
	return UpdateServiceType200JSONResponse{
		ServiceTypeUpdatedJSONResponse: ServiceTypeUpdatedJSONResponse(serviceTypeResponse(serviceType)),
	}, nil
}

func (h *Handler) DeleteServiceType(ctx context.Context, request DeleteServiceTypeRequestObject) (DeleteServiceTypeResponseObject, error) {
	err := h.service.DeleteServiceType(
		ctx,
		identityFrom(ctx),
		uuid.UUID(request.DealershipId),
		uuid.UUID(request.ServiceTypeId),
	)
	if err != nil {
		return deleteServiceTypeErrorResponse(err)
	}
	return DeleteServiceType204Response{}, nil
}

func serviceTypeResponse(serviceType domain.ServiceType) ServiceType {
	return ServiceType{
		ServiceTypeId:          serviceType.ID(),
		DealershipId:           serviceType.DealershipID(),
		Name:                   serviceType.Name(),
		DefaultDurationMinutes: serviceType.DefaultDurationMinutes(),
		MinDurationMinutes:     serviceType.MinDurationMinutes(),
		MaxDurationMinutes:     serviceType.MaxDurationMinutes(),
		IsActive:               serviceType.IsActive(),
		CreatedAt:              serviceType.CreatedAt(),
		UpdatedAt:              serviceType.UpdatedAt(),
	}
}

func (h *Handler) CreateServiceTypeRequiredSkill(ctx context.Context, request CreateServiceTypeRequiredSkillRequestObject) (CreateServiceTypeRequiredSkillResponseObject, error) {
	if request.Body == nil {
		return CreateServiceTypeRequiredSkill400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	requiredSkill, err := h.service.CreateServiceTypeRequiredSkill(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceTypeId), app.CreateServiceTypeRequiredSkillInput{SkillID: uuid.UUID(request.Body.SkillId)})
	if err != nil {
		return createServiceTypeRequiredSkillErrorResponse(err)
	}
	return CreateServiceTypeRequiredSkill201JSONResponse{ServiceTypeRequiredSkillCreatedJSONResponse: ServiceTypeRequiredSkillCreatedJSONResponse(requiredSkillResponse(requiredSkill))}, nil
}

func (h *Handler) ListServiceTypeRequiredSkills(ctx context.Context, request ListServiceTypeRequiredSkillsRequestObject) (ListServiceTypeRequiredSkillsResponseObject, error) {
	requiredSkills, err := h.service.ListServiceTypeRequiredSkills(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceTypeId))
	if err != nil {
		return listServiceTypeRequiredSkillsErrorResponse(err)
	}
	response := make(ServiceTypeRequiredSkillsListedJSONResponse, 0, len(requiredSkills))
	for _, requiredSkill := range requiredSkills {
		response = append(response, requiredSkillResponse(requiredSkill))
	}
	return ListServiceTypeRequiredSkills200JSONResponse{ServiceTypeRequiredSkillsListedJSONResponse: response}, nil
}

func (h *Handler) UpdateServiceTypeRequiredSkill(ctx context.Context, request UpdateServiceTypeRequiredSkillRequestObject) (UpdateServiceTypeRequiredSkillResponseObject, error) {
	if request.Body == nil {
		return UpdateServiceTypeRequiredSkill400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	skillID := uuid.UUID(request.Body.SkillId)
	requiredSkill, err := h.service.UpdateServiceTypeRequiredSkill(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceTypeId), uuid.UUID(request.RequiredSkillId), app.UpdateServiceTypeRequiredSkillInput{SkillID: &skillID})
	if err != nil {
		return updateServiceTypeRequiredSkillErrorResponse(err)
	}
	return UpdateServiceTypeRequiredSkill200JSONResponse{ServiceTypeRequiredSkillUpdatedJSONResponse: ServiceTypeRequiredSkillUpdatedJSONResponse(requiredSkillResponse(requiredSkill))}, nil
}

func (h *Handler) DeleteServiceTypeRequiredSkill(ctx context.Context, request DeleteServiceTypeRequiredSkillRequestObject) (DeleteServiceTypeRequiredSkillResponseObject, error) {
	err := h.service.DeleteServiceTypeRequiredSkill(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceTypeId), uuid.UUID(request.RequiredSkillId))
	if err != nil {
		return deleteServiceTypeRequiredSkillErrorResponse(err)
	}
	return DeleteServiceTypeRequiredSkill204Response{}, nil
}

func requiredSkillResponse(requiredSkill domain.ServiceTypeRequiredSkill) ServiceTypeRequiredSkill {
	return ServiceTypeRequiredSkill{RequiredSkillId: requiredSkill.ID(), ServiceTypeId: requiredSkill.ServiceTypeID(), Skill: Skill{SkillId: requiredSkill.SkillID(), Code: requiredSkill.SkillCode(), Name: requiredSkill.SkillName()}, CreatedAt: requiredSkill.CreatedAt(), UpdatedAt: requiredSkill.UpdatedAt()}
}

func (h *Handler) CreateServiceTypeRequiredBayCapability(ctx context.Context, request CreateServiceTypeRequiredBayCapabilityRequestObject) (CreateServiceTypeRequiredBayCapabilityResponseObject, error) {
	if request.Body == nil {
		return CreateServiceTypeRequiredBayCapability400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	requiredCapability, err := h.service.CreateServiceTypeRequiredBayCapability(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceTypeId), app.CreateServiceTypeRequiredBayCapabilityInput{BayCapabilityID: uuid.UUID(request.Body.BayCapabilityId)})
	if err != nil {
		return createServiceTypeRequiredBayCapabilityErrorResponse(err)
	}
	return CreateServiceTypeRequiredBayCapability201JSONResponse{ServiceTypeRequiredBayCapabilityCreatedJSONResponse: ServiceTypeRequiredBayCapabilityCreatedJSONResponse(requiredBayCapabilityResponse(requiredCapability))}, nil
}

func (h *Handler) ListServiceTypeRequiredBayCapabilities(ctx context.Context, request ListServiceTypeRequiredBayCapabilitiesRequestObject) (ListServiceTypeRequiredBayCapabilitiesResponseObject, error) {
	requiredCapabilities, err := h.service.ListServiceTypeRequiredBayCapabilities(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceTypeId))
	if err != nil {
		return listServiceTypeRequiredBayCapabilitiesErrorResponse(err)
	}
	response := make(ServiceTypeRequiredBayCapabilitiesListedJSONResponse, 0, len(requiredCapabilities))
	for _, requiredCapability := range requiredCapabilities {
		response = append(response, requiredBayCapabilityResponse(requiredCapability))
	}
	return ListServiceTypeRequiredBayCapabilities200JSONResponse{ServiceTypeRequiredBayCapabilitiesListedJSONResponse: response}, nil
}

func (h *Handler) UpdateServiceTypeRequiredBayCapability(ctx context.Context, request UpdateServiceTypeRequiredBayCapabilityRequestObject) (UpdateServiceTypeRequiredBayCapabilityResponseObject, error) {
	if request.Body == nil {
		return UpdateServiceTypeRequiredBayCapability400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	bayCapabilityID := uuid.UUID(request.Body.BayCapabilityId)
	requiredCapability, err := h.service.UpdateServiceTypeRequiredBayCapability(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceTypeId), uuid.UUID(request.RequiredCapabilityId), app.UpdateServiceTypeRequiredBayCapabilityInput{BayCapabilityID: &bayCapabilityID})
	if err != nil {
		return updateServiceTypeRequiredBayCapabilityErrorResponse(err)
	}
	return UpdateServiceTypeRequiredBayCapability200JSONResponse{ServiceTypeRequiredBayCapabilityUpdatedJSONResponse: ServiceTypeRequiredBayCapabilityUpdatedJSONResponse(requiredBayCapabilityResponse(requiredCapability))}, nil
}

func (h *Handler) DeleteServiceTypeRequiredBayCapability(ctx context.Context, request DeleteServiceTypeRequiredBayCapabilityRequestObject) (DeleteServiceTypeRequiredBayCapabilityResponseObject, error) {
	err := h.service.DeleteServiceTypeRequiredBayCapability(ctx, identityFrom(ctx), uuid.UUID(request.DealershipId), uuid.UUID(request.ServiceTypeId), uuid.UUID(request.RequiredCapabilityId))
	if err != nil {
		return deleteServiceTypeRequiredBayCapabilityErrorResponse(err)
	}
	return DeleteServiceTypeRequiredBayCapability204Response{}, nil
}

func requiredBayCapabilityResponse(requiredCapability domain.ServiceTypeRequiredBayCapability) ServiceTypeRequiredBayCapability {
	return ServiceTypeRequiredBayCapability{
		RequiredCapabilityId: requiredCapability.ID(),
		ServiceTypeId:        requiredCapability.ServiceTypeID(),
		BayCapability: BayCapability{
			BayCapabilityId: requiredCapability.BayCapabilityID(),
			Code:            requiredCapability.CapabilityCode(),
			Name:            requiredCapability.CapabilityName(),
		},
		CreatedAt: requiredCapability.CreatedAt(),
		UpdatedAt: requiredCapability.UpdatedAt(),
	}
}

func (h *Handler) CreateDealershipUser(ctx context.Context, request CreateDealershipUserRequestObject) (CreateDealershipUserResponseObject, error) {
	if request.Body == nil {
		response := errorResponse(common.NewInvalidInputError("request_body_required", "request body is required"))
		return CreateDealershipUser400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	user, err := h.service.CreateDealershipUser(ctx, identityFrom(ctx), app.CreateDealershipUserInput{
		DealershipID: uuid.UUID(request.Body.DealershipId),
		Email:        string(request.Body.Email),
		Role:         string(request.Body.Role),
	})
	if err != nil {
		return createDealershipUserErrorResponse(err)
	}
	return CreateDealershipUser201JSONResponse{DealershipUserCreatedJSONResponse: DealershipUserCreatedJSONResponse{
		UserId: user.ID(), AuthUserId: user.AuthUserID(), DealershipId: user.DealershipID(),
		Name: user.Name(), Email: openapi_types.Email(user.Email()), IsActive: user.IsActive(),
		Role: DealershipUserRole(user.Role()), CreatedAt: user.CreatedAt(), UpdatedAt: user.UpdatedAt(),
	}}, nil
}

func (h *Handler) SearchAuthUserByEmail(ctx context.Context, request SearchAuthUserByEmailRequestObject) (SearchAuthUserByEmailResponseObject, error) {
	user, err := h.service.SearchAuthUserByEmail(ctx, identityFrom(ctx), string(request.Params.Email))
	if err != nil {
		return searchAuthUserByEmailErrorResponse(err)
	}
	return SearchAuthUserByEmail200JSONResponse{AuthUserFoundJSONResponse: AuthUserFoundJSONResponse{
		UserId:   user.ID,
		Email:    openapi_types.Email(user.Email),
		FullName: user.FullName,
		Status:   user.Status,
		Role:     user.Role,
	}}, nil
}

func (h *Handler) CreateDealershipAdmin(ctx context.Context, request CreateDealershipAdminRequestObject) (CreateDealershipAdminResponseObject, error) {
	if request.Body == nil {
		response := errorResponse(common.NewInvalidInputError("request_body_required", "request body is required"))
		return CreateDealershipAdmin400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	if request.Body.Email == "" {
		response := errorResponse(common.NewForbiddenError("email", "the email is required"))
		return CreateDealershipAdmin400JSONResponse{
				BadRequestJSONResponse: BadRequestJSONResponse(response),
			},
			nil
	}
	admin, err := h.service.CreateDealershipAdmin(ctx, identityFrom(ctx), app.CreateDealershipAdminInput{
		DealershipID: uuid.UUID(request.Body.DealershipId),
		Name:         request.Body.Name,
		Phone:        request.Body.Phone,
		Email:        string(request.Body.Email),
	})
	if err != nil {
		return createDealershipAdminErrorResponse(err)
	}
	return CreateDealershipAdmin201JSONResponse{DealershipAdminCreatedJSONResponse: DealershipAdminCreatedJSONResponse{
		UserId:       admin.ID(),
		AuthUserId:   admin.AuthUserID(),
		DealershipId: admin.DealershipID(),
		Name:         admin.Name(),
		Phone:        admin.Phone(),
		Email:        adminEmailPointer(admin.Email()),
		IsActive:     admin.IsActive(),
		Role:         DealershipAdminRoleAdmin,
		CreatedAt:    admin.CreatedAt(),
		UpdatedAt:    admin.UpdatedAt(),
	}}, nil
}

func adminEmailPointer(value *string) *openapi_types.Email {
	if value == nil {
		return nil
	}
	result := openapi_types.Email(*value)
	return &result
}

func (h *Handler) CreateTechnician(ctx context.Context, request CreateTechnicianRequestObject) (CreateTechnicianResponseObject, error) {
	if request.Body == nil {
		return CreateTechnician400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	var email *string
	if request.Body.Email != nil {
		value := string(*request.Body.Email)
		email = &value
	}
	isActive := true
	if request.Body.IsActive != nil {
		isActive = *request.Body.IsActive
	}
	technician, err := h.service.CreateTechnician(ctx, identityFrom(ctx), app.CreateTechnicianInput{Name: request.Body.Name, Phone: request.Body.Phone, Email: email, IsActive: isActive})
	if err != nil {
		return createTechnicianErrorResponse(err)
	}
	return CreateTechnician201JSONResponse{TechnicianCreatedJSONResponse: TechnicianCreatedJSONResponse(technicianResponse(technician))}, nil
}

func (h *Handler) ListTechnicians(ctx context.Context, request ListTechniciansRequestObject) (ListTechniciansResponseObject, error) {
	limit, offset := 25, 0
	if request.Params.Limit != nil {
		limit = *request.Params.Limit
	}
	if request.Params.Offset != nil {
		offset = *request.Params.Offset
	}
	technicians, err := h.service.ListTechnicians(ctx, identityFrom(ctx), request.Params.IsActive, limit, offset)
	if err != nil {
		return listTechniciansErrorResponse(err)
	}
	items := make([]Technician, 0, len(technicians))
	for _, technician := range technicians {
		items = append(items, technicianResponse(technician))
	}
	return ListTechnicians200JSONResponse{TechniciansListedJSONResponse: TechniciansListedJSONResponse(TechnicianPage{Items: items, Limit: limit, Offset: offset})}, nil
}

func (h *Handler) GetTechnician(ctx context.Context, request GetTechnicianRequestObject) (GetTechnicianResponseObject, error) {
	technician, err := h.service.GetTechnician(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId))
	if err != nil {
		return getTechnicianErrorResponse(err)
	}
	return GetTechnician200JSONResponse{TechnicianFoundJSONResponse: TechnicianFoundJSONResponse(technicianResponse(technician))}, nil
}

func (h *Handler) UpdateTechnician(ctx context.Context, request UpdateTechnicianRequestObject) (UpdateTechnicianResponseObject, error) {
	if request.Body == nil || (request.Body.Name == nil && request.Body.Phone == nil && request.Body.Email == nil && request.Body.IsActive == nil) {
		return UpdateTechnician400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "at least one field is required")))}, nil
	}
	input := app.UpdateTechnicianInput{Name: request.Body.Name, Phone: request.Body.Phone, IsActive: request.Body.IsActive}
	if request.Body.Email != nil {
		input.EmailPresent, input.Email = request.Body.Email.Present, request.Body.Email.Value
	}
	technician, err := h.service.UpdateTechnician(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), input)
	if err != nil {
		return updateTechnicianErrorResponse(err)
	}
	return UpdateTechnician200JSONResponse{TechnicianUpdatedJSONResponse: TechnicianUpdatedJSONResponse(technicianResponse(technician))}, nil
}

func (h *Handler) DeleteTechnician(ctx context.Context, request DeleteTechnicianRequestObject) (DeleteTechnicianResponseObject, error) {
	if err := h.service.DeactivateTechnician(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId)); err != nil {
		return deleteTechnicianErrorResponse(err)
	}
	return DeleteTechnician204Response{}, nil
}

func technicianResponse(technician domain.Technician) Technician {
	var email *openapi_types.Email
	if value := technician.Email(); value != nil {
		result := openapi_types.Email(*value)
		email = &result
	}
	return Technician{TechnicianId: technician.ID(), UserId: technician.UserID(), Name: technician.Name(), Phone: technician.Phone(), Email: email, IsActive: technician.IsActive(), CreatedAt: technician.CreatedAt(), UpdatedAt: technician.UpdatedAt()}
}

func (h *Handler) CreateTechnicianSkill(ctx context.Context, request CreateTechnicianSkillRequestObject) (CreateTechnicianSkillResponseObject, error) {
	if request.Body == nil {
		response := errorResponse(common.NewInvalidInputError("request_body_required", "request body is required"))
		return CreateTechnicianSkill400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	skill, err := h.service.CreateTechnicianSkill(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), app.CreateTechnicianSkillInput{SkillID: uuid.UUID(request.Body.SkillId)})
	if err != nil {
		return createTechnicianSkillErrorResponse(err)
	}
	return CreateTechnicianSkill201JSONResponse{TechnicianSkillCreatedJSONResponse: TechnicianSkillCreatedJSONResponse(technicianSkillResponse(skill))}, nil
}

func (h *Handler) ListTechnicianSkills(ctx context.Context, request ListTechnicianSkillsRequestObject) (ListTechnicianSkillsResponseObject, error) {
	skills, err := h.service.ListTechnicianSkills(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId))
	if err != nil {
		return listTechnicianSkillsErrorResponse(err)
	}
	response := make(TechnicianSkillsListedJSONResponse, 0, len(skills))
	for _, skill := range skills {
		response = append(response, technicianSkillResponse(skill))
	}
	return ListTechnicianSkills200JSONResponse{TechnicianSkillsListedJSONResponse: response}, nil
}

func (h *Handler) UpdateTechnicianSkill(ctx context.Context, request UpdateTechnicianSkillRequestObject) (UpdateTechnicianSkillResponseObject, error) {
	if request.Body == nil {
		response := errorResponse(common.NewInvalidInputError("request_body_required", "request body is required"))
		return UpdateTechnicianSkill400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	skillID := uuid.UUID(request.Body.SkillId)
	skill, err := h.service.UpdateTechnicianSkill(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), uuid.UUID(request.TechnicianSkillId), app.UpdateTechnicianSkillInput{SkillID: &skillID})
	if err != nil {
		return updateTechnicianSkillErrorResponse(err)
	}
	return UpdateTechnicianSkill200JSONResponse{TechnicianSkillUpdatedJSONResponse: TechnicianSkillUpdatedJSONResponse(technicianSkillResponse(skill))}, nil
}

func (h *Handler) DeleteTechnicianSkill(ctx context.Context, request DeleteTechnicianSkillRequestObject) (DeleteTechnicianSkillResponseObject, error) {
	err := h.service.DeleteTechnicianSkill(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), uuid.UUID(request.TechnicianSkillId))
	if err != nil {
		return deleteTechnicianSkillErrorResponse(err)
	}
	return DeleteTechnicianSkill204Response{}, nil
}

func technicianSkillResponse(skill domain.TechnicianSkill) TechnicianSkill {
	return TechnicianSkill{TechnicianSkillId: skill.ID(), TechnicianId: skill.TechnicianID(), SkillId: skill.SkillID(), CreatedAt: skill.CreatedAt(), UpdatedAt: skill.UpdatedAt()}
}

func (h *Handler) CreateTechnicianShift(ctx context.Context, request CreateTechnicianShiftRequestObject) (CreateTechnicianShiftResponseObject, error) {
	if request.Body == nil {
		return createTechnicianShiftErrorResponse(common.NewInvalidInputError("validation_failed", "request body is required"))
	}
	startsAt, err := parseShiftTime(request.Body.StartsAt)
	if err != nil {
		return createTechnicianShiftErrorResponse(err)
	}
	endsAt, err := parseShiftTime(request.Body.EndsAt)
	if err != nil {
		return createTechnicianShiftErrorResponse(err)
	}
	shift, err := h.service.CreateTechnicianShift(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), app.CreateTechnicianShiftInput{DayOfWeek: request.Body.DayOfWeek, StartsAt: startsAt, EndsAt: endsAt})
	if err != nil {
		return createTechnicianShiftErrorResponse(err)
	}
	return CreateTechnicianShift201JSONResponse{TechnicianShiftCreatedJSONResponse: TechnicianShiftCreatedJSONResponse(technicianShiftResponse(shift))}, nil
}

func (h *Handler) ListTechnicianShifts(ctx context.Context, request ListTechnicianShiftsRequestObject) (ListTechnicianShiftsResponseObject, error) {
	shifts, err := h.service.ListTechnicianShifts(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId))
	if err != nil {
		return listTechnicianShiftErrorResponse(err)
	}
	response := make(TechnicianShiftsListedJSONResponse, 0, len(shifts))
	for _, shift := range shifts {
		response = append(response, technicianShiftResponse(shift))
	}
	return ListTechnicianShifts200JSONResponse{TechnicianShiftsListedJSONResponse: response}, nil
}

func (h *Handler) UpdateTechnicianShift(ctx context.Context, request UpdateTechnicianShiftRequestObject) (UpdateTechnicianShiftResponseObject, error) {
	if request.Body == nil || (request.Body.DayOfWeek == nil && request.Body.StartsAt == nil && request.Body.EndsAt == nil) {
		return updateTechnicianShiftErrorResponse(common.NewInvalidInputError("validation_failed", "at least one field is required"))
	}
	input := app.UpdateTechnicianShiftInput{DayOfWeek: request.Body.DayOfWeek}
	if request.Body.StartsAt != nil {
		value, err := parseShiftTime(*request.Body.StartsAt)
		if err != nil {
			return updateTechnicianShiftErrorResponse(err)
		}
		input.StartsAt = &value
	}
	if request.Body.EndsAt != nil {
		value, err := parseShiftTime(*request.Body.EndsAt)
		if err != nil {
			return updateTechnicianShiftErrorResponse(err)
		}
		input.EndsAt = &value
	}
	shift, err := h.service.UpdateTechnicianShift(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), uuid.UUID(request.ShiftId), input)
	if err != nil {
		return updateTechnicianShiftErrorResponse(err)
	}
	return UpdateTechnicianShift200JSONResponse{TechnicianShiftUpdatedJSONResponse: TechnicianShiftUpdatedJSONResponse(technicianShiftResponse(shift))}, nil
}

func (h *Handler) DeleteTechnicianShift(ctx context.Context, request DeleteTechnicianShiftRequestObject) (DeleteTechnicianShiftResponseObject, error) {
	if err := h.service.DeleteTechnicianShift(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), uuid.UUID(request.ShiftId)); err != nil {
		return deleteTechnicianShiftErrorResponse(err)
	}
	return DeleteTechnicianShift204Response{}, nil
}

func parseShiftTime(value string) (time.Duration, error) {
	parsed, err := time.Parse("15:04", value)
	if err != nil || len(value) != 5 || parsed.Format("15:04") != value {
		return 0, common.NewInvalidInputError("validation_failed", "time must use HH:MM format")
	}
	return time.Duration(parsed.Hour())*time.Hour + time.Duration(parsed.Minute())*time.Minute, nil
}

func technicianShiftResponse(shift domain.TechnicianShift) TechnicianShift {
	return TechnicianShift{TechnicianShiftId: shift.ID(), TechnicianId: shift.TechnicianID(), DayOfWeek: shift.DayOfWeek(), StartsAt: formatOperationTime(shift.StartsAt()), EndsAt: formatOperationTime(shift.EndsAt()), CreatedAt: shift.CreatedAt(), UpdatedAt: shift.UpdatedAt()}
}

func (h *Handler) CreateTechnicianTimeOff(ctx context.Context, request CreateTechnicianTimeOffRequestObject) (CreateTechnicianTimeOffResponseObject, error) {
	if request.Body == nil {
		return CreateTechnicianTimeOff400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "request body is required")))}, nil
	}
	item, err := h.service.CreateTechnicianTimeOff(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), app.CreateTechnicianTimeOffInput{StartsAt: request.Body.StartsAt, EndsAt: request.Body.EndsAt, Reason: request.Body.Reason})
	if err != nil {
		return createTechnicianTimeOffError(err)
	}
	return CreateTechnicianTimeOff201JSONResponse{TechnicianTimeOffCreatedJSONResponse: TechnicianTimeOffCreatedJSONResponse(technicianTimeOffResponse(item))}, nil
}

func (h *Handler) ListTechnicianTimeOff(ctx context.Context, request ListTechnicianTimeOffRequestObject) (ListTechnicianTimeOffResponseObject, error) {
	limit, offset := 25, 0
	if request.Params.Limit != nil {
		limit = int(*request.Params.Limit)
	}
	if request.Params.Offset != nil {
		offset = int(*request.Params.Offset)
	}
	if request.Params.From != nil && request.Params.To != nil && !request.Params.To.After(*request.Params.From) {
		return ListTechnicianTimeOff400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("invalid_time_off_interval", "to must be after from")))}, nil
	}
	items, err := h.service.ListTechnicianTimeOff(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), request.Params.From, request.Params.To, limit, offset)
	if err != nil {
		return listTechnicianTimeOffError(err)
	}
	response := make([]TechnicianTimeOff, 0, len(items))
	for _, item := range items {
		response = append(response, technicianTimeOffResponse(item))
	}
	return ListTechnicianTimeOff200JSONResponse{TechnicianTimeOffListedJSONResponse: TechnicianTimeOffListedJSONResponse(TechnicianTimeOffPage{Items: response, Limit: limit, Offset: offset})}, nil
}

func (h *Handler) GetTechnicianTimeOff(ctx context.Context, request GetTechnicianTimeOffRequestObject) (GetTechnicianTimeOffResponseObject, error) {
	item, err := h.service.GetTechnicianTimeOff(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), uuid.UUID(request.TimeOffId))
	if err != nil {
		return getTechnicianTimeOffError(err)
	}
	return GetTechnicianTimeOff200JSONResponse{TechnicianTimeOffFoundJSONResponse: TechnicianTimeOffFoundJSONResponse(technicianTimeOffResponse(item))}, nil
}

func (h *Handler) UpdateTechnicianTimeOff(ctx context.Context, request UpdateTechnicianTimeOffRequestObject) (UpdateTechnicianTimeOffResponseObject, error) {
	if request.Body == nil || (request.Body.StartsAt == nil && request.Body.EndsAt == nil && request.Body.Reason == nil) {
		return UpdateTechnicianTimeOff400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("request_body_required", "at least one field is required")))}, nil
	}
	input := app.UpdateTechnicianTimeOffInput{StartsAt: request.Body.StartsAt, EndsAt: request.Body.EndsAt}
	if request.Body.Reason != nil {
		input.ReasonSet, input.Reason = request.Body.Reason.Present, request.Body.Reason.Value
	}
	item, err := h.service.UpdateTechnicianTimeOff(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), uuid.UUID(request.TimeOffId), input)
	if err != nil {
		return updateTechnicianTimeOffError(err)
	}
	return UpdateTechnicianTimeOff200JSONResponse{TechnicianTimeOffUpdatedJSONResponse: TechnicianTimeOffUpdatedJSONResponse(technicianTimeOffResponse(item))}, nil
}

func (h *Handler) DeleteTechnicianTimeOff(ctx context.Context, request DeleteTechnicianTimeOffRequestObject) (DeleteTechnicianTimeOffResponseObject, error) {
	if err := h.service.DeleteTechnicianTimeOff(ctx, identityFrom(ctx), uuid.UUID(request.TechnicianId), uuid.UUID(request.TimeOffId)); err != nil {
		return deleteTechnicianTimeOffError(err)
	}
	return DeleteTechnicianTimeOff204Response{}, nil
}

func technicianTimeOffResponse(item domain.TechnicianTimeOff) TechnicianTimeOff {
	return TechnicianTimeOff{TechnicianTimeOffId: item.ID(), TechnicianId: item.TechnicianID(), StartsAt: item.StartsAt(), EndsAt: item.EndsAt(), Reason: item.Reason(), CreatedByUserId: item.CreatedByUserID(), CreatedAt: item.CreatedAt(), UpdatedAt: item.UpdatedAt()}
}

func (h *Handler) CreateCustomer(ctx context.Context, request CreateCustomerRequestObject) (CreateCustomerResponseObject, error) {
	if request.Body == nil {
		return CreateCustomer400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("invalid_request", "request body is required")))}, nil
	}
	var email *string
	if request.Body.Email != nil {
		value := string(*request.Body.Email)
		email = &value
	}
	customer, err := h.service.CreateCustomer(ctx, identityFrom(ctx), app.CreateCustomerInput{
		Name:  request.Body.Name,
		Phone: request.Body.Phone,
		Email: email,
	})
	if err != nil {
		return createCustomerErrorResponse(err)
	}
	return CreateCustomer201JSONResponse{CustomerCreatedJSONResponse: CustomerCreatedJSONResponse{
		Body:    customerResponse(customer),
		Headers: CustomerCreatedResponseHeaders{Location: "/v1/customers/" + customer.ID().String()},
	}}, nil
}

func (h *Handler) GetCustomer(ctx context.Context, request GetCustomerRequestObject) (GetCustomerResponseObject, error) {
	customer, err := h.service.GetCustomer(ctx, identityFrom(ctx), uuid.UUID(request.CustomerId))
	if err != nil {
		return getCustomerErrorResponse(err)
	}
	return GetCustomer200JSONResponse{CustomerFoundJSONResponse: CustomerFoundJSONResponse(customerResponse(customer))}, nil
}

func (h *Handler) UpdateCustomer(ctx context.Context, request UpdateCustomerRequestObject) (UpdateCustomerResponseObject, error) {
	if request.Body == nil {
		return UpdateCustomer400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("invalid_request", "request body is required")))}, nil
	}
	input := app.UpdateCustomerInput{Name: request.Body.Name, Phone: request.Body.Phone}
	if request.Body.Email != nil {
		input.EmailPresent = request.Body.Email.Present
		input.Email = request.Body.Email.Value
	}
	customer, err := h.service.UpdateCustomer(ctx, identityFrom(ctx), uuid.UUID(request.CustomerId), input)
	if err != nil {
		return updateCustomerErrorResponse(err)
	}
	return UpdateCustomer200JSONResponse{CustomerUpdatedJSONResponse: CustomerUpdatedJSONResponse(customerResponse(customer))}, nil
}

func (h *Handler) SearchCustomers(ctx context.Context, request SearchCustomersRequestObject) (SearchCustomersResponseObject, error) {
	var email *string
	if request.Params.Email != nil {
		value := string(*request.Params.Email)
		email = &value
	}
	customers, err := h.service.SearchCustomers(ctx, identityFrom(ctx), request.Params.Phone, email)
	if err != nil {
		return searchCustomersErrorResponse(err)
	}
	items := make([]Customer, 0, len(customers))
	for _, customer := range customers {
		items = append(items, customerResponse(customer))
	}
	return SearchCustomers200JSONResponse{CustomersListedJSONResponse: CustomersListedJSONResponse(CustomerListResponse{Items: items})}, nil
}

func customerResponse(customer domain.Customer) Customer {
	var email *openapi_types.Email
	if customer.Email() != nil {
		value := openapi_types.Email(*customer.Email())
		email = &value
	}
	return Customer{
		CustomerId: customer.ID(),
		Name:       customer.Name(),
		Phone:      customer.Phone(),
		Email:      email,
		CreatedAt:  customer.CreatedAt(),
		UpdatedAt:  customer.UpdatedAt(),
	}
}

func (h *Handler) CreateVehicle(ctx context.Context, request CreateVehicleRequestObject) (CreateVehicleResponseObject, error) {
	if request.Body == nil {
		return CreateVehicle400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("invalid_request", "request body is required")))}, nil
	}
	vehicle, err := h.service.CreateVehicle(ctx, identityFrom(ctx), uuid.UUID(request.CustomerId), app.CreateVehicleInput{VIN: request.Body.Vin, RegistrationPlate: request.Body.RegistrationPlate, Make: request.Body.Make, Model: request.Body.Model, ModelYear: request.Body.ModelYear})
	if err != nil {
		return createVehicleErrorResponse(err)
	}
	return CreateVehicle201JSONResponse{VehicleCreatedJSONResponse: VehicleCreatedJSONResponse(vehicleResponse(vehicle))}, nil
}

func (h *Handler) GetVehicle(ctx context.Context, request GetVehicleRequestObject) (GetVehicleResponseObject, error) {
	vehicle, err := h.service.GetVehicle(ctx, identityFrom(ctx), uuid.UUID(request.VehicleId))
	if err != nil {
		return getVehicleErrorResponse(err)
	}
	return GetVehicle200JSONResponse{VehicleFoundJSONResponse: VehicleFoundJSONResponse(vehicleResponse(vehicle))}, nil
}

func (h *Handler) ListCustomerVehicles(ctx context.Context, request ListCustomerVehiclesRequestObject) (ListCustomerVehiclesResponseObject, error) {
	vehicles, err := h.service.ListCustomerVehicles(ctx, identityFrom(ctx), uuid.UUID(request.CustomerId))
	if err != nil {
		return listVehiclesErrorResponse(err)
	}
	items := make([]Vehicle, 0, len(vehicles))
	for _, vehicle := range vehicles {
		items = append(items, vehicleResponse(vehicle))
	}
	return ListCustomerVehicles200JSONResponse{VehiclesListedJSONResponse: VehiclesListedJSONResponse(VehicleListResponse{Items: items})}, nil
}

func (h *Handler) UpdateVehicle(ctx context.Context, request UpdateVehicleRequestObject) (UpdateVehicleResponseObject, error) {
	if request.Body == nil || (request.Body.Vin == nil && request.Body.RegistrationPlate == nil && request.Body.Make == nil && request.Body.Model == nil && request.Body.ModelYear == nil) {
		return UpdateVehicle400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(common.NewInvalidInputError("invalid_request", "at least one field is required")))}, nil
	}
	input := app.UpdateVehicleInput{Make: request.Body.Make, Model: request.Body.Model}
	if request.Body.Vin != nil {
		input.VINPresent = request.Body.Vin.Present
		input.VIN = request.Body.Vin.Value
	}
	if request.Body.RegistrationPlate != nil {
		input.RegistrationPlatePresent = request.Body.RegistrationPlate.Present
		input.RegistrationPlate = request.Body.RegistrationPlate.Value
	}
	if request.Body.ModelYear != nil {
		input.ModelYearPresent = request.Body.ModelYear.Present
		input.ModelYear = request.Body.ModelYear.Value
	}
	vehicle, err := h.service.UpdateVehicle(ctx, identityFrom(ctx), uuid.UUID(request.VehicleId), input)
	if err != nil {
		return updateVehicleErrorResponse(err)
	}
	return UpdateVehicle200JSONResponse{VehicleUpdatedJSONResponse: VehicleUpdatedJSONResponse(vehicleResponse(vehicle))}, nil
}

func (h *Handler) DeleteVehicle(ctx context.Context, request DeleteVehicleRequestObject) (DeleteVehicleResponseObject, error) {
	if err := h.service.DeleteVehicle(ctx, identityFrom(ctx), uuid.UUID(request.VehicleId)); err != nil {
		return deleteVehicleErrorResponse(err)
	}
	return DeleteVehicle204Response{}, nil
}

func vehicleResponse(vehicle domain.Vehicle) Vehicle {
	return Vehicle{VehicleId: vehicle.ID(), CustomerId: vehicle.CustomerID(), Vin: vehicle.VIN(), RegistrationPlate: vehicle.RegistrationPlate(), Make: vehicle.Make(), Model: vehicle.Model(), ModelYear: vehicle.ModelYear(), CreatedAt: vehicle.CreatedAt(), UpdatedAt: vehicle.UpdatedAt()}
}

func (h *Handler) CreateDealership(ctx context.Context, request CreateDealershipRequestObject) (CreateDealershipResponseObject, error) {
	if request.Body == nil {
		response := errorResponse(common.NewInvalidInputError("request_body_required", "request body is required"))
		return CreateDealership400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	}
	dealership, err := h.service.CreateDealership(ctx, identityFrom(ctx), app.CreateDealershipInput{
		Name:     request.Body.Name,
		Code:     request.Body.Code,
		Address:  request.Body.Address,
		Timezone: request.Body.Timezone,
	})
	if err != nil {
		return createDealershipErrorResponse(err)
	}
	return CreateDealership201JSONResponse{DealershipCreatedJSONResponse: DealershipCreatedJSONResponse{
		DealershipId: dealership.ID(),
		Name:         dealership.Name(),
		Code:         dealership.Code(),
		Address:      dealership.Address(),
		Timezone:     dealership.Timezone(),
		IsActive:     dealership.IsActive(),
		CreatedAt:    dealership.CreatedAt(),
		UpdatedAt:    dealership.UpdatedAt(),
	}}, nil
}

func (h *Handler) requireIdentity(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		identity, err := h.auth.AuthenticateAccessToken(bearerToken(c.Request()))
		if err != nil || identity.UserID == uuid.Nil {
			return c.JSON(stdhttp.StatusUnauthorized, errorResponse(common.NewUnauthorizedError("authentication_required", "authentication required")))
		}
		request := c.Request().WithContext(context.WithValue(c.Request().Context(), identityKey{}, identity.UserID))
		c.SetRequest(request)
		return next(c)
	}
}

func bearerToken(request *stdhttp.Request) string {
	value := request.Header.Get("Authorization")
	prefix := "Bearer "
	if len(value) < len(prefix) || !strings.EqualFold(value[:len(prefix)], prefix) {
		return ""
	}
	return strings.TrimSpace(value[len(prefix):])
}

func identityFrom(ctx context.Context) uuid.UUID {
	identity, _ := ctx.Value(identityKey{}).(uuid.UUID)
	return identity
}

func customerProblem(err error) common.Error {
	var structured common.Error
	if errors.As(err, &structured) {
		return structured
	}
	return common.Error{PublicError: "internal server error", ErrorSlug: "internal_error"}
}

func technicianProblem(err error) common.Error {
	var structured common.Error
	if errors.As(err, &structured) {
		return structured
	}
	return common.Error{PublicError: "internal server error", ErrorSlug: "internal_server_error"}
}

func createTechnicianErrorResponse(err error) (CreateTechnicianResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 400:
		return CreateTechnician400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case 401:
		return CreateTechnician401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return CreateTechnician403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 409:
		return CreateTechnician409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	case 422:
		return CreateTechnician422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	default:
		return CreateTechnician500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listTechniciansErrorResponse(err error) (ListTechniciansResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 400:
		return ListTechnicians400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case 401:
		return ListTechnicians401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return ListTechnicians403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	default:
		return ListTechnicians500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func getTechnicianErrorResponse(err error) (GetTechnicianResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 401:
		return GetTechnician401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return GetTechnician403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return GetTechnician404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return GetTechnician500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateTechnicianErrorResponse(err error) (UpdateTechnicianResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 400:
		return UpdateTechnician400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case 401:
		return UpdateTechnician401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return UpdateTechnician403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return UpdateTechnician404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case 409:
		return UpdateTechnician409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	case 422:
		return UpdateTechnician422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	default:
		return UpdateTechnician500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteTechnicianErrorResponse(err error) (DeleteTechnicianResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 401:
		return DeleteTechnician401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return DeleteTechnician403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return DeleteTechnician404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case 409:
		return DeleteTechnician409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return DeleteTechnician500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func createTechnicianSkillErrorResponse(err error) (CreateTechnicianSkillResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 400:
		return CreateTechnicianSkill400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case 401:
		return CreateTechnicianSkill401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return CreateTechnicianSkill403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return CreateTechnicianSkill404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case 409:
		return CreateTechnicianSkill409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return CreateTechnicianSkill500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listTechnicianSkillsErrorResponse(err error) (ListTechnicianSkillsResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 400:
		return ListTechnicianSkills400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case 401:
		return ListTechnicianSkills401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return ListTechnicianSkills403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return ListTechnicianSkills404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListTechnicianSkills500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateTechnicianSkillErrorResponse(err error) (UpdateTechnicianSkillResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 400:
		return UpdateTechnicianSkill400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case 401:
		return UpdateTechnicianSkill401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return UpdateTechnicianSkill403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return UpdateTechnicianSkill404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case 409:
		return UpdateTechnicianSkill409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return UpdateTechnicianSkill500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteTechnicianSkillErrorResponse(err error) (DeleteTechnicianSkillResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 401:
		return DeleteTechnicianSkill401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return DeleteTechnicianSkill403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return DeleteTechnicianSkill404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return DeleteTechnicianSkill500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func createTechnicianShiftErrorResponse(err error) (CreateTechnicianShiftResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 400:
		return CreateTechnicianShift422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	case 401:
		return CreateTechnicianShift401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return CreateTechnicianShift403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return CreateTechnicianShift404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case 409:
		return CreateTechnicianShift409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	case 422:
		return CreateTechnicianShift422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	default:
		return CreateTechnicianShift500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listTechnicianShiftErrorResponse(err error) (ListTechnicianShiftsResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 401:
		return ListTechnicianShifts401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return ListTechnicianShifts403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return ListTechnicianShifts404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListTechnicianShifts500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateTechnicianShiftErrorResponse(err error) (UpdateTechnicianShiftResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 400:
		return UpdateTechnicianShift422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	case 401:
		return UpdateTechnicianShift401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return UpdateTechnicianShift403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return UpdateTechnicianShift404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case 409:
		return UpdateTechnicianShift409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	case 422:
		return UpdateTechnicianShift422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	default:
		return UpdateTechnicianShift500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteTechnicianShiftErrorResponse(err error) (DeleteTechnicianShiftResponseObject, error) {
	structured, response := technicianProblem(err), errorResponse(technicianProblem(err))
	switch structured.HttpErrorCode {
	case 401:
		return DeleteTechnicianShift401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case 403:
		return DeleteTechnicianShift403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case 404:
		return DeleteTechnicianShift404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case 409:
		return DeleteTechnicianShift409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return DeleteTechnicianShift500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func createTechnicianTimeOffError(err error) (CreateTechnicianTimeOffResponseObject, error) {
	problem, body := technicianProblem(err), errorResponse(technicianProblem(err))
	switch problem.HttpErrorCode {
	case 400:
		return CreateTechnicianTimeOff400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(body)}, nil
	case 401:
		return CreateTechnicianTimeOff401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(body)}, nil
	case 403:
		return CreateTechnicianTimeOff403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(body)}, nil
	case 404:
		return CreateTechnicianTimeOff404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(body)}, nil
	case 409:
		return CreateTechnicianTimeOff409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(body)}, nil
	default:
		return CreateTechnicianTimeOff500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(body)}, nil
	}
}
func listTechnicianTimeOffError(err error) (ListTechnicianTimeOffResponseObject, error) {
	problem, body := technicianProblem(err), errorResponse(technicianProblem(err))
	switch problem.HttpErrorCode {
	case 400:
		return ListTechnicianTimeOff400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(body)}, nil
	case 401:
		return ListTechnicianTimeOff401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(body)}, nil
	case 403:
		return ListTechnicianTimeOff403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(body)}, nil
	case 404:
		return ListTechnicianTimeOff404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(body)}, nil
	default:
		return ListTechnicianTimeOff500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(body)}, nil
	}
}
func getTechnicianTimeOffError(err error) (GetTechnicianTimeOffResponseObject, error) {
	problem, body := technicianProblem(err), errorResponse(technicianProblem(err))
	switch problem.HttpErrorCode {
	case 401:
		return GetTechnicianTimeOff401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(body)}, nil
	case 403:
		return GetTechnicianTimeOff403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(body)}, nil
	case 404:
		return GetTechnicianTimeOff404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(body)}, nil
	default:
		return GetTechnicianTimeOff500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(body)}, nil
	}
}
func updateTechnicianTimeOffError(err error) (UpdateTechnicianTimeOffResponseObject, error) {
	problem, body := technicianProblem(err), errorResponse(technicianProblem(err))
	switch problem.HttpErrorCode {
	case 400:
		return UpdateTechnicianTimeOff400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(body)}, nil
	case 401:
		return UpdateTechnicianTimeOff401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(body)}, nil
	case 403:
		return UpdateTechnicianTimeOff403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(body)}, nil
	case 404:
		return UpdateTechnicianTimeOff404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(body)}, nil
	case 409:
		return UpdateTechnicianTimeOff409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(body)}, nil
	default:
		return UpdateTechnicianTimeOff500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(body)}, nil
	}
}
func deleteTechnicianTimeOffError(err error) (DeleteTechnicianTimeOffResponseObject, error) {
	problem, body := technicianProblem(err), errorResponse(technicianProblem(err))
	switch problem.HttpErrorCode {
	case 401:
		return DeleteTechnicianTimeOff401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(body)}, nil
	case 403:
		return DeleteTechnicianTimeOff403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(body)}, nil
	case 404:
		return DeleteTechnicianTimeOff404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(body)}, nil
	default:
		return DeleteTechnicianTimeOff500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(body)}, nil
	}
}

func createCustomerErrorResponse(err error) (CreateCustomerResponseObject, error) {
	structured := customerProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateCustomer400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateCustomer401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateCustomer403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateCustomer409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return CreateCustomer500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func getCustomerErrorResponse(err error) (GetCustomerResponseObject, error) {
	structured := customerProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return GetCustomer400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return GetCustomer401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return GetCustomer403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return GetCustomer404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return GetCustomer500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateCustomerErrorResponse(err error) (UpdateCustomerResponseObject, error) {
	structured := customerProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return UpdateCustomer400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return UpdateCustomer401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return UpdateCustomer403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return UpdateCustomer404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return UpdateCustomer409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return UpdateCustomer500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func searchCustomersErrorResponse(err error) (SearchCustomersResponseObject, error) {
	structured := customerProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return SearchCustomers400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return SearchCustomers401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return SearchCustomers403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	default:
		return SearchCustomers500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func vehicleProblem(err error) common.Error {
	var structured common.Error
	if errors.As(err, &structured) {
		return structured
	}
	return common.Error{PublicError: "internal server error", ErrorSlug: "internal_error"}
}

func createVehicleErrorResponse(err error) (CreateVehicleResponseObject, error) {
	structured := vehicleProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateVehicle400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateVehicle401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateVehicle403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return CreateVehicle404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateVehicle409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return CreateVehicle500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func getVehicleErrorResponse(err error) (GetVehicleResponseObject, error) {
	structured := vehicleProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return GetVehicle401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return GetVehicle403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return GetVehicle404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return GetVehicle500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listVehiclesErrorResponse(err error) (ListCustomerVehiclesResponseObject, error) {
	structured := vehicleProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return ListCustomerVehicles401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListCustomerVehicles403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ListCustomerVehicles404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListCustomerVehicles500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateVehicleErrorResponse(err error) (UpdateVehicleResponseObject, error) {
	structured := vehicleProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return UpdateVehicle400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return UpdateVehicle401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return UpdateVehicle403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return UpdateVehicle404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return UpdateVehicle409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return UpdateVehicle500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteVehicleErrorResponse(err error) (DeleteVehicleResponseObject, error) {
	structured := vehicleProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return DeleteVehicle401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return DeleteVehicle403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return DeleteVehicle404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return DeleteVehicle409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return DeleteVehicle500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func createDealershipErrorResponse(err error) (CreateDealershipResponseObject, error) {
	var structured common.Error
	if !errors.As(err, &structured) {
		return nil, err
	}
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateDealership400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateDealership401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateDealership403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateDealership409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return nil, err
	}
}

func createDealershipAdminErrorResponse(err error) (CreateDealershipAdminResponseObject, error) {
	var structured common.Error
	if !errors.As(err, &structured) {
		return nil, err
	}
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateDealershipAdmin400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateDealershipAdmin401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateDealershipAdmin403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return CreateDealershipAdmin404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateDealershipAdmin409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return nil, err
	}
}

func createDealershipUserErrorResponse(err error) (CreateDealershipUserResponseObject, error) {
	var structured common.Error
	if !errors.As(err, &structured) {
		return nil, err
	}
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateDealershipUser400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateDealershipUser401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateDealershipUser403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return CreateDealershipUser404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateDealershipUser409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return nil, err
	}
}

func searchAuthUserByEmailErrorResponse(err error) (SearchAuthUserByEmailResponseObject, error) {
	var structured common.Error
	if !errors.As(err, &structured) {
		response := errorResponse(common.Error{
			PublicError: "internal server error",
			ErrorSlug:   "internal_server_error",
		})
		return SearchAuthUserByEmail500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return SearchAuthUserByEmail400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return SearchAuthUserByEmail401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return SearchAuthUserByEmail403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return SearchAuthUserByEmail404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		response := errorResponse(common.Error{
			PublicError: "internal server error",
			ErrorSlug:   "internal_server_error",
		})
		return SearchAuthUserByEmail500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func serviceTypeProblem(err error) (common.Error, bool) {
	var structured common.Error
	if errors.As(err, &structured) {
		return structured, true
	}
	return common.Error{PublicError: "internal server error", ErrorSlug: "internal_server_error"}, false
}

func createServiceTypeErrorResponse(err error) (CreateServiceTypeResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateServiceType400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateServiceType401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateServiceType403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateServiceType409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return CreateServiceType500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listServiceTypesErrorResponse(err error) (ListServiceTypesResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return ListServiceTypes401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListServiceTypes403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	default:
		return ListServiceTypes500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func getServiceTypeErrorResponse(err error) (GetServiceTypeResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return GetServiceType401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return GetServiceType403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return GetServiceType404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return GetServiceType500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateServiceTypeErrorResponse(err error) (UpdateServiceTypeResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return UpdateServiceType400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return UpdateServiceType401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return UpdateServiceType403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return UpdateServiceType404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return UpdateServiceType409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return UpdateServiceType500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteServiceTypeErrorResponse(err error) (DeleteServiceTypeResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return DeleteServiceType401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return DeleteServiceType403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return DeleteServiceType404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return DeleteServiceType409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return DeleteServiceType500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func createServiceTypeRequiredSkillErrorResponse(err error) (CreateServiceTypeRequiredSkillResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateServiceTypeRequiredSkill400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateServiceTypeRequiredSkill401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateServiceTypeRequiredSkill403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return CreateServiceTypeRequiredSkill404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateServiceTypeRequiredSkill409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return CreateServiceTypeRequiredSkill500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listServiceTypeRequiredSkillsErrorResponse(err error) (ListServiceTypeRequiredSkillsResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return ListServiceTypeRequiredSkills401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListServiceTypeRequiredSkills403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ListServiceTypeRequiredSkills404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListServiceTypeRequiredSkills500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateServiceTypeRequiredSkillErrorResponse(err error) (UpdateServiceTypeRequiredSkillResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return UpdateServiceTypeRequiredSkill400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return UpdateServiceTypeRequiredSkill401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return UpdateServiceTypeRequiredSkill403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return UpdateServiceTypeRequiredSkill404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return UpdateServiceTypeRequiredSkill409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return UpdateServiceTypeRequiredSkill500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteServiceTypeRequiredSkillErrorResponse(err error) (DeleteServiceTypeRequiredSkillResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return DeleteServiceTypeRequiredSkill401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return DeleteServiceTypeRequiredSkill403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return DeleteServiceTypeRequiredSkill404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return DeleteServiceTypeRequiredSkill500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func createServiceTypeRequiredBayCapabilityErrorResponse(err error) (CreateServiceTypeRequiredBayCapabilityResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateServiceTypeRequiredBayCapability400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateServiceTypeRequiredBayCapability401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateServiceTypeRequiredBayCapability403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return CreateServiceTypeRequiredBayCapability404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateServiceTypeRequiredBayCapability409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return CreateServiceTypeRequiredBayCapability500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listServiceTypeRequiredBayCapabilitiesErrorResponse(err error) (ListServiceTypeRequiredBayCapabilitiesResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return ListServiceTypeRequiredBayCapabilities401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListServiceTypeRequiredBayCapabilities403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ListServiceTypeRequiredBayCapabilities404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListServiceTypeRequiredBayCapabilities500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateServiceTypeRequiredBayCapabilityErrorResponse(err error) (UpdateServiceTypeRequiredBayCapabilityResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return UpdateServiceTypeRequiredBayCapability400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return UpdateServiceTypeRequiredBayCapability401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return UpdateServiceTypeRequiredBayCapability403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return UpdateServiceTypeRequiredBayCapability404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return UpdateServiceTypeRequiredBayCapability409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return UpdateServiceTypeRequiredBayCapability500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteServiceTypeRequiredBayCapabilityErrorResponse(err error) (DeleteServiceTypeRequiredBayCapabilityResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return DeleteServiceTypeRequiredBayCapability401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return DeleteServiceTypeRequiredBayCapability403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return DeleteServiceTypeRequiredBayCapability404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return DeleteServiceTypeRequiredBayCapability500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func createServiceBayErrorResponse(err error) (CreateServiceBayResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateServiceBay400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateServiceBay401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateServiceBay403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateServiceBay409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return CreateServiceBay500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listServiceBaysErrorResponse(err error) (ListServiceBaysResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return ListServiceBays400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return ListServiceBays401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListServiceBays403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	default:
		return ListServiceBays500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func getServiceBayErrorResponse(err error) (GetServiceBayResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return GetServiceBay401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return GetServiceBay403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return GetServiceBay404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return GetServiceBay500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateServiceBayErrorResponse(err error) (UpdateServiceBayResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return UpdateServiceBay400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return UpdateServiceBay401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return UpdateServiceBay403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return UpdateServiceBay404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return UpdateServiceBay409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return UpdateServiceBay500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteServiceBayErrorResponse(err error) (DeleteServiceBayResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return DeleteServiceBay401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return DeleteServiceBay403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return DeleteServiceBay404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return DeleteServiceBay409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return DeleteServiceBay500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func createServiceBayCapabilityErrorResponse(err error) (CreateServiceBayCapabilityResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateServiceBayCapability400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateServiceBayCapability401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateServiceBayCapability403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return CreateServiceBayCapability404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateServiceBayCapability409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return CreateServiceBayCapability500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listServiceBayCapabilitiesErrorResponse(err error) (ListServiceBayCapabilitiesResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return ListServiceBayCapabilities401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListServiceBayCapabilities403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ListServiceBayCapabilities404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListServiceBayCapabilities500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateServiceBayCapabilityErrorResponse(err error) (UpdateServiceBayCapabilityResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return UpdateServiceBayCapability400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return UpdateServiceBayCapability401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return UpdateServiceBayCapability403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return UpdateServiceBayCapability404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return UpdateServiceBayCapability409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	default:
		return UpdateServiceBayCapability500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteServiceBayCapabilityErrorResponse(err error) (DeleteServiceBayCapabilityResponseObject, error) {
	structured, _ := serviceTypeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return DeleteServiceBayCapability401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return DeleteServiceBayCapability403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return DeleteServiceBayCapability404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return DeleteServiceBayCapability500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func errorResponse(err common.Error) ErrorResponse {
	details := make([]ErrorDetail, 0, len(err.Details))
	for _, detail := range err.Details {
		details = append(details, ErrorDetail{
			EntityType: detail.EntityType,
			EntityId:   detail.EntityID,
			ErrorSlug:  detail.ErrorSlug,
			Message:    detail.Message,
		})
	}
	status := err.HttpErrorCode
	if status == 0 {
		status = stdhttp.StatusInternalServerError
	}
	message := err.PublicError
	slug := err.ErrorSlug
	return ErrorResponse{
		Type:    "about:blank",
		Title:   stdhttp.StatusText(status),
		Status:  status,
		Detail:  message,
		Code:    slug,
		Errors:  &details,
		Message: &message,
		Slug:    &slug,
		Details: &details,
	}
}

func operationTimeProblem(err error) common.Error {
	var structured common.Error
	if errors.As(err, &structured) {
		return structured
	}
	return common.Error{PublicError: "internal server error", ErrorSlug: "internal_server_error"}
}

func createOperationTimeErrorResponse(err error) (CreateDealershipOperationTimeResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return CreateDealershipOperationTime400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return CreateDealershipOperationTime401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return CreateDealershipOperationTime403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return CreateDealershipOperationTime404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return CreateDealershipOperationTime409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	case 422:
		return CreateDealershipOperationTime422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	default:
		return CreateDealershipOperationTime500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func listOperationTimeErrorResponse(err error) (ListDealershipOperationTimesResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return ListDealershipOperationTimes401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return ListDealershipOperationTimes403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return ListDealershipOperationTimes404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return ListDealershipOperationTimes500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func updateOperationTimeErrorResponse(err error) (UpdateDealershipOperationTimeResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusBadRequest:
		return UpdateDealershipOperationTime400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(response)}, nil
	case stdhttp.StatusUnauthorized:
		return UpdateDealershipOperationTime401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return UpdateDealershipOperationTime403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return UpdateDealershipOperationTime404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	case stdhttp.StatusConflict:
		return UpdateDealershipOperationTime409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(response)}, nil
	case 422:
		return UpdateDealershipOperationTime422JSONResponse{UnprocessableEntityJSONResponse: UnprocessableEntityJSONResponse(response)}, nil
	default:
		return UpdateDealershipOperationTime500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}

func deleteOperationTimeErrorResponse(err error) (DeleteDealershipOperationTimeResponseObject, error) {
	structured := operationTimeProblem(err)
	response := errorResponse(structured)
	switch structured.HttpErrorCode {
	case stdhttp.StatusUnauthorized:
		return DeleteDealershipOperationTime401JSONResponse{UnauthorizedJSONResponse: UnauthorizedJSONResponse(response)}, nil
	case stdhttp.StatusForbidden:
		return DeleteDealershipOperationTime403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(response)}, nil
	case stdhttp.StatusNotFound:
		return DeleteDealershipOperationTime404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(response)}, nil
	default:
		return DeleteDealershipOperationTime500JSONResponse{InternalServerErrorJSONResponse: InternalServerErrorJSONResponse(response)}, nil
	}
}
