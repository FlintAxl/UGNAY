from fastapi import APIRouter, Depends

from ..auth import require_role
from ..database import users
from ..helpers import api_error, log_audit, now, signed_url, to_object_id
from ..models import ALL_STATUSES, ApproveRequest, RejectRequest, Status

router = APIRouter(prefix="/admin", tags=["admin"])

SUMMARY_FIELDS = {"email": 1, "full_name": 1, "phone": 1, "status": 1, "role": 1,
                  "created_at": 1}


def summary(u: dict) -> dict:
    return {"id": str(u["_id"]), "email": u["email"], "full_name": u["full_name"],
            "phone": u["phone"], "status": u["status"], "role": u["role"],
            "created_at": u["created_at"]}


@router.get("/applicants")
async def list_applicants(status: str = "PENDING", admin: dict = Depends(require_role("admin"))):
    status = status.upper()
    if status not in ALL_STATUSES:
        raise api_error(400, "INVALID_STATUS", f"Status must be one of {sorted(ALL_STATUSES)}.")
    cursor = users.find({"status": status}, SUMMARY_FIELDS).sort("created_at", -1).limit(200)
    return [summary(u) async for u in cursor]


@router.get("/applicants/{user_id}")
async def applicant_detail(user_id: str, admin: dict = Depends(require_role("admin"))):
    u = await users.find_one({"_id": to_object_id(user_id)}, {"face_embedding": 0,
                                                              "password_hash": 0})
    if not u:
        raise api_error(404, "NOT_FOUND", "User not found.")
    return {
        **summary(u),
        "address": u["address"],
        "id_photo_url": signed_url(u.get("id_photo_id")),
        "face_photo_url": signed_url(u.get("face_photo_id")),
        "reviewed_by": str(u["reviewed_by"]) if u.get("reviewed_by") else None,
        "reviewed_at": u.get("reviewed_at"),
        "rejection_reason": u.get("rejection_reason"),
    }


async def _fail_review(oid):
    """Called when the PENDING filter matched nothing: 404 vs already reviewed."""
    if not await users.find_one({"_id": oid}, {"_id": 1}):
        raise api_error(404, "NOT_FOUND", "User not found.")
    raise api_error(409, "ALREADY_REVIEWED", "This applicant is no longer pending.")


@router.post("/applicants/{user_id}/approve")
async def approve(user_id: str, body: ApproveRequest,
                  admin: dict = Depends(require_role("admin"))):
    oid = to_object_id(user_id)
    # The status filter makes this atomic: two admins can't approve the same user.
    result = await users.update_one(
        {"_id": oid, "status": Status.PENDING},
        {"$set": {"status": Status.ACTIVE, "role": body.role.value,
                  "reviewed_by": admin["_id"], "reviewed_at": now(),
                  "rejection_reason": None, "updated_at": now()}},
    )
    if result.matched_count == 0:
        await _fail_review(oid)
    await log_audit(admin["_id"], "USER_APPROVED", oid, {"role_assigned": body.role.value})
    return {"message": "Applicant approved.", "role": body.role.value}


@router.post("/applicants/{user_id}/reject")
async def reject(user_id: str, body: RejectRequest,
                 admin: dict = Depends(require_role("admin"))):
    oid = to_object_id(user_id)
    result = await users.update_one(
        {"_id": oid, "status": Status.PENDING},
        {"$set": {"status": Status.REJECTED, "rejection_reason": body.reason.strip(),
                  "reviewed_by": admin["_id"], "reviewed_at": now(),
                  "updated_at": now()}},
    )
    if result.matched_count == 0:
        await _fail_review(oid)
    await log_audit(admin["_id"], "USER_REJECTED", oid, {"reason": body.reason.strip()})
    return {"message": "Applicant rejected."}