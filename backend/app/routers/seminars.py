from datetime import date, datetime
from typing import Optional

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends
from pymongo import UpdateOne
from pymongo.errors import BulkWriteError

from ..auth import require_associate_member, require_role
from ..database import (pmes_applications, pmes_seminar_participants,
                        pmes_seminars, users)
from ..helpers import api_error, log_audit, now
from ..models import (PMES_REJECTED, RESPONSE_ATTEND, RESPONSE_DECLINE,
                      SEMINAR_CANCELLED, SEMINAR_SCHEDULED, SeminarCancelRequest,
                      SeminarCreateRequest, SeminarResponseRequest, Status)
from ..pmes_schedule import (PMES_VENUE, attendance_totals, date_label,
                             response_locked, schedule_problem, seminar_phase,
                             today_ph)
from ..pricing import to_ph_date

admin_router = APIRouter(prefix="/admin/seminars", tags=["admin-seminars"])
member_router = APIRouter(prefix="/member/seminars", tags=["member-seminars"])

ASSOCIATE_QUERY = {"status": Status.ACTIVE, "role": "member",
                   "membership_type": "ASSOCIATE"}


# =====================================================================
# Helpers
# =====================================================================

def seminar_oid(value: str) -> ObjectId:
    try:
        return ObjectId(value)
    except (InvalidId, TypeError):
        raise api_error(404, "SEMINAR_NOT_FOUND", "Seminar not found.")


def iso_date(value) -> Optional[str]:
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str) and len(value) >= 10:
        return value[:10]
    return None


def approval_date(user: dict) -> date:
    value = user.get("reviewed_at") or user.get("updated_at") or user.get("created_at")
    return to_ph_date(value) if isinstance(value, datetime) else date.min


def seminar_out(seminar: dict, counts: dict | None = None,
                can_respond: bool | None = None) -> dict:
    day = date.fromisoformat(seminar["date"])
    status = seminar.get("status", SEMINAR_SCHEDULED)
    out = {
        "id": str(seminar["_id"]),
        "date": seminar["date"],
        "label": date_label(day),
        "venue": seminar.get("venue", PMES_VENUE),
        "status": status,
        "phase": seminar_phase(day, status),
        "created_at": seminar.get("created_at"),
    }
    if counts:
        out.update(counts)
    if can_respond is not None:
        out["can_respond"] = can_respond
    return out


async def sync_seminar_participants(seminar: dict) -> None:
    """Snapshot eligible associates, adding new approvals until the seminar date."""
    if seminar.get("status") == SEMINAR_CANCELLED:
        return

    seminar_date = date.fromisoformat(seminar["date"])
    t = now()
    ops = []
    async for user in users.find(ASSOCIATE_QUERY,
                                 {"_id": 1, "reviewed_at": 1, "updated_at": 1,
                                  "created_at": 1}):
        if approval_date(user) > seminar_date:
            continue
        ops.append(UpdateOne(
            {"seminar_id": seminar["_id"], "user_id": user["_id"]},
            {"$setOnInsert": {
                "seminar_id": seminar["_id"],
                "user_id": user["_id"],
                "response": None,
                "invited_at": t,
                "responded_at": None,
                "created_at": t,
                "updated_at": t,
            }},
            upsert=True,
        ))
    if not ops:
        return
    try:
        await pmes_seminar_participants.bulk_write(ops, ordered=False)
    except BulkWriteError as exc:
        errors = exc.details.get("writeErrors", [])
        if any(err.get("code") != 11000 for err in errors):
            raise


async def participant_counts(seminar_ids: list[ObjectId]) -> dict:
    empty = {"attending": 0, "not_attending": 0, "no_response": 0, "total": 0}
    if not seminar_ids:
        return {}
    counts = {sid: dict(empty) for sid in seminar_ids}
    pipeline = [
        {"$match": {"seminar_id": {"$in": seminar_ids}}},
        {"$group": {"_id": {"seminar_id": "$seminar_id",
                            "response": "$response"},
                    "count": {"$sum": 1}}},
    ]
    async for row in pmes_seminar_participants.aggregate(pipeline):
        sid = row["_id"]["seminar_id"]
        bucket = counts.setdefault(sid, dict(empty))
        response = row["_id"].get("response")
        if response == RESPONSE_ATTEND:
            bucket["attending"] += row["count"]
        elif response == RESPONSE_DECLINE:
            bucket["not_attending"] += row["count"]
        else:
            bucket["no_response"] += row["count"]
        bucket["total"] += row["count"]
    return counts


