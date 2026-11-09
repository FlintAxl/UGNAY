from enum import Enum

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