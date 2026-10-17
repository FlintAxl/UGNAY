"""
Create the first admin. The face-service must be running (the admin also logs in
with face verification).

Run from the backend folder:   python seed_admin.py
"""
import asyncio
import getpass
from pathlib import Path

from app.auth import hash_password
from app.database import init_indexes, users
from app.helpers import get_embedding, now, upload_image


async def main():
    await init_indexes()
    email = input("Admin email: ").strip().lower()
    if await users.find_one({"email": email}, {"_id": 1}):
        print("That email already exists.")
        return
    full_name = input("Full name: ").strip()
    phone = input("Phone: ").strip()
    password = getpass.getpass("Password (min 8 chars): ")
    if len(password) < 8:
        print("Password too short.")
        return
    photo_path = Path(input("Path to a clear face photo (jpg/png): ").strip().strip('"'))
    data = photo_path.read_bytes()

    embedding = await get_embedding(data)
    face_public_id = await upload_image(data, "faces")

    await users.insert_one({
        "email": email,
        "password_hash": hash_password(password),
        "full_name": full_name,
        "phone": phone,
        "address": "",
        "status": "ACTIVE",
        "role": "admin",
        "id_photo_id": None,
        "face_photo_id": face_public_id,
        "face_embedding": embedding,
        "reviewed_by": None,
        "reviewed_at": None,
        "rejection_reason": None,
        "created_at": now(),
        "updated_at": now(),
    })
    print(f"Admin created: {email}")


if __name__ == "__main__":
    asyncio.run(main())