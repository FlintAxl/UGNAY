import re
from datetime import date, datetime
from decimal import Decimal
from typing import Literal, Optional

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, File, UploadFile
from pydantic import BaseModel, Field
from pymongo import ReturnDocument
from pymongo.errors import DuplicateKeyError

from ..auth import require_role
from ..database import bidding_rounds, counters, suppliers
from ..ginger_math import entry_total, weight_problem
from ..helpers import api_error, log_audit, now, read_image, signed_url, upload_image
from ..pricing import PH_TZ, d128, dec, money

router = APIRouter(prefix="/production", tags=["production"])

production_only = require_role("production")
can_view = require_role("production", "admin")

MAX_PHOTOS_PER_ENTRY = 6
ZERO = Decimal("0")
GingerKind = Literal["NATIVE", "HALF_NATIVE"]


# =====================================================================
# Request models
# =====================================================================

class SupplierCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    phone: Optional[str] = Field(default=None, max_length=30)
    address: Optional[str] = Field(default=None, max_length=200)
    notes: Optional[str] = Field(default=None, max_length=300)


class SupplierUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=2, max_length=120)
    phone: Optional[str] = Field(default=None, max_length=30)
    address: Optional[str] = Field(default=None, max_length=200)
    notes: Optional[str] = Field(default=None, max_length=300)
    is_active: Optional[bool] = None


class RoundCreate(BaseModel):
    title: Optional[str] = Field(default=None, max_length=120)
    notes: Optional[str] = Field(default=None, max_length=500)
    bidding_date: Optional[date] = None      # defaults to today (Philippine time)


class BidCreate(BaseModel):
    supplier_id: str
    ginger_kind: GingerKind
    weigh_in_kg: Decimal = Field(gt=0, decimal_places=2)
    good_kg: Decimal = Field(ge=0, decimal_places=2)
    bad_kg: Decimal = Field(ge=0, decimal_places=2)
    price_per_kg_good: Decimal = Field(gt=0, decimal_places=2)   # the only price: bad kilos are not bought
    remarks: Optional[str] = Field(default=None, max_length=300)


class BidUpdate(BaseModel):
    """Weights are locked after weigh-in. Only the price and remarks can change."""
    price_per_kg_good: Optional[Decimal] = Field(default=None, gt=0, decimal_places=2)
    remarks: Optional[str] = Field(default=None, max_length=300)


class AwardRequest(BaseModel):
    accepted_bid_ids: list[str] = Field(min_length=1)
    remarks: Optional[str] = Field(default=None, max_length=500)   # why these were chosen


# =====================================================================
# Helpers
# =====================================================================

def oid(value: str, what: str) -> ObjectId:
    try:
        return ObjectId(value)
    except (InvalidId, TypeError):
        raise api_error(404, "NOT_FOUND", f"{what} not found.")


def kg_str(x) -> str:
    return str(dec(x).quantize(Decimal("0.01")))


def money_str(x) -> str:
    return str(money(dec(x)))


def clean(text: Optional[str]) -> Optional[str]:
    return (text or "").strip() or None


async def next_round_no() -> str:
    year = datetime.now(PH_TZ).year
    c = await counters.find_one_and_update(
        {"_id": f"bidding-{year}"}, {"$inc": {"seq": 1}},
        upsert=True, return_document=ReturnDocument.AFTER)
    return f"B-{year}-{c['seq']:04d}"


async def get_round_or_404(round_id: str) -> dict:
    r = await bidding_rounds.find_one({"_id": oid(round_id, "Round")})
    if not r:
        raise api_error(404, "NOT_FOUND", "Bidding round not found.")
    return r


def require_open(r: dict):
    if r["status"] != "OPEN":
        raise api_error(409, "ROUND_NOT_OPEN", f"This round is {r['status'].lower()}, so it can no longer be changed.")


def find_bid(r: dict, bid_id: str) -> tuple[int, dict]:
    target = oid(bid_id, "Entry")
    for i, b in enumerate(r["bids"]):
        if b["bid_id"] == target:
            return i, b
    raise api_error(404, "NOT_FOUND", "Entry not found in this round.")