async def current_seminar() -> Optional[dict]:
    return await pmes_seminars.find_one(
        {"status": SEMINAR_SCHEDULED, "date": {"$gte": today_ph().isoformat()}},
        sort=[("date", 1)])


# =====================================================================
# Admin endpoints
# =====================================================================

@admin_router.get("/preferences")
async def preferences(admin: dict = Depends(require_role("admin"))):
    apps = [a async for a in pmes_applications.find(
        {"status": {"$ne": PMES_REJECTED}})]
    user_ids = [a["user_id"] for a in apps if a.get("user_id")]
    user_map = {}
    if user_ids:
        async for user in users.find({"_id": {"$in": user_ids}},
                                     {"full_name": 1, "email": 1, "phone": 1}):
            user_map[user["_id"]] = user

    groups: dict[str, list[dict]] = {}
    for app in apps:
        day = iso_date(app.get("schedule_date"))
        if not day:
            continue
        groups.setdefault(day, []).append(app)

    today = today_ph()
    top = max((len(items) for items in groups.values()), default=0)
    dates = []
    for day, items in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        try:
            parsed = date.fromisoformat(day)
            label = date_label(parsed)
            is_past = parsed < today
        except ValueError:
            label = day
            is_past = True
        applicants = []
        for app in sorted(items, key=lambda a: (
                (user_map.get(a.get("user_id"), {}).get("full_name")
                 or a.get("email") or "").lower())):
            user = user_map.get(app.get("user_id"), {})
            applicants.append({
                "application_id": str(app["_id"]),
                "reference_no": app.get("reference_no"),
                "user_id": str(app["user_id"]) if app.get("user_id") else None,
                "full_name": user.get("full_name"),
                "email": user.get("email") or app.get("email"),
                "phone": user.get("phone"),
                "status": app.get("status"),
            })
        dates.append({
            "date": day,
            "label": label,
            "count": len(items),
            "is_past": is_past,
            "is_most_preferred": len(items) == top and top > 0,
            "applicants": applicants,
        })

    return {"total_applications": sum(len(v) for v in groups.values()),
            "dates": dates}


@admin_router.get("")
async def list_seminars(admin: dict = Depends(require_role("admin"))):
    seminars = [s async for s in pmes_seminars.find().sort("date", -1)]
    today = today_ph()
    for seminar in seminars:
        if (seminar.get("status") == SEMINAR_SCHEDULED
                and date.fromisoformat(seminar["date"]) >= today):
            await sync_seminar_participants(seminar)
    counts = await participant_counts([s["_id"] for s in seminars])
    return [seminar_out(s, counts.get(s["_id"])) for s in seminars]


@admin_router.post("", status_code=201)
async def schedule_seminar(body: SeminarCreateRequest,
                           admin: dict = Depends(require_role("admin"))):
    problem = schedule_problem(body.date)
    if problem:
        raise api_error(422, "INVALID_SEMINAR_DATE", problem)

    existing = await current_seminar()
    if existing:
        raise api_error(
            409, "SEMINAR_ALREADY_SCHEDULED",
            f"A PMES seminar is already scheduled for {existing['date']}. "
            "Cancel it before scheduling another.",
            seminar_id=str(existing["_id"]), date=existing["date"])

    t = now()
    doc = {
        "date": body.date.isoformat(),
        "venue": (body.venue or "").strip() or PMES_VENUE,
        "status": SEMINAR_SCHEDULED,
        "created_by": admin["_id"],
        "created_at": t,
        "updated_at": t,
    }
    result = await pmes_seminars.insert_one(doc)
    doc["_id"] = result.inserted_id
    await sync_seminar_participants(doc)
    counts = await participant_counts([doc["_id"]])
    await log_audit(admin["_id"], "PMES_SEMINAR_SCHEDULED", doc["_id"],
                    {"date": doc["date"],
                     "invited": counts.get(doc["_id"], {}).get("total", 0)})
    return seminar_out(doc, counts.get(doc["_id"]))


@admin_router.post("/{seminar_id}/cancel")
async def cancel_seminar(seminar_id: str,
                         body: SeminarCancelRequest | None = None,
                         admin: dict = Depends(require_role("admin"))):
    oid = seminar_oid(seminar_id)
    seminar = await pmes_seminars.find_one({"_id": oid})
    if not seminar:
        raise api_error(404, "SEMINAR_NOT_FOUND", "Seminar not found.")
    if seminar.get("status") != SEMINAR_SCHEDULED:
        raise api_error(409, "SEMINAR_NOT_SCHEDULED",
                        "Only scheduled seminars can be cancelled.")

    t = now()
    reason = ((body.reason if body else None) or "").strip() or None
    result = await pmes_seminars.update_one(
        {"_id": oid, "status": SEMINAR_SCHEDULED},
        {"$set": {"status": SEMINAR_CANCELLED, "cancelled_by": admin["_id"],
                  "cancelled_at": t, "cancel_reason": reason,
                  "updated_at": t}},
    )
    if result.matched_count == 0:
        raise api_error(409, "SEMINAR_NOT_SCHEDULED",
                        "Only scheduled seminars can be cancelled.")

    seminar = await pmes_seminars.find_one({"_id": oid})
    counts = await participant_counts([oid])
    await log_audit(admin["_id"], "PMES_SEMINAR_CANCELLED", oid,
                    {"date": seminar["date"], "reason": reason})
    return seminar_out(seminar, counts.get(oid))


@admin_router.get("/{seminar_id}/attendance")
async def seminar_attendance(seminar_id: str,
                             admin: dict = Depends(require_role("admin"))):
    oid = seminar_oid(seminar_id)
    seminar = await pmes_seminars.find_one({"_id": oid})
    if not seminar:
        raise api_error(404, "SEMINAR_NOT_FOUND", "Seminar not found.")

    await sync_seminar_participants(seminar)
    participants = [p async for p in pmes_seminar_participants.find(
        {"seminar_id": oid})]
    user_ids = [p["user_id"] for p in participants]
    user_map = {}
    if user_ids:
        async for user in users.find({"_id": {"$in": user_ids}},
                                     {"full_name": 1, "email": 1, "phone": 1}):
            user_map[user["_id"]] = user

    groups = {"attending": [], "not_attending": [], "no_response": []}
    for participant in participants:
        user = user_map.get(participant["user_id"], {})
        item = {
            "user_id": str(participant["user_id"]),
            "full_name": user.get("full_name"),
            "email": user.get("email"),
            "phone": user.get("phone"),
            "responded_at": participant.get("responded_at"),
        }
        response = participant.get("response")
        if response == RESPONSE_ATTEND:
            groups["attending"].append(item)
        elif response == RESPONSE_DECLINE:
            groups["not_attending"].append(item)
        else:
            groups["no_response"].append(item)

    for items in groups.values():
        items.sort(key=lambda item: (item.get("full_name") or "").lower())

    return {
        "seminar": seminar_out(seminar),
        "totals": attendance_totals([p.get("response") for p in participants]),
        **groups,
    }


# =====================================================================
# Member endpoints
# =====================================================================

@member_router.get("/current")
async def my_seminar(user: dict = Depends(require_associate_member())):
    seminar = await current_seminar()
    if not seminar:
        return {"seminar": None, "response": None, "responded_at": None,
                "can_respond": False}

    await sync_seminar_participants(seminar)
    participant = await pmes_seminar_participants.find_one(
        {"seminar_id": seminar["_id"], "user_id": user["_id"]})
    if not participant:
        return {"seminar": None, "response": None, "responded_at": None,
                "can_respond": False}

    locked = response_locked(date.fromisoformat(seminar["date"]))
    return {
        "seminar": seminar_out(seminar, can_respond=not locked),
        "response": participant.get("response"),
        "responded_at": participant.get("responded_at"),
        "can_respond": not locked,
    }


@member_router.put("/{seminar_id}/response")
async def respond_to_seminar(seminar_id: str, body: SeminarResponseRequest,
                             user: dict = Depends(require_associate_member())):
    oid = seminar_oid(seminar_id)
    seminar = await pmes_seminars.find_one({"_id": oid})
    if not seminar:
        raise api_error(404, "SEMINAR_NOT_FOUND", "Seminar not found.")
    if seminar.get("status") != SEMINAR_SCHEDULED:
        raise api_error(409, "SEMINAR_NOT_OPEN",
                        "This seminar is no longer accepting responses.")
    if response_locked(date.fromisoformat(seminar["date"])):
        raise api_error(409, "SEMINAR_LOCKED",
                        "This seminar date has passed. Responses are locked.")

    t = now()
    await pmes_seminar_participants.update_one(
        {"seminar_id": oid, "user_id": user["_id"]},
        {"$set": {"response": body.response, "responded_at": t,
                  "updated_at": t},
         "$setOnInsert": {"seminar_id": oid, "user_id": user["_id"],
                          "invited_at": t, "created_at": t}},
        upsert=True,
    )
    await log_audit(user["_id"], "PMES_SEMINAR_RESPONSE", oid,
                    {"date": seminar["date"], "response": body.response})
    return {
        "seminar": seminar_out(seminar, can_respond=True),
        "response": body.response,
        "responded_at": t,
        "can_respond": True,
    }
