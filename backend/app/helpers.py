import io
import math
from datetime import datetime, timezone

import cloudinary
import cloudinary.uploader
import cloudinary.utils
import httpx
from bson import ObjectId
from bson.errors import InvalidId
from fastapi import HTTPException, UploadFile
from starlette.concurrency import run_in_threadpool

from .config import settings
from .database import audit_logs

cloudinary.config(
    cloud_name=settings.CLOUDINARY_CLOUD_NAME,
    api_key=settings.CLOUDINARY_API_KEY,
    api_secret=settings.CLOUDINARY_API_SECRET,
    secure=True,
)

MAX_IMAGE_BYTES = 5 * 1024 * 1024


def now() -> datetime:
    return datetime.now(timezone.utc)


def api_error(status: int, code: str, message: str, **extra) -> HTTPException:
    return HTTPException(status_code=status, detail={"code": code, "message": message, **extra})


def to_object_id(value: str) -> ObjectId:
    try:
        return ObjectId(value)
    except (InvalidId, TypeError):
        raise api_error(404, "NOT_FOUND", "User not found.")


async def read_image(file: UploadFile) -> bytes:
    data = await file.read()
    if not data:
        raise api_error(400, "INVALID_IMAGE", "Empty image file.")
    if len(data) > MAX_IMAGE_BYTES:
        raise api_error(413, "IMAGE_TOO_LARGE", "Image must be 5 MB or smaller.")
    is_jpeg = data[:3] == b"\xff\xd8\xff"
    is_png = data[:8] == b"\x89PNG\r\n\x1a\n"
    if not (is_jpeg or is_png):
        raise api_error(400, "INVALID_IMAGE", "Only JPEG or PNG images are allowed.")
    return data


# ---------- Face service ----------

async def get_embedding(image_bytes: bytes) -> list[float]:
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            r = await client.post(
                f"{settings.FACE_SERVICE_URL}/face/embed",
                files={"image": ("face.jpg", image_bytes, "image/jpeg")},
            )
    except httpx.HTTPError:
        raise api_error(503, "FACE_SERVICE_UNAVAILABLE", "Face service is not reachable.")

    if r.status_code == 422:
        detail = r.json().get("detail", {})
        if not isinstance(detail, dict):
            detail = {}
        raise api_error(422, detail.get("code", "FACE_ERROR"),
                        detail.get("message", "Face check failed."))
    if r.status_code != 200:
        raise api_error(502, "FACE_SERVICE_ERROR", "Face service returned an error.")
    return r.json()["embedding"]


def cosine_similarity(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


# ---------- Cloudinary ----------

async def upload_image(data: bytes, subfolder: str) -> str:
    """Upload as 'authenticated' (not publicly guessable). Returns the public_id."""
    def _upload():
        result = cloudinary.uploader.upload(
            io.BytesIO(data),
            folder=f"{settings.CLOUDINARY_UPLOAD_FOLDER}/{subfolder}",
            type="authenticated",
            resource_type="image",
        )
        return result["public_id"]

    try:
        return await run_in_threadpool(_upload)
    except Exception:
        raise api_error(502, "UPLOAD_FAILED", "Could not upload the image.")


def signed_url(public_id: str | None) -> str | None:
    if not public_id:
        return None
    url, _ = cloudinary.utils.cloudinary_url(
        public_id, type="authenticated", sign_url=True, secure=True,
        width=800, crop="limit",
    )
    return url


# ---------- Audit log ----------

async def log_audit(actor_id, action: str, target_id=None, details: dict | None = None):
    await audit_logs.insert_one({
        "actor_id": actor_id,
        "action": action,
        "target_id": target_id,
        "details": details or {},
        "created_at": now(),
    })