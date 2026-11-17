"""Publish bidding rounds to the cooperative's Facebook Page.

Uses the Graph API Pages endpoints. Posting is best-effort: the helpers return
a status dict instead of raising, so a Facebook outage never blocks round
creation. The Page access token is only ever sent in the request body and is
never included in returned errors.
"""
from datetime import date, datetime, timezone

import httpx

from .config import settings

_MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]

DEFAULT_TITLE = "Ginger bidding"
FOOTER = ("Interested suppliers may visit PRIC MPC (2000), "
          "Barangay Pinagdanlayan, Dolores, Quezon.")


def facebook_configured() -> bool:
    return bool(settings.FACEBOOK_PAGE_ID.strip()
                and settings.FACEBOOK_PAGE_ACCESS_TOKEN.strip())


def _graph_version() -> str:
    version = settings.FACEBOOK_GRAPH_VERSION.strip() or "v26.0"
    return version if version.startswith("v") else f"v{version}"


def format_round_date(value) -> str:
    if not value:
        return ""
    if isinstance(value, datetime):
        value = value.date()
    if not isinstance(value, date):
        try:
            value = date.fromisoformat(str(value)[:10])
        except ValueError:
            return str(value)
    return f"{_MONTHS[value.month - 1]} {value.day}, {value.year}"


def build_round_message(*, round_no: str, title: str | None = None,
                        notes: str | None = None, bidding_date=None) -> str:
    lines = [
        "ACTIVE BIDDING ROUND",
        f"Round {round_no} - {title or DEFAULT_TITLE}",
    ]
    when = format_round_date(bidding_date)
    if when:
        lines.append(f"Bidding date: {when}")
    if notes and notes.strip():
        lines.extend(["", notes.strip()])
    lines.extend(["", FOOTER])
    return "\n".join(lines)


async def post_round(*, round_no: str, title: str | None = None,
                     notes: str | None = None, bidding_date=None,
                     image_url: str | None = None) -> dict:
    """Create a Page post. Returns a status dict; never raises."""
    attempted = datetime.now(timezone.utc)
    if not facebook_configured():
        return {
            "status": "SKIPPED",
            "error": "Facebook is not configured.",
            "attempted_at": attempted,
        }

    message = build_round_message(
        round_no=round_no, title=title, notes=notes, bidding_date=bidding_date)
    page_id = settings.FACEBOOK_PAGE_ID.strip()
    token = settings.FACEBOOK_PAGE_ACCESS_TOKEN.strip()
    base = f"https://graph.facebook.com/{_graph_version()}/{page_id}"

    try:
        async with httpx.AsyncClient(
                timeout=settings.FACEBOOK_POST_TIMEOUT_SECONDS) as client:
            if image_url:
                response = await client.post(
                    f"{base}/photos",
                    data={"url": image_url, "caption": message,
                          "access_token": token},
                )
            else:
                response = await client.post(
                    f"{base}/feed",
                    data={"message": message, "access_token": token},
                )
    except httpx.HTTPError as exc:
        return {
            "status": "FAILED",
            "error": f"Facebook is unreachable ({type(exc).__name__}).",
            "attempted_at": attempted,
        }

    try:
        payload = response.json()
    except ValueError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    if response.status_code == 200 and not payload.get("error"):
        return {
            "status": "POSTED",
            "post_id": payload.get("post_id") or payload.get("id"),
            "photo_id": payload.get("id") if image_url else None,
            "error": None,
            "attempted_at": attempted,
            "posted_at": datetime.now(timezone.utc),
        }

    error = payload.get("error")
    if isinstance(error, dict):
        detail = error.get("message") or "Facebook rejected the post."
        code = error.get("code")
        subcode = error.get("error_subcode")
        if code is not None:
            detail = f"{detail} (code {code}"
            detail += f", subcode {subcode})" if subcode is not None else ")"
    else:
        detail = f"Facebook returned HTTP {response.status_code}."
    return {
        "status": "FAILED",
        "error": detail[:400],
        "attempted_at": attempted,
    }
