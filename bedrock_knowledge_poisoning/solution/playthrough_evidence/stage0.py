"""Stage 0 -- Cognito self-signup as an employee."""
from _play_helpers import *

banner("Stage 0 / Cognito self-signup")

email    = f"playthrough-v10-{uuid.uuid4().hex[:8]}@atlas.example"
password = "PlayPass!2026"
print(f"[stage0] sign-up email = {email}")

resp = cognito.sign_up(
    ClientId=CLIENT_ID,
    Username=email,
    Password=password,
    UserAttributes=[{"Name": "email", "Value": email}],
)
print(f"[stage0] sign_up      UserConfirmed={resp['UserConfirmed']} sub={resp['UserSub']}")
print(f"[stage0] auto-confirm Lambda fired (no email verification step)")

auth = cognito.initiate_auth(
    ClientId=CLIENT_ID,
    AuthFlow="USER_PASSWORD_AUTH",
    AuthParameters={"USERNAME": email, "PASSWORD": password},
)
id_token = auth["AuthenticationResult"]["IdToken"]
sub      = jwt_sub(id_token)
groups   = jwt_groups(id_token)
print(f"[stage0] initiate_auth USER_PASSWORD_AUTH succeeded")
print(f"[stage0] JWT claims    sub={sub} email={email} cognito:groups={groups}")
print(f"[stage0] this is an employee session (groups is empty)")

save_session("stage0", {
    "email":    email,
    "password": password,
    "id_token": id_token,
    "sub":      sub,
    "groups":   groups,
})

write_evidence("stage0_signup_response.json", {
    "UserConfirmed": resp["UserConfirmed"],
    "UserSub":       resp["UserSub"],
    "ResponseMetadata_HTTPStatusCode": resp["ResponseMetadata"]["HTTPStatusCode"],
})

write_evidence("stage0_id_token_claims.json", {
    "sub":             sub,
    "email":           email,
    "cognito:groups":  groups,
})

print("[stage0] PASS")
