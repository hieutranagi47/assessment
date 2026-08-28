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
	service *app.Service
	auth    client.Authenticator
}

func NewHandler(service *app.Service, auth client.Authenticator) *Handler {
	if service == nil || auth == nil {
		panic("dealership HTTP dependencies are required")
	}
	return &Handler{service: service, auth: auth}
}

func Register(_ context.Context, router common.EchoRouter, handler *Handler) error {
	RegisterHandlersWithOptions(router, NewStrictHandler(handler, nil), RegisterHandlersOptions{
		OperationMiddlewares: map[string][]echo.MiddlewareFunc{
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
		},
	})
	return nil
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
	return ErrorResponse{Message: err.PublicError, Slug: err.ErrorSlug, Details: details}
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
