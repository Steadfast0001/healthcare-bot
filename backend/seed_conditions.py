import os
import csv
import urllib.request
from sqlalchemy.orm import Session
from backend.database import SessionLocal, engine
from backend import models

# Ensure tables are created (just in case, though they likely already are)
models.Base.metadata.create_all(bind=engine)

def seed_icd10():
    db: Session = SessionLocal()
    print("Downloading ICD-10 data...")
    url = "https://raw.githubusercontent.com/k4m1113/ICD-10-CSV/master/codes.csv"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        response = urllib.request.urlopen(req, timeout=15)
        lines = [line.decode('utf-8').strip() for line in response.readlines()]
    except Exception as e:
        print(f"Error downloading: {e}")
        return

    print(f"Downloaded {len(lines)} lines. Parsing and inserting...")
    
    reader = csv.reader(lines)
    
    batch_size = 5000
    batch = []
    
    print("Fetching existing conditions...")
    existing_names = set(row[0] for row in db.query(models.Condition.name).all())
    
    inserted_count = 0
    for i, row in enumerate(reader):
        if not row:
            continue
            
        if i == 0 and "Description" in row[-1]: # Skip header if present
            continue
            
        # k4m1113 CSV columns:
        # Category Code, Diagnosis Code, Full Code, Abbreviated Description, Full Description, Category Title
        if len(row) >= 5:
            full_code = row[2].strip()
            description = row[4].strip()
        elif len(row) >= 2:
            full_code = row[0].strip()
            description = row[1].strip()
        else:
            continue
            
        # Create a unique name (max 120 chars)
        name = f"{description} ({full_code})"
        if len(name) > 120:
            name = name[:117] + "..."
            
        if name in existing_names:
            continue
            
        condition = models.Condition(
            name=name,
            description=f"ICD-10 Code: {full_code}. {description}",
            severity="unknown",
            advice="Please consult a healthcare professional for an accurate diagnosis and treatment plan."
        )
        batch.append(condition)
        existing_names.add(name)
        
        if len(batch) >= batch_size:
            db.bulk_save_objects(batch)
            db.commit()
            inserted_count += len(batch)
            print(f"Inserted {inserted_count} conditions...")
            batch.clear()
            
    if batch:
        db.bulk_save_objects(batch)
        db.commit()
        inserted_count += len(batch)
        
    print(f"Done! Successfully inserted {inserted_count} new conditions.")

if __name__ == "__main__":
    seed_icd10()
