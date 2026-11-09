"""Run from the backend folder:  pytest -q"""
from decimal import Decimal

from app.ginger_math import entry_total, weight_problem


def test_total_is_good_kilos_times_good_price():
    assert entry_total("88", "120.00") == Decimal("10560.00")
    assert entry_total("80.50", "120.00") == Decimal("9660.00")


def test_total_rounds_to_centavos():
    assert entry_total("3.33", "10.10") == Decimal("33.63")    # 33.633 rounds to 33.63


def test_no_good_kilos_means_zero_total():
    assert entry_total("0", "120.00") == Decimal("0.00")


def test_weights_must_fit_inside_weigh_in():
    assert weight_problem("100", "90", "10") is None          # exactly equal is fine
    assert weight_problem("100", "80", "10") is None          # dirt or soil can account for the gap
    assert "cannot be more" in weight_problem("100", "95", "10")


def test_weights_must_be_positive():
    assert weight_problem("0", "0", "0") is not None
    assert weight_problem("50", "0", "0") is not None         # nothing graded