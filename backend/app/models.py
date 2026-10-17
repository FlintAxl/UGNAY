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
    logistics = "logistics"
    production = "production"
    marketing = "marketing"
    microfinance = "microfinance"
    savings = "savings"


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class ApproveRequest(BaseModel):
    role: AssignableRole


class RejectRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=500)