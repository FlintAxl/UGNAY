"""Pure PMES schedule rules (no database, no web framework), so they are easy to test.

PMES is held on Saturdays only at the cooperative's office.
"""
from datetime import date, datetime, timedelta

from .pricing import PH_TZ

PMES_VENUE = "PRIC Cooperative, Barangay Pinagdanlayan, Dolores, Quezon"
SATURDAY = 5  # date.weekday(): Monday=0 ... Sunday=6


def today_ph() -> date:
    return datetime.now(PH_TZ).date()


def next_saturdays(start: date, count: int = 12) -> list[date]:
    """Upcoming Saturdays on or after `start`."""
    days_ahead = (SATURDAY - start.weekday()) % 7
    first = start + timedelta(days=days_ahead)
    return [first + timedelta(weeks=i) for i in range(count)]


def schedule_problem(schedule_date: date, today: date | None = None) -> str | None:
    """Returns an error message, or None when the date can be booked."""
    today = today or today_ph()
    if schedule_date < today:
        return "The PMES schedule cannot be in the past."
    if schedule_date.weekday() != SATURDAY:
        return "PMES is held on Saturdays only."
    return None


def date_label(value: date) -> str:
    return value.strftime("%A, %B %d, %Y")


def seminar_phase(seminar_date: date, status: str, today: date | None = None) -> str:
    """Display phase for a stored seminar: UPCOMING, PAST, or CANCELLED."""
    if status == "CANCELLED":
        return "CANCELLED"
    today = today or today_ph()
    return "UPCOMING" if seminar_date >= today else "PAST"


def response_locked(seminar_date: date, today: date | None = None) -> bool:
    """Responses stay editable through the seminar date, then lock."""
    return seminar_date < (today or today_ph())


def attendance_totals(responses: list[str | None]) -> dict:
    attending = sum(1 for r in responses if r == "ATTEND")
    not_attending = sum(1 for r in responses if r == "DECLINE")
    total = len(responses)
    return {
        "attending": attending,
        "not_attending": not_attending,
        "no_response": total - attending - not_attending,
        "total": total,
    }
