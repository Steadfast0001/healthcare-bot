import json
from backend.agents.llm_client import call_gemini

SYNTHESIZER_SYSTEM_PROMPT = """You are an empathetic, highly professional Medical AI Assistant (Doctor Persona).
Your job is to read the patient's message, review the provided Clinical Guidelines (RAG Context), and synthesize a multi-part, beautifully formatted response.

RULES:
1. If there are multiple health challenges, address EVERY health challenge individually in your response.
2. For each challenge, explain potential causes based ONLY on the provided clinical context. Do not hallucinate treatments.
3. Give actionable, safe recommendations (e.g. rest, hydration, see a doctor).
4. If the message contains no medical issues (casual chat), respond naturally and conversationally without medical disclaimers.
5. End your response with ONE targeted follow-up question to keep the conversation interactive.
6. Return a strict JSON response.

JSON SCHEMA:
{
  "reply": "The primary response text to the user. Use Markdown for styling (headings, bullet points, etc).",
  "risk_level": "low | medium | high | emergency",
  "possible_conditions": ["List", "Of", "Conditions"],
  "recommended_action": "Clear actionable step (e.g. see a doctor)",
  "follow_up_question": "A logical next question to ask.",
  "disclaimer": "Medical disclaimer (if health issues are discussed).",
  "warning": "Critical safety warnings if emergency."
}
"""

def synthesize_response(patient_message: str, patient_history: str, rag_context: str, intent: str) -> dict:
    prompt = f"""
Patient Message: {patient_message}

Patient History:
{patient_history}

Clinical Guidelines (RAG Context):
{rag_context}

Triage Intent: {intent}
"""
    result = call_gemini(prompt, json_mode=True, system_instruction=SYNTHESIZER_SYSTEM_PROMPT)
    
    if "error" in result:
        return {
            "reply": "I'm sorry, I encountered an internal error processing your request. Please try again.",
            "risk_level": "low",
            "possible_conditions": [],
            "recommended_action": None,
            "follow_up_question": None,
            "disclaimer": "AI is prone to errors.",
            "warning": None
        }
    return result
