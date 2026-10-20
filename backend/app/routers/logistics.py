import hashlib
import json
import re
from datetime import datetime, timezone
from decimal import Decimal
from typing import Literal, Optional

from bson import ObjectId
from bson.decimal128 import Decimal128
from bson.errors import InvalidId
from fastapi import APIRouter, Depends, File, Form, UploadFile
from pydantic import BaseModel, Field
from pymongo import ReturnDocument
from pymongo.errors import DuplicateKeyError

from ..auth import require_role
from ..database import client, counters, rental_items, rentals
from ..helpers import api_error, log_audit, now, read_image, signed_url, upload_image
from ..pricing import (PH_TZ, compute_due_at, d128, days_late, dec, is_weekend, line_amount,
                       min_down_payment, money, penalty_amount)
from ..terms import TERMS, TERMS_VERSION

router = APIRouter(prefix="/logistics", tags=["logistics"])

logistics_only = require_role("logistics")
can_view = require_role("logistics", "admin")

ZERO = Decimal("0")


# =====================================================================
# Request models
# =====================================================================

class ItemCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    category: Literal["EQUIPMENT", "COVER_AND_TELA"]
    unit: Literal["pc", "yard"]
    price: Decimal = Field(ge=0, decimal_places=2)
    total_quantity: Decimal = Field(default=ZERO, ge=0, decimal_places=2)


class ItemUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=2, max_length=80)
    price: Optional[Decimal] = Field(default=None, ge=0, decimal_places=2)
    is_active: Optional[bool] = None


class StockUpdate(BaseModel):
    total_quantity: Decimal = Field(ge=0, decimal_places=2)


class RentalLineIn(BaseModel):
    item_id: str
    quantity: Decimal = Field(gt=0, decimal_places=2)


class RentalCreate(BaseModel):
    borrower_name: str = Field(min_length=2, max_length=120)
    borrower_phone: Optional[str] = Field(default=None, max_length=30)
    member_name: Optional[str] = Field(default=None, max_length=120)   # optional: not all renters are members
    referred_by: Optional[str] = Field(default=None, max_length=120)
    venue: str = Field(min_length=2, max_length=200)
    pickup_at: datetime
    items: list[RentalLineIn] = Field(min_length=1)


class PaymentIn(BaseModel):
    amount: Decimal = Field(gt=0, decimal_places=2)
    note: Optional[str] = Field(default=None, max_length=200)


class ReleaseRequest(BaseModel):
    override_weekend: bool = False


class ReturnLine(BaseModel):
    item_id: str
    returned: Decimal = Field(default=ZERO, ge=0, decimal_places=2)
    lost: Decimal = Field(default=ZERO, ge=0, decimal_places=2)
    damaged: Decimal = Field(default=ZERO, ge=0, decimal_places=2)
    charge: Decimal = Field(default=ZERO, ge=0, decimal_places=2)   # amount the borrower pays for lost/damaged


class ReturnRequest(BaseModel):
    lines: list[ReturnLine] = Field(min_length=1)
    override_weekend: bool = False


# =====================================================================
# Small helpers
# =====================================================================

def oid(value: str, what: str) -> ObjectId:
    try:
        return ObjectId(value)
    except (InvalidId, TypeError):
        raise api_error(404, "NOT_FOUND", f"{what} not found.")


def ensure_aware(dt: datetime) -> datetime:
    """Naive datetimes are treated as Philippine time. Result is UTC."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=PH_TZ)
    return dt.astimezone(timezone.utc)


def check_qty(unit: str, qty: Decimal, label: str) -> Decimal:
    """Pieces must be whole numbers; yards may have decimals."""
    if unit == "pc" and qty != qty.to_integral_value():
        raise api_error(422, "INVALID_QUANTITY", f"{label} is counted in whole pieces.")
    return qty


def money_str(x) -> str:
    return str(money(dec(x)))


def qty_str(x) -> str:
    return format(dec(x).normalize(), "f")


async def next_rental_no() -> str:
    year = datetime.now(PH_TZ).year
    c = await counters.find_one_and_update(
        {"_id": f"rental-{year}"}, {"$inc": {"seq": 1}},
        upsert=True, return_document=ReturnDocument.AFTER)
    return f"R-{year}-{c['seq']:04d}"


def snapshot_hash(r: dict) -> str:
    """Fingerprint of what the borrower agreed to. Stored with the signature."""
    payload = {
        "rental_no": r["rental_no"],
        "borrower_name": r["borrower_name"],
        "terms_version": TERMS_VERSION,
        "rental_cost": money_str(r["rental_cost"]),
        "items": [[str(l["item_id"]), qty_str(l["quantity"]), money_str(l["unit_price"])]
                  for l in r["items"]],
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


async def get_rental_or_404(rental_id: str) -> dict:
    r = await rentals.find_one({"_id": oid(rental_id, "Rental")})
    if not r:
        raise api_error(404, "NOT_FOUND", "Rental not found.")
    return r


# =====================================================================
# Totals and serialization
# =====================================================================

def compute_totals(r: dict, as_of: datetime) -> dict:
    """Penalty is live while items are out, and frozen once they are returned."""
    cost = dec(r["rental_cost"])
    if r["status"] == "RETURNED":
        late = int(r.get("days_late", 0))
        penalty = dec(r["penalty_amount"])
        other = dec(r["other_charges"])
    elif r["status"] == "RELEASED":
        late = days_late(r["due_at"], as_of)
        penalty = penalty_amount(cost, late)
        other = ZERO
    else:
        late, penalty, other = 0, ZERO, ZERO
    total = cost + penalty + other
    paid = dec(r["total_paid"])
    return {"rental_cost": cost, "days_late": late, "penalty": penalty, "other_charges": other,
            "total_due": total, "total_paid": paid, "balance": total - paid}


def item_out(i: dict) -> dict:
    total, available = dec(i["total_quantity"]), dec(i["available_quantity"])
    return {"id": str(i["_id"]), "name": i["name"], "category": i["category"], "unit": i["unit"],
            "price": money_str(i["price"]), "total_quantity": qty_str(total),
            "available_quantity": qty_str(available), "out_quantity": qty_str(total - available),
            "is_active": i["is_active"]}


def rental_summary(r: dict, as_of: datetime) -> dict:
    t = compute_totals(r, as_of)
    return {
        "id": str(r["_id"]), "rental_no": r["rental_no"], "status": r["status"],
        "borrower_name": r["borrower_name"], "member_name": r.get("member_name"),
        "pickup_at": r["pickup_at"], "due_at": r.get("due_at"),
        "is_overdue": r["status"] == "RELEASED" and t["days_late"] > 0,
        "days_late": t["days_late"], "item_count": len(r["items"]),
        "total_due": money_str(t["total_due"]), "total_paid": money_str(t["total_paid"]),
        "balance": money_str(t["balance"]),
    }


def rental_detail(r: dict, as_of: datetime) -> dict:
    t = compute_totals(r, as_of)
    sig = r.get("signature")
    out = rental_summary(r, as_of)
    out.update({
        "borrower_phone": r.get("borrower_phone"), "referred_by": r.get("referred_by"),
        "venue": r["venue"], "released_at": r.get("released_at"), "returned_at": r.get("returned_at"),
        "prepared_by_name": r.get("prepared_by_name"),
        "rental_cost": money_str(t["rental_cost"]), "penalty": money_str(t["penalty"]),
        "other_charges": money_str(t["other_charges"]),
        "min_down_payment": money_str(min_down_payment(r["rental_cost"])),
        "items": [{
            "item_id": str(l["item_id"]), "name": l["name"], "unit": l["unit"],
            "quantity": qty_str(l["quantity"]), "unit_price": money_str(l["unit_price"]),
            "amount": money_str(l["amount"]), "returned": qty_str(l["returned"]),
            "lost": qty_str(l["lost"]), "damaged": qty_str(l["damaged"]),
            "charge": money_str(l["charge"]),
        } for l in r["items"]],
        "payments": [{
            "amount": money_str(p["amount"]), "kind": p["kind"], "note": p.get("note"),
            "received_by_name": p.get("received_by_name"), "at": p["at"],
        } for p in r.get("payments", [])],
        "signature": ({"signed_at": sig["signed_at"], "terms_version": sig["terms_version"],
                       "signed_by_name": sig["signed_by_name"],
                       "url": signed_url(sig["public_id"])} if sig else None),
    })
    return out


def weekend_guard(t: datetime, override: bool, action: str):
    if is_weekend(t) and not override:
        raise api_error(409, "WEEKEND_NOT_ALLOWED",
                        f"The cooperative does not accept {action} on Saturdays and Sundays. "
                        "Continue anyway?")


# =====================================================================
# Terms
# =====================================================================

@router.get("/terms")
async def get_terms(user: dict = Depends(can_view)):
    return {"version": TERMS_VERSION, "terms": TERMS}


# =====================================================================
# Inventory items
# =====================================================================

@router.get("/items")
async def list_items(active_only: bool = True, category: Optional[str] = None,
                     q: Optional[str] = None, user: dict = Depends(can_view)):
    filt: dict = {}
    if active_only:
        filt["is_active"] = True
    if category:
        filt["category"] = category.upper()
    if q:
        filt["name"] = {"$regex": re.escape(q.strip()), "$options": "i"}
    cursor = rental_items.find(filt).sort([("category", 1), ("name", 1)])
    return [item_out(i) async for i in cursor]


@router.post("/items", status_code=201)
async def create_item(body: ItemCreate, user: dict = Depends(logistics_only)):
    check_qty(body.unit, body.total_quantity, body.name)
    t = now()
    doc = {
        "name": body.name.strip().upper(), "category": body.category, "unit": body.unit,
        "price": d128(money(body.price)),
        "total_quantity": d128(body.total_quantity), "available_quantity": d128(body.total_quantity),
        "is_active": True, "created_at": t, "updated_at": t,
    }
    try:
        await rental_items.insert_one(doc)
    except DuplicateKeyError:
        raise api_error(409, "ITEM_EXISTS", "An item with this name already exists.")
    await log_audit(user["_id"], "ITEM_CREATED", doc["_id"], {"name": doc["name"]})
    return item_out(doc)


@router.patch("/items/{item_id}")
async def update_item(item_id: str, body: ItemUpdate, user: dict = Depends(logistics_only)):
    changes: dict = {}
    if body.name is not None:
        changes["name"] = body.name.strip().upper()
    if body.price is not None:
        changes["price"] = d128(money(body.price))   # old rentals keep their own price snapshot
    if body.is_active is not None:
        changes["is_active"] = body.is_active
    if not changes:
        raise api_error(400, "NO_CHANGES", "Nothing to update.")
    changes["updated_at"] = now()
    try:
        item = await rental_items.find_one_and_update(
            {"_id": oid(item_id, "Item")}, {"$set": changes}, return_document=ReturnDocument.AFTER)
    except DuplicateKeyError:
        raise api_error(409, "ITEM_EXISTS", "An item with this name already exists.")
    if not item:
        raise api_error(404, "NOT_FOUND", "Item not found.")
    await log_audit(user["_id"], "ITEM_UPDATED", item["_id"],
                    {k: str(v) for k, v in changes.items() if k != "updated_at"})
    return item_out(item)


@router.patch("/items/{item_id}/stock")
async def set_stock(item_id: str, body: StockUpdate, user: dict = Depends(logistics_only)):
    """Set the total owned quantity. Available quantity moves by the same difference."""
    item_oid = oid(item_id, "Item")
    item = await rental_items.find_one({"_id": item_oid})
    if not item:
        raise api_error(404, "NOT_FOUND", "Item not found.")
    new_total = check_qty(item["unit"], body.total_quantity, item["name"])
    old_total = dec(item["total_quantity"])
    delta = new_total - old_total
    out = old_total - dec(item["available_quantity"])
    if new_total < out:
        raise api_error(409, "STOCK_BELOW_RENTED",
                        f"{qty_str(out)} are currently rented out, so the total cannot be lower than that.")
    res = await rental_items.update_one(
        {"_id": item_oid, "total_quantity": item["total_quantity"]},   # guards against concurrent changes
        {"$inc": {"total_quantity": d128(delta), "available_quantity": d128(delta)},
         "$set": {"updated_at": now()}})
    if res.matched_count == 0:
        raise api_error(409, "STOCK_CHANGED", "Stock changed while you were editing. Please retry.")
    await log_audit(user["_id"], "ITEM_STOCK_SET", item_oid,
                    {"name": item["name"], "from": qty_str(old_total), "to": qty_str(new_total)})
    return item_out(await rental_items.find_one({"_id": item_oid}))


# =====================================================================
# Rentals: create, list, detail
# =====================================================================

@router.post("/rentals", status_code=201)
async def create_rental(body: RentalCreate, user: dict = Depends(logistics_only)):
    ids = [oid(l.item_id, "Item") for l in body.items]
    if len(set(ids)) != len(ids):
        raise api_error(422, "DUPLICATE_ITEM", "Each item can appear only once. Combine the quantities.")
    found = {d["_id"]: d async for d in rental_items.find({"_id": {"$in": ids}})}

    lines, cost = [], ZERO
    for l, item_id in zip(body.items, ids):
        item = found.get(item_id)
        if not item or not item["is_active"]:
            raise api_error(404, "ITEM_NOT_FOUND", "One of the items is not available for rent.")
        qty = check_qty(item["unit"], l.quantity, item["name"])
        if qty > dec(item["available_quantity"]):
            raise api_error(409, "INSUFFICIENT_STOCK",
                            f"Not enough {item['name']} in stock "
                            f"(available: {qty_str(item['available_quantity'])}).")
        amount = line_amount(qty, item["price"])
        cost += amount
        lines.append({
            "item_id": item_id, "name": item["name"], "unit": item["unit"],
            "quantity": d128(qty), "unit_price": item["price"], "amount": d128(amount),
            "returned": d128(ZERO), "lost": d128(ZERO), "damaged": d128(ZERO), "charge": d128(ZERO),
        })

    t = now()
    doc = {
        "rental_no": await next_rental_no(), "status": "DRAFT",
        "borrower_name": body.borrower_name.strip(),
        "borrower_phone": (body.borrower_phone or "").strip() or None,
        "member_name": (body.member_name or "").strip() or None,
        "referred_by": (body.referred_by or "").strip() or None,
        "venue": body.venue.strip(),
        "pickup_at": ensure_aware(body.pickup_at), "due_at": None,
        "items": lines, "rental_cost": d128(money(cost)),
        "penalty_amount": d128(ZERO), "other_charges": d128(ZERO), "total_due": d128(money(cost)),
        "total_paid": d128(ZERO), "payments": [], "signature": None,
        "prepared_by": user["_id"], "prepared_by_name": user["full_name"],
        "created_at": t, "updated_at": t,
    }
    await rentals.insert_one(doc)
    await log_audit(user["_id"], "RENTAL_CREATED", doc["_id"],
                    {"rental_no": doc["rental_no"], "borrower": doc["borrower_name"],
                     "rental_cost": money_str(cost)})
    return rental_detail(doc, t)


_UNPAID_RETURNED = {"status": "RETURNED",
                    "$expr": {"$gt": [{"$subtract": ["$total_due", "$total_paid"]}, Decimal128("0")]}}


@router.get("/rentals")
async def list_rentals(status: str = "OUT", q: Optional[str] = None,
                       user: dict = Depends(can_view)):
    """status: OUT (not yet returned), OVERDUE, UNPAID (returned, balance owed),
    RETURNED, DRAFT, CANCELLED, ALL."""
    status = status.upper()
    t = now()
    if status == "OUT":
        filt: dict = {"status": "RELEASED"}
    elif status == "OVERDUE":
        filt = {"status": "RELEASED", "due_at": {"$lt": t}}
    elif status == "UNPAID":
        filt = dict(_UNPAID_RETURNED)
    elif status in ("RETURNED", "DRAFT", "CANCELLED"):
        filt = {"status": status}
    elif status == "ALL":
        filt = {}
    else:
        raise api_error(400, "INVALID_STATUS", "Unknown status filter.")
    if q and q.strip():
        rx = {"$regex": re.escape(q.strip()), "$options": "i"}
        filt["$or"] = [{"borrower_name": rx}, {"member_name": rx}, {"rental_no": rx}]
    order = [("due_at", 1)] if status in ("OUT", "OVERDUE") else [("created_at", -1)]
    cursor = rentals.find(filt).sort(order).limit(200)
    return [rental_summary(r, t) async for r in cursor]


@router.get("/rentals/{rental_id}")
async def rental_by_id(rental_id: str, user: dict = Depends(can_view)):
    return rental_detail(await get_rental_or_404(rental_id), now())


# =====================================================================
# Rentals: signature, payments, release, return, cancel
# =====================================================================

@router.post("/rentals/{rental_id}/signature")
async def sign_rental(rental_id: str, agreed: bool = Form(...), image: UploadFile = File(...),
                      user: dict = Depends(logistics_only)):
    if not agreed:
        raise api_error(422, "TERMS_NOT_ACCEPTED", "The borrower must agree to the terms.")
    r = await get_rental_or_404(rental_id)
    if r["status"] != "DRAFT":
        raise api_error(409, "NOT_DRAFT", "Only a draft rental can be signed.")
    data = await read_image(image)
    public_id = await upload_image(data, "signatures")
    t = now()
    signature = {"public_id": public_id, "signed_at": t, "terms_version": TERMS_VERSION,
                 "signed_by_name": r["borrower_name"], "content_hash": snapshot_hash(r)}
    res = await rentals.update_one({"_id": r["_id"], "status": "DRAFT"},
                                   {"$set": {"signature": signature, "updated_at": t}})
    if res.matched_count == 0:
        raise api_error(409, "NOT_DRAFT", "Only a draft rental can be signed.")
    await log_audit(user["_id"], "RENTAL_SIGNED", r["_id"], {"rental_no": r["rental_no"]})
    return rental_detail(await rentals.find_one({"_id": r["_id"]}), t)


@router.post("/rentals/{rental_id}/payments")
async def add_payment(rental_id: str, body: PaymentIn, user: dict = Depends(logistics_only)):
    """The system does not process payments. The handler records what the renter paid."""
    r = await get_rental_or_404(rental_id)
    if r["status"] == "CANCELLED":
        raise api_error(409, "CANCELLED", "This rental was cancelled.")
    t = now()
    amount = money(body.amount)
    balance = compute_totals(r, t)["balance"]
    if amount > balance:
        raise api_error(422, "OVERPAYMENT", f"The amount is more than the balance of {money_str(balance)}.")
    kind = {"DRAFT": "DOWN_PAYMENT", "RELEASED": "PAYMENT", "RETURNED": "BALANCE"}[r["status"]]
    payment = {"amount": d128(amount), "kind": kind, "note": body.note,
               "received_by": user["_id"], "received_by_name": user["full_name"], "at": t}
    res = await rentals.update_one(
        {"_id": r["_id"], "status": r["status"]},
        {"$push": {"payments": payment}, "$inc": {"total_paid": d128(amount)},
         "$set": {"updated_at": t}})
    if res.matched_count == 0:
        raise api_error(409, "RENTAL_CHANGED", "The rental changed. Please reload and try again.")
    await log_audit(user["_id"], "RENTAL_PAYMENT", r["_id"],
                    {"rental_no": r["rental_no"], "amount": str(amount), "kind": kind})
    return rental_detail(await rentals.find_one({"_id": r["_id"]}), t)


@router.post("/rentals/{rental_id}/release")
async def release_rental(rental_id: str, body: Optional[ReleaseRequest] = None,
                         user: dict = Depends(logistics_only)):
    override = bool(body and body.override_weekend)
    r = await get_rental_or_404(rental_id)
    if r["status"] != "DRAFT":
        raise api_error(409, "NOT_DRAFT", "Only a draft rental can be released.")
    if not r.get("signature"):
        raise api_error(409, "SIGNATURE_REQUIRED", "The borrower must sign before the items are released.")
    required = min_down_payment(r["rental_cost"])
    if dec(r["total_paid"]) < required:
        raise api_error(409, "DOWN_PAYMENT_REQUIRED",
                        f"A 50% down payment of {money_str(required)} is required before release.",
                        required=money_str(required), paid=money_str(r["total_paid"]))
    t = now()
    weekend_guard(t, override, "releases")
    due_at = compute_due_at(r["pickup_at"])

    # Stock and rental status change together or not at all.
    async with await client.start_session() as session:
        async with session.start_transaction():
            for line in r["items"]:
                res = await rental_items.update_one(
                    {"_id": line["item_id"], "available_quantity": {"$gte": line["quantity"]}},
                    {"$inc": {"available_quantity": d128(-dec(line["quantity"]))},
                     "$set": {"updated_at": t}},
                    session=session)
                if res.matched_count == 0:
                    raise api_error(409, "INSUFFICIENT_STOCK", f"Not enough {line['name']} in stock.")
            res = await rentals.update_one(
                {"_id": r["_id"], "status": "DRAFT"},
                {"$set": {"status": "RELEASED", "released_at": t, "due_at": due_at,
                          "released_by": user["_id"], "updated_at": t}},
                session=session)
            if res.matched_count == 0:
                raise api_error(409, "NOT_DRAFT", "Only a draft rental can be released.")
    await log_audit(user["_id"], "RENTAL_RELEASED", r["_id"],
                    {"rental_no": r["rental_no"], "due_at": due_at.isoformat()})
    return rental_detail(await rentals.find_one({"_id": r["_id"]}), t)


@router.post("/rentals/{rental_id}/return")
async def return_rental(rental_id: str, body: ReturnRequest, user: dict = Depends(logistics_only)):
    """One return event covering every item: returned + lost + damaged must equal what was rented.
    Lost and damaged items leave the stock count (the borrower pays the charge you enter)."""
    r = await get_rental_or_404(rental_id)
    if r["status"] != "RELEASED":
        raise api_error(409, "NOT_RELEASED", "Only a released rental can be returned.")
    t = now()
    weekend_guard(t, body.override_weekend, "returns")

    by_id = {str(l["item_id"]): l for l in r["items"]}
    given = {}
    for ln in body.lines:
        if ln.item_id not in by_id:
            raise api_error(422, "UNKNOWN_ITEM", "A returned item is not part of this rental.")
        if ln.item_id in given:
            raise api_error(422, "DUPLICATE_ITEM", "An item appears twice in the return.")
        given[ln.item_id] = ln
    if set(given) != set(by_id):
        raise api_error(422, "MISSING_ITEMS", "Account for every rented item (returned, lost, or damaged).")

    new_lines, other = [], ZERO
    for key, line in by_id.items():
        ln = given[key]
        for label, v in (("returned", ln.returned), ("lost", ln.lost), ("damaged", ln.damaged)):
            check_qty(line["unit"], v, line["name"])
        if ln.returned + ln.lost + ln.damaged != dec(line["quantity"]):
            raise api_error(422, "COUNT_MISMATCH",
                            f"{line['name']}: returned + lost + damaged must equal {qty_str(line['quantity'])}.")
        if ln.charge > 0 and (ln.lost + ln.damaged) == 0:
            raise api_error(422, "CHARGE_WITHOUT_LOSS",
                            f"{line['name']}: a charge needs a lost or damaged quantity.")
        other += money(ln.charge)
        new_lines.append({**line, "returned": d128(ln.returned), "lost": d128(ln.lost),
                          "damaged": d128(ln.damaged), "charge": d128(money(ln.charge))})

    cost = dec(r["rental_cost"])
    late = days_late(r["due_at"], t)
    penalty = penalty_amount(cost, late)
    total_due = cost + penalty + other

    async with await client.start_session() as session:
        async with session.start_transaction():
            for line in new_lines:
                back, gone = dec(line["returned"]), dec(line["lost"]) + dec(line["damaged"])
                inc = {}
                if back > 0:
                    inc["available_quantity"] = d128(back)
                if gone > 0:
                    inc["total_quantity"] = d128(-gone)
                if inc:
                    await rental_items.update_one(
                        {"_id": line["item_id"]}, {"$inc": inc, "$set": {"updated_at": t}},
                        session=session)
            res = await rentals.update_one(
                {"_id": r["_id"], "status": "RELEASED"},
                {"$set": {"status": "RETURNED", "items": new_lines, "returned_at": t,
                          "returned_by": user["_id"], "days_late": late,
                          "penalty_amount": d128(penalty), "other_charges": d128(other),
                          "total_due": d128(total_due), "updated_at": t}},
                session=session)
            if res.matched_count == 0:
                raise api_error(409, "NOT_RELEASED", "Only a released rental can be returned.")
    await log_audit(user["_id"], "RENTAL_RETURNED", r["_id"],
                    {"rental_no": r["rental_no"], "days_late": late, "penalty": str(penalty),
                     "other_charges": str(other)})
    return rental_detail(await rentals.find_one({"_id": r["_id"]}), t)


@router.post("/rentals/{rental_id}/cancel")
async def cancel_rental(rental_id: str, user: dict = Depends(logistics_only)):
    r = await get_rental_or_404(rental_id)
    if r["status"] != "DRAFT":
        raise api_error(409, "NOT_DRAFT", "Only a draft rental can be cancelled.")
    if dec(r["total_paid"]) > 0:
        raise api_error(409, "HAS_PAYMENTS", "This rental already has a payment recorded.")
    t = now()
    res = await rentals.update_one({"_id": r["_id"], "status": "DRAFT"},
                                   {"$set": {"status": "CANCELLED", "updated_at": t}})
    if res.matched_count == 0:
        raise api_error(409, "NOT_DRAFT", "Only a draft rental can be cancelled.")
    await log_audit(user["_id"], "RENTAL_CANCELLED", r["_id"], {"rental_no": r["rental_no"]})
    return {"message": "Rental cancelled."}


# =====================================================================
# Summary
# =====================================================================

@router.get("/summary")
async def summary(user: dict = Depends(can_view)):
    t = now()
    return {
        "out": await rentals.count_documents({"status": "RELEASED"}),
        "overdue": await rentals.count_documents({"status": "RELEASED", "due_at": {"$lt": t}}),
        "unpaid_returned": await rentals.count_documents(_UNPAID_RETURNED),
        "drafts": await rentals.count_documents({"status": "DRAFT"}),
        "active_items": await rental_items.count_documents({"is_active": True}),
    }