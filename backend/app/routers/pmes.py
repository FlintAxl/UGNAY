from datetime import date, datetime
from typing import Literal, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from pymongo import ReturnDocument

from ..auth import get_pmes_user
from ..database import counters, pmes_applications
from ..helpers import api_error, log_audit, now
from ..models import (PMES_APPROVED, PMES_REJECTED, PMES_SUBMITTED)
from ..pmes_schedule import (PMES_VENUE, next_saturdays, schedule_problem,
                             today_ph)
from ..pricing import PH_TZ

router = APIRouter(prefix="/pmes", tags=["pmes"])

MembershipCategory = Literal["ARB", "ARB_HH", "NON_ARB"]
CivilStatus = Literal["SINGLE", "MARRIED", "WIDOW", "SEPARATED"]
Sex = Literal["MALE", "FEMALE"]


# =====================================================================
# Request models
# =====================================================================

class BeneficiaryIn(BaseModel):
    name: Optional[str] = Field(default=None, max_length=120)
    relationship: Optional[str] = Field(default=None, max_length=80)
    birth_date: Optional[date] = None


class EducationEntryIn(BaseModel):
    school: Optional[str] = Field(default=None, max_length=160)
    year_graduated: Optional[str] = Field(default=None, max_length=20)


class EducationIn(BaseModel):
    college: EducationEntryIn = Field(default_factory=EducationEntryIn)
    vocational: EducationEntryIn = Field(default_factory=EducationEntryIn)
    secondary: EducationEntryIn = Field(default_factory=EducationEntryIn)
    elementary: EducationEntryIn = Field(default_factory=EducationEntryIn)


class IdsIn(BaseModel):
    tin: Optional[str] = Field(default=None, max_length=40)
    pagibig: Optional[str] = Field(default=None, max_length=40)
    sss: Optional[str] = Field(default=None, max_length=40)
    philhealth: Optional[str] = Field(default=None, max_length=40)
    senior_id: Optional[str] = Field(default=None, max_length=40)
    national_id: Optional[str] = Field(default=None, max_length=40)
    other: Optional[str] = Field(default=None, max_length=80)


class PmesApplicationIn(BaseModel):
    membership_category: MembershipCategory

    # Core personal information
    last_name: str = Field(min_length=1, max_length=80)
    first_name: str = Field(min_length=1, max_length=80)
    middle_name: Optional[str] = Field(default=None, max_length=80)
    address: str = Field(min_length=5, max_length=300)
    birth_date: date
    birth_place: str = Field(min_length=2, max_length=160)
    civil_status: CivilStatus
    sex: Sex
    nationality: str = Field(min_length=2, max_length=60)
    phone: str = Field(min_length=7, max_length=30)

    # Optional personal details
    religion: Optional[str] = Field(default=None, max_length=80)
    weight: Optional[str] = Field(default=None, max_length=20)
    height: Optional[str] = Field(default=None, max_length=20)
    occupation: Optional[str] = Field(default=None, max_length=160)

    # Optional family details
    mother_name: Optional[str] = Field(default=None, max_length=120)
    mother_occupation: Optional[str] = Field(default=None, max_length=120)
    father_name: Optional[str] = Field(default=None, max_length=120)
    father_occupation: Optional[str] = Field(default=None, max_length=120)
    spouse_name: Optional[str] = Field(default=None, max_length=120)
    spouse_occupation: Optional[str] = Field(default=None, max_length=120)

    beneficiaries: list[BeneficiaryIn] = Field(default_factory=list, max_length=3)
    education: EducationIn = Field(default_factory=EducationIn)
    ids: IdsIn = Field(default_factory=IdsIn)

    # PMES schedule
    schedule_date: date
    signature_name: str = Field(min_length=2, max_length=120)


# =====================================================================
# Helpers
# =====================================================================

async def next_pmes_no() -> str:
    year = datetime.now(PH_TZ).year
    c = await counters.find_one_and_update(
        {"_id": f"pmes-{year}"}, {"$inc": {"seq": 1}},
        upsert=True, return_document=ReturnDocument.AFTER)
    return f"PMES-{year}-{c['seq']:04d}"


