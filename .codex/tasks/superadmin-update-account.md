# Superadmin update role for other account.

## Requirements:
- Create one API to update role for an account in the `auth` module.

## Rules:
- superadmin user can grant any user to any role, but cannot update its role.
- admin user or user user cannot update their role, and API will return no permission

## Guide:
- Can use `CreateUserRole` in the `dealership/modules/auth/adapters/db/queries/users.sql`, if the user has a role, the method will update it