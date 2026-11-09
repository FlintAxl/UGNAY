import certifi
from motor.motor_asyncio import AsyncIOMotorClient

from .config import settings

# tz_aware=True: datetimes read back from MongoDB are timezone-aware (UTC).
client = AsyncIOMotorClient(settings.DB_URI, tlsCAFile=certifi.where(), tz_aware=True)
db = client[settings.DATABASE_NAME]

users = db["users"]
audit_logs = db["audit_logs"]
counters = db["counters"]

# Logistics
rental_items = db["rental_items"]
rentals = db["rentals"]

# Production (ginger bidding)
suppliers = db["suppliers"]
bidding_rounds = db["bidding_rounds"]

# PMES (aspiring members)
pmes_applications = db["pmes_applications"]


async def init_indexes():
    await users.create_index("email", unique=True)
    await users.create_index([("status", 1), ("created_at", -1)])
    await audit_logs.create_index([("created_at", -1)])

    await rental_items.create_index("name", unique=True)
    await rentals.create_index("rental_no", unique=True)
    await rentals.create_index([("status", 1), ("due_at", 1)])
    await rentals.create_index([("created_at", -1)])

    await suppliers.create_index("name_key", unique=True)
    await bidding_rounds.create_index("round_no", unique=True)
    await bidding_rounds.create_index([("status", 1), ("created_at", -1)])

    await pmes_applications.create_index("user_id", unique=True)
    await pmes_applications.create_index("reference_no", unique=True)
    await pmes_applications.create_index([("schedule_date", 1)])
    await pmes_applications.create_index([("status", 1), ("created_at", -1)])