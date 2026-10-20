"""
Pure business rules for rentals (no database, no web framework), so they are easy to test.

Rules come from the cooperative's rental form:
- Flat price per piece (or per yard) for up to 3 days.
- 50% down payment of the rental cost at pick-up.
- After the 3rd day, a penalty of 1% of the total rental cost per day.
- Releases and returns are not accepted on Saturdays and Sundays (holidays: later).
"""
from datetime import date, datetime, time, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal
from zoneinfo import ZoneInfo

from bson.decimal128 import Decimal128

PH_TZ = ZoneInfo("Asia/Manila")

RENTAL_DAYS = 3
PENALTY_RATE_PER_DAY = Decimal("0.01")   # 1% of total rental cost, per day late
DOWN_PAYMENT_RATE = Decimal("0.50")      # 50% of total rental cost

_CENTAVO = Decimal("0.01")


# ---------- Decimal helpers ----------

def money(value) -> Decimal:
    """Round to centavos."""
    return Decimal(str(value)).quantize(_CENTAVO, rounding=ROUND_HALF_UP)


def d128(value) -> Decimal128:
    """Python Decimal -> MongoDB Decimal128."""
    return Decimal128(str(value))


def dec(value) -> Decimal:
    """MongoDB Decimal128 (or number/string) -> Python Decimal."""
    if isinstance(value, Decimal128):
        return value.to_decimal()
    return Decimal(str(value))


# ---------- Amounts ----------

def line_amount(quantity, unit_price) -> Decimal:
    return money(dec(quantity) * dec(unit_price))


def min_down_payment(rental_cost) -> Decimal:
    return money(dec(rental_cost) * DOWN_PAYMENT_RATE)


def penalty_amount(rental_cost, late_days: int) -> Decimal:
    return money(dec(rental_cost) * PENALTY_RATE_PER_DAY * late_days)


# ---------- Dates (all calendar logic uses Philippine time) ----------

def to_ph_date(dt: datetime) -> date:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(PH_TZ).date()


def compute_due_at(pickup_at: datetime) -> datetime:
    """End of the 3rd day after pick-up (23:59:59 Philippine time), returned in UTC."""
    due_date = to_ph_date(pickup_at) + timedelta(days=RENTAL_DAYS)
    return datetime.combine(due_date, time(23, 59, 59), tzinfo=PH_TZ).astimezone(timezone.utc)


def days_late(due_at: datetime, as_of: datetime) -> int:
    """Whole calendar days past the due date. Returning any time on the due date = 0."""
    return max(0, (to_ph_date(as_of) - to_ph_date(due_at)).days)


def is_weekend(dt: datetime) -> bool:
    return to_ph_date(dt).weekday() >= 5