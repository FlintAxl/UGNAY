from datetime import timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from bson import ObjectId
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import settings
from .database import users
from .helpers import api_error, now
from .models import Status

_hasher = PasswordHasher()
_bearer = HTTPBearer()


# ---------- Passwords ----------

def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except (VerificationError, InvalidHashError):
        return False


# ---------- JWT ----------

def create_token(user_id, token_type: str, expires: timedelta) -> str:
    payload = {"sub": str(user_id), "type": token_type, "exp": now() + expires}
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str, expected_type: str) -> dict:
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise api_error(401, "TOKEN_EXPIRED", "Token has expired.")
    except jwt.PyJWTError:
        raise api_error(401, "INVALID_TOKEN", "Invalid token.")
    if payload.get("type") != expected_type:
        raise api_error(401, "INVALID_TOKEN", "Wrong token type.")
    return payload


def issue_tokens(user: dict) -> dict:
    return {
        "access_token": create_token(
            user["_id"], "access", timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)),
        "refresh_token": create_token(
            user["_id"], "refresh", timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)),
        "token_type": "bearer",
        "role": user["role"],
        "full_name": user["full_name"],
    }


# ---------- Dependencies ----------

async def get_current_user(creds: HTTPAuthorizationCredentials = Depends(_bearer)) -> dict:
    payload = decode_token(creds.credentials, "access")
    user = await users.find_one({"_id": ObjectId(payload["sub"])})
    if not user or user["status"] != Status.ACTIVE:
        raise api_error(401, "INVALID_TOKEN", "Account is not active.")
    return user


def require_role(*roles: str):
    async def checker(user: dict = Depends(get_current_user)) -> dict:
        if user["role"] not in roles:
            raise api_error(403, "FORBIDDEN", "You do not have access to this resource.")
        return user
    return checker