def application_out(app: dict) -> dict:
    out = {k: v for k, v in app.items() if k not in ("_id", "user_id")}
    out["id"] = str(app["_id"])
    out["status"] = app.get("status", PMES_SUBMITTED)
    out["reviewed_by"] = str(app["reviewed_by"]) if app.get("reviewed_by") else None
    return out


def clean(text: Optional[str]) -> Optional[str]:
    return (text or "").strip() or None


def tidy(data: dict) -> dict:
    """Trim the optional free-text fields so blank inputs become null."""
    for key in ("middle_name", "religion", "weight", "height", "occupation",
                "mother_name", "mother_occupation", "father_name", "father_occupation",
                "spouse_name", "spouse_occupation"):
        data[key] = clean(data.get(key))
    for b in data.get("beneficiaries", []):
        b["name"] = clean(b.get("name"))
        b["relationship"] = clean(b.get("relationship"))
    for entry in data.get("education", {}).values():
        entry["school"] = clean(entry.get("school"))
        entry["year_graduated"] = clean(entry.get("year_graduated"))
    for key in ("tin", "pagibig", "sss", "philhealth", "senior_id", "national_id", "other"):
        data["ids"][key] = clean(data["ids"].get(key))
    data["signature_name"] = clean(data.get("signature_name"))
    return data


# =====================================================================
# Endpoints
# =====================================================================

@router.get("/schedule-options")
async def schedule_options(count: int = 12, user: dict = Depends(get_pmes_user)):
    count = max(1, min(count, 52))
    return [{
        "date": d.isoformat(),
        "label": d.strftime("%A, %B %d, %Y"),
        "venue": PMES_VENUE,
    } for d in next_saturdays(today_ph(), count)]


@router.get("/application")
async def get_application(user: dict = Depends(get_pmes_user)):
    app = await pmes_applications.find_one({"user_id": user["_id"]})
    return {"application": application_out(app) if app else None}


@router.put("/application")
async def save_application(body: PmesApplicationIn, user: dict = Depends(get_pmes_user)):
    problem = schedule_problem(body.schedule_date)
    if problem:
        raise api_error(422, "INVALID_SCHEDULE", problem)

    data = tidy(body.model_dump(mode="json"))
    data["venue"] = PMES_VENUE
    t = now()
    existing = await pmes_applications.find_one({"user_id": user["_id"]})

    if existing:
        current = existing.get("status", PMES_SUBMITTED)
        if current == PMES_APPROVED:
            raise api_error(409, "APPLICATION_LOCKED",
                            "Your PMES application has already been approved and can no longer be changed.")
        if existing["schedule_date"] < today_ph().isoformat():
            raise api_error(409, "SCHEDULE_PASSED",
                            "Your PMES schedule has passed, so the application can no longer be changed.")
        changes = {**data, "updated_at": t}
        if current == PMES_REJECTED:
            changes.update({
                "status": PMES_SUBMITTED,
                "reviewed_by": None,
                "reviewed_at": None,
                "rejection_reason": None,
            })
            action = "PMES_APPLICATION_RESUBMITTED"
            match = {"_id": existing["_id"], "status": PMES_REJECTED}
        else:
            action = "PMES_APPLICATION_UPDATED"
            match = {"_id": existing["_id"],
                     "$or": [{"status": PMES_SUBMITTED},
                             {"status": {"$exists": False}}]}
        result = await pmes_applications.update_one(match, {"$set": changes})
        if result.matched_count == 0:
            raise api_error(409, "APPLICATION_LOCKED",
                            "The application status changed. Please reload and try again.")
    else:
        doc = {
            "user_id": user["_id"],
            "email": user["email"],
            "reference_no": await next_pmes_no(),
            **data,
            "status": PMES_SUBMITTED,
            "reviewed_by": None,
            "reviewed_at": None,
            "rejection_reason": None,
            "signed_at": t,
            "created_at": t,
            "updated_at": t,
        }
        await pmes_applications.insert_one(doc)
        action = "PMES_APPLICATION_CREATED"

    app = await pmes_applications.find_one({"user_id": user["_id"]})
    await log_audit(user["_id"], action, app["_id"],
                    {"reference_no": app["reference_no"],
                     "schedule_date": app["schedule_date"]})
    return {"application": application_out(app)}