async def commit(r: dict, fields: dict) -> dict:
    """Saves changes only if nobody else changed the round since we read it
    (the embedded entries make a version check safer than field-level updates)."""
    fields = {**fields, "version": r["version"] + 1, "updated_at": now()}
    res = await bidding_rounds.update_one(
        {"_id": r["_id"], "version": r["version"]}, {"$set": fields})
    if res.matched_count == 0:
        raise api_error(409, "ROUND_CHANGED", "This round was changed by someone else. Please reload and try again.")
    return await bidding_rounds.find_one({"_id": r["_id"]})


# =====================================================================
# Serialization
# =====================================================================

def supplier_out(s: dict) -> dict:
    return {"id": str(s["_id"]), "name": s["name"], "phone": s.get("phone"),
            "address": s.get("address"), "notes": s.get("notes"), "is_active": s["is_active"]}


def bid_out(b: dict) -> dict:
    return {
        "bid_id": str(b["bid_id"]), "supplier_id": str(b["supplier_id"]),
        "supplier_name": b["supplier_name"], "ginger_kind": b["ginger_kind"],
        "weigh_in_kg": kg_str(b["weigh_in_kg"]), "good_kg": kg_str(b["good_kg"]),
        "bad_kg": kg_str(b["bad_kg"]),
        "price_per_kg_good": money_str(b["price_per_kg_good"]),
        "total_price": money_str(b["total_price"]),   # good kilos x good price
        "status": b["status"], "remarks": b.get("remarks"),
        "photos": [{"photo_id": p["photo_id"], "url": signed_url(p["public_id"])} for p in b["photos"]],
        "recorded_by_name": b.get("recorded_by_name"), "created_at": b["created_at"],
    }


def accepted_totals(r: dict) -> dict:
    acc = [b for b in r["bids"] if b["status"] == "ACCEPTED"]
    return {
        "accepted_count": len(acc),
        "accepted_weigh_in_kg": kg_str(sum((dec(b["weigh_in_kg"]) for b in acc), ZERO)),
        "accepted_good_kg": kg_str(sum((dec(b["good_kg"]) for b in acc), ZERO)),
        "accepted_bad_kg": kg_str(sum((dec(b["bad_kg"]) for b in acc), ZERO)),
        "accepted_total_price": money_str(sum((dec(b["total_price"]) for b in acc), ZERO)),
    }


def round_summary(r: dict) -> dict:
    t = accepted_totals(r)
    return {
        "id": str(r["_id"]), "round_no": r["round_no"], "title": r.get("title"),
        "status": r["status"], "bidding_date": r["bidding_date"],
        "entry_count": sum(1 for b in r["bids"] if b["status"] != "WITHDRAWN"),
        "accepted_count": t["accepted_count"], "accepted_total_price": t["accepted_total_price"],
        "created_at": r["created_at"], "awarded_at": r.get("awarded_at"),
    }


def round_detail(r: dict) -> dict:
    out = round_summary(r)
    out.update(accepted_totals(r))
    out.update({
        "notes": r.get("notes"), "award_remarks": r.get("award_remarks"),
        "awarded_by_name": r.get("awarded_by_name"), "created_by_name": r.get("created_by_name"),
        "bids": [bid_out(b) for b in r["bids"]],
    })
    return out


# =====================================================================
# Suppliers
# =====================================================================

@router.get("/suppliers")
async def list_suppliers(active_only: bool = True, q: Optional[str] = None,
                         user: dict = Depends(can_view)):
    filt: dict = {}
    if active_only:
        filt["is_active"] = True
    if q and q.strip():
        filt["name"] = {"$regex": re.escape(q.strip()), "$options": "i"}
    return [supplier_out(s) async for s in suppliers.find(filt).sort("name", 1).limit(500)]


@router.post("/suppliers", status_code=201)
async def create_supplier(body: SupplierCreate, user: dict = Depends(production_only)):
    t = now()
    doc = {"name": body.name.strip(), "name_key": body.name.strip().lower(),
           "phone": clean(body.phone), "address": clean(body.address), "notes": clean(body.notes),
           "is_active": True, "created_at": t, "updated_at": t}
    try:
        await suppliers.insert_one(doc)
    except DuplicateKeyError:
        raise api_error(409, "SUPPLIER_EXISTS", "A supplier with this name already exists.")
    await log_audit(user["_id"], "SUPPLIER_CREATED", doc["_id"], {"name": doc["name"]})
    return supplier_out(doc)


