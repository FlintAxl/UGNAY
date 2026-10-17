import certifi
from motor.motor_asyncio import AsyncIOMotorClient

from .config import settings

client = AsyncIOMotorClient(settings.DB_URI, tlsCAFile=certifi.where())
db = client[settings.DATABASE_NAME]

users = db["users"]
audit_logs = db["audit_logs"]


async def init_indexes():
    await users.create_index("email", unique=True)
    await users.create_index([("status", 1), ("created_at", -1)])
    await audit_logs.create_index([("created_at", -1)])