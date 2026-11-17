"""Run from the backend folder:  pytest -q"""
import asyncio
from datetime import date

from app.config import settings
from app.facebook import (build_round_message, facebook_configured,
                          format_round_date, post_round)


def test_round_message_contains_all_details():
    message = build_round_message(
        round_no="B-2026-0007",
        title="October ginger buying",
        notes="Native and half-native only.",
        bidding_date="2026-11-20",
    )
    assert "ACTIVE BIDDING ROUND" in message
    assert "Round B-2026-0007 - October ginger buying" in message
    assert "Bidding date: November 20, 2026" in message
    assert "Native and half-native only." in message
    assert "PRIC MPC (2000)" in message


def test_round_message_falls_back_when_fields_missing():
    message = build_round_message(round_no="B-2026-0008")
    assert "Ginger bidding" in message
    assert "Bidding date:" not in message


def test_round_date_accepts_date_and_iso_string():
    assert format_round_date(date(2026, 1, 5)) == "January 5, 2026"
    assert format_round_date("2026-12-31") == "December 31, 2026"
    assert format_round_date(None) == ""


def test_facebook_configured_requires_both_values(monkeypatch):
    monkeypatch.setattr(settings, "FACEBOOK_PAGE_ID", "123")
    monkeypatch.setattr(settings, "FACEBOOK_PAGE_ACCESS_TOKEN", "token")
    assert facebook_configured()

    monkeypatch.setattr(settings, "FACEBOOK_PAGE_ACCESS_TOKEN", "")
    assert not facebook_configured()


def test_post_round_skips_without_configuration(monkeypatch):
    monkeypatch.setattr(settings, "FACEBOOK_PAGE_ID", "")
    monkeypatch.setattr(settings, "FACEBOOK_PAGE_ACCESS_TOKEN", "")
    result = asyncio.run(post_round(round_no="B-2026-0009"))
    assert result["status"] == "SKIPPED"
    assert "not configured" in result["error"]