@router.patch("/suppliers/{supplier_id}")
async def update_supplier(supplier_id: str, body: SupplierUpdate,
                          user: dict = Depends(production_only)):
    changes: dict = {}
    if body.name is not None:
        changes["name"] = body.name.strip()
        changes["name_key"] = body.name.strip().lower()
    for field in ("phone", "address", "notes"):
        if getattr(body, field) is not None:
            changes[field] = clean(getattr(body, field))
    if body.is_active is not None:
        changes["is_active"] = body.is_active
    if not changes:
        raise api_error(400, "NO_CHANGES", "Nothing to update.")
    changes["updated_at"] = now()
    try:
        s = await suppliers.find_one_and_update(
            {"_id": oid(supplier_id, "Supplier")}, {"$set": changes},
            return_document=ReturnDocument.AFTER)
    except DuplicateKeyError:
        raise api_error(409, "SUPPLIER_EXISTS", "A supplier with this name already exists.")
    if not s:
        raise api_error(404, "NOT_FOUND", "Supplier not found.")
    await log_audit(user["_id"], "SUPPLIER_UPDATED", s["_id"],
                    {k: str(v) for k, v in changes.items() if k not in ("updated_at", "name_key")})
    return supplier_out(s)


# =====================================================================
# Bidding rounds
# =====================================================================

@router.post("/rounds", status_code=201)
async def create_round(body: RoundCreate, user: dict = Depends(production_only)):
    t = now()
    doc = {
        "round_no": await next_round_no(), "title": clean(body.title), "notes": clean(body.notes),
        "bidding_date": (body.bidding_date or datetime.now(PH_TZ).date()).isoformat(),
        "status": "OPEN", "bids": [], "version": 1,
        "created_by": user["_id"], "created_by_name": user["full_name"],
        "created_at": t, "updated_at": t,
    }
    await bidding_rounds.insert_one(doc)
    await log_audit(user["_id"], "ROUND_CREATED", doc["_id"], {"round_no": doc["round_no"]})
    return round_detail(doc)


@router.get("/rounds")
async def list_rounds(status: str = "OPEN", q: Optional[str] = None,
                      user: dict = Depends(can_view)):
    """status: OPEN, AWARDED, CANCELLED, ALL."""
    status = status.upper()
    if status in ("OPEN", "AWARDED", "CANCELLED"):
        filt: dict = {"status": status}
    elif status == "ALL":
        filt = {}
    else:
        raise api_error(400, "INVALID_STATUS", "Unknown status filter.")
    if q and q.strip():
        rx = {"$regex": re.escape(q.strip()), "$options": "i"}
        filt["$or"] = [{"round_no": rx}, {"title": rx}, {"bids.supplier_name": rx}]
    cursor = bidding_rounds.find(filt).sort("created_at", -1).limit(200)
    return [round_summary(r) async for r in cursor]


@router.get("/rounds/{round_id}")
async def round_by_id(round_id: str, user: dict = Depends(can_view)):
    return round_detail(await get_round_or_404(round_id))


@router.post("/rounds/{round_id}/cancel")
async def cancel_round(round_id: str, user: dict = Depends(production_only)):
    r = await get_round_or_404(round_id)
    require_open(r)
    await commit(r, {"status": "CANCELLED", "cancelled_at": now(), "cancelled_by": user["_id"]})
    await log_audit(user["_id"], "ROUND_CANCELLED", r["_id"], {"round_no": r["round_no"]})
    return {"message": "Bidding round cancelled."}


@router.post("/rounds/{round_id}/award")
async def award_round(round_id: str, body: AwardRequest, user: dict = Depends(production_only)):
    """The production manager picks the winning entries by quality and price.
    Picked entries become ACCEPTED, all other active entries REJECTED, and the round is closed."""
    r = await get_round_or_404(round_id)
    require_open(r)

    picked = {str(oid(i, "Entry")) for i in body.accepted_bid_ids}
    by_id = {str(b["bid_id"]): b for b in r["bids"]}
    for key in picked:
        b = by_id.get(key)
        if not b:
            raise api_error(422, "UNKNOWN_ENTRY", "A selected entry is not part of this round.")
        if b["status"] != "SUBMITTED":
            raise api_error(422, "ENTRY_NOT_ACTIVE", f"{b['supplier_name']}'s entry was withdrawn.")
        if not b["photos"]:
            raise api_error(409, "PHOTO_REQUIRED",
                            f"Add at least one photo to {b['supplier_name']}'s entry before accepting it.")

    t = now()
    new_bids = []
    for b in r["bids"]:
        if str(b["bid_id"]) in picked:
            b = {**b, "status": "ACCEPTED", "updated_at": t}
        elif b["status"] == "SUBMITTED":
            b = {**b, "status": "REJECTED", "updated_at": t}
        new_bids.append(b)

    updated = await commit(r, {
        "status": "AWARDED", "bids": new_bids, "awarded_at": t, "awarded_by": user["_id"],
        "awarded_by_name": user["full_name"], "award_remarks": clean(body.remarks)})
    totals = accepted_totals(updated)
    await log_audit(user["_id"], "ROUND_AWARDED", r["_id"],
                    {"round_no": r["round_no"], "accepted": sorted(picked),
                     "accepted_total_price": totals["accepted_total_price"]})
    return round_detail(updated)


# =====================================================================
# Entries (one per bidder)
# =====================================================================

@router.post("/rounds/{round_id}/bids", status_code=201)
async def add_bid(round_id: str, body: BidCreate, user: dict = Depends(production_only)):
    r = await get_round_or_404(round_id)
    require_open(r)

    supplier = await suppliers.find_one({"_id": oid(body.supplier_id, "Supplier")})
    if not supplier or not supplier["is_active"]:
        raise api_error(404, "SUPPLIER_NOT_FOUND", "Supplier not found or inactive.")

    problem = weight_problem(body.weigh_in_kg, body.good_kg, body.bad_kg)
    if problem:
        raise api_error(422, "INVALID_WEIGHTS", problem)

    if any(b["supplier_id"] == supplier["_id"] and b["ginger_kind"] == body.ginger_kind
           and b["status"] != "WITHDRAWN" for b in r["bids"]):
        raise api_error(409, "DUPLICATE_ENTRY",
                        f"{supplier['name']} already has an active {body.ginger_kind.replace('_', ' ').title()} "
                        "entry in this round. Withdraw it first to re-enter.")

    total = entry_total(body.good_kg, body.price_per_kg_good)
    t = now()
    bid = {
        "bid_id": ObjectId(), "supplier_id": supplier["_id"], "supplier_name": supplier["name"],
        "ginger_kind": body.ginger_kind,
        "weigh_in_kg": d128(body.weigh_in_kg), "good_kg": d128(body.good_kg), "bad_kg": d128(body.bad_kg),
        "price_per_kg_good": d128(money(body.price_per_kg_good)),
        "total_price": d128(total),
        "status": "SUBMITTED", "remarks": clean(body.remarks), "photos": [],
        "recorded_by": user["_id"], "recorded_by_name": user["full_name"],
        "created_at": t, "updated_at": t,
    }
    updated = await commit(r, {"bids": r["bids"] + [bid]})
    await log_audit(user["_id"], "BID_ADDED", r["_id"],
                    {"round_no": r["round_no"], "supplier": supplier["name"],
                     "kind": body.ginger_kind, "total_price": str(total)})
    return round_detail(updated)


@router.patch("/rounds/{round_id}/bids/{bid_id}")
async def update_bid(round_id: str, bid_id: str, body: BidUpdate,
                     user: dict = Depends(production_only)):
    """Correct the price or remarks until the round is awarded. Weights stay locked."""
    r = await get_round_or_404(round_id)
    require_open(r)
    idx, b = find_bid(r, bid_id)
    if b["status"] != "SUBMITTED":
        raise api_error(409, "ENTRY_NOT_ACTIVE", "Only an active entry can be changed.")
    if body.price_per_kg_good is None and body.remarks is None:
        raise api_error(400, "NO_CHANGES", "Nothing to update.")

    price_good = (money(body.price_per_kg_good) if body.price_per_kg_good is not None
                  else dec(b["price_per_kg_good"]))
    total = entry_total(b["good_kg"], price_good)
    old_total = money_str(b["total_price"])

    new_b = {**b, "price_per_kg_good": d128(price_good), "total_price": d128(total),
             "updated_at": now()}
    if body.remarks is not None:
        new_b["remarks"] = clean(body.remarks)
    bids = list(r["bids"])
    bids[idx] = new_b
    updated = await commit(r, {"bids": bids})
    await log_audit(user["_id"], "BID_PRICE_UPDATED", r["_id"],
                    {"round_no": r["round_no"], "supplier": b["supplier_name"],
                     "old_total": old_total, "new_total": str(total)})
    return round_detail(updated)


@router.post("/rounds/{round_id}/bids/{bid_id}/withdraw")
async def withdraw_bid(round_id: str, bid_id: str, user: dict = Depends(production_only)):
    r = await get_round_or_404(round_id)
    require_open(r)
    idx, b = find_bid(r, bid_id)
    if b["status"] != "SUBMITTED":
        raise api_error(409, "ENTRY_NOT_ACTIVE", "Only an active entry can be withdrawn.")
    bids = list(r["bids"])
    bids[idx] = {**b, "status": "WITHDRAWN", "updated_at": now()}
    updated = await commit(r, {"bids": bids})
    await log_audit(user["_id"], "BID_WITHDRAWN", r["_id"],
                    {"round_no": r["round_no"], "supplier": b["supplier_name"]})
    return round_detail(updated)


@router.post("/rounds/{round_id}/bids/{bid_id}/photos")
async def add_photos(round_id: str, bid_id: str, files: list[UploadFile] = File(...),
                     user: dict = Depends(production_only)):
    r = await get_round_or_404(round_id)
    require_open(r)
    idx, b = find_bid(r, bid_id)
    if b["status"] != "SUBMITTED":
        raise api_error(409, "ENTRY_NOT_ACTIVE", "Photos can only be added to an active entry.")
    if len(b["photos"]) + len(files) > MAX_PHOTOS_PER_ENTRY:
        raise api_error(422, "TOO_MANY_PHOTOS",
                        f"An entry can have up to {MAX_PHOTOS_PER_ENTRY} photos "
                        f"({len(b['photos'])} already saved).")

    uploaded = []
    for f in files:
        data = await read_image(f)
        public_id = await upload_image(data, "ginger")
        uploaded.append({"photo_id": str(ObjectId()), "public_id": public_id, "uploaded_at": now()})

    bids = list(r["bids"])
    bids[idx] = {**b, "photos": b["photos"] + uploaded, "updated_at": now()}
    updated = await commit(r, {"bids": bids})
    await log_audit(user["_id"], "BID_PHOTOS_ADDED", r["_id"],
                    {"round_no": r["round_no"], "supplier": b["supplier_name"], "count": len(uploaded)})
    return round_detail(updated)


@router.delete("/rounds/{round_id}/bids/{bid_id}/photos/{photo_id}")
async def delete_photo(round_id: str, bid_id: str, photo_id: str,
                       user: dict = Depends(production_only)):
    r = await get_round_or_404(round_id)
    require_open(r)
    idx, b = find_bid(r, bid_id)
    if b["status"] != "SUBMITTED":
        raise api_error(409, "ENTRY_NOT_ACTIVE", "Photos can only be removed from an active entry.")
    remaining = [p for p in b["photos"] if p["photo_id"] != photo_id]
    if len(remaining) == len(b["photos"]):
        raise api_error(404, "NOT_FOUND", "Photo not found.")
    bids = list(r["bids"])
    bids[idx] = {**b, "photos": remaining, "updated_at": now()}
    updated = await commit(r, {"bids": bids})
    await log_audit(user["_id"], "BID_PHOTO_REMOVED", r["_id"],
                    {"round_no": r["round_no"], "supplier": b["supplier_name"]})
    return round_detail(updated)


# =====================================================================
# Summary
# =====================================================================

@router.get("/summary")
async def summary(user: dict = Depends(can_view)):
    return {
        "open_rounds": await bidding_rounds.count_documents({"status": "OPEN"}),
        "awarded_rounds": await bidding_rounds.count_documents({"status": "AWARDED"}),
        "active_suppliers": await suppliers.count_documents({"is_active": True}),
    }