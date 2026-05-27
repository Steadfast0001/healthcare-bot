from sqlalchemy.orm import Session
from sqlalchemy import text
from backend import models

def retrieve_clinical_context(db: Session, extracted_issues: list) -> str:
    """
    Simulates a Vector DB RAG retrieval by querying the local SQLite tables
    for clinical context regarding the extracted issues.
    """
    if not extracted_issues:
        return "No specific medical issues identified."
        
    context_blocks = []
    
    for item in extracted_issues:
        issue = item.get("issue", "").lower()
        context_blocks.append(f"### Target Issue: {issue.capitalize()}")
        
        # We query the `Condition` table based on loose keyword matches
        conditions = db.query(models.Condition).filter(
            models.Condition.name.ilike(f"%{issue}%") |
            models.Condition.description.ilike(f"%{issue}%")
        ).limit(3).all()
        
        if conditions:
            for c in conditions:
                context_blocks.append(f"- **{c.name}**: {c.description}")
                context_blocks.append(f"  *Severity*: {c.severity_level}")
                context_blocks.append(f"  *Clinical Advice*: {c.typical_advice}")
                context_blocks.append(f"  *Emergency Steps*: {c.emergency_steps if c.emergency_steps else 'None'}")
        else:
            context_blocks.append(f"No direct clinical match found for '{issue}' in local DB. Provide general safe advice.")
            
        context_blocks.append("")  # spacer
        
    return "\n".join(context_blocks)
