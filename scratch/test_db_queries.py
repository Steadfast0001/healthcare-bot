import os
import sys
import re

# Add project root to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from backend import models

print("Connecting to DB...")
engine = create_engine("sqlite:///./wadocta.db")
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
db = SessionLocal()

print("Connection successful.")

def _parse_list_items(text: str) -> list[str]:
    if not text:
        return []
    cleaned = text.strip()
    if cleaned.endswith("."):
        cleaned = cleaned[:-1]
    cleaned = re.sub(r'\b(or|and)\b', ',', cleaned)
    items = [item.strip() for item in cleaned.split(',') if item.strip()]
    
    final_items = []
    for item in items:
        if not item:
            continue
        item = re.sub(r'^(prevention\s*&\s*solution:\s*|causes:\s*|proposed\s*solution:\s*)', '', item, flags=re.IGNORECASE)
        if item:
            final_items.append(item[0].upper() + item[1:])
    return final_items


def _get_seek_help_conditions(condition_name: str, description: str) -> list[str]:
    name_l = condition_name.lower()
    desc_l = description.lower()
    
    if any(k in name_l or k in desc_l for k in ["back", "neck", "knee", "joint", "bone", "spine", "muscle", "sprain", "arthritis", "gout", "sciatica", "spondylitis", "tendonitis", "bursitis", "disc"]):
        return [
            "Lasts more than a few weeks",
            "Spreads down the legs",
            "Causes numbness or weakness",
            "Is severe at night",
            "Comes with fever or weight loss",
            "Causes bladder/bowel problems"
        ]
    
    if any(k in name_l or k in desc_l for k in ["cough", "breath", "lung", "bronch", "asthma", "pneumonia", "cold", "flu", "sinus", "tonsil", "throat", "respiratory"]):
        return [
            "Causes severe difficulty breathing",
            "Lips, face, or fingernails turn blue or gray",
            "Chest pain persists",
            "High fever doesn't come down",
            "Cough up blood"
        ]
        
    if any(k in name_l or k in desc_l for k in ["heart", "cardiac", "artery", "vein", "blood pressure", "hypertension", "angina", "stroke", "pulse", "tachycardia", "bradycardia"]):
        return [
            "Sudden chest pain, pressure, or squeezing",
            "Pain radiates to the jaw, neck, back, or arms",
            "Severe shortness of breath or dizziness",
            "Fainting, palpitations, or irregular heartbeat",
            "Sudden swelling in legs or ankles"
        ]
        
    if any(k in name_l or k in desc_l for k in ["stomach", "abdominal", "gut", "digest", "liver", "hepatitis", "gerd", "ulcer", "bowel", "colon", "constipation", "diarrhea", "vomit", "nausea", "gall"]):
        return [
            "Sudden, severe abdominal pain",
            "Persistent vomiting",
            "Blood in stool or vomit",
            "High fever or severe abdominal swelling",
            "Signs of severe dehydration"
        ]
        
    if any(k in name_l or k in desc_l for k in ["brain", "neurological", "seizure", "epilepsy", "migraine", "headache", "palsy", "nerve", "stroke", "dementia"]):
        return [
            "Sudden numbness or weakness on one side",
            "Sudden confusion or trouble speaking",
            "Sudden vision changes",
            "Sudden trouble walking or loss of balance",
            "Severe sudden headache with no cause"
        ]

    return [
        "Lasts more than a few days",
        "Worsens over time",
        "Is accompanied by high fever",
        "Causes severe pain",
        "Prevents normal daily activities"
    ]


def _format_condition_response(condition: models.Condition) -> str:
    causes = _parse_list_items(condition.description)
    tips = _parse_list_items(condition.advice)
    seek_help = _get_seek_help_conditions(condition.name, condition.description)
    
    response_lines = []
    response_lines.append(f"Common Causes of {condition.name}")
    for cause in causes:
        response_lines.append(cause)
    response_lines.append("When to Seek Medical Help\n")
    response_lines.append(f"See a healthcare professional if {condition.name.lower()}:\n")
    for help_item in seek_help:
        response_lines.append(help_item)
    response_lines.append("Prevention Tips")
    for tip in tips:
        response_lines.append(tip)
        
    return "\n".join(response_lines)


def _find_and_format_direct_match(message: str, db) -> dict | None:
    print("Direct match query starting...")
    lower_message = message.lower()
    conditions = db.query(models.Condition).all()
    print(f"Total conditions retrieved: {len(conditions)}")
    # Sort by length descending to match longer names first
    conditions = sorted(conditions, key=lambda c: len(c.name), reverse=True)
    
    matched_cond = None
    for cond in conditions:
        cond_name = cond.name.lower()
        escaped_name = re.escape(cond_name)
        pattern = r'\b' + escaped_name + r'\b'
        if re.search(pattern, lower_message):
            print(f"Matched condition: {cond.name}")
            matched_cond = cond
            break
            
    if not matched_cond:
        print("No match found.")
        return None
        
    reply_text = _format_condition_response(matched_cond)
    print("Formatting complete.")
    return {
        "reply": reply_text
    }

print("Running test...")
res = _find_and_format_direct_match("i have back pain", db)
if res:
    print("RESULT:")
    print(res["reply"])
else:
    print("No result.")

db.close()
