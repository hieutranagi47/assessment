// Package http exposes the dealership OpenAPI surface through Echo.
package http

import (
	"context"
	"errors"
	stdhttp "net/http"
	"strings"

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
			"createServiceBay":               {handler.requireIdentity},
			"listServiceBays":                {handler.requireIdentity},
			"getServiceBay":                  {handler.requireIdentity},
			"updateServiceBay":               {handler.requireIdentity},
			"deleteServiceBay":               {handler.requireIdentity},
			"createServiceType":              {handler.requireIdentity},
			"listServiceTypes":               {handler.requireIdentity},
			"getServiceType":                 {handler.requireIdentity},
			"updateServiceType":              {handler.requireIdentity},
			"deleteServiceType":              {handler.requireIdentity},
			"createServiceTypeRequiredSkill": {handler.requireIdentity},
			"listServiceTypeRequiredSkills":  {handler.requireIdentity},
			"updateServiceTypeRequiredSkill": {handler.requireIdentity},
			"deleteServiceTypeRequiredSkill": {handler.requireIdentity},
			"createDealershipUser":           {handler.requireIdentity},
			"createDealership":               {handler.requireIdentity},
			"createDealershipAdmin":          {handler.requireIdentity},
			"searchAuthUserByEmail":          {handler.requireIdentity},
		},
	})
	return nil
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
