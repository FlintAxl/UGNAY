"""
Load the cooperative's rental catalog (from RENTAL-FORM.xlsx) into MongoDB.

Run from the backend folder (safe to run again; existing items are left alone):

    python seed_items.py                      # insert items with stock 0, write item_stock_template.csv
    python seed_items.py --stock item_stock.csv   # set stock counts from your filled-in CSV

CSV columns: name, unit, quantity   (open the template in Excel, fill in quantity, save as CSV)
"""
import argparse
import asyncio
import csv
from decimal import Decimal, InvalidOperation
from pathlib import Path

from app.database import init_indexes, rental_items
from app.helpers import now
from app.pricing import d128, dec

# (name, category, unit, price) read from the cooperative's rental form
ITEMS = [
    ("SILYA", "EQUIPMENT", "pc", "5"),
    ("ROUND TABLE SMALL", "EQUIPMENT", "pc", "50"),
    ("ROUND TABLE BIG", "EQUIPMENT", "pc", "75"),
    ("RECTANGULAR TABLE", "EQUIPMENT", "pc", "75"),
    ("LONG TABLE WOOD", "EQUIPMENT", "pc", "85"),
    ("PLATO PLASTIC", "EQUIPMENT", "pc", "3"),
    ("PLATO BUBOG BIG", "EQUIPMENT", "pc", "3"),
    ("PLATO SMALL", "EQUIPMENT", "pc", "2"),
    ("PLATITO", "EQUIPMENT", "pc", "2"),
    ("BANDIHADO BIG", "EQUIPMENT", "pc", "3"),
    ("BANDIHADO SMALL", "EQUIPMENT", "pc", "3"),
    ("BOWL BIG", "EQUIPMENT", "pc", "10"),
    ("BOWL MEDIUM", "EQUIPMENT", "pc", "3"),
    ("BOWL SMALL", "EQUIPMENT", "pc", "2"),
    ("KUTSARA", "EQUIPMENT", "pc", "1"),
    ("TINIDOR", "EQUIPMENT", "pc", "1"),
    ("KUTSARITA", "EQUIPMENT", "pc", "1"),
    ("SERVING SPOON", "EQUIPMENT", "pc", "3"),
    ("KAWOT STAINLESS", "EQUIPMENT", "pc", "5"),
    ("SIYANSE", "EQUIPMENT", "pc", "10"),
    ("FOOD WARMER BIG", "EQUIPMENT", "pc", "150"),
    ("FOOD WARMER SMALL", "EQUIPMENT", "pc", "80"),
    ("GLASS ORDINARY", "EQUIPMENT", "pc", "2"),
    ("TALL GLASS", "EQUIPMENT", "pc", "10"),
    ("WINE GLASS", "EQUIPMENT", "pc", "3"),
    ("TASA", "EQUIPMENT", "pc", "2"),
    ("PITCHER STAINLESS", "EQUIPMENT", "pc", "30"),
    ("WATER JUG", "EQUIPMENT", "pc", "100"),
    ("STYROFOAM", "EQUIPMENT", "pc", "50"),
    ("PLANGANA", "EQUIPMENT", "pc", "15"),
    ("TULYASE", "EQUIPMENT", "pc", "100"),
    ("CHAIR COVER", "COVER_AND_TELA", "pc", "10"),
    ("APPLE GREEN", "COVER_AND_TELA", "yard", "10"),
    ("AQUA BLUE", "COVER_AND_TELA", "yard", "10"),
    ("AQUA GREEN", "COVER_AND_TELA", "yard", "10"),
    ("BABY PINK", "COVER_AND_TELA", "yard", "10"),
    ("BLACK", "COVER_AND_TELA", "yard", "10"),
    ("BEIGE", "COVER_AND_TELA", "yard", "10"),
    ("BLUE", "COVER_AND_TELA", "yard", "10"),
    ("BLUSH PINK", "COVER_AND_TELA", "yard", "10"),
    ("BABY BLUE", "COVER_AND_TELA", "yard", "10"),
    ("DARK BLUE", "COVER_AND_TELA", "yard", "10"),
    ("EMERALD GREEN", "COVER_AND_TELA", "yard", "10"),
    ("FUSCHA PINK", "COVER_AND_TELA", "yard", "10"),
    ("GOLD GRAY", "COVER_AND_TELA", "yard", "10"),
    ("GREEN", "COVER_AND_TELA", "yard", "10"),
    ("LAVANDER", "COVER_AND_TELA", "yard", "10"),
    ("LIGHT PINK", "COVER_AND_TELA", "yard", "10"),
    ("LIGHT YELLOW", "COVER_AND_TELA", "yard", "10"),
    ("MAROON", "COVER_AND_TELA", "yard", "10"),
    ("MUSTARD", "COVER_AND_TELA", "yard", "10"),
    ("MINT GREEN", "COVER_AND_TELA", "yard", "10"),
    ("NAVY BLUE", "COVER_AND_TELA", "yard", "10"),
    ("NEON GREEN", "COVER_AND_TELA", "yard", "10"),
    ("NEON ORANGE", "COVER_AND_TELA", "yard", "10"),
    ("OLD ROSE", "COVER_AND_TELA", "yard", "10"),
    ("ORANGE", "COVER_AND_TELA", "yard", "10"),
    ("PEACH", "COVER_AND_TELA", "yard", "10"),
    ("PURPLE", "COVER_AND_TELA", "yard", "10"),
    ("POMELO", "COVER_AND_TELA", "yard", "10"),
    ("RED", "COVER_AND_TELA", "yard", "10"),
    ("ROYAL BLUE", "COVER_AND_TELA", "yard", "10"),
    ("SILVER", "COVER_AND_TELA", "yard", "10"),
    ("SILIDON GREEN", "COVER_AND_TELA", "yard", "10"),
    ("WHITE", "COVER_AND_TELA", "yard", "10"),
    ("YELLOW", "COVER_AND_TELA", "yard", "10"),
    ("YELLOW GOLD", "COVER_AND_TELA", "yard", "10"),
    ("VIOLET", "COVER_AND_TELA", "yard", "10"),
]

TEMPLATE = Path("item_stock_template.csv")


async def insert_items() -> None:
    inserted = 0
    for name, category, unit, price in ITEMS:
        t = now()
        res = await rental_items.update_one(
            {"name": name},
            {"$setOnInsert": {
                "name": name, "category": category, "unit": unit,
                "price": d128(Decimal(price).quantize(Decimal("0.01"))),
                "total_quantity": d128(Decimal(0)), "available_quantity": d128(Decimal(0)),
                "is_active": True, "created_at": t, "updated_at": t,
            }},
            upsert=True,
        )
        if res.upserted_id is not None:
            inserted += 1
    print(f"Catalog: {inserted} new item(s) inserted, {len(ITEMS) - inserted} already existed.")


def write_template() -> None:
    with TEMPLATE.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["name", "unit", "quantity"])
        for name, _, unit, _ in ITEMS:
            w.writerow([name, unit, 0])
    print(f"Wrote {TEMPLATE}. Fill in the quantity column, save as item_stock.csv, then run:")
    print("    python seed_items.py --stock item_stock.csv")


async def apply_stock(path: str) -> None:
    updated = 0
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            name = (row.get("name") or "").strip().upper()
            try:
                qty = Decimal((row.get("quantity") or "0").strip() or "0")
            except InvalidOperation:
                print(f"  skipped {name}: quantity is not a number")
                continue
            item = await rental_items.find_one({"name": name})
            if not item:
                print(f"  skipped {name}: not in the catalog")
                continue
            if qty < 0 or (item["unit"] == "pc" and qty != qty.to_integral_value()):
                print(f"  skipped {name}: invalid quantity {qty}")
                continue
            out = dec(item["total_quantity"]) - dec(item["available_quantity"])
            if qty < out:
                print(f"  skipped {name}: {out} are currently rented out")
                continue
            await rental_items.update_one(
                {"_id": item["_id"]},
                {"$set": {"total_quantity": d128(qty), "available_quantity": d128(qty - out),
                          "updated_at": now()}})
            updated += 1
    print(f"Stock updated for {updated} item(s).")


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stock", help="CSV file with name, unit, quantity")
    args = parser.parse_args()
    await init_indexes()
    if args.stock:
        await apply_stock(args.stock)
    else:
        await insert_items()
        write_template()


if __name__ == "__main__":
    asyncio.run(main())                         