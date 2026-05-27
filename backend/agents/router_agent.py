import json
from backend.agents.llm_client import call_gemini

ROUTER_SYSTEM_PROMPT = """You are a highly efficient Medical Intent Router and Entity Extractor.
Your job is to read a patient's message and determine if it contains any medical concerns, symptoms, or health-related queries.
If it does, extract each distinct health challenge/symptom into a list.
If the message is just a casual greeting or non-medical query (like asking for a password reset, or just saying "hi"), set intent to "casual".
If the user mentions life-threatening symptoms (chest pain, stroke symptoms, heavy bleeding), set intent to "emergency".

Respond ONLY with JSON using this schema:
{
  "intent": "casual | medical | emergency",
  "extracted_issues": [
    {
      "issue": "Brief description of the issue (e.g. 'Headache')",
      "context": "Any extra details provided (e.g. 'Since yesterday', 'Swollen ankle from running')"
    }
  ]
}
"""

def route_message(patient_message: str) -> dict:
    prompt = f"Patient Message: {patient_message}"
    result = call_gemini(prompt, json_mode=True, system_instruction=ROUTER_SYSTEM_PROMPT)
    
    # Provide safe defaults if the LLM fails
    if "error" in result:
        return {
            "intent": "casual",
            "extracted_issues": []
        }
        
    return result
