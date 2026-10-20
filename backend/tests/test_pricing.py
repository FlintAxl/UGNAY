"""Run from the backend folder:  pytest -q"""
from datetime import datetime, timezone
from decimal import Decimal

from app.pricing import (PH_TZ, compute_due_at, days_late, is_weekend, line_amount,
                         min_down_payment, money, penalty_amount)


def manila(y, m, d, hh=12, mm=0):
    return datetime(y, m, d, hh, mm, tzinfo=PH_TZ)


def test_money_rounds_half_up():
    assert money("10.005") == Decimal("10.01")
    assert money("10.004") == Decimal("10.00")


def test_line_amount_pieces_and_yards():
    assert line_amount(5, "75.00") == Decimal("375.00")      # 5 round tables
    assert line_amount("2.5", "10.00") == Decimal("25.00")   # 2.5 yards of cloth


def test_due_date_is_end_of_third_day():
    pickup = manila(2026, 10, 19, 10)                         # Monday
    due = compute_due_at(pickup).astimezone(PH_TZ)
    assert (due.year, due.month, due.day) == (2026, 10, 22)   # Thursday
    assert (due.hour, due.minute, due.second) == (23, 59, 59)


def test_no_penalty_on_or_before_due_date():
    due = compute_due_at(manila(2026, 10, 19, 10))
    assert days_late(due, manila(2026, 10, 20)) == 0
    assert days_late(due, manila(2026, 10, 22, 23, 30)) == 0   # last evening of day 3


def test_penalty_starts_the_day_after_due_date():
    due = compute_due_at(manila(2026, 10, 19, 10))
    assert days_late(due, manila(2026, 10, 23, 0, 30)) == 1
    assert days_late(due, manila(2026, 10, 26, 9)) == 4        # returned the following Monday


def test_utc_timestamp_uses_philippine_calendar_day():
    due = compute_due_at(manila(2026, 10, 19, 10))
    # 16:30 UTC on Oct 22 is already 00:30 on Oct 23 in Manila
    assert days_late(due, datetime(2026, 10, 22, 16, 30, tzinfo=timezone.utc)) == 1


def test_penalty_is_one_percent_of_total_rental_cost_per_day():
    assert penalty_amount("1000.00", 0) == Decimal("0.00")
    assert penalty_amount("1000.00", 1) == Decimal("10.00")
    assert penalty_amount("1000.00", 4) == Decimal("40.00")
    assert penalty_amount("1234.50", 3) == Decimal("37.04")    # 37.035 rounds half up


def test_down_payment_is_half():
    assert min_down_payment("1000.00") == Decimal("500.00")
    assert min_down_payment("1001.00") == Decimal("500.50")


def test_weekend_detection_in_manila_time():
    assert is_weekend(manila(2026, 10, 24))        # Saturday
    assert is_weekend(manila(2026, 10, 25))        # Sunday
    assert not is_weekend(manila(2026, 10, 23))    # Friday
    # Friday 17:00 UTC is already Saturday 01:00 in Manila
    assert is_weekend(datetime(2026, 10, 23, 17, 0, tzinfo=timezone.utc))