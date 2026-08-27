# Searching user from the auth module by email

## Requirement
- in the appointment_scheduler, create an API to search a user in auth module.
- the API will call the GetUserInfoByEmail in `/Users/hieutran/Development/Assessment/dealership/modules/auth/api/module/module.go` to get user information.
- Only admin/superadmin of the auth module or admin of appointment_scheduler.users can use this api

## API purpose
Admin can search a user who has signed up an account, and assign that user to be an user in appointment_scheduler module.