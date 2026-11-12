from datetime import date
from enum import Enum
from typing import Literal, Optional

from pydantic import BaseModel, EmailStr, Field


class Status:
    PENDING = "PENDING"
    ACTIVE = "ACTIVE"
    REJECTED = "REJECTED"
    SUSPENDED = "SUSPENDED"


ALL_STATUSES = {Status.PENDING, Status.ACTIVE, Status.REJECTED, Status.SUSPENDED}


class AssignableRole(str, Enum):
    """Roles an admin may assign. 'admin' and 'UNASSIGNED' are deliberately absent."""
    member = "member"
    logistics = "logistics"
    production = "production"
    marketing = "marketing"
    microfinance = "microfinance"
    savings = "savings"


class MembershipType(str, Enum):
    """Cooperative membership class, independent of the account's access role."""
    associate = "ASSOCIATE"
    fully_pledged = "FULLY_PLEDGED"


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class ApproveRequest(BaseModel):
    role: AssignableRole
    membership_type: MembershipType = MembershipType.associate


class MembershipUpdateRequest(BaseModel):
    membership_type: MembershipType


class RejectRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=500)


PMES_SUBMITTED = "SUBMITTED"
PMES_APPROVED = "APPROVED"
PMES_REJECTED = "REJECTED"
PMES_STATUSES = {PMES_SUBMITTED, PMES_APPROVED, PMES_REJECTED}


class PmesRejectRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=500)


SEMINAR_SCHEDULED = "SCHEDULED"
SEMINAR_CANCELLED = "CANCELLED"
SEMINAR_STATUSES = {SEMINAR_SCHEDULED, SEMINAR_CANCELLED}

RESPONSE_ATTEND = "ATTEND"
RESPONSE_DECLINE = "DECLINE"
SEMINAR_RESPONSES = {RESPONSE_ATTEND, RESPONSE_DECLINE}


class SeminarCreateRequest(BaseModel):
    date: date
    venue: Optional[str] = Field(default=None, max_length=200)


class SeminarCancelRequest(BaseModel):
    reason: Optional[str] = Field(default=None, max_length=500)


class SeminarResponseRequest(BaseModel):
    response: Literal["ATTEND", "DECLINE"]