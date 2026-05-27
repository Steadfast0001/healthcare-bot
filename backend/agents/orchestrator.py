from sqlalchemy.orm import Session
from backend.agents.router_agent import route_message
from backend.agents.rag_retriever import retrieve_clinical_context
from backend.agents.synthesizer_agent import synthesize_response

def orchestrate_chat(patient_message: str, patient_history: str, db: Session) -> dict:
    # 1. Triage / Router Agent
    triage_result = route_message(patient_message)
    intent = triage_result.get("intent", "casual")
    extracted_issues = triage_result.get("extracted_issues", [])
    
    # 2. Clinical RAG Retriever
    rag_context = ""
    if intent in ["medical", "emergency"]:
        rag_context = retrieve_clinical_context(db, extracted_issues)
    else:
        rag_context = "No medical context retrieved because intent is casual."
        
    # 3. Synthesizer Agent (Doctor Persona)
    final_response = synthesize_response(
        patient_message=patient_message,
        patient_history=patient_history,
        rag_context=rag_context,
        intent=intent
    )
    
    # Add model tracking
    final_response["model"] = "multi-agent-rag-pipeline"
    return final_response
