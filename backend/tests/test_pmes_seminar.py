"""Run from the backend folder:  pytest -q"""
from datetime import date

from app.pmes_schedule import (attendance_totals, date_label, response_locked,
                               seminar_phase)


def test_seminar_phase():
    today = date(2026, 11, 12)
    assert seminar_phase(date(2026, 11, 14), "SCHEDULED", today) == "UPCOMING"
    assert seminar_phase(date(2026, 11, 12), "SCHEDULED", today) == "UPCOMING"
    assert seminar_phase(date(2026, 11, 7), "SCHEDULED", today) == "PAST"
    assert seminar_phase(date(2026, 11, 7), "CANCELLED", today) == "CANCELLED"


def test_response_locked_until_the_day_after_the_seminar():
    seminar = date(2026, 11, 14)
    assert response_locked(seminar, date(2026, 11, 13)) is False
    assert response_locked(seminar, seminar) is False
    assert response_locked(seminar, date(2026, 11, 15)) is True


def test_attendance_totals():
    assert attendance_totals([]) == {
        "attending": 0,
        "not_attending": 0,
        "no_response": 0,
        "total": 0,
    }
    assert attendance_totals(["ATTEND", "DECLINE", None, "ATTEND"]) == {
        "attending": 2,
        "not_attending": 1,
        "no_response": 1,
        "total": 4,
    }


def test_date_label():
    assert date_label(date(2026, 11, 14)) == "Saturday, November 14, 2026"
