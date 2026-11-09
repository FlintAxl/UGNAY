"""Pure rules for ginger bidding entries (no database), so they are easy to test.

The cooperative only buys the GOOD ginger. Bad-quality kilos are recorded for the
record but are not bought, so they never affect the price.
"""
from decimal import Decimal
from typing import Optional

from .pricing import dec, money

GINGER_KINDS = ("NATIVE", "HALF_NATIVE")


def entry_total(good_kg, price_per_kg_good) -> Decimal:
    """Total price of an entry = good kilos x price per kilo, rounded to centavos."""
    return money(dec(good_kg) * dec(price_per_kg_good))


def weight_problem(weigh_in_kg, good_kg, bad_kg) -> Optional[str]:
    """Returns an error message, or None when the weights are consistent."""
    w, g, b = dec(weigh_in_kg), dec(good_kg), dec(bad_kg)
    if w <= Decimal(0):
        return "Weigh-in weight must be more than zero."
    if g + b <= Decimal(0):
        return "Enter the good and/or bad quality kilos."
    if g + b > w:
        return f"Good ({g}) + bad ({b}) kilos cannot be more than the weigh-in weight ({w})."
    return None