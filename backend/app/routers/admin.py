from fastapi import APIRouter, Depends

from ..auth import require_role
from ..database import pmes_applications, users
from ..helpers import api_error, log_audit, now, signed_url, to_object_id
from ..models import (ALL_STATUSES, ApproveRequest, MembershipUpdateRequest,
                      PMES_APPROVED, PMES_REJECTED, PMES_STATUSES,
                      PMES_SUBMITTED, PmesRejectRequest, RejectRequest, Status)
from .pmes import application_out

router = APIRouter(prefix="/admin", tags=["admin"])

SUMMARY_FIELDS = {"email": 1, "full_name": 1, "phone": 1, "status": 1, "role": 1,
                  "membership_type": 1, "created_at": 1}


def summary(u: dict) -> dict:
    return {"id": str(u["_id"]), "email": u["email"], "full_name": u["full_name"],
            "phone": u["phone"], "status": u["status"], "role": u["role"],
            "membership_type": u.get("membership_type"),
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
                  "membership_type": body.membership_type.value,
                  "reviewed_by": admin["_id"], "reviewed_at": now(),
                  "rejection_reason": None, "updated_at": now()}},
    )
    if result.matched_count == 0:
        await _fail_review(oid)
    await log_audit(admin["_id"], "USER_APPROVED", oid,
                    {"role_assigned": body.role.value,
                     "membership_type": body.membership_type.value})
    return {"message": "Applicant approved.", "role": body.role.value,
            "membership_type": body.membership_type.value}


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


@router.patch("/users/{user_id}/membership-type")
async def update_membership_type(user_id: str, body: MembershipUpdateRequest,
                                 admin: dict = Depends(require_role("admin"))):
    oid = to_object_id(user_id)
    result = await users.update_one(
        {"_id": oid, "status": Status.ACTIVE},
        {"$set": {"membership_type": body.membership_type.value, "updated_at": now()}},
    )
    if result.matched_count == 0:
        if not await users.find_one({"_id": oid}, {"_id": 1}):
            raise api_error(404, "NOT_FOUND", "User not found.")
        raise api_error(409, "NOT_ACTIVE",
                        "Membership type can only be set for active accounts.")
    await log_audit(admin["_id"], "MEMBERSHIP_TYPE_UPDATED", oid,
                    {"membership_type": body.membership_type.value})
    return {"message": "Membership type updated.",
            "membership_type": body.membership_type.value}


# =====================================================================
# PMES applications
# =====================================================================

def pmes_summary(app: dict, user: dict | None) -> dict:
    return {
        "id": str(app["_id"]),
        "reference_no": app.get("reference_no"),
        "email": app.get("email"),
        "full_name": (user or {}).get("full_name"),
        "schedule_date": app.get("schedule_date"),
        "status": app.get("status", PMES_SUBMITTED),
        "created_at": app.get("created_at"),
        "updated_at": app.get("updated_at"),
    }


async def _fail_pmes_review(oid):
    if not await pmes_applications.find_one({"_id": oid}, {"_id": 1}):
        raise api_error(404, "NOT_FOUND", "PMES application not found.")
    raise api_error(409, "ALREADY_REVIEWED",
                    "This PMES application has already been reviewed.")


def _submitted_filter(oid) -> dict:
    return {"_id": oid,
            "$or": [{"status": PMES_SUBMITTED}, {"status": {"$exists": False}}]}


@router.get("/pmes")
async def list_pmes(status: str = PMES_SUBMITTED,
                    admin: dict = Depends(require_role("admin"))):
    status = status.upper()
    if status not in PMES_STATUSES:
        raise api_error(400, "INVALID_STATUS",
                        f"Status must be one of {sorted(PMES_STATUSES)}.")
    query = ({"$or": [{"status": PMES_SUBMITTED}, {"status": {"$exists": False}}]}
             if status == PMES_SUBMITTED else {"status": status})
    apps = [a async for a in pmes_applications.find(query).sort("created_at", -1).limit(200)]
    user_ids = [a["user_id"] for a in apps if a.get("user_id")]
    user_map = {}
    if user_ids:
        async for u in users.find({"_id": {"$in": user_ids}},
                                  {"full_name": 1, "email": 1}):
            user_map[u["_id"]] = u
    return [pmes_summary(a, user_map.get(a.get("user_id"))) for a in apps]


@router.get("/pmes/{application_id}")
async def pmes_detail(application_id: str,
                      admin: dict = Depends(require_role("admin"))):
    oid = to_object_id(application_id)
    app = await pmes_applications.find_one({"_id": oid})
    if not app:
        raise api_error(404, "NOT_FOUND", "PMES application not found.")
    out = application_out(app)
    u = await users.find_one({"_id": app.get("user_id")}, {"password_hash": 0,
                                                           "face_embedding": 0})
    out["applicant"] = None if not u else {
        "id": str(u["_id"]),
        "full_name": u["full_name"],
        "email": u["email"],
        "phone": u.get("phone"),
        "status": u["status"],
        "role": u["role"],
        "membership_type": u.get("membership_type"),
        "id_photo_url": signed_url(u.get("id_photo_id")),
        "face_photo_url": signed_url(u.get("face_photo_id")),
    }
    return out


@router.post("/pmes/{application_id}/approve")
async def approve_pmes(application_id: str,
                       admin: dict = Depends(require_role("admin"))):
    oid = to_object_id(application_id)
    t = now()
    result = await pmes_applications.update_one(
        _submitted_filter(oid),
        {"$set": {"status": PMES_APPROVED, "reviewed_by": admin["_id"],
                  "reviewed_at": t, "rejection_reason": None, "updated_at": t}},
    )
    if result.matched_count == 0:
        await _fail_pmes_review(oid)
    app = await pmes_applications.find_one({"_id": oid})
    await log_audit(admin["_id"], "PMES_APPLICATION_APPROVED", oid,
                    {"reference_no": app.get("reference_no")})
    return {"message": "PMES application approved.",
            "application": application_out(app)}


@router.post("/pmes/{application_id}/reject")
async def reject_pmes(application_id: str, body: PmesRejectRequest,
                      admin: dict = Depends(require_role("admin"))):
    oid = to_object_id(application_id)
    t = now()
    result = await pmes_applications.update_one(
        _submitted_filter(oid),
        {"$set": {"status": PMES_REJECTED, "rejection_reason": body.reason.strip(),
                  "reviewed_by": admin["_id"], "reviewed_at": t,
                  "updated_at": t}},
    )
    if result.matched_count == 0:
        await _fail_pmes_review(oid)
    app = await pmes_applications.find_one({"_id": oid})
    await log_audit(admin["_id"], "PMES_APPLICATION_REJECTED", oid,
                    {"reference_no": app.get("reference_no"),
                     "reason": body.reason.strip()})
    return {"message": "PMES application rejected.",
            "application": application_out(app)}