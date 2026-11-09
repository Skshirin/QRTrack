"""Demo data: python -m app.seed   (safe to run twice). Coordinates are placeholders near Kanha - replace with real ones."""
import random
from datetime import datetime, timedelta, timezone

from geoalchemy2 import WKTElement
from sqlalchemy import select

from .db import Base, SessionLocal, engine
from .models import Asset, AssetType, ChecklistTemplate, Site, Tag, User, Zone
from .security import hash_pin
from .services.tagsheet import new_code

LAT, LNG = 17.1800, 78.2200


def yn(key, en, te, hi, fail, severity="medium"):
    return {"key": key, "type": "yesno", "label": {"en": en, "te": te, "hi": hi}, "fail_values": [fail], "severity": severity}


def photo(en="Photo of the control point", te="నియంత్రణ స్థానం ఫోటో", hi="नियंत्रण बिंदु की फोटो"):
    return {"key": "photo", "type": "photo", "required": True, "label": {"en": en, "te": te, "hi": hi}}


TYPES = [  # code, names, interval days, radius
    ("ovitrap", {"en": "Ovitrap", "te": "ఓవిట్రాప్", "hi": "ओविट्रैप"}, 7, 30),
    ("co2_trap", {"en": "CO₂ trap", "te": "CO₂ ట్రాప్", "hi": "CO₂ ट्रैप"}, 3, 30),
    ("drip_cap", {"en": "Drip line cap", "te": "డ్రిప్ లైన్ క్యాప్", "hi": "ड्रिप लाइन कैप"}, 14, 30),
    ("statue_gap", {"en": "Statue gap", "te": "విగ్రహం ఖాళీలు", "hi": "मूर्ति की दरारें"}, 14, 30),
    ("tree_hole", {"en": "Tree hole", "te": "చెట్టు తొర్ర", "hi": "पेड़ का छेद"}, 14, 30),
    ("water_pit_mat", {"en": "Water pit mat", "te": "నీటి గుంత మ్యాట్", "hi": "पानी के गड्ढे की मैट"}, 7, 30),
    ("drain", {"en": "Drain", "te": "డ్రైన్", "hi": "नाली"}, 7, 30),
]

TEMPLATES = {  # DRAFT checklists - the real ones come from Kanha's Lab
    "water_pit_mat": [
        yn("mat_in_place", "Is the mat in place?", "మ్యాట్ సరైన చోట ఉందా?", "क्या मैट अपनी जगह पर है?", "no", "high"),
        yn("standing_water", "Any standing water visible?", "నిలిచిన నీరు కనిపిస్తోందా?", "क्या पानी जमा दिख रहा है?", "yes", "high"),
        {"key": "mat_condition", "type": "choice", "label": {"en": "Mat condition", "te": "మ్యాట్ స్థితి", "hi": "मैट की स्थिति"},
         "options": [{"value": "good", "label": {"en": "Good", "te": "బాగుంది", "hi": "ठीक"}},
                     {"value": "torn", "label": {"en": "Torn", "te": "చిరిగింది", "hi": "फटी हुई"}},
                     {"value": "missing", "label": {"en": "Missing", "te": "లేదు", "hi": "गायब"}}],
         "fail_values": ["torn", "missing"], "severity": "medium"},
        photo("Photo of the pit", "గుంత ఫోటో", "गड्ढे की फोटो"),
    ],
    "ovitrap": [
        yn("water_present", "Is there water in the pot?", "కుండలో నీరు ఉందా?", "क्या बर्तन में पानी है?", "no"),
        yn("sticks_cleaned", "Sticks cleaned/replaced?", "కర్రలు శుభ్రం/మార్చారా?", "क्या डंडियाँ साफ़/बदली गईं?", "no"),
        photo(),
    ],
}


def run():
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        if db.scalar(select(Site).where(Site.name == "Kanha Shanti Vanam")):
            print("already seeded")
            return
        site = Site(name="Kanha Shanti Vanam")
        db.add(site)
        db.flush()
        zones = []
        for i, name in enumerate(["Dining", "Dormitories", "Lakeside", "Perimeter"]):
            x, y = LNG + (i % 2) * 0.004, LAT + (i // 2) * 0.004
            poly = f"POLYGON(({x} {y},{x+0.004} {y},{x+0.004} {y+0.004},{x} {y+0.004},{x} {y}))"
            z = Zone(site_id=site.id, name=name, boundary=WKTElement(poly, srid=4326))
            db.add(z)
            zones.append(z)
        types = {}
        for code, name, interval, radius in TYPES:
            t = AssetType(code=code, name=name, default_interval_days=interval, geofence_radius_m=radius)
            db.add(t)
            types[code] = t
        db.flush()
        for code, qs in TEMPLATES.items():
            db.add(ChecklistTemplate(asset_type_id=types[code].id, version=1, questions=qs))
        generic = [yn("in_good_condition", "Is it in good condition?", "మంచి స్థితిలో ఉందా?", "क्या यह ठीक स्थिति में है?", "no"), photo()]
        for code, t in types.items():
            if code not in TEMPLATES:
                db.add(ChecklistTemplate(asset_type_id=t.id, version=1, questions=generic))
        db.flush()
        users = [("Admin", "+919999900001", "admin", []), ("Manager", "+919999900002", "manager", []),
                 ("Supervisor", "+919999900003", "supervisor", [z.id for z in zones]),
                 ("Field Staff", "+919999900004", "field_staff", [z.id for z in zones[:2]])]
        for n, ph, role, zs in users:
            db.add(User(name=n, phone=ph, role=role, zone_ids=zs, pin_hash=hash_pin("1234"), email=f"{role}@example.com"))
        random.seed(7)
        now = datetime.now(timezone.utc)
        codes = list(types)
        for i in range(24):
            z = zones[i % 4]
            t = types[codes[i % len(codes)]]
            zi = i % 4
            lat = LAT + (zi // 2) * 0.004 + random.uniform(0.0003, 0.0037)
            lng = LNG + (zi % 2) * 0.004 + random.uniform(0.0003, 0.0037)
            a = Asset(type_id=t.id, zone_id=z.id, name=f"{t.name['en']} {i + 1:02d}", lat=lat, lng=lng,
                      location=WKTElement(f"POINT({lng} {lat})", srid=4326), interval_days=t.default_interval_days,
                      next_due_at=now + timedelta(days=random.randint(-6, 6)), created_at=now - timedelta(days=30))
            db.add(a)
            db.flush()
            tag = Tag(code=new_code(), asset_id=a.id, linked_at=now)
            db.add(tag)
            if i < 3:
                print("demo tag:", tag.code, "->", a.name)
        db.add_all([Tag(code=new_code()) for _ in range(5)])  # unlinked tags for the "new asset" flow
        db.commit()
        print("seeded. Logins (PIN 1234): admin +919999900001, manager ...02, supervisor ...03, field staff ...04")


if __name__ == "__main__":
    run()
