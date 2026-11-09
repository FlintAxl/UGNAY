"""Run from the backend folder:  pytest -q"""
from datetime import date

from app.pmes_schedule import next_saturdays, schedule_problem


def test_next_saturdays_starts_on_the_coming_saturday():
    monday = date(2026, 10, 19)
    days = next_saturdays(monday, 3)
    assert [d.isoformat() for d in days] == ["2026-10-24", "2026-10-31", "2026-11-07"]


def test_next_saturdays_keeps_today_when_it_is_saturday():
    saturday = date(2026, 10, 24)
    assert next_saturdays(saturday, 1) == [saturday]


def test_only_saturdays_are_allowed():
    today = date(2026, 10, 19)  # Monday
    assert schedule_problem(date(2026, 10, 24), today) is None
    assert "Saturdays only" in schedule_problem(date(2026, 10, 23), today)  # Friday
    assert "Saturdays only" in schedule_problem(date(2026, 10, 25), today)  # Sunday


def test_past_dates_are_rejected():
    today = date(2026, 10, 19)
    assert "past" in schedule_problem(date(2026, 10, 17), today)


def test_same_day_is_allowed():
    saturday = date(2026, 10, 24)
    assert schedule_problem(saturday, saturday) is None
