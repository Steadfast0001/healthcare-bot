import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from backend import models
from backend.main import _ensure_reference_data

engine = create_engine("sqlite:///./wadocta.db")
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
db = SessionLocal()

print("Running _ensure_reference_data(db)...")
_ensure_reference_data(db)
print("Finished successfully!")

db.close()
