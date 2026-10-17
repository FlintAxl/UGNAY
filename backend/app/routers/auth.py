from datetime import timedelta

from bson import ObjectId
from fastapi import APIRouter, Depends, File, Form, UploadFile
from pydantic import EmailStr
from pymongo.errors import DuplicateKeyError

from ..auth import (create_token, decode_token, get_current_user, hash_password,
                    issue_tokens, verify_password)
from ..config import settings
from ..database import users
from ..helpers import (api_error, cosine_similarity, get_embedding, log_audit, now,
                       read_image, upload_image)
from ..models import LoginRequest, RefreshRequest, Status

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", status_code=201)
async def register(
    full_name: str = Form(..., min_length=2),
    email: EmailStr = Form(...),
    phone: str = Form(...),
    address: str = Form(...),
    password: str = Form(..., min_length=8),
    id_photo: UploadFile = File(...),
    face_photo: UploadFile = File(...),
):
    email = email.lower()
    if await users.find_one({"email": email}, {"_id": 1}):
        raise api_error(409, "EMAIL_TAKEN", "This email is already registered.")

    id_bytes = await read_image(id_photo)
    face_bytes = await read_image(face_photo)

    # Check the face first so we don't upload photos for a bad capture.
    embedding = await get_embedding(face_bytes)

    id_public_id = await upload_image(id_bytes, "ids")
    face_public_id = await upload_image(face_bytes, "faces")

    doc = {
        "email": email,
        "password_hash": hash_password(password),
        "full_name": full_name.strip(),
        "phone": phone.strip(),
        "address": address.strip(),
        "status": Status.PENDING,
        "role": "UNASSIGNED",
        "id_photo_id": id_public_id,
        "face_photo_id": face_public_id,
        "face_embedding": embedding,
        "reviewed_by": None,
        "reviewed_at": None,
        "rejection_reason": None,
        "created_at": now(),
        "updated_at": now(),
    }
    try:
        result = await users.insert_one(doc)
    except DuplicateKeyError:
        raise api_error(409, "EMAIL_TAKEN", "This email is already registered.")

    await log_audit(result.inserted_id, "USER_REGISTERED", result.inserted_id)
    return {"message": "Registration submitted. Please wait for admin approval.",
            "status": Status.PENDING}


@router.post("/login")
async def login(body: LoginRequest):
    user = await users.find_one({"email": body.email.lower()})
    if not user or not verify_password(body.password, user["password_hash"]):
        raise api_error(401, "INVALID_CREDENTIALS", "Incorrect email or password.")

    if user["status"] == Status.PENDING:
        raise api_error(403, "ACCOUNT_PENDING", "Your account is still pending review.")
    if user["status"] == Status.REJECTED:
        raise api_error(403, "ACCOUNT_REJECTED", "Your registration was rejected.",
                        reason=user.get("rejection_reason"))
    if user["status"] == Status.SUSPENDED:
        raise api_error(403, "ACCOUNT_SUSPENDED", "Your account has been suspended.")

    # Password OK and ACTIVE: no JWT yet. Issue a short-lived, single-purpose token.
    face_token = create_token(
        user["_id"], "face_challenge",
        timedelta(minutes=settings.FACE_CHALLENGE_EXPIRE_MINUTES))
    return {"face_token": face_token,
            "message": "Password verified. Face verification required."}


@router.post("/verify-face")
async def verify_face(face_token: str = Form(...), image: UploadFile = File(...)):
    payload = decode_token(face_token, "face_challenge")
    user = await users.find_one({"_id": ObjectId(payload["sub"])})
    if not user or user["status"] != Status.ACTIVE:
        raise api_error(403, "ACCOUNT_NOT_ACTIVE", "Account is not active.")

    live_embedding = await get_embedding(await read_image(image))
    score = cosine_similarity(live_embedding, user["face_embedding"])

    if score < settings.FACE_THRESHOLD:
        await log_audit(user["_id"], "LOGIN_FACE_FAILED", user["_id"],
                        {"score": round(score, 3)})
        raise api_error(401, "FACE_MISMATCH", "Face did not match. Please try again.")

    await users.update_one({"_id": user["_id"]}, {"$set": {"last_login_at": now()}})
    await log_audit(user["_id"], "LOGIN_SUCCESS", user["_id"], {"score": round(score, 3)})
    return issue_tokens(user)


@router.post("/refresh")
async def refresh(body: RefreshRequest):
    payload = decode_token(body.refresh_token, "refresh")
    user = await users.find_one({"_id": ObjectId(payload["sub"])})
    if not user or user["status"] != Status.ACTIVE:
        raise api_error(401, "INVALID_TOKEN", "Account is not active.")
    return {"access_token": create_token(
        user["_id"], "access", timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))}


@router.get("/me")
async def me(user: dict = Depends(get_current_user)):
    return {"id": str(user["_id"]), "email": user["email"], "full_name": user["full_name"],
            "role": user["role"], "status": user["status"]}