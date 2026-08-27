# LOGIC FLOW


## Auth module
- User can sign up an account, and it's `user` role
- Supperadmin will be created by /auth/v1/internal/superadmin only once.
- Supperadmin can update a user in auth module to be admin or superadmin.
- when user login successfully, user will get the access_token in the response body and http_cookie only in the cookie
- the email will be encrypted because of privacy (however it should be encrypt by the user password that I don't implement yet), and the email must be hashed instead of encrypt by a key when I want to check an email existed or not.
- When user change password and want to loggout from all device, I'll increase a number of the token_ver, then user must log in again, and available access_tokens expired, the user will be logged out.

## Appointment scheduler module
- only superadmin/admin from auth.users can create Dealership
- a login user (admin, supperadmin) can search user from auth.users table by provided email from the dealership staff to add it into appointment_scheduler.users table and grant admin role for a dealership
- an admin of a dealership can get user by email from auth.users with the email that provided by the dealer staff, and grant the role as admin/staff/dealer.
- an admin of a dealership can create technican account.
- a staff/admin of the dealership can make the shifts for the technician of the dealership.
- a dealer can create customer account and make appointment for the customer for the dealership

## Hard part
- at first, I don't review the plan carefully then I got some redundant tables, and I asked AI to design API and implement it. I made the big mistake. then I remembered that I should design features first, and user behavior, and base on it, I would ask AI to design API following as feature instead of DB.
- AI should handle every single API instead of the whole features.
