from datetime import datetime, timedelta, timezone
from email.mime.text import MIMEText
import json
import os
import re
import secrets
import smtplib

from fastapi import BackgroundTasks, Depends, FastAPI, HTTPException, Response, status
from fastapi.responses import HTMLResponse
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
import urllib.error
import urllib.request
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr, Field
import uuid
from typing import List, Optional
from sqlalchemy import text, func
from sqlalchemy.orm import Session
from starlette.middleware.base import BaseHTTPMiddleware

from . import models
from .database import Base, engine, get_db
from .agents.orchestrator import orchestrate_chat


# Allowed CORS origins
ALLOWED_ORIGINS_ENV = os.getenv("ALLOWED_ORIGINS", "")
allowed_origins = [o.strip() for o in ALLOWED_ORIGINS_ENV.split(",") if o.strip()]

# Local development domains
local_ip = "127.0.0.1"
try:
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(('10.255.255.255', 1))
    local_ip = s.getsockname()[0]
    s.close()
except Exception:
    pass

dev_origins = [
    "http://localhost",
    "http://127.0.0.1",
    f"http://{local_ip}",
    "https://localhost",
    "https://127.0.0.1",
    f"https://{local_ip}",
]

def is_origin_allowed(origin: str) -> bool:
    if not origin:
        return False
    if origin in allowed_origins:
        return True
    # For local development convenience, match standard local hostnames/IPs with any port
    for dev in dev_origins:
        if origin == dev or origin.startswith(dev + ":"):
            return True
    return False


class AggressiveCORSMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        origin = request.headers.get("origin")
        
        # If it's a preflight options request and not allowed, reject it or return empty
        if request.method == "OPTIONS":
            response = Response()
        else:
            response = await call_next(request)

        # Only add CORS headers if origin is allowed
        if origin and is_origin_allowed(origin):
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Allow-Credentials"] = "true"
            req_method = request.headers.get("access-control-request-method", "GET, POST, PUT, DELETE, OPTIONS")
            req_headers = request.headers.get("access-control-request-headers", "Authorization, Content-Type, Accept, Origin, User-Agent")
            response.headers["Access-Control-Allow-Methods"] = req_method
            response.headers["Access-Control-Allow-Headers"] = req_headers
            response.headers["Access-Control-Allow-Private-Network"] = "true"
        return response


def run_db_migrations():
    try:
        from sqlalchemy import inspect, text
        inspector = inspect(engine)
        columns = [col["name"] for col in inspector.get_columns("care_providers")]
        user_columns = [col["name"] for col in inspector.get_columns("users")]
        
        with engine.begin() as conn:
            db_url = str(engine.url)
            
            if "profile_picture" not in user_columns:
                print("Migration: adding profile_picture to users table...")
                conn.execute(text("ALTER TABLE users ADD COLUMN profile_picture TEXT"))
            
            if "user_id" not in columns:
                print("Migration: adding user_id to care_providers table...")
                if "sqlite" in db_url:
                    conn.execute(text("ALTER TABLE care_providers ADD COLUMN user_id TEXT REFERENCES users(id) ON DELETE CASCADE"))
                else:
                    conn.execute(text("ALTER TABLE care_providers ADD COLUMN user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE"))
                    
            if "license_number" not in columns:
                print("Migration: adding license_number to care_providers table...")
                conn.execute(text("ALTER TABLE care_providers ADD COLUMN license_number VARCHAR(50)"))
                
            if "working_experience" not in columns:
                print("Migration: adding working_experience to care_providers table...")
                conn.execute(text("ALTER TABLE care_providers ADD COLUMN working_experience VARCHAR(200)"))
                
        print("Database migrations checked/run successfully.")
    except Exception as e:
        print(f"Error running database migrations: {e}")

run_db_migrations()
Base.metadata.create_all(bind=engine)
app = FastAPI(title="Healthcare Chatbot API")
app.add_middleware(AggressiveCORSMiddleware)

SECRET_KEY = os.getenv("JWT_SECRET_KEY")
if not SECRET_KEY or SECRET_KEY == "change-me-to-a-secure-secret":
    # Prevent execution with default or missing keys in production
    # In dev, we auto-generate a random secure secret to eliminate fallback vulnerabilities
    SECRET_KEY = secrets.token_hex(32)
    print("WARNING: JWT_SECRET_KEY environment variable is not set or is insecure. "
          "A random secret key has been generated for this session. "
          "Note: Sessions will be invalidated when the server restarts.")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "1440"))
EMAIL_VERIFICATION_TOKEN_EXPIRE_HOURS = int(
    os.getenv("EMAIL_VERIFICATION_TOKEN_EXPIRE_HOURS", "24")
)
PASSWORD_RESET_TOKEN_EXPIRE_HOURS = int(
    os.getenv("PASSWORD_RESET_TOKEN_EXPIRE_HOURS", "1")
)
SMTP_HOST = os.getenv("SMTP_HOST")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
EMAIL_FROM = os.getenv("EMAIL_FROM", "no-reply@healthcare-app.local")
FRONTEND_BASE_URL = os.getenv("FRONTEND_BASE_URL", "http://localhost:8080")
GOOGLE_MODEL = os.getenv("GOOGLE_MODEL", "gemini-2.0-flash")
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

PASSWORD_PATTERN = re.compile(
    r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\w\s]).{8,}$"
)
STANDARD_DISCLAIMER = (
    "I am not a replacement for a licensed clinician. Use this guidance for education "
    "and seek professional medical care for diagnosis or treatment."
)
VALID_RISK_LEVELS = {"low", "medium", "high", "emergency"}


def _parse_retry_delay(error_text: str, default: float = 5.0) -> float:
    """Parse retryDelay seconds from a Gemini 429 error body. Returns -1.0 for hard daily limit."""
    try:
        err_json = json.loads(error_text)
        error_obj = err_json.get("error", {})
        message = error_obj.get("message", "")
        # If it's a daily quota limit, return -1.0 so we do not retry or wait
        if "FreeTier" in message or "limit: 20" in message or "Daily" in message:
            return -1.0
            
        for detail in error_obj.get("details", []):
            if detail.get("@type", "").endswith("RetryInfo"):
                delay_str = detail.get("retryDelay", "")
                # Format is e.g. "23s" or "38.3s"
                delay_str = delay_str.rstrip("s")
                return float(delay_str) + 2.0  # add 2s buffer
    except Exception:
        pass
    return default


def _call_gemini(prompt_text: str, json_mode: bool = False) -> dict:
    if not GOOGLE_API_KEY:
        raise RuntimeError("GOOGLE_API_KEY is not configured.")

    models_to_try = [GOOGLE_MODEL, "gemini-2.5-flash"]
    
    seen = set()
    unique_models = []
    for m in models_to_try:
        if m and m not in seen:
            seen.add(m)
            unique_models.append(m)

    payload = {
        "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": 2048,
            "topP": 0.95,
            "topK": 40,
        },
        "contents": [
            {
                "parts": [
                    {
                        "text": prompt_text,
                    }
                ]
            }
        ],
    }
    if json_mode:
        payload["generationConfig"]["responseMimeType"] = "application/json"
        
    request_data = json.dumps(payload).encode("utf-8")

    last_exception = None
    for model_name in unique_models:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent"
        for attempt in range(3):
            try:
                request = urllib.request.Request(
                    url,
                    data=request_data,
                    headers={
                        "Content-Type": "application/json; charset=utf-8",
                        "X-goog-api-key": GOOGLE_API_KEY,
                    },
                    method="POST",
                )
                with urllib.request.urlopen(request, timeout=60) as response:
                    res_json = json.loads(response.read().decode("utf-8"))
                    res_json["model"] = model_name
                    return res_json
            except urllib.error.HTTPError as exc:
                error_text = exc.read().decode("utf-8")
                last_exception = RuntimeError(
                    f"Gemini API error for model {model_name}: {exc.code} {exc.reason}: {error_text}"
                )
                if exc.code in (429, 503):
                    wait_sec = _parse_retry_delay(error_text)
                    if wait_sec < 0:
                        print(f"Warning: Model {model_name} hit hard daily quota limit. Skipping retry.", flush=True)
                        break
                    print(f"Warning: Model {model_name} returned {exc.code}. Waiting {wait_sec:.1f}s then retrying... ({attempt+1}/3)", flush=True)
                    import time
                    time.sleep(wait_sec)
                    continue
                else:
                    break
            except Exception as exc:
                last_exception = RuntimeError(f"Gemini request failed for model {model_name}: {exc}")
                break

    # Exhausted all models/attempts — return a safe fallback instead of raising.
    print("Warning: Gemini generateContent failed for all models; returning fallback response.", flush=True)
    return {"model": "none", "error": "generate_failed", "candidates": []}


def cosine_similarity(v1: list[float], v2: list[float]) -> float:
    dot_product = sum(x * y for x, y in zip(v1, v2))
    magnitude_1 = sum(x * x for x in v1) ** 0.5
    magnitude_2 = sum(y * y for y in v2) ** 0.5
    if magnitude_1 == 0 or magnitude_2 == 0:
        return 0.0
    return dot_product / (magnitude_1 * magnitude_2)


def _call_gemini_embedding(text: str) -> list[float]:
    if not GOOGLE_API_KEY:
        raise RuntimeError("GOOGLE_API_KEY is not configured.")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent"
    payload = {
        "model": "models/gemini-embedding-001",
        "content": {
            "parts": [{"text": text}]
        },
        "outputDimensionality": 768
    }
    request_data = json.dumps(payload).encode("utf-8")
    
    last_exception = None
    for attempt in range(3):
        try:
            request = urllib.request.Request(
                url,
                data=request_data,
                headers={
                    "Content-Type": "application/json; charset=utf-8",
                    "X-goog-api-key": GOOGLE_API_KEY,
                },
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                res_json = json.loads(response.read().decode("utf-8"))
                embedding_val = res_json["embedding"]["values"]
                return [float(x) for x in embedding_val]
        except urllib.error.HTTPError as exc:
            error_text = exc.read().decode("utf-8")
            last_exception = RuntimeError(
                f"Gemini embedding API error: {exc.code} {exc.reason}: {error_text}"
            )
            if exc.code in (429, 503):
                wait_sec = _parse_retry_delay(error_text)
                if wait_sec < 0:
                    print(f"Warning: Embedding API hit hard daily quota limit. Skipping retry.", flush=True)
                    break
                print(f"Warning: Embedding API returned {exc.code}. Waiting {wait_sec:.1f}s then retrying... ({attempt+1}/3)", flush=True)
                import time
                time.sleep(wait_sec)
                continue
            else:
                break
        except Exception as exc:
            last_exception = RuntimeError(f"Gemini embedding request failed: {exc}")
            break
            
    # Exhausted retries for embeddings — return a safe zero-vector embedding.
    print("Warning: Gemini embedding failed after retries; returning zero-vector embedding.", flush=True)
    return [0.0] * 768


def _ensure_disease_embeddings(db: Session) -> None:
    conditions = db.query(models.Condition).all()
    for condition in conditions:
        exists = db.query(models.DiseaseEmbedding).filter_by(condition_id=condition.id).first()
        if not exists:
            content_text = f"Condition: {condition.name}. Description: {condition.description}. Severity: {condition.severity}. Advice: {condition.advice}."
            # Use a fast local dummy embedding vector (768 dimensions) to avoid blocking network requests
            dummy_vector = [0.0] * 768
            db.add(
                models.DiseaseEmbedding(
                    condition_id=condition.id,
                    content=content_text,
                    embedding=json.dumps(dummy_vector)
                )
            )
    db.commit()


def query_medical_knowledge_base(query: str, db: Session) -> str:
    try:
        query_vector = _call_gemini_embedding(query)
        embeddings = db.query(models.DiseaseEmbedding).all()
        if not embeddings:
            return "No disease reference data available in the medical knowledge base."
        
        scored_conditions = []
        for emb in embeddings:
            emb_vector = json.loads(emb.embedding)
            similarity = cosine_similarity(query_vector, emb_vector)
            scored_conditions.append((similarity, emb.condition, emb.content))
        
        scored_conditions.sort(key=lambda x: x[0], reverse=True)
        top_matches = scored_conditions[:3]
        results = []
        for score, condition, content in top_matches:
            results.append(
                f"- Match Score: {score:.4f}\n"
                f"  Name: {condition.name}\n"
                f"  Severity: {condition.severity}\n"
                f"  Advice: {condition.advice}\n"
                f"  Details: {condition.description}"
            )
        return "\n\n".join(results)
    except Exception as e:
        print(f"Error querying medical knowledge base: {e}", flush=True)
        return "Failed to query the medical knowledge base due to a connection or model error."


def _classify_safety_guardrail(message: str) -> dict:
    prompt = f"""You are a medical safety classification engine. Evaluate the patient message below.
Detect if there is a true medical emergency described (e.g. severe chest pain, sudden paralysis, severe bleeding, anaphylaxis, cannot breathe).
Do not trigger an emergency for mild symptoms or if the patient explicitly negates the emergency (e.g. "no chest pain").

Return JSON ONLY matching the following schema:
{{
  "is_emergency": true | false,
  "emergency_reason": "Description of the warning indicator or null if none."
}}

Patient Message: {message}"""
    try:
        res_json = _call_gemini(prompt, json_mode=True)
        extracted_text = _extract_gemini_text(res_json)
        result = json.loads(extracted_text)
        return {
            "is_emergency": bool(result.get("is_emergency", False)),
            "emergency_reason": result.get("emergency_reason")
        }
    except Exception as e:
        print(f"Error running safety guardrail: {e}", flush=True)
        return {"is_emergency": False, "emergency_reason": None}


def _summarize_older_history(chats: list) -> str:
    if len(chats) <= 3:
        return ""
    
    older_chats = chats[:-3]
    summary_parts = []
    # Fast local compression (avoids blocking network call, saving ~2 seconds of latency)
    for chat in older_chats[-4:]:  # last 4 older chats to keep prompt size optimized
        summary_parts.append(f"User: '{chat.user_message[:50]}...' -> AI: '{chat.ai_response[:50]}...'")
    return "Topics discussed in past messages:\n" + "\n".join(summary_parts)


def _check_semantic_cache(message: str, db: Session) -> dict | None:
    try:
        import difflib
        query_vector = None
        try:
            query_vector = _call_gemini_embedding(message)
        except Exception as e:
            print(f"Warning: Gemini embedding failed in check_cache ({e}). Using text similarity fallback.", flush=True)

        cached_items = db.query(models.SemanticCache).all()
        for item in cached_items:
            # Try embedding similarity if we have a query vector and a cached vector
            if query_vector and item.query_embedding:
                try:
                    item_vector = json.loads(item.query_embedding)
                    if item_vector:
                        similarity = cosine_similarity(query_vector, item_vector)
                        if similarity > 0.92:
                            print(f"Semantic Cache hit (embedding)! Similarity: {similarity:.4f}", flush=True)
                            data = json.loads(item.response_json)
                            if "model" not in data:
                                data["model"] = "semantic-cache"
                            return data
                except Exception:
                    pass
            
            # Fallback 1: difflib SequenceMatcher
            ratio = difflib.SequenceMatcher(None, message.strip().lower(), item.query_text.strip().lower()).ratio()
            if ratio > 0.85:
                print(f"Semantic Cache hit (text ratio)! Similarity: {ratio:.4f}", flush=True)
                data = json.loads(item.response_json)
                if "model" not in data:
                    data["model"] = "semantic-cache"
                return data
                
            # Fallback 2: Token-based content overlap
            w1 = set(w.strip("?,.!") for w in message.lower().split() if len(w) > 2)
            w2 = set(w.strip("?,.!") for w in item.query_text.lower().split() if len(w) > 2)
            if w1 and w2:
                intersection = w1.intersection(w2)
                key_words = {"vital", "vitals", "bp", "pressure", "glucose", "heart", "temp", "weight", "normal", "emergency"}
                key_intersect = intersection.intersection(key_words)
                if key_intersect:
                    overlap_ratio = len(intersection) / min(len(w1), len(w2))
                    if overlap_ratio >= 0.60:
                        print(f"Semantic Cache hit (token overlap)! Score: {overlap_ratio:.4f}", flush=True)
                        data = json.loads(item.response_json)
                        if "model" not in data:
                            data["model"] = "semantic-cache"
                        return data
    except Exception as e:
        print(f"Error checking semantic cache: {e}", flush=True)
    return None


def _save_to_semantic_cache(message: str, response_dict: dict, db: Session) -> None:
    try:
        query_vector = None
        try:
            query_vector = _call_gemini_embedding(message)
        except Exception as e:
            print(f"Warning: Gemini embedding failed in save_cache ({e}). Storing cache item without embedding.", flush=True)
        
        db.add(
            models.SemanticCache(
                query_text=message,
                query_embedding=json.dumps(query_vector) if query_vector else "[]",
                response_json=json.dumps(response_dict)
            )
        )
        db.commit()
    except Exception as e:
        print(f"Error saving to semantic cache: {e}", flush=True)


def _get_tool_vitals(db: Session, current_user) -> str:
    vitals_list = db.query(models.VitalLog).filter(models.VitalLog.user_id == current_user.id).order_by(models.VitalLog.created_at.desc()).limit(5).all()
    if not vitals_list:
        return "No vitals logs recorded."
    return "\n".join([f"  * {v.created_at.strftime('%Y-%m-%d %H:%M') if v.created_at else 'N/A'}: BP={v.systolic_bp}/{v.diastolic_bp} mmHg, Glucose={v.blood_glucose} mg/dL, HR={v.heart_rate} bpm, Temp={v.temperature} C, Weight={v.weight} kg" for v in vitals_list])


def _get_tool_medications(db: Session, current_user) -> str:
    medication_list = db.query(models.ReminderAlert).filter(models.ReminderAlert.user_id == current_user.id, models.ReminderAlert.type == "medication", models.ReminderAlert.is_enabled == True).all()
    if not medication_list:
        return "No active prescribed medications."
    return "\n".join([f"  * {m.title}: {m.body} (Next dose: {m.trigger_time.strftime('%Y-%m-%d %H:%M') if m.trigger_time else 'N/A'})" for m in medication_list])


def _get_tool_activities(db: Session, current_user) -> str:
    activity_list = db.query(models.ActivityLog).filter(models.ActivityLog.user_id == current_user.id).order_by(models.ActivityLog.created_at.desc()).limit(5).all()
    if not activity_list:
        return "No activity logs recorded."
    return "\n".join([f"  * {a.created_at.strftime('%Y-%m-%d') if a.created_at else 'Unknown'}: Steps={a.steps}, Sleep={a.sleep_hours} hrs, Water={a.water_intake} ml, Meal={a.meal_notes}" for a in activity_list])


def _get_tool_goals(db: Session, current_user) -> str:
    goals_list = db.query(models.HealthGoal).filter(models.HealthGoal.user_id == current_user.id).order_by(models.HealthGoal.created_at.desc()).all()
    if not goals_list:
        return "No health goals configured."
    return "\n".join([f"  * Goal {g.goal_type}: Target={g.target_value}, Current={g.current_value}, Target Date={g.target_date.strftime('%Y-%m-%d') if g.target_date else 'N/A'}, Completed={g.is_completed}" for g in goals_list])


def _call_gemini_with_tools(prompt_text: str, current_user, db: Session) -> dict:
    if not GOOGLE_API_KEY:
        raise RuntimeError("GOOGLE_API_KEY is not configured.")

    tools_config = [
        {
            "functionDeclarations": [
                {
                    "name": "get_patient_vitals",
                    "description": "Retrieves the patient's recorded vitals (blood pressure, glucose, heart rate, temperature, weight)."
                },
                {
                    "name": "get_patient_active_medications",
                    "description": "Retrieves the list of active prescriptions and medication schedules for the patient."
                },
                {
                    "name": "get_patient_activities",
                    "description": "Retrieves the patient's logged activities (steps, sleep hours, water intake, calories)."
                },
                {
                    "name": "get_patient_goals",
                    "description": "Retrieves the patient's current health goals and their progress."
                },
                {
                    "name": "query_medical_knowledge_base",
                    "description": "Searches for matching medical guidelines, symptoms, and clinical advice for conditions/diseases.",
                    "parameters": {
                        "type": "OBJECT",
                        "properties": {
                            "query": {
                                "type": "STRING",
                                "description": "The medical term, symptom, or disease query to search for."
                            }
                        },
                        "required": ["query"]
                    }
                }
            ]
        }
    ]

    contents = []
    contents.append({
        "role": "user",
        "parts": [{"text": prompt_text}]
    })

    models_to_try = [GOOGLE_MODEL, "gemini-2.5-flash"]
    seen = set()
    unique_models = []
    for m in models_to_try:
        if m and m not in seen:
            seen.add(m)
            unique_models.append(m)

    last_exception = None
    for model_name in unique_models:
        try:
            contents_copy = list(contents)
            for iteration in range(5):
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent"
                payload = {
                    "generationConfig": {
                        "temperature": 0.2,
                        "maxOutputTokens": 2048,
                        "topP": 0.95,
                        "topK": 40,
                    },
                    "contents": contents_copy,
                    "tools": tools_config
                }
                
                request_data = json.dumps(payload).encode("utf-8")
                
                for attempt in range(3):
                    try:
                        request = urllib.request.Request(
                            url,
                            data=request_data,
                            headers={
                                "Content-Type": "application/json; charset=utf-8",
                                "X-goog-api-key": GOOGLE_API_KEY,
                            },
                            method="POST",
                        )
                        with urllib.request.urlopen(request, timeout=30) as response:
                            res_json = json.loads(response.read().decode("utf-8"))
                            res_json["model"] = model_name
                            
                            candidates = res_json.get("candidates", [])
                            if not candidates:
                                return res_json
                                
                            content_part = candidates[0].get("content", {})
                            parts = content_part.get("parts", [])
                            if not parts:
                                return res_json
                                
                            function_call = parts[0].get("functionCall")
                            if function_call:
                                fn_name = function_call["name"]
                                args = function_call.get("args", {})
                                
                                print(f"Agentic Tool Execution ({model_name}): calling {fn_name} with args {args}", flush=True)
                                result = None
                                if fn_name == "get_patient_vitals":
                                    result = _get_tool_vitals(db, current_user)
                                elif fn_name == "get_patient_active_medications":
                                    result = _get_tool_medications(db, current_user)
                                elif fn_name == "get_patient_activities":
                                    result = _get_tool_activities(db, current_user)
                                elif fn_name == "get_patient_goals":
                                    result = _get_tool_goals(db, current_user)
                                elif fn_name == "query_medical_knowledge_base":
                                    query_str = args.get("query", "")
                                    result = query_medical_knowledge_base(query_str, db)
                                else:
                                    result = "Unknown function call"
                                
                                contents_copy.append(content_part)
                                contents_copy.append({
                                    "role": "function",
                                    "parts": [
                                        {
                                            "functionResponse": {
                                                "name": fn_name,
                                                "response": {"result": result}
                                            }
                                        }
                                    ]
                                })
                                break
                            else:
                                return res_json
                    except urllib.error.HTTPError as exc:
                        error_text = exc.read().decode("utf-8")
                        last_exception = RuntimeError(
                            f"Gemini API error in tools call for model {model_name}: {exc.code} {exc.reason}: {error_text}"
                        )
                        if exc.code in (429, 503):
                            wait_sec = _parse_retry_delay(error_text)
                            if wait_sec < 0:
                                print(f"Warning: Model {model_name} in tools hit hard daily quota limit. Skipping model.", flush=True)
                                # Stop retrying this model and try next model
                                break
                            print(f"Warning: Model {model_name} in tools returned {exc.code}. Waiting {wait_sec:.1f}s... ({attempt+1}/3)", flush=True)
                            import time
                            time.sleep(wait_sec)
                            continue
                        else:
                            raise last_exception
                    except Exception as exc:
                        last_exception = RuntimeError(f"Gemini tools request failed for model {model_name}: {exc}")
                        raise last_exception
                else:
                    # Exhausted attempts for this model, move to next model
                    break
            return res_json
        except Exception as e:
            print(f"Warning: Model {model_name} failed tools run, trying next model. Error: {e}", flush=True)
            continue

    # Exhausted all models/attempts — return a safe fallback instead of raising an exception.
    print("Warning: Gemini tools generateContent failed for all models; returning fallback response.", flush=True)
    return {"model": "none", "error": "generate_failed", "candidates": []}


def _extract_gemini_text(response_json: dict) -> str:
    if not isinstance(response_json, dict):
        return json.dumps(response_json)

    candidates = response_json.get("candidates") or []
    if candidates:
        first_candidate = candidates[0]
        content = first_candidate.get("content") or first_candidate.get("output")
        if isinstance(content, dict):
            parts = content.get("parts") or []
            if isinstance(parts, list):
                text_parts = []
                for item in parts:
                    if isinstance(item, dict) and "text" in item:
                        text_parts.append(item["text"])
                    elif isinstance(item, str):
                        text_parts.append(item)
                if text_parts:
                    return "\n".join(text_parts)
        elif isinstance(content, list):
            text_parts = []
            for item in content:
                if isinstance(item, dict):
                    if "text" in item:
                        text_parts.append(item["text"])
                    elif item.get("type") == "message" and "text" in item:
                        text_parts.append(item["text"])
                elif isinstance(item, str):
                    text_parts.append(item)
            if text_parts:
                return "\n".join(text_parts)
        elif isinstance(content, str):
            return content

    output = response_json.get("output")
    if isinstance(output, str):
        return output
    if isinstance(output, list):
        collected = []
        for item in output:
            if isinstance(item, dict) and "text" in item:
                collected.append(item["text"])
            elif isinstance(item, str):
                collected.append(item)
        if collected:
            return "\n".join(collected)

    return json.dumps(response_json)


# Medical report schemas and /generate-report endpoint were removed per request.



class SignupRequest(BaseModel):
    full_name: str = Field(..., min_length=1)
    email: EmailStr
    phone_number: str | None = None
    password: str = Field(..., min_length=8)
    confirm_password: str = Field(..., min_length=8)
    username: str | None = None
    role: str = Field(default="user")
    license_number: str | None = Field(default=None)


class LoginRequest(BaseModel):
    email_or_username: str = Field(..., min_length=3)
    password: str = Field(..., min_length=8)
    remember_me: bool = False


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    token: str
    password: str = Field(..., min_length=8)
    confirm_password: str = Field(..., min_length=8)


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class SignupResponse(AuthResponse):
    message: str
    is_verified: bool
    verification_link: str | None = None


class EmergencyContactInput(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    phone_number: str = Field(..., min_length=3, max_length=30)
    allow_call: bool = True
    allow_whatsapp: bool = False


def _validate_emergency_contacts(
    contacts: list[EmergencyContactInput] | None,
) -> list[EmergencyContactInput]:
    if contacts is None:
        return []
    if len(contacts) > 10:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You can add up to 10 emergency contacts.",
        )
    for contact in contacts:
        if not contact.allow_call and not contact.allow_whatsapp:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Emergency contact '{contact.name}' must allow call or WhatsApp."
                ),
            )
    return contacts


class EmergencyContactResponse(BaseModel):
    id: str
    name: str
    phone_number: str
    allow_call: bool
    allow_whatsapp: bool
    sort_order: int


class UserResponse(BaseModel):
    id: str
    full_name: str
    email: EmailStr
    username: str | None = None
    phone_number: str | None = None
    age: int | None = None
    gender: str | None = None
    country: str | None = None
    city: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contacts: list[EmergencyContactResponse] = Field(default_factory=list)
    allergies: str | None = None
    known_conditions: str | None = None
    medical_history: str | None = None
    role: str
    is_verified: bool
    specialty: str | None = None
    provider_type: str | None = None
    working_experience: str | None = None
    license_number: str | None = None
    profile_picture: str | None = None


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)


class SymptomAssessmentRequest(BaseModel):
    symptoms: list[str] = Field(..., min_length=1)
    notes: str | None = Field(default=None, max_length=1000)


class StructuredAdvice(BaseModel):
    reply: str | None = None
    risk_level: str
    possible_conditions: list[str] = Field(default_factory=list)
    recommended_action: str | None = None
    follow_up_question: str | None = None
    disclaimer: str | None = None
    warning: str | None = None


class ChatReplyResponse(BaseModel):
    reply: str
    risk_level: str
    possible_conditions: list[str]
    recommended_action: str | None = None
    follow_up_question: str | None = None
    disclaimer: str | None = None
    warning: str | None = None
    is_emergency: bool
    model: str


class ChatHistoryItem(BaseModel):
    id: str
    user_message: str
    ai_response: str
    risk_level: str
    possible_conditions: list[str]
    recommended_action: str | None = None
    follow_up_question: str | None = None
    disclaimer: str | None = None
    warning: str | None = None
    is_emergency: bool
    created_at: datetime | None = None


class HealthTipResponse(BaseModel):
    id: int
    title: str
    content: str
    category: str | None = None


class ProviderReviewResponse(BaseModel):
    id: str
    rating: int
    review_text: str | None = None
    created_at: datetime | None = None


class ProviderReviewCreateRequest(BaseModel):
    rating: int = Field(..., ge=1, le=5)
    review_text: str | None = None


class ProviderResponse(BaseModel):
    id: str
    name: str
    provider_type: str
    specialty: str | None = None
    city: str | None = None
    country: str | None = None
    address: str | None = None
    phone_number: str | None = None
    average_rating: float = 0
    total_reviews: int = 0
    reviews: list[ProviderReviewResponse] = Field(default_factory=list)


class AppointmentCreateRequest(BaseModel):
    provider_id: str
    scheduled_at: datetime
    reason: str | None = None
    reminder_minutes_before: int = Field(default=60, ge=0, le=10080)


class AppointmentUpdateRequest(BaseModel):
    scheduled_at: datetime | None = None
    reason: str | None = None
    reminder_minutes_before: int | None = Field(default=None, ge=0, le=10080)


class AppointmentResponse(BaseModel):
    id: str
    provider: ProviderResponse
    scheduled_at: datetime
    reason: str | None = None
    status: str
    reminder_minutes_before: int
    created_at: datetime | None = None
    patient: UserResponse | None = None


class ProfileUpdateRequest(BaseModel):
    full_name: str | None = None
    phone_number: str | None = None
    age: int | None = None
    gender: str | None = None
    country: str | None = None
    city: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contacts: list[EmergencyContactInput] | None = None
    allergies: str | None = None
    known_conditions: str | None = None
    medical_history: str | None = None
    specialty: str | None = None
    provider_type: str | None = None
    working_experience: str | None = None
    license_number: str | None = None
    profile_picture: str | None = None


class VitalLogCreate(BaseModel):
    systolic_bp: int | None = Field(default=None, ge=30, le=300)
    diastolic_bp: int | None = Field(default=None, ge=20, le=200)
    blood_glucose: int | None = Field(default=None, ge=10, le=1000)
    heart_rate: int | None = Field(default=None, ge=30, le=250)
    temperature: float | None = Field(default=None, ge=30.0, le=45.0)
    weight: float | None = Field(default=None, ge=2.0, le=500.0)


class VitalLogResponse(BaseModel):
    id: str
    systolic_bp: int | None = None
    diastolic_bp: int | None = None
    blood_glucose: int | None = None
    heart_rate: int | None = None
    temperature: float | None = None
    weight: float | None = None
    created_at: datetime


class ActivityLogCreate(BaseModel):
    steps: int | None = Field(default=None, ge=0)
    calories_burned: int | None = Field(default=None, ge=0)
    water_intake: int | None = Field(default=None, ge=0)
    sleep_hours: float | None = Field(default=None, ge=0.0, le=24.0)
    calories_consumed: int | None = Field(default=None, ge=0)
    meal_notes: str | None = Field(default=None, max_length=1000)


class ActivityLogResponse(BaseModel):
    id: str
    date: datetime
    steps: int | None = None
    calories_burned: int | None = None
    water_intake: int | None = None
    sleep_hours: float | None = None
    calories_consumed: int | None = None
    meal_notes: str | None = None
    created_at: datetime


class HealthGoalCreate(BaseModel):
    goal_type: str = Field(..., min_length=2, max_length=50)
    target_value: float = Field(..., gt=0.0)
    target_date: datetime


class HealthGoalResponse(BaseModel):
    id: str
    goal_type: str
    target_value: float
    current_value: float
    start_date: datetime
    target_date: datetime
    is_completed: bool
    created_at: datetime


class HealthGoalProgressUpdate(BaseModel):
    current_value: float = Field(..., ge=0.0)


class HealthReportCreate(BaseModel):
    report_type: str = Field(..., min_length=2, max_length=30)
    period_start: datetime
    period_end: datetime


class HealthReportResponse(BaseModel):
    id: str
    report_type: str
    period_start: datetime
    period_end: datetime
    title: str
    summary: str
    data_snapshot: str
    created_at: datetime


class MedicalRecordCreate(BaseModel):
    record_type: str = Field(..., min_length=2, max_length=30)
    title: str = Field(..., min_length=1, max_length=255)
    notes: str | None = Field(default=None, max_length=2000)
    file_name: str = Field(..., min_length=1, max_length=255)
    file_data: str # base64 encoded
    file_mime: str = Field(..., min_length=3, max_length=100)
    provider_name: str | None = Field(default=None, max_length=160)
    record_date: datetime


class MedicalRecordResponse(BaseModel):
    id: str
    record_type: str
    title: str
    notes: str | None = None
    file_name: str
    file_mime: str
    file_size: int
    provider_name: str | None = None
    record_date: datetime
    created_at: datetime


class MedicalRecordDetailResponse(BaseModel):
    id: str
    record_type: str
    title: str
    notes: str | None = None
    file_name: str
    file_data: str # base64 encoded
    file_mime: str
    file_size: int
    provider_name: str | None = None
    record_date: datetime
    created_at: datetime


class RecordShareLinkCreate(BaseModel):
    share_type: str = Field(..., min_length=2, max_length=20)
    target_id: str | None = None
    recipient_name: str = Field(..., min_length=1, max_length=120)
    recipient_email: str | None = Field(default=None, max_length=120)
    expires_in_days: int = Field(default=7, ge=1, le=365)


class RecordShareLinkResponse(BaseModel):
    id: str
    share_token: str
    share_type: str
    target_id: str | None = None
    recipient_name: str
    recipient_email: str | None = None
    expires_at: datetime
    is_revoked: bool
    access_count: int
    created_at: datetime


class ReminderAlertCreate(BaseModel):
    type: str = Field(..., min_length=2, max_length=30)
    title: str = Field(..., min_length=1, max_length=255)
    body: str = Field(..., min_length=1)
    trigger_time: datetime
    metadata_json: str | None = None


class ReminderAlertResponse(BaseModel):
    id: str
    type: str
    title: str
    body: str
    trigger_time: datetime
    is_enabled: bool
    metadata_json: str | None = None
    created_at: datetime
    updated_at: datetime



def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def is_password_strong(password: str) -> bool:
    return bool(PASSWORD_PATTERN.match(password))


def create_access_token(data: dict, expires_delta: timedelta | None = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (
        expires_delta if expires_delta else timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire, "iat": datetime.utcnow()})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def generate_token() -> str:
    return secrets.token_urlsafe(32)


def send_email(recipient: str, subject: str, body: str) -> None:
    if not SMTP_HOST or not SMTP_USER or not SMTP_PASSWORD:
        print(f"[email] skipping send_email to {recipient}; SMTP not configured")
        return

    msg = MIMEText(body, "html")
    msg["Subject"] = subject
    msg["From"] = EMAIL_FROM
    msg["To"] = recipient

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=10) as server:
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.sendmail(EMAIL_FROM, [recipient], msg.as_string())


def get_current_user(
    token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)
):
    # Check if token is blacklisted/revoked
    revoked = db.query(models.RevokedToken).filter_by(token=token).first()
    if revoked:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session has been logged out. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid session token. Please log in again.",
                headers={"WWW-Authenticate": "Bearer"},
            )
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session has expired. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or corrupted session token. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    user = db.query(models.User).filter_by(id=user_id).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User account not found. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def get_current_active_user(current_user=Depends(get_current_user)):
    if not current_user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email address not verified",
        )
    return current_user


def _mentions_term(text: str, term: str) -> bool:
    return term.lower() in text.lower()


def _normalize_risk_level(value: str | None) -> str:
    normalized = (value or "").strip().lower()
    return normalized if normalized in VALID_RISK_LEVELS else "low"


def _matched_symptoms_from_text(message: str, db: Session) -> list[models.Symptom]:
    lower_message = message.lower()
    symptoms = db.query(models.Symptom).order_by(models.Symptom.name).all()
    return [
        symptom
        for symptom in symptoms
        if symptom.name and _mentions_term(lower_message, symptom.name)
    ]


def _rank_condition_matches(
    symptoms: list[models.Symptom], db: Session
) -> list[dict[str, object]]:
    ranked: dict[int, dict[str, object]] = {}

    for symptom in symptoms:
        mappings = (
            db.query(models.SymptomConditionMap)
            .filter(models.SymptomConditionMap.symptom_id == symptom.id)
            .all()
        )
        for mapping in mappings:
            condition = mapping.condition
            if condition is None:
                continue
            score = float(mapping.weight or 0)
            entry = ranked.setdefault(
                condition.id,
                {
                    "name": condition.name,
                    "severity": (condition.severity or "low").lower(),
                    "advice": condition.advice or "",
                    "description": condition.description or "",
                    "score": 0.0,
                },
            )
            entry["score"] = float(entry["score"]) + score

    return sorted(
        ranked.values(),
        key=lambda item: (
            {"emergency": 4, "high": 3, "medium": 2, "low": 1}.get(
                str(item["severity"]), 0
            ),
            float(item["score"]),
        ),
        reverse=True,
    )


import time
import re

_patient_context_cache = {}

def _get_cached_patient_context(db: Session, current_user) -> tuple[str, str, str, str]:
    now = time.time()
    if current_user.id in _patient_context_cache:
        cached_data, expires_at = _patient_context_cache[current_user.id]
        if now < expires_at:
            return cached_data
            
    vitals_list = db.query(models.VitalLog).filter(models.VitalLog.user_id == current_user.id).order_by(models.VitalLog.created_at.desc()).limit(3).all()
    symptom_list = db.query(models.SymptomAssessment).filter(models.SymptomAssessment.user_id == current_user.id).order_by(models.SymptomAssessment.created_at.desc()).limit(3).all()
    activity_list = db.query(models.ActivityLog).filter(models.ActivityLog.user_id == current_user.id).order_by(models.ActivityLog.created_at.desc()).limit(3).all()
    medication_list = db.query(models.ReminderAlert).filter(models.ReminderAlert.user_id == current_user.id, models.ReminderAlert.type == "medication", models.ReminderAlert.is_enabled == True).all()

    vitals_str = "None"
    if vitals_list:
        vitals_str = "\n".join([f"  * {v.created_at.strftime('%Y-%m-%d %H:%M')}: BP={v.systolic_bp}/{v.diastolic_bp} mmHg, Glucose={v.blood_glucose} mg/dL, HR={v.heart_rate} bpm, Temp={v.temperature} C, Weight={v.weight} kg" for v in vitals_list])
    symptoms_str = "None"
    if symptom_list:
        symptoms_str = "\n".join([f"  * {s.created_at.strftime('%Y-%m-%d %H:%M')}: Symptoms=[{s.symptoms}], Risk={s.risk_level}, Actions={s.recommended_action}" for s in symptom_list])
    activities_str = "None"
    if activity_list:
        activities_str = "\n".join([f"  * {a.created_at.strftime('%Y-%m-%d') if a.created_at else 'Unknown'}: Steps={a.steps}, Sleep={a.sleep_hours} hrs, Water={a.water_intake} ml, Meal={a.meal_notes}" for a in activity_list])
    medications_str = "None"
    if medication_list:
        medications_str = "\n".join([f"  * {m.title}: {m.body} (Next dose: {m.trigger_time.strftime('%Y-%m-%d %H:%M') if m.trigger_time else 'N/A'})" for m in medication_list])

    result = (vitals_str, symptoms_str, activities_str, medications_str)
    _patient_context_cache[current_user.id] = (result, now + 60)
    return result

def _is_negated(text: str, keyword: str) -> bool:
    pattern = r'\b(no|not|without|never|don\'t|do not|didn\'t|zero|none)\b(?:\s+\w+){0,4}\s+' + re.escape(keyword)
    return bool(re.search(pattern, text))

def _detect_emergency_keywords(message: str, db: Session) -> list[str]:
    lower_message = message.lower()
    keywords = db.query(models.EmergencyKeyword).order_by(models.EmergencyKeyword.keyword).all()
    matches = [
        keyword.keyword
        for keyword in keywords
        if keyword.keyword and keyword.keyword.lower() in lower_message
        and not _is_negated(lower_message, keyword.keyword.lower())
    ]

    fallback_keywords = [
        "chest pain",
        "severe bleeding",
        "unconscious",
        "unconsciousness",
        "cannot breathe",
        "difficulty breathing",
        "shortness of breath",
        "stroke",
        "stroke symptoms",
        "seizure",
        "severe allergic reaction",
        "suicidal thoughts",
        "severe pregnancy complications",
        "pregnancy bleeding",
    ]
    matches.extend(
        keyword for keyword in fallback_keywords 
        if keyword in lower_message 
        and keyword not in matches 
        and not _is_negated(lower_message, keyword)
    )
    return matches


def _build_database_context(
    message: str, db: Session
) -> tuple[list[str], list[dict[str, object]], list[str], str]:
    matched_symptoms = _matched_symptoms_from_text(message, db)
    symptom_names = [symptom.name for symptom in matched_symptoms if symptom.name]
    ranked_conditions = _rank_condition_matches(matched_symptoms, db)

    if ranked_conditions:
        condition_context = [
            (
                f"- Possible condition: {condition['name']} "
                f"(severity: {condition['severity']}, score: {condition['score']:.2f}) "
                f"- advice: {condition['advice']}"
            )
            for condition in ranked_conditions[:5]
        ]
    else:
        top_conditions = db.query(models.Condition).order_by(models.Condition.name).limit(6).all()
        condition_context = [
            f"- Reference condition: {condition.name} ({condition.severity}) - advice: {condition.advice}"
            for condition in top_conditions
        ]

    context = "\n".join(condition_context)
    return symptom_names, ranked_conditions, condition_context, context


def _is_health_query(message: str, db: Session) -> bool:
    symptom_names, ranked_conditions, _, _ = _build_database_context(message, db)
    emergency_matches = _detect_emergency_keywords(message, db)
    if symptom_names or ranked_conditions or emergency_matches:
        return True
    
    health_keywords = {
        "pain", "hurt", "ache", "sick", "ill", "doctor", "hospital", "clinic", "fever",
        "cough", "flu", "cold", "covid", "vomit", "nausea", "dizzy", "headache", "throat",
        "stomach", "medicine", "pill", "drug", "dose", "symptom", "disease", "infection",
        "treatment", "diagnose", "prescription", "allergy", "bleed", "wound", "injury",
        "health", "medical", "treatment", "prevent", "cure", "physician", "nurse", "vitals"
    }
    words = set(re.findall(r'\w+', message.lower()))
    if words.intersection(health_keywords):
        return True
        
    return False


def _recommended_action_for_risk(
    risk_level: str,
    ranked_conditions: list[dict[str, object]],
    emergency_matches: list[str],
) -> str:
    if risk_level == "emergency":
        reason = (
            f" because of symptoms like {', '.join(emergency_matches)}"
            if emergency_matches
            else ""
        )
        return (
            "Seek emergency medical care immediately"
            f"{reason}. Contact local emergency services or go to the nearest emergency department now."
        )
    if risk_level == "high":
        top_advice = str(ranked_conditions[0]["advice"]) if ranked_conditions else "Arrange urgent medical review."
        return f"Arrange same-day medical review. {top_advice}"
    if risk_level == "medium":
        top_advice = str(ranked_conditions[0]["advice"]) if ranked_conditions else "Book a routine clinician visit if symptoms continue."
        return f"Monitor symptoms closely and consider booking a clinician visit within 24-48 hours. {top_advice}"
    return (
        "Try home care measures like hydration, rest, and symptom monitoring. "
        "If you feel worse, develop new symptoms, or do not improve, contact a clinician."
    )


def _follow_up_question_for_context(
    symptom_names: list[str], risk_level: str
) -> str | None:
    if risk_level in {"high", "emergency"}:
        return "How long have these symptoms been happening, and are they getting worse right now?"
    if "fever" in symptom_names:
        return "Have you checked your temperature, and do you also have chills, body aches, or vomiting?"
    if "cough" in symptom_names:
        return "Is the cough dry or productive, and do you have trouble breathing or chest discomfort?"
    if symptom_names:
        return "When did these symptoms start, and is there anything that makes them better or worse?"
    return "Can you share when the symptoms began and whether anything has changed since they started?"


def _warning_for_risk(risk_level: str) -> str | None:
    if risk_level == "emergency":
        return "Potential emergency symptoms detected. Do not delay urgent care."
    if risk_level == "high":
        return "Your symptoms may need prompt medical attention today."
    return None


def _build_fallback_advice(
    message: str,
    db: Session,
    emergency_matches: list[str],
) -> StructuredAdvice:
    symptom_names, ranked_conditions, _, _ = _build_database_context(message, db)
    severity_levels = {str(condition["severity"]) for condition in ranked_conditions}

    # Heuristic check to see if this is a general query or greeting
    is_health = bool(symptom_names or ranked_conditions or emergency_matches or _is_health_query(message, db))
    
    if not is_health:
        return StructuredAdvice(
            reply="Hello! I am your AI Health Assistant. How can I help you today? Please feel free to tell me about any symptoms, ask medical questions, or check your logs.",
            risk_level="low",
            possible_conditions=[],
            recommended_action=None,
            follow_up_question=None,
            disclaimer=None,
            warning=None,
        )

    if emergency_matches:
        risk_level = "emergency"
    elif "high" in severity_levels:
        risk_level = "high"
    elif "medium" in severity_levels or len(symptom_names) >= 2:
        risk_level = "medium"
    else:
        risk_level = "low"

    # Build clear, precise reply text detailing issues, causes, and proposed solutions locally
    reply_lines = []
    if emergency_matches:
        reply_lines.append(f"⚠️ EMERGENCY WARNING: Key emergency indicators detected: {', '.join(emergency_matches)}.")
        reply_lines.append("Please seek immediate professional medical attention or visit the nearest clinic.\n")

    if ranked_conditions:
        # Get the actual condition object
        top_cond_name = ranked_conditions[0]["name"]
        cond_obj = db.query(models.Condition).filter_by(name=top_cond_name).first()
        if cond_obj:
            reply_lines.append(_format_condition_response(cond_obj))
        else:
            # Fallback formatting
            reply_lines.append(f"Common Causes of {top_cond_name}")
            causes = _parse_list_items(str(ranked_conditions[0]["description"]))
            for cause in causes:
                reply_lines.append(cause)
            reply_lines.append("When to Seek Medical Help\n")
            reply_lines.append(f"See a healthcare professional if {top_cond_name.lower()}:\n")
            seek_help = _get_seek_help_conditions(top_cond_name, str(ranked_conditions[0]["description"]))
            for help_item in seek_help:
                reply_lines.append(help_item)
            reply_lines.append("Prevention Tips")
            tips = _parse_list_items(str(ranked_conditions[0]["advice"]))
            for tip in tips:
                reply_lines.append(tip)
    else:
        reply_lines.append("No specific match found for the symptoms in our local reference database.")

    reply_text = "\n".join(reply_lines)

    return StructuredAdvice(
        reply=reply_text,
        risk_level=risk_level,
        possible_conditions=[str(condition["name"]) for condition in ranked_conditions[:3]],
        recommended_action=_recommended_action_for_risk(
            risk_level,
            ranked_conditions,
            emergency_matches,
        ),
        follow_up_question=_follow_up_question_for_context(symptom_names, risk_level),
        disclaimer=STANDARD_DISCLAIMER,
        warning=_warning_for_risk(risk_level),
    )


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


def _find_and_format_direct_match(message: str, db: Session) -> dict | None:
    lower_message = message.lower()
    conditions = db.query(models.Condition).all()
    # Sort by length descending to match longer names first
    conditions = sorted(conditions, key=lambda c: len(c.name), reverse=True)
    
    matched_cond = None
    for cond in conditions:
        cond_name = cond.name.lower()
        escaped_name = re.escape(cond_name)
        pattern = r'\b' + escaped_name + r'\b'
        if re.search(pattern, lower_message):
            matched_cond = cond
            break
            
    if not matched_cond:
        return None
        
    reply_text = _format_condition_response(matched_cond)
    
    return {
        "reply": reply_text,
        "risk_level": (matched_cond.severity or "low").lower(),
        "possible_conditions": [matched_cond.name],
        "recommended_action": matched_cond.advice or "Consult a clinician.",
        "follow_up_question": "How long have you been experiencing this, and do you have any other symptoms?",
        "disclaimer": STANDARD_DISCLAIMER,
        "warning": _warning_for_risk((matched_cond.severity or "low").lower()),
        "is_emergency": (matched_cond.severity or "low").lower() == "emergency"
    }


def _build_reply_text(advice: StructuredAdvice) -> str:
    if advice.reply and advice.reply.strip():
        return advice.reply.strip()

    lines = [f"Risk Level: {advice.risk_level}"]
    if advice.warning:
        lines.extend(["", advice.warning])
    if advice.possible_conditions:
        lines.extend(
            [
                "",
                "Possible conditions to discuss with a clinician: "
                + ", ".join(advice.possible_conditions),
            ]
        )
    lines.extend(["", f"Recommended action: {advice.recommended_action}"])
    if advice.follow_up_question:
        lines.extend(["", f"Follow-up question: {advice.follow_up_question}"])
    lines.extend(["", f"Disclaimer: {advice.disclaimer}"])
    return "\n".join(lines)


def _parse_structured_advice(raw_content: str | None) -> StructuredAdvice | None:
    if not raw_content:
        return None

    cleaned = raw_content.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines).strip()

    try:
        payload = json.loads(cleaned)
    except json.JSONDecodeError:
        return None

    if not isinstance(payload, dict):
        return None

    def clean_str(val):
        if val is None:
            return None
        s = str(val).strip()
        if s.lower() in ("none", "null", ""):
            return None
        return s

    try:
        advice = StructuredAdvice(
            reply=clean_str(payload.get("reply")),
            risk_level=_normalize_risk_level(payload.get("risk_level")),
            possible_conditions=[
                str(item).strip()
                for item in payload.get("possible_conditions", [])
                if str(item).strip() and str(item).strip().lower() not in ("none", "null")
            ],
            recommended_action=clean_str(payload.get("recommended_action")),
            follow_up_question=clean_str(payload.get("follow_up_question")),
            disclaimer=clean_str(payload.get("disclaimer")) or STANDARD_DISCLAIMER,
            warning=clean_str(payload.get("warning")),
        )
    except Exception:
        return None

    return advice


def _serialize_chat(chat: models.Chat) -> ChatHistoryItem:
    try:
        possible_conditions = json.loads(chat.possible_conditions or "[]")
        if not isinstance(possible_conditions, list):
            possible_conditions = []
    except json.JSONDecodeError:
        possible_conditions = []

    return ChatHistoryItem(
        id=str(chat.id),
        user_message=chat.user_message,
        ai_response=chat.ai_response,
        risk_level=chat.risk_level or "low",
        possible_conditions=[str(item) for item in possible_conditions],
        recommended_action=chat.recommended_action,
        follow_up_question=chat.follow_up_question,
        disclaimer=chat.disclaimer,
        warning=chat.warning,
        is_emergency=bool(chat.is_emergency),
        created_at=chat.created_at,
    )


def _serialize_provider(
    provider: models.CareProvider,
    average_rating: float = 0,
    total_reviews: int = 0,
    include_reviews: bool = True,
) -> ProviderResponse:
    return ProviderResponse(
        id=str(provider.id),
        name=provider.name,
        provider_type=provider.provider_type,
        specialty=provider.specialty,
        city=provider.city,
        country=provider.country,
        address=provider.address,
        phone_number=provider.phone_number,
        average_rating=round(float(average_rating), 1) if total_reviews else 0,
        total_reviews=total_reviews,
        reviews=[
            ProviderReviewResponse(
                id=str(review.id),
                rating=review.rating,
                review_text=review.review_text,
                created_at=review.created_at,
            )
            for review in (provider.reviews if include_reviews else [])[:5]
        ],
    )


def _serialize_appointment(appointment: models.Appointment) -> AppointmentResponse:
    provider = appointment.provider
    review_avg, review_count = (0, 0)
    if provider and provider.reviews:
        review_count = len(provider.reviews)
        review_avg = sum(review.rating for review in provider.reviews) / review_count
    return AppointmentResponse(
        id=str(appointment.id),
        provider=_serialize_provider(
            provider,
            average_rating=review_avg,
            total_reviews=review_count,
            include_reviews=False,
        ),
        scheduled_at=appointment.scheduled_at,
        reason=appointment.reason,
        status=appointment.status,
        reminder_minutes_before=appointment.reminder_minutes_before,
        created_at=appointment.created_at,
        patient=_serialize_user(appointment.user) if appointment.user else None,
    )


def _serialize_vital_log(log: models.VitalLog) -> dict:
    return {
        "id": str(log.id),
        "systolic_bp": log.systolic_bp,
        "diastolic_bp": log.diastolic_bp,
        "blood_glucose": log.blood_glucose,
        "heart_rate": log.heart_rate,
        "temperature": float(log.temperature) if log.temperature is not None else None,
        "weight": float(log.weight) if log.weight is not None else None,
        "created_at": log.created_at,
    }


def _serialize_activity_log(log: models.ActivityLog) -> dict:
    return {
        "id": str(log.id),
        "date": log.date,
        "steps": log.steps,
        "calories_burned": log.calories_burned,
        "water_intake": log.water_intake,
        "sleep_hours": float(log.sleep_hours) if log.sleep_hours is not None else None,
        "calories_consumed": log.calories_consumed,
        "meal_notes": log.meal_notes,
        "created_at": log.created_at,
    }


def _serialize_health_goal(goal: models.HealthGoal) -> dict:
    return {
        "id": str(goal.id),
        "goal_type": goal.goal_type,
        "target_value": float(goal.target_value),
        "current_value": float(goal.current_value),
        "start_date": goal.start_date,
        "target_date": goal.target_date,
        "is_completed": bool(goal.is_completed),
        "created_at": goal.created_at,
    }


def _has_appointment_conflict(
    db: Session,
    user_id: str,
    scheduled_at: datetime,
    exclude_appointment_id: str | None = None,
) -> bool:
    conflict_window = timedelta(minutes=60)
    start = scheduled_at - conflict_window
    end = scheduled_at + conflict_window
    query = db.query(models.Appointment).filter(
        models.Appointment.user_id == user_id,
        models.Appointment.status != "cancelled",
        models.Appointment.scheduled_at >= start,
        models.Appointment.scheduled_at <= end,
    )
    if exclude_appointment_id:
        query = query.filter(models.Appointment.id != exclude_appointment_id)
    return query.first() is not None


def check_provider_access_to_patient(db: Session, provider_user_id: str, patient_user_id: str) -> bool:
    provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == provider_user_id).first()
    if not provider:
        return False
    # Check if there is an appointment
    apt_exists = db.query(models.Appointment).filter(
        models.Appointment.user_id == patient_user_id,
        models.Appointment.provider_id == provider.id
    ).first() is not None
    if apt_exists:
        return True
    # Check if there is a consultation thread
    thread_exists = db.query(models.ConsultationThread).filter(
        models.ConsultationThread.user_id == patient_user_id,
        models.ConsultationThread.provider_id == provider.id
    ).first() is not None
    if thread_exists:
        return True
    return False


def add_doctor_to_emergency_contacts(db: Session, patient_user_id: str, provider_id: str) -> None:
    provider = db.query(models.CareProvider).filter(models.CareProvider.id == provider_id).first()
    if not provider or not provider.phone_number or not provider.phone_number.strip():
        return
    
    profile = db.query(models.PatientProfile).filter(models.PatientProfile.user_id == patient_user_id).first()
    if not profile:
        profile = models.PatientProfile(user_id=patient_user_id)
        db.add(profile)
        db.flush()
    
    # Check duplicate
    phone = provider.phone_number.strip()
    existing = db.query(models.EmergencyContact).filter(
        models.EmergencyContact.patient_profile_id == profile.id,
        models.EmergencyContact.phone_number == phone
    ).first()
    
    if existing:
        return
        
    contacts_count = db.query(models.EmergencyContact).filter(
        models.EmergencyContact.patient_profile_id == profile.id
    ).count()
    
    if contacts_count >= 10:
        return
        
    doc_name = provider.name.strip()
    if not doc_name.lower().startswith("dr"):
        doc_name = f"Dr. {doc_name}"
        
    new_contact = models.EmergencyContact(
        patient_profile_id=profile.id,
        name=doc_name,
        phone_number=phone,
        allow_call=True,
        allow_whatsapp=True,
        sort_order=contacts_count
    )
    db.add(new_contact)
    
    if contacts_count == 0:
        profile.emergency_contact_name = doc_name
        profile.emergency_contact_phone = phone
        
    db.flush()


def _ensure_reference_data(db: Session) -> None:
    symptom_rows = [
        ("fever", "Elevated body temperature"),
        ("headache", "Pain in the head"),
        ("cough", "Persistent coughing"),
        ("vomiting", "Throwing up"),
        ("fatigue", "Feeling tired"),
        ("chest pain", "Pain or pressure in the chest"),
        ("shortness of breath", "Difficulty breathing"),
        ("nausea", "Feeling like vomiting"),
        ("dizziness", "Feeling lightheaded or off-balance"),
        ("diarrhea", "Frequent loose, watery bowel movements"),
        ("increased thirst", "Excessive need to drink fluids"),
        ("frequent urination", "Need to urinate more often than usual"),
        ("abdominal pain", "Pain in the stomach or belly area"),
        ("burning urination", "Pain or discomfort when passing urine"),
    ]
    for name, description in symptom_rows:
        exists = db.query(models.Symptom).filter_by(name=name).first()
        if not exists:
            db.add(models.Symptom(name=name, description=description))

    condition_rows = [
        (
            "Malaria",
            "Mosquito-borne disease common in tropical areas",
            "high",
            "Seek malaria testing and treatment immediately.",
        ),
        (
            "Flu",
            "Viral respiratory infection",
            "medium",
            "Rest, hydrate, and monitor symptoms.",
        ),
        (
            "Typhoid",
            "Bacterial infection often linked to contaminated food or water",
            "high",
            "Visit a hospital or clinic for diagnosis and treatment.",
        ),
        (
            "Dehydration",
            "Loss of body fluids",
            "medium",
            "Drink oral rehydration fluids and seek care if severe.",
        ),
        (
            "Possible Emergency",
            "Symptoms may indicate an urgent medical emergency",
            "high",
            "Seek emergency medical care immediately.",
        ),
        (
            "Cholera",
            "Waterborne bacterial disease causing severe watery diarrhea, vomiting, and rapid dehydration",
            "high",
            "Start oral rehydration salts (ORS) immediately and visit a cholera treatment center.",
        ),
        (
            "Yellow Fever",
            "Mosquito-borne viral hemorrhagic disease causing fever, jaundice, and muscle pain",
            "high",
            "Seek immediate supportive treatment and clinical testing at a regional hospital.",
        ),
        (
            "Hypertension",
            "Persistent high blood pressure, potentially caused by high sodium intake, lack of exercise, stress, or genetics.",
            "high",
            "Monitor blood pressure daily, reduce dietary salt, exercise regularly, and seek medical consultation for medication.",
        ),
        (
            "Diabetes Mellitus",
            "Chronic condition characterized by high blood glucose levels due to insulin deficiency or resistance.",
            "high",
            "Monitor blood sugar levels, maintain a low-glycemic index diet, stay active, and consult an endocrinologist.",
        ),
        (
            "Gastroenteritis",
            "Inflammation of the stomach and intestines, commonly caused by viral or bacterial foodborne pathogens.",
            "medium",
            "Drink plenty of fluids (water, ORS) to prevent dehydration, rest, eat bland foods, and see a doctor if symptoms persist.",
        ),
        (
            "Urinary Tract Infection",
            "Bacterial infection of the urinary tract, commonly caused by E. coli bacteria migrating upward.",
            "medium",
            "Increase fluid intake (especially water), practice good hygiene, and seek medical consultation for appropriate antibiotics.",
        ),
        (
            "Bronchitis",
            "Inflammation of the bronchial tubes, typically caused by viral respiratory infections or smoke exposure.",
            "medium",
            "Rest, stay well-hydrated, use humidifiers, avoid smoke, and seek medical care if symptoms worsen or breathing is labored.",
        ),
    ]
    for name, description, severity, advice in condition_rows:
        exists = db.query(models.Condition).filter_by(name=name).first()
        if not exists:
            db.add(
                models.Condition(
                    name=name,
                    description=description,
                    severity=severity,
                    advice=advice,
                )
            )

    tip_rows = [
        (
            "Malaria Prevention",
            "Use insecticide-treated mosquito nets, wear long sleeves, and remove stagnant water around your home.",
            "Malaria prevention",
        ),
        (
            "Hydration Advice",
            "Drink enough clean water daily and use oral rehydration solution when dehydrated.",
            "Hydration",
        ),
        (
            "Balanced Nutrition",
            "Eat fruits, vegetables, whole grains, and lean proteins while limiting excess sugar and salt.",
            "Nutrition",
        ),
        (
            "Mental Health Check-In",
            "Make time for rest, supportive conversations, and professional help if stress feels overwhelming.",
            "Mental health",
        ),
        (
            "Sleep Hygiene",
            "Keep a regular sleep schedule and reduce screen use before bedtime.",
            "Sleep",
        ),
        (
            "Vaccination Awareness",
            "Stay up to date with recommended vaccines and talk to a health worker about local vaccination schedules.",
            "Vaccination",
        ),
        (
            "Emergency Preparedness",
            "Know your local emergency number, keep a basic first-aid kit, and act quickly if you notice danger signs.",
            "Emergency preparedness",
        ),
    ]
    for title, content, category in tip_rows:
        exists = db.query(models.HealthTip).filter_by(title=title).first()
        if not exists:
            db.add(models.HealthTip(title=title, content=content, category=category))

    emergency_rows = [
        ("chest pain", "emergency"),
        ("severe bleeding", "emergency"),
        ("unconscious", "emergency"),
        ("unconsciousness", "emergency"),
        ("cannot breathe", "emergency"),
        ("difficulty breathing", "emergency"),
        ("shortness of breath", "emergency"),
        ("stroke", "emergency"),
        ("stroke symptoms", "emergency"),
        ("seizure", "emergency"),
        ("severe allergic reaction", "emergency"),
        ("suicidal thoughts", "emergency"),
        ("severe pregnancy complications", "emergency"),
        ("pregnancy bleeding", "emergency"),
    ]
    for keyword, level in emergency_rows:
        exists = db.query(models.EmergencyKeyword).filter_by(keyword=keyword).first()
        if not exists:
            db.add(models.EmergencyKeyword(keyword=keyword, level=level))

    provider_rows = [
        ("CityCare General Hospital", "hospital", "General Medicine", "Kigali", "Rwanda", "KG 11 Ave", "+250700000001"),
        ("Hope Women's Clinic", "hospital", "Obstetrics & Gynecology", "Kigali", "Rwanda", "KK 18 St", "+250700000002"),
        ("Dr. A. Uwase", "doctor", "Family Medicine", "Kigali", "Rwanda", "Remera", "+250700000003"),
        ("Dr. J. Mensah", "doctor", "Cardiology", "Accra", "Ghana", "Airport Residential", "+233240000001"),
        ("La Quintinie Hospital Douala", "hospital", "General Medicine & Pediatrics", "Douala", "Cameroon", "Rue Hospital, Akwa", "+237699000001"),
        ("Hôpital Général de Yaoundé", "hospital", "Emergency & Specialized Care", "Yaoundé", "Cameroon", "Ngousso District", "+237699000002"),
        ("Bamenda Regional Hospital", "hospital", "General Surgery & Medicine", "Bamenda", "Cameroon", "Hospital Road", "+237699000003"),
        ("Buea Regional Hospital", "hospital", "Maternal & Child Health", "Buea", "Cameroon", "Clerks Quarters", "+237699000004"),
        ("Dr. E. Biye", "doctor", "Pediatrics", "Yaoundé", "Cameroon", "Bastos District", "+237699000005"),
        ("Dr. M. Ngassa", "doctor", "Obstetrics & Gynecology", "Douala", "Cameroon", "Bonapriso", "+237699000006"),
        ("Dr. F. Fomulu", "doctor", "Cardiology", "Bamenda", "Cameroon", "Up Station", "+237699000007"),
    ]
    for name, provider_type, specialty, city, country, address, phone in provider_rows:
        exists = (
            db.query(models.CareProvider)
            .filter(
                models.CareProvider.name == name,
                models.CareProvider.provider_type == provider_type,
            )
            .first()
        )
        if not exists:
            db.add(
                models.CareProvider(
                    name=name,
                    provider_type=provider_type,
                    specialty=specialty,
                    city=city,
                    country=country,
                    address=address,
                    phone_number=phone,
                )
            )

    db.commit()

    symptom_ids = {
        symptom.name: symptom.id
        for symptom in db.query(models.Symptom).all()
        if symptom.name
    }
    condition_ids = {
        condition.name: condition.id
        for condition in db.query(models.Condition).all()
        if condition.name
    }
    mapping_rows = [
        ("fever", "Malaria", 0.90),
        ("fever", "Flu", 0.60),
        ("fever", "Typhoid", 0.70),
        ("headache", "Malaria", 0.65),
        ("headache", "Flu", 0.50),
        ("cough", "Flu", 0.75),
        ("vomiting", "Typhoid", 0.65),
        ("vomiting", "Dehydration", 0.70),
        ("fatigue", "Dehydration", 0.85),
        ("chest pain", "Possible Emergency", 1.00),
        ("shortness of breath", "Possible Emergency", 1.00),
        ("vomiting", "Cholera", 0.80),
        ("nausea", "Cholera", 0.60),
        ("fatigue", "Cholera", 0.70),
        ("fever", "Yellow Fever", 0.85),
        ("headache", "Yellow Fever", 0.70),
        ("nausea", "Yellow Fever", 0.60),
        ("fatigue", "Yellow Fever", 0.65),
        ("dizziness", "Hypertension", 0.75),
        ("headache", "Hypertension", 0.60),
        ("chest pain", "Hypertension", 0.80),
        ("increased thirst", "Diabetes Mellitus", 0.90),
        ("frequent urination", "Diabetes Mellitus", 0.85),
        ("fatigue", "Diabetes Mellitus", 0.70),
        ("vomiting", "Gastroenteritis", 0.75),
        ("nausea", "Gastroenteritis", 0.65),
        ("abdominal pain", "Gastroenteritis", 0.80),
        ("diarrhea", "Gastroenteritis", 0.90),
        ("burning urination", "Urinary Tract Infection", 0.95),
        ("frequent urination", "Urinary Tract Infection", 0.80),
        ("fever", "Urinary Tract Infection", 0.50),
        ("cough", "Bronchitis", 0.90),
        ("shortness of breath", "Bronchitis", 0.70),
        ("fatigue", "Bronchitis", 0.60),
        ("fever", "Bronchitis", 0.50),
    ]
    for symptom_name, condition_name, weight in mapping_rows:
        symptom_id = symptom_ids.get(symptom_name)
        condition_id = condition_ids.get(condition_name)
        if symptom_id is None or condition_id is None:
            continue
        exists = (
            db.query(models.SymptomConditionMap)
            .filter_by(symptom_id=symptom_id, condition_id=condition_id)
            .first()
        )
        if not exists:
            db.add(
                models.SymptomConditionMap(
                    symptom_id=symptom_id,
                    condition_id=condition_id,
                    weight=weight,
                )
            )
    db.commit()

    provider_map = {provider.name: provider for provider in db.query(models.CareProvider).all()}
    first_user = db.query(models.User).first()
    if provider_map and first_user and not db.query(models.ProviderReview).first():
        seed_reviews = [
            ("CityCare General Hospital", 5, "Fast service and kind staff."),
            ("CityCare General Hospital", 4, "Clean environment."),
            ("Dr. A. Uwase", 5, "Very attentive consultation."),
            ("Hope Women's Clinic", 4, "Helpful and professional."),
        ]
        for provider_name, rating, review_text in seed_reviews:
            provider = provider_map.get(provider_name)
            if provider is None:
                continue
            db.add(
                models.ProviderReview(
                    provider_id=provider.id,
                    user_id=first_user.id,
                    rating=rating,
                    review_text=review_text,
                )
            )
        db.commit()

    _ensure_disease_embeddings(db)


@app.get("/", response_class=HTMLResponse)
def root():
    return """
    <html>
      <head>
        <title>Healthcare Chatbot API</title>
        <style>
          body { font-family: Arial, sans-serif; max-width: 760px; margin: 40px auto; padding: 0 16px; color: #143b2e; }
          .card { background: #f3fbf7; border: 1px solid #d7ece0; border-radius: 16px; padding: 24px; }
          code { background: #e7f4ed; padding: 2px 6px; border-radius: 6px; }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Healthcare Chatbot API</h1>
          <p>The backend is running. Use the Flutter app for the full patient experience.</p>
          <p>Helpful endpoints: <code>/health</code>, <code>/chat</code>, <code>/chat/history</code>, <code>/health-tips</code>, <code>/symptom-assessment</code>.</p>
        </div>
      </body>
    </html>
    """


@app.get("/health")
def health_check(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        return {
            "status": "ok",
            "message": "API and database are running properly.",
        }
    except Exception as exc:
        return {
            "status": "error",
            "message": f"Database connection failed: {str(exc)}",
        }


@app.post("/auth/signup", status_code=status.HTTP_201_CREATED)
def signup(
    payload: SignupRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    email = payload.email.lower().strip()
    if payload.password != payload.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Password mismatch"
        )
    if not is_password_strong(payload.password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Password must have at least 8 characters, one uppercase letter, "
                "one lowercase letter, one number, and one special character."
            ),
        )
    existing = db.query(models.User).filter(models.User.email == email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Email already exists"
        )

    username_lower = None
    if payload.username:
        username_lower = payload.username.strip().lower()
        existing_username = (
            db.query(models.User).filter(models.User.username == username_lower).first()
        )
        if existing_username:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already exists",
            )

    role = payload.role.strip().lower() if payload.role else "user"
    if role not in ["user", "provider"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid role selected. Must be 'user' or 'provider'."
        )

    if role == "provider":
        if not payload.license_number or len(payload.license_number.strip()) < 5:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A valid medical license number (minimum 5 characters) is required for healthcare providers."
            )

    user = models.User(
        full_name=payload.full_name.strip(),
        username=username_lower,
        email=email,
        phone_number=payload.phone_number.strip() if payload.phone_number else None,
        password_hash=hash_password(payload.password),
        role=role,
        is_verified=True,
        verification_token=None,
        verification_token_expires=None,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    if role == "provider":
        provider = models.CareProvider(
            name=user.full_name,
            provider_type="Doctor",
            user_id=user.id,
            license_number=payload.license_number.strip(),
            phone_number=user.phone_number,
            specialty="General Practitioner",
            country="Cameroon"
        )
        db.add(provider)
        db.commit()
        db.refresh(provider)

    expires_delta = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES * 7)
    token = create_access_token(
        {"sub": str(user.id), "email": user.email, "role": user.role},
        expires_delta,
    )

    return {
        "message": "Account created successfully.",
        "access_token": token,
        "token_type": "bearer",
        "expires_in": int(expires_delta.total_seconds()),
        "is_verified": True,
        "verification_link": None,
    }


@app.post("/auth/login", response_model=AuthResponse)
def login(payload: LoginRequest, response: Response, db: Session = Depends(get_db)):
    identifier = payload.email_or_username.strip().lower()
    user = (
        db.query(models.User)
        .filter(
            (models.User.email == identifier) | (models.User.username == identifier)
        )
        .first()
    )
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email/username or password",
        )
    if user.locked_until and user.locked_until > datetime.utcnow():
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Account temporarily locked. Try again later.",
        )
    if not verify_password(payload.password, user.password_hash):
        user.failed_login_attempts += 1
        if user.failed_login_attempts >= 5:
            user.locked_until = datetime.utcnow() + timedelta(minutes=15)
        db.add(user)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email/username or password",
        )
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account not verified",
        )

    user.failed_login_attempts = 0
    user.locked_until = None
    user.last_login_at = datetime.utcnow()
    db.add(user)
    db.commit()

    expires_delta = timedelta(
        minutes=(
            ACCESS_TOKEN_EXPIRE_MINUTES
            if not payload.remember_me
            else ACCESS_TOKEN_EXPIRE_MINUTES * 7
        )
    )
    token = create_access_token(
        {"sub": str(user.id), "email": user.email, "role": user.role},
        expires_delta,
    )
    response.set_cookie(
        key="access_token",
        value=token,
        httponly=True,
        secure=True,
        samesite="lax",
        max_age=int(expires_delta.total_seconds()),
    )
    return {
        "access_token": token,
        "token_type": "bearer",
        "expires_in": int(expires_delta.total_seconds()),
    }


@app.get("/auth/verify-email")
def verify_email(token: str, db: Session = Depends(get_db)):
    user = db.query(models.User).filter_by(verification_token=token).first()
    if (
        not user
        or not user.verification_token_expires
        or user.verification_token_expires < datetime.utcnow()
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification token",
        )
    user.is_verified = True
    user.verification_token = None
    user.verification_token_expires = None
    db.add(user)
    db.commit()
    return {"message": "Email verified successfully. You can now log in."}


@app.post("/auth/forgot-password")
def forgot_password(
    payload: ForgotPasswordRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    email = payload.email.lower().strip()
    user = db.query(models.User).filter_by(email=email).first()
    if user:
        token = generate_token()
        expires_at = datetime.utcnow() + timedelta(
            hours=PASSWORD_RESET_TOKEN_EXPIRE_HOURS
        )
        user.reset_token = token
        user.reset_token_expires = expires_at
        db.add(user)
        db.commit()
        email_body = (
            f"<p>Hi {user.full_name},</p>"
            f"<p>You requested to reset your password. Use the verification token below to reset it. The token expires in {PASSWORD_RESET_TOKEN_EXPIRE_HOURS} hour(s).</p>"
            f"<h3><b>{token}</b></h3>"
            f"<p>Copy and paste this token into the Wadocta app.</p>"
        )
        background_tasks.add_task(
            send_email,
            user.email,
            "Reset your Healthcare password",
            email_body,
        )
    return {
        "message": "If the email exists in our system, a password reset link has been sent."
    }


@app.post("/auth/reset-password")
def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    if payload.password != payload.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Password mismatch"
        )
    if not is_password_strong(payload.password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Password must have at least 8 characters, one uppercase letter, "
                "one lowercase letter, one number, and one special character."
            ),
        )
    user = db.query(models.User).filter_by(reset_token=payload.token).first()
    if (
        not user
        or not user.reset_token_expires
        or user.reset_token_expires < datetime.utcnow()
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired reset token",
        )
    user.password_hash = hash_password(payload.password)
    user.reset_token = None
    user.reset_token_expires = None
    db.add(user)
    db.commit()
    return {"message": "Password reset successfully. You can now log in."}


@app.post("/auth/logout")
def logout(
    response: Response,
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
):
    # Clear cookie if it was set
    response.delete_cookie(key="access_token")
    
    try:
        # Decode token to extract expiration
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        exp_timestamp = payload.get("exp")
        if exp_timestamp:
            # datetime.utcfromtimestamp is used since JWT exp is UTC epoch
            expires_at = datetime.utcfromtimestamp(exp_timestamp)
        else:
            expires_at = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        ) from exc
    
    # Check if already blacklisted
    exists = db.query(models.RevokedToken).filter_by(token=token).first()
    if not exists:
        revoked_token = models.RevokedToken(
            token=token,
            expires_at=expires_at
        )
        db.add(revoked_token)
        
        # Periodic cleanup of expired revoked tokens
        db.query(models.RevokedToken).filter(models.RevokedToken.expires_at < datetime.utcnow()).delete()
        
        db.commit()
        
    return {"message": "Successfully logged out"}


def _serialize_user(user: models.User) -> dict:
    if not user:
        return None
    is_provider = user.role == "provider"
    
    if is_provider:
        provider = user.care_provider
        return {
            "id": str(user.id),
            "full_name": user.full_name,
            "email": user.email,
            "username": user.username,
            "phone_number": user.phone_number,
            "age": user.age,
            "gender": user.gender,
            "country": provider.country if provider else user.country,
            "city": provider.city if provider else None,
            "emergency_contact_name": None,
            "emergency_contact_phone": None,
            "emergency_contacts": [],
            "allergies": None,
            "known_conditions": None,
            "medical_history": None,
            "role": user.role,
            "is_verified": user.is_verified,
            "specialty": provider.specialty if provider else None,
            "provider_type": provider.provider_type if provider else None,
            "working_experience": provider.working_experience if provider else None,
            "license_number": provider.license_number if provider else None,
            "profile_picture": user.profile_picture,
        }
    
    profile = user.profile
    emergency_contacts = []
    if profile:
        emergency_contacts = [
            {
                "id": str(contact.id),
                "name": contact.name,
                "phone_number": contact.phone_number,
                "allow_call": contact.allow_call,
                "allow_whatsapp": contact.allow_whatsapp,
                "sort_order": contact.sort_order,
            }
            for contact in profile.emergency_contacts
        ]
    return {
        "id": str(user.id),
        "full_name": user.full_name,
        "email": user.email,
        "username": user.username,
        "phone_number": user.phone_number,
        "age": profile.age if profile else user.age,
        "gender": profile.gender if profile else user.gender,
        "country": profile.country if profile else user.country,
        "city": profile.city if profile else None,
        "emergency_contact_name": profile.emergency_contact_name if profile else None,
        "emergency_contact_phone": profile.emergency_contact_phone if profile else None,
        "emergency_contacts": emergency_contacts,
        "allergies": profile.allergies if profile else None,
        "known_conditions": profile.known_conditions if profile else None,
        "medical_history": profile.medical_history if profile else None,
        "role": user.role,
        "is_verified": user.is_verified,
        "specialty": None,
        "provider_type": None,
        "working_experience": None,
        "license_number": None,
        "profile_picture": user.profile_picture,
    }


@app.get("/auth/me", response_model=UserResponse)
def get_me(current_user=Depends(get_current_active_user)):
    return _serialize_user(current_user)


@app.put("/auth/me", response_model=UserResponse)
def update_profile(
    payload: ProfileUpdateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if payload.full_name is not None and payload.full_name.strip():
        current_user.full_name = payload.full_name.strip()
    if payload.phone_number is not None:
        current_user.phone_number = payload.phone_number.strip() or None
    if payload.profile_picture is not None:
        current_user.profile_picture = payload.profile_picture.strip() or None

    if current_user.role == "provider":
        provider = current_user.care_provider
        if not provider:
            provider = models.CareProvider(
                name=current_user.full_name,
                provider_type="Doctor",
                user_id=current_user.id,
                specialty="General Practitioner"
            )
            db.add(provider)
            db.flush()
        
        if payload.age is not None:
            current_user.age = payload.age
        if payload.gender is not None:
            current_user.gender = payload.gender.strip() or None
        if payload.city is not None:
            provider.city = payload.city.strip() or None
        if payload.country is not None:
            provider.country = payload.country.strip() or None
            current_user.country = payload.country.strip() or None
        if payload.phone_number is not None:
            provider.phone_number = payload.phone_number.strip() or None
        if payload.specialty is not None:
            provider.specialty = payload.specialty.strip() or None
        if payload.provider_type is not None:
            provider.provider_type = payload.provider_type.strip() or None
        if payload.working_experience is not None:
            provider.working_experience = payload.working_experience.strip() or None
        if payload.license_number is not None:
            provider.license_number = payload.license_number.strip() or None

        db.add(current_user)
        db.add(provider)
        db.commit()
        db.refresh(current_user)
        return _serialize_user(current_user)

    profile = current_user.profile
    if profile is None:
        profile = models.PatientProfile(user_id=current_user.id)
        db.add(profile)
        db.flush()

    if payload.age is not None:
        profile.age = payload.age
    if payload.gender is not None:
        profile.gender = payload.gender.strip() or None
    if payload.country is not None:
        profile.country = payload.country.strip() or None
        current_user.country = payload.country.strip() or None
    if payload.city is not None:
        profile.city = payload.city.strip() or None
    incoming_contacts = _validate_emergency_contacts(payload.emergency_contacts)

    if payload.emergency_contact_name is not None:
        profile.emergency_contact_name = payload.emergency_contact_name.strip() or None
    if payload.emergency_contact_phone is not None:
        profile.emergency_contact_phone = payload.emergency_contact_phone.strip() or None
    if payload.allergies is not None:
        profile.allergies = payload.allergies.strip() or None
    if payload.known_conditions is not None:
        profile.known_conditions = payload.known_conditions.strip() or None
    if payload.medical_history is not None:
        profile.medical_history = payload.medical_history.strip() or None
    if payload.emergency_contacts is not None:
        profile.emergency_contacts.clear()
        for index, contact in enumerate(incoming_contacts):
            profile.emergency_contacts.append(
                models.EmergencyContact(
                    name=contact.name.strip(),
                    phone_number=contact.phone_number.strip(),
                    allow_call=contact.allow_call,
                    allow_whatsapp=contact.allow_whatsapp,
                    sort_order=index,
                )
            )
        if incoming_contacts:
            first_contact = incoming_contacts[0]
            profile.emergency_contact_name = first_contact.name.strip()
            profile.emergency_contact_phone = first_contact.phone_number.strip()
        else:
            profile.emergency_contact_name = None
            profile.emergency_contact_phone = None

    db.add(current_user)
    db.add(profile)
    db.commit()
    db.refresh(current_user)

    return _serialize_user(current_user)


@app.post("/seed")
def seed_database(db: Session = Depends(get_db)):
    _ensure_reference_data(db)
    return {"message": "Reference data seeded successfully."}


@app.get("/health-tips", response_model=list[HealthTipResponse])
def get_health_tips(db: Session = Depends(get_db)):
    _ensure_reference_data(db)
    tips = db.query(models.HealthTip).order_by(models.HealthTip.category, models.HealthTip.title).all()
    return [
        HealthTipResponse(
            id=tip.id,
            title=tip.title,
            content=tip.content,
            category=tip.category,
        )
        for tip in tips
    ]


@app.get("/providers/search", response_model=list[ProviderResponse])
def search_providers(
    query: str | None = None,
    provider_type: str | None = None,
    city: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    _ensure_reference_data(db)
    provider_query = db.query(models.CareProvider)
    if provider_type:
        provider_query = provider_query.filter(
            models.CareProvider.provider_type == provider_type.lower().strip()
        )
    if city:
        provider_query = provider_query.filter(
            func.lower(models.CareProvider.city) == city.lower().strip()
        )
    if query:
        term = f"%{query.lower().strip()}%"
        provider_query = provider_query.filter(
            (func.lower(models.CareProvider.name).like(term))
            | (func.lower(models.CareProvider.specialty).like(term))
            | (func.lower(models.CareProvider.city).like(term))
        )

    providers = provider_query.order_by(models.CareProvider.name.asc()).limit(50).all()
    items: list[ProviderResponse] = []
    for provider in providers:
        review_count = len(provider.reviews)
        review_avg = (
            sum(review.rating for review in provider.reviews) / review_count
            if review_count
            else 0
        )
        items.append(
            _serialize_provider(
                provider,
                average_rating=review_avg,
                total_reviews=review_count,
                include_reviews=True,
            )
        )
    return items


@app.post("/appointments", response_model=AppointmentResponse)
def book_appointment(
    payload: AppointmentCreateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    provider = (
        db.query(models.CareProvider)
        .filter(models.CareProvider.id == payload.provider_id.strip())
        .first()
    )
    if not provider:
        raise HTTPException(status_code=404, detail="Provider not found")
    if payload.scheduled_at < datetime.now(timezone.utc):
        raise HTTPException(
            status_code=400, detail="Appointment time must be in the future"
        )
    if _has_appointment_conflict(db, current_user.id, payload.scheduled_at):
        raise HTTPException(
            status_code=409,
            detail=(
                "You already have another appointment within 60 minutes of this time."
            ),
        )

    appointment = models.Appointment(
        user_id=current_user.id,
        provider_id=provider.id,
        scheduled_at=payload.scheduled_at,
        reason=payload.reason.strip() if payload.reason else None,
        status="booked",
        reminder_minutes_before=payload.reminder_minutes_before,
    )
    db.add(appointment)
    db.commit()
    db.refresh(appointment)
    return _serialize_appointment(appointment)


@app.get("/appointments", response_model=list[AppointmentResponse])
def list_appointments(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            return []
        appointments = (
            db.query(models.Appointment)
            .join(models.User, models.Appointment.user_id == models.User.id)
            .filter(
                models.Appointment.provider_id == provider.id,
                models.User.role == "user"
            )
            .order_by(models.Appointment.scheduled_at.asc())
            .all()
        )
    else:
        appointments = (
            db.query(models.Appointment)
            .filter(models.Appointment.user_id == current_user.id)
            .order_by(models.Appointment.scheduled_at.asc())
            .all()
        )
    return [_serialize_appointment(item) for item in appointments]


@app.patch("/appointments/{appointment_id}/reschedule", response_model=AppointmentResponse)
def reschedule_appointment(
    appointment_id: str,
    payload: AppointmentUpdateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Appointment not found")
        appointment = (
            db.query(models.Appointment)
            .filter(
                models.Appointment.id == appointment_id,
                models.Appointment.provider_id == provider.id,
            )
            .first()
        )
    else:
        appointment = (
            db.query(models.Appointment)
            .filter(
                models.Appointment.id == appointment_id,
                models.Appointment.user_id == current_user.id,
            )
            .first()
        )

    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if appointment.status == "cancelled":
        raise HTTPException(
            status_code=400, detail="Cancelled appointments cannot be rescheduled"
        )
    if payload.scheduled_at is not None:
        if payload.scheduled_at < datetime.now(timezone.utc):
            raise HTTPException(
                status_code=400, detail="Appointment time must be in the future"
            )
        if _has_appointment_conflict(
            db,
            appointment.user_id,
            payload.scheduled_at,
            exclude_appointment_id=appointment.id,
        ):
            raise HTTPException(
                status_code=409,
                detail=(
                    "The patient already has another appointment within 60 minutes of this time."
                ),
            )
        appointment.scheduled_at = payload.scheduled_at
    if payload.reason is not None:
        appointment.reason = payload.reason.strip() or None
    if payload.reminder_minutes_before is not None:
        appointment.reminder_minutes_before = payload.reminder_minutes_before
    appointment.status = "rescheduled"
    db.add(appointment)
    db.commit()
    db.refresh(appointment)
    return _serialize_appointment(appointment)


@app.patch("/appointments/{appointment_id}/cancel", response_model=AppointmentResponse)
def cancel_appointment(
    appointment_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Appointment not found")
        appointment = (
            db.query(models.Appointment)
            .filter(
                models.Appointment.id == appointment_id,
                models.Appointment.provider_id == provider.id,
            )
            .first()
        )
    else:
        appointment = (
            db.query(models.Appointment)
            .filter(
                models.Appointment.id == appointment_id,
                models.Appointment.user_id == current_user.id,
            )
            .first()
        )

    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    appointment.status = "cancelled"
    db.add(appointment)
    db.commit()
    db.refresh(appointment)
    return _serialize_appointment(appointment)


@app.get("/appointments/{appointment_id}/reminder")
def appointment_reminder_preview(
    appointment_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    appointment = (
        db.query(models.Appointment)
        .filter(
            models.Appointment.id == appointment_id,
            models.Appointment.user_id == current_user.id,
        )
        .first()
    )
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    reminder_at = appointment.scheduled_at - timedelta(
        minutes=appointment.reminder_minutes_before
    )
    return {
        "message": "Reminder configured successfully.",
        "appointment_id": str(appointment.id),
        "provider_name": appointment.provider.name if appointment.provider else None,
        "scheduled_at": appointment.scheduled_at,
        "reminder_at": reminder_at,
        "notification_channel": "in-app",
    }


@app.post("/providers/{provider_id}/reviews", response_model=ProviderResponse)
def submit_provider_review(
    provider_id: str,
    payload: ProviderReviewCreateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    provider = db.query(models.CareProvider).filter(models.CareProvider.id == provider_id).first()
    if not provider:
        raise HTTPException(status_code=404, detail="Provider not found")

    existing_review = (
        db.query(models.ProviderReview)
        .filter(
            models.ProviderReview.provider_id == provider.id,
            models.ProviderReview.user_id == current_user.id,
        )
        .first()
    )
    if existing_review:
        existing_review.rating = payload.rating
        existing_review.review_text = (
            payload.review_text.strip() if payload.review_text else None
        )
        db.add(existing_review)
    else:
        db.add(
            models.ProviderReview(
                provider_id=provider.id,
                user_id=current_user.id,
                rating=payload.rating,
                review_text=payload.review_text.strip()
                if payload.review_text
                else None,
            )
        )
    db.commit()
    db.refresh(provider)

    review_count = len(provider.reviews)
    review_avg = (
        sum(review.rating for review in provider.reviews) / review_count
        if review_count
        else 0
    )
    return _serialize_provider(
        provider,
        average_rating=review_avg,
        total_reviews=review_count,
        include_reviews=True,
    )


@app.get("/chat/history", response_model=list[ChatHistoryItem])
def get_chat_history(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    chats = (
        db.query(models.Chat)
        .filter(models.Chat.user_id == current_user.id)
        .order_by(models.Chat.created_at.asc())
        .all()
    )
    return [_serialize_chat(chat) for chat in chats]


@app.delete("/chat/history")
def clear_chat_history(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    db.query(models.Chat).filter(models.Chat.user_id == current_user.id).delete()
    db.query(models.AiLog).filter(models.AiLog.user_id == current_user.id).delete()
    db.commit()
    return {"message": "Chat history cleared."}


@app.post("/symptom-assessment", response_model=ChatReplyResponse)
def assess_symptoms(
    payload: SymptomAssessmentRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    _ensure_reference_data(db)
    symptom_text = ", ".join(symptom.strip().lower() for symptom in payload.symptoms if symptom.strip())
    notes = payload.notes.strip() if payload.notes else ""
    composite_message = symptom_text if not notes else f"{symptom_text}. Notes: {notes}"
    emergency_matches = _detect_emergency_keywords(composite_message, db)
    advice = _build_fallback_advice(composite_message, db, emergency_matches)
    reply = _build_reply_text(advice)

    chat = models.Chat(
        user_id=current_user.id,
        user_message=f"Symptom assessment: {composite_message}",
        ai_response=reply,
        risk_level=advice.risk_level,
        possible_conditions=json.dumps(advice.possible_conditions),
        recommended_action=advice.recommended_action,
        follow_up_question=advice.follow_up_question,
        disclaimer=advice.disclaimer,
        warning=advice.warning,
        is_emergency=advice.risk_level == "emergency",
    )
    db.add(chat)
    assessment = models.SymptomAssessment(
        user_id=current_user.id,
        symptoms=json.dumps([s.strip() for s in payload.symptoms if s.strip()]),
        notes=notes or None,
        risk_level=advice.risk_level,
        possible_conditions=json.dumps(advice.possible_conditions),
        recommended_action=advice.recommended_action,
    )
    db.add(assessment)
    db.commit()

    return ChatReplyResponse(
        reply=reply,
        risk_level=advice.risk_level,
        possible_conditions=advice.possible_conditions,
        recommended_action=advice.recommended_action,
        follow_up_question=advice.follow_up_question,
        disclaimer=advice.disclaimer,
        warning=advice.warning,
        is_emergency=advice.risk_level == "emergency",
        model="rules-and-db",
    )


@app.post("/chat", response_model=ChatReplyResponse)
async def chat(
    req: ChatRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    print("--- CHAT ENDPOINT HIT! ---", flush=True)
    print("Checking reference data...", flush=True)
    _ensure_reference_data(db)
    print("Reference data checked.", flush=True)
    patient_message = req.message.strip()
    print(f"Patient message: {patient_message}", flush=True)

    # 0. Direct match check for 300+ health issues (conditions)
    print("Checking direct match...", flush=True)
    direct_match = _find_and_format_direct_match(patient_message, db)
    print(f"Direct match found: {direct_match is not None}", flush=True)
    if direct_match:
        # Save to database
        print("Inserting chat log to DB...", flush=True)
        chat_log = models.Chat(
            user_id=current_user.id,
            user_message=patient_message,
            ai_response=direct_match["reply"],
            risk_level=direct_match["risk_level"],
            possible_conditions=json.dumps(direct_match["possible_conditions"]),
            recommended_action=direct_match["recommended_action"],
            follow_up_question=direct_match["follow_up_question"],
            disclaimer=direct_match["disclaimer"],
            warning=direct_match["warning"],
            is_emergency=direct_match["is_emergency"],
        )
        db.add(chat_log)
        
        ai_log = models.AiLog(
            user_id=current_user.id,
            prompt_tokens=0,
            completion_tokens=0,
            model_used="direct-match-local-db",
            response_time_ms=1,
        )
        db.add(ai_log)
        print("Committing to DB...", flush=True)
        db.commit()
        print("Committed successfully.", flush=True)
        
        return ChatReplyResponse(
            reply=direct_match["reply"],
            risk_level=direct_match["risk_level"],
            possible_conditions=direct_match["possible_conditions"],
            recommended_action=direct_match["recommended_action"],
            follow_up_question=direct_match["follow_up_question"],
            disclaimer=direct_match["disclaimer"],
            warning=direct_match["warning"],
            is_emergency=direct_match["is_emergency"],
            model="direct-match-local-db",
        )

    # 1. Semantic Cache check
    cached_reply = _check_semantic_cache(patient_message, db)
    if cached_reply:
        chat_log = models.Chat(
            user_id=current_user.id,
            user_message=patient_message,
            ai_response=cached_reply["reply"],
            risk_level=cached_reply["risk_level"],
            possible_conditions=json.dumps(cached_reply["possible_conditions"]),
            recommended_action=cached_reply["recommended_action"],
            follow_up_question=cached_reply["follow_up_question"],
            disclaimer=cached_reply["disclaimer"],
            warning=cached_reply["warning"],
            is_emergency=cached_reply["is_emergency"],
        )
        db.add(chat_log)
        db.commit()
        return ChatReplyResponse(**cached_reply)

    # 2. Sliding Window memory & summarization
    recent_chats = (
        db.query(models.Chat)
        .filter(models.Chat.user_id == current_user.id)
        .order_by(models.Chat.created_at.desc())
        .limit(10)
        .all()
    )
    recent_chats.reverse()
    
    older_summary = _summarize_older_history(recent_chats)
    patient_history = f"Summary of older conversation:\n{older_summary}\n\nRecent messages:\n"
    for previous_chat in (recent_chats[-3:] if len(recent_chats) > 3 else recent_chats):
        patient_history += f"Patient: {previous_chat.user_message}\nDoctor: {previous_chat.ai_response}\n"

    start_time = time.time()
    
    # NEW MULTI-AGENT RAG ARCHITECTURE
    import time
    response_json = orchestrate_chat(patient_message, patient_history, db)
    
    reply_text = response_json.get("reply", "I'm sorry, I couldn't process that.")
    risk_level = response_json.get("risk_level", "low")
    possible_conditions = response_json.get("possible_conditions", [])
    recommended_action = response_json.get("recommended_action")
    follow_up_question = response_json.get("follow_up_question")
    disclaimer = response_json.get("disclaimer")
    warning = response_json.get("warning")
    model_used = response_json.get("model", "multi-agent-rag-pipeline")
    is_emergency = risk_level == "emergency"
    
    duration_ms = int((time.time() - start_time) * 1000)

    chat_log = models.Chat(
        user_id=current_user.id,
        user_message=patient_message,
        ai_response=reply_text,
        risk_level=risk_level,
        possible_conditions=json.dumps(possible_conditions),
        recommended_action=recommended_action,
        follow_up_question=follow_up_question,
        disclaimer=disclaimer,
        warning=warning,
        is_emergency=is_emergency,
    )
    db.add(chat_log)

    ai_log = models.AiLog(
        user_id=current_user.id,
        prompt_tokens=0,
        completion_tokens=0,
        model_used=model_used,
        response_time_ms=duration_ms,
    )
    db.add(ai_log)
    db.commit()

    response_payload = {
        "reply": reply_text,
        "risk_level": risk_level,
        "possible_conditions": possible_conditions,
        "recommended_action": recommended_action,
        "follow_up_question": follow_up_question,
        "disclaimer": disclaimer,
        "warning": warning,
        "is_emergency": is_emergency,
        "model": model_used,
    }
    _save_to_semantic_cache(patient_message, response_payload, db)

    return ChatReplyResponse(**response_payload)


# ============================================================================
# Health Tracker Endpoints
# ============================================================================

@app.post("/health-tracker/vitals", response_model=VitalLogResponse)
def log_vitals(
    payload: VitalLogCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    vital_log = models.VitalLog(
        user_id=current_user.id,
        systolic_bp=payload.systolic_bp,
        diastolic_bp=payload.diastolic_bp,
        blood_glucose=payload.blood_glucose,
        heart_rate=payload.heart_rate,
        temperature=payload.temperature,
        weight=payload.weight,
    )
    db.add(vital_log)
    db.commit()
    db.refresh(vital_log)
    return _serialize_vital_log(vital_log)


@app.get("/health-tracker/vitals", response_model=list[VitalLogResponse])
def get_vitals(
    patient_id: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    target_user_id = current_user.id
    if patient_id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, patient_id):
            raise HTTPException(status_code=403, detail="Not authorized to view this patient's vitals")
        target_user_id = patient_id

    logs = (
        db.query(models.VitalLog)
        .filter(models.VitalLog.user_id == target_user_id)
        .order_by(models.VitalLog.created_at.desc())
        .limit(100)
        .all()
    )
    return [_serialize_vital_log(log) for log in logs]


@app.post("/health-tracker/activity", response_model=ActivityLogResponse)
def log_activity(
    payload: ActivityLogCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    activity_log = models.ActivityLog(
        user_id=current_user.id,
        steps=payload.steps,
        calories_burned=payload.calories_burned,
        water_intake=payload.water_intake,
        sleep_hours=payload.sleep_hours,
        calories_consumed=payload.calories_consumed,
        meal_notes=payload.meal_notes,
    )
    db.add(activity_log)
    db.commit()
    db.refresh(activity_log)
    return _serialize_activity_log(activity_log)


@app.get("/health-tracker/activity", response_model=list[ActivityLogResponse])
def get_activity_logs(
    patient_id: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    target_user_id = current_user.id
    if patient_id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, patient_id):
            raise HTTPException(status_code=403, detail="Not authorized to view this patient's activity logs")
        target_user_id = patient_id

    logs = (
        db.query(models.ActivityLog)
        .filter(models.ActivityLog.user_id == target_user_id)
        .order_by(models.ActivityLog.date.desc())
        .limit(100)
        .all()
    )
    return [_serialize_activity_log(log) for log in logs]


@app.post("/health-tracker/goals", response_model=HealthGoalResponse)
def create_goal(
    payload: HealthGoalCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    goal = models.HealthGoal(
        user_id=current_user.id,
        goal_type=payload.goal_type,
        target_value=payload.target_value,
        target_date=payload.target_date,
        current_value=0.0,
        is_completed=False,
    )
    db.add(goal)
    db.commit()
    db.refresh(goal)
    return _serialize_health_goal(goal)


@app.get("/health-tracker/goals", response_model=list[HealthGoalResponse])
def get_goals(
    patient_id: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    target_user_id = current_user.id
    if patient_id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, patient_id):
            raise HTTPException(status_code=403, detail="Not authorized to view this patient's health goals")
        target_user_id = patient_id

    goals = (
        db.query(models.HealthGoal)
        .filter(models.HealthGoal.user_id == target_user_id)
        .order_by(models.HealthGoal.created_at.desc())
        .all()
    )
    return [_serialize_health_goal(goal) for goal in goals]


@app.patch("/health-tracker/goals/{goal_id}/progress", response_model=HealthGoalResponse)
def update_goal_progress(
    goal_id: str,
    payload: HealthGoalProgressUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    goal = (
        db.query(models.HealthGoal)
        .filter(
            models.HealthGoal.id == goal_id,
            models.HealthGoal.user_id == current_user.id,
        )
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")

    goal.current_value = payload.current_value
    if goal.current_value >= goal.target_value:
        goal.is_completed = True
    else:
        goal.is_completed = False

    db.add(goal)
    db.commit()
    db.refresh(goal)
    return _serialize_health_goal(goal)


@app.delete("/health-tracker/goals/{goal_id}")
def delete_goal(
    goal_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    goal = (
        db.query(models.HealthGoal)
        .filter(
            models.HealthGoal.id == goal_id,
            models.HealthGoal.user_id == current_user.id,
        )
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")

    db.delete(goal)
    db.commit()
    return {"message": "Goal deleted successfully"}


# ==============================================================================
# CONSULTATIONS
# ==============================================================================

class ThreadCreateRequest(BaseModel):
    provider_id: str
    subject: str = Field(default="", max_length=255)
    consultation_type: str = Field(default="chat")  # 'chat' | 'video_request' | 'voice_request'
    opening_message: str = Field(default="", max_length=4000)
    patient_id: str | None = None


class MessageCreateRequest(BaseModel):
    body: str = Field(default="", max_length=4000)
    attachment_name: str | None = None
    attachment_data: str | None = None   # base64-encoded file content
    attachment_mime: str | None = None


class CallRequestBody(BaseModel):
    call_type: str = Field(default="video")   # 'video' | 'voice'
    scheduled_call_at: str | None = None      # ISO-8601 datetime string


def _thread_to_dict(thread: models.ConsultationThread) -> dict:
    unread = sum(1 for m in thread.messages if not m.is_read and m.sender_role != "patient")
    last_msg = thread.messages[-1] if thread.messages else None
    return {
        "id": str(thread.id),
        "user_id": str(thread.user_id),
        "patient_name": thread.user.full_name if thread.user else "",
        "patient_profile_picture": thread.user.profile_picture if thread.user else None,
        "provider_id": str(thread.provider_id),
        "provider_name": thread.provider.name if thread.provider else "",
        "provider_specialty": thread.provider.specialty if thread.provider else "",
        "provider_profile_picture": thread.provider.user.profile_picture if (thread.provider and thread.provider.user) else None,
        "subject": thread.subject or "",
        "consultation_type": thread.consultation_type,
        "status": thread.status,
        "scheduled_call_at": thread.scheduled_call_at.isoformat() if thread.scheduled_call_at else None,
        "unread_count": unread,
        "last_message": last_msg.body if last_msg else None,
        "last_message_at": last_msg.created_at.isoformat() if last_msg else thread.created_at.isoformat(),
        "created_at": thread.created_at.isoformat(),
        "updated_at": thread.updated_at.isoformat() if thread.updated_at else thread.created_at.isoformat(),
    }


def _message_to_dict(msg: models.ConsultationMessage) -> dict:
    # Estimate attachment size in bytes from base64 string length
    attachment_size: int | None = None
    if msg.attachment_data:
        attachment_size = int(len(msg.attachment_data) * 3 / 4)
    return {
        "id": str(msg.id),
        "thread_id": str(msg.thread_id),
        "sender_role": msg.sender_role,
        "body": msg.body or "",
        "attachment_name": msg.attachment_name,
        "attachment_data": msg.attachment_data,
        "attachment_mime": msg.attachment_mime,
        "attachment_size": attachment_size,
        "is_read": msg.is_read,
        "created_at": msg.created_at.isoformat(),
    }


@app.get("/consultations/unread-count")
async def get_consultation_unread_count(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    """Return total unread incoming messages across all threads."""
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            return {"unread_count": 0}
        count = (
            db.query(models.ConsultationMessage)
            .join(models.ConsultationThread, models.ConsultationMessage.thread_id == models.ConsultationThread.id)
            .filter(
                models.ConsultationThread.provider_id == provider.id,
                models.ConsultationMessage.is_read == False,  # noqa: E712
                models.ConsultationMessage.sender_role == "patient",
            )
            .count()
        )
    else:
        count = (
            db.query(models.ConsultationMessage)
            .join(models.ConsultationThread, models.ConsultationMessage.thread_id == models.ConsultationThread.id)
            .filter(
                models.ConsultationThread.user_id == current_user.id,
                models.ConsultationMessage.is_read == False,  # noqa: E712
                models.ConsultationMessage.sender_role != "patient",
            )
            .count()
        )
    return {"unread_count": count}


@app.get("/consultations/threads")
async def list_consultation_threads(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            return []
        threads = (
            db.query(models.ConsultationThread)
            .filter(models.ConsultationThread.provider_id == provider.id)
            .order_by(models.ConsultationThread.updated_at.desc())
            .all()
        )
    else:
        threads = (
            db.query(models.ConsultationThread)
            .filter(models.ConsultationThread.user_id == current_user.id)
            .order_by(models.ConsultationThread.updated_at.desc())
            .all()
        )
    return [_thread_to_dict(t) for t in threads]


@app.post("/consultations/threads", status_code=201)
async def create_consultation_thread(
    req: ThreadCreateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(
            models.CareProvider.user_id == current_user.id
        ).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Provider profile not found for this user")
        if not req.patient_id:
            raise HTTPException(status_code=400, detail="patient_id is required when creating a thread as a provider")
        patient_id = req.patient_id
    else:
        provider = db.query(models.CareProvider).filter(
            models.CareProvider.id == req.provider_id
        ).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Provider not found")
        patient_id = str(current_user.id)

    valid_types = {"chat", "video_request", "voice_request"}
    ctype = req.consultation_type if req.consultation_type in valid_types else "chat"

    thread = models.ConsultationThread(
        user_id=patient_id,
        provider_id=provider.id,
        subject=req.subject.strip() or f"Consultation with {provider.name}",
        consultation_type=ctype,
        status="active",
    )
    db.add(thread)
    db.flush()  # get thread.id

    # Auto-create opening message if provided
    if req.opening_message.strip():
        opening = models.ConsultationMessage(
            thread_id=thread.id,
            sender_role="provider" if current_user.role == "provider" else "patient",
            body=req.opening_message.strip(),
            is_read=True,
        )
        db.add(opening)

    # If video or voice request, add a system message
    if ctype in ("video_request", "voice_request"):
        call_label = "video" if ctype == "video_request" else "voice"
        system_msg = models.ConsultationMessage(
            thread_id=thread.id,
            sender_role="system",
            body=f"📞 {call_label.capitalize()} call requested. Waiting for provider to confirm a time.",
            is_read=True,
        )
        db.add(system_msg)

    # Auto-register doctor in emergency contacts
    if current_user.role != "provider":
        add_doctor_to_emergency_contacts(db, current_user.id, provider.id)

    db.commit()
    db.refresh(thread)
    return _thread_to_dict(thread)


@app.get("/consultations/threads/{thread_id}")
async def get_consultation_thread(
    thread_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Thread not found")
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.provider_id == provider.id,
        ).first()
    else:
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.user_id == current_user.id,
        ).first()

    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found")

    # Mark incoming messages as read
    for msg in thread.messages:
        if not msg.is_read:
            if current_user.role == "provider" and msg.sender_role == "patient":
                msg.is_read = True
            elif current_user.role != "provider" and msg.sender_role != "patient":
                msg.is_read = True
    db.commit()
    db.refresh(thread)

    return {
        **_thread_to_dict(thread),
        "messages": [_message_to_dict(m) for m in thread.messages],
    }


@app.post("/consultations/threads/{thread_id}/messages", status_code=201)
async def send_consultation_message(
    thread_id: str,
    req: MessageCreateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Thread not found")
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.provider_id == provider.id,
        ).first()
    else:
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.user_id == current_user.id,
        ).first()

    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found")
    if thread.status == "closed":
        raise HTTPException(status_code=400, detail="This consultation thread is closed")

    if not req.body.strip() and not req.attachment_data:
        raise HTTPException(status_code=400, detail="Message must have body or attachment")

    sender_role = "provider" if current_user.role == "provider" else "patient"
    msg = models.ConsultationMessage(
        thread_id=thread.id,
        sender_role=sender_role,
        body=req.body.strip() if req.body else None,
        attachment_name=req.attachment_name,
        attachment_data=req.attachment_data,
        attachment_mime=req.attachment_mime,
        is_read=True,
    )
    db.add(msg)
    thread.updated_at = datetime.utcnow()

    # Auto-register doctor in emergency contacts if sender is patient
    if current_user.role != "provider":
        add_doctor_to_emergency_contacts(db, current_user.id, thread.provider_id)

    db.commit()
    db.refresh(msg)
    return _message_to_dict(msg)


@app.patch("/consultations/threads/{thread_id}/messages/{msg_id}/read")
async def mark_message_read(
    thread_id: str,
    msg_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Thread not found")
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.provider_id == provider.id,
        ).first()
    else:
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.user_id == current_user.id,
        ).first()

    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found")

    msg = db.query(models.ConsultationMessage).filter(
        models.ConsultationMessage.id == msg_id,
        models.ConsultationMessage.thread_id == thread_id,
    ).first()
    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")

    msg.is_read = True
    db.commit()
    return {"message": "Marked as read"}


@app.patch("/consultations/threads/{thread_id}/close")
async def close_consultation_thread(
    thread_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Thread not found")
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.provider_id == provider.id,
        ).first()
    else:
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.user_id == current_user.id,
        ).first()

    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found")

    thread.status = "closed"
    system_msg = models.ConsultationMessage(
        thread_id=thread.id,
        sender_role="system",
        body="✅ This consultation has been closed.",
        is_read=True,
    )
    db.add(system_msg)
    db.commit()
    return {"message": "Thread closed"}


@app.post("/consultations/threads/{thread_id}/call-request")
async def request_call(
    thread_id: str,
    req: CallRequestBody,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    if current_user.role == "provider":
        provider = db.query(models.CareProvider).filter(models.CareProvider.user_id == current_user.id).first()
        if not provider:
            raise HTTPException(status_code=404, detail="Thread not found")
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.provider_id == provider.id,
        ).first()
    else:
        thread = db.query(models.ConsultationThread).filter(
            models.ConsultationThread.id == thread_id,
            models.ConsultationThread.user_id == current_user.id,
        ).first()

    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found")

    call_type = "video" if req.call_type == "video" else "voice"
    thread.consultation_type = f"{call_type}_request"
    thread.status = f"{call_type}_scheduled" if req.scheduled_call_at else "active"

    if req.scheduled_call_at:
        try:
            thread.scheduled_call_at = datetime.fromisoformat(req.scheduled_call_at.replace("Z", "+00:00"))
        except ValueError:
            pass

    label = "📹 Video" if call_type == "video" else "🎙️ Voice"
    time_str = f" scheduled for {req.scheduled_call_at}" if req.scheduled_call_at else ""
    waiting_text = (
        "Awaiting provider confirmation." if current_user.role != "provider"
        else "Awaiting patient confirmation."
    )
    system_msg = models.ConsultationMessage(
        thread_id=thread.id,
        sender_role="system",
        body=f"{label} call requested{time_str}. {waiting_text}",
        is_read=True,
    )
    db.add(system_msg)
    db.commit()
    db.refresh(thread)
    return _thread_to_dict(thread)


# ─── Reports & Records Helpers ───────────────────────────────────────────────

def _report_to_dict(report: models.HealthReport) -> dict:
    return {
        "id": str(report.id),
        "report_type": report.report_type,
        "period_start": report.period_start.isoformat(),
        "period_end": report.period_end.isoformat(),
        "title": report.title,
        "summary": report.summary,
        "data_snapshot": report.data_snapshot,
        "created_at": report.created_at.isoformat(),
    }


def _record_to_dict(rec: models.MedicalRecord, include_data: bool = False) -> dict:
    res = {
        "id": str(rec.id),
        "record_type": rec.record_type,
        "title": rec.title,
        "notes": rec.notes or "",
        "file_name": rec.file_name,
        "file_mime": rec.file_mime,
        "file_size": rec.file_size,
        "provider_name": rec.provider_name or "",
        "record_date": rec.record_date.isoformat(),
        "created_at": rec.created_at.isoformat(),
    }
    if include_data:
        res["file_data"] = rec.file_data
    return res


def _share_to_dict(share: models.RecordShareLink) -> dict:
    return {
        "id": str(share.id),
        "share_token": share.share_token,
        "share_type": share.share_type,
        "target_id": str(share.target_id) if share.target_id else None,
        "recipient_name": share.recipient_name,
        "recipient_email": share.recipient_email or "",
        "expires_at": share.expires_at.isoformat(),
        "is_revoked": share.is_revoked,
        "access_count": share.access_count,
        "created_at": share.created_at.isoformat(),
    }


# ─── Reports Endpoints ───────────────────────────────────────────────────────

@app.post("/reports/generate")
async def generate_health_report(
    req: HealthReportCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    vitals = db.query(models.VitalLog).filter(
        models.VitalLog.user_id == current_user.id,
        models.VitalLog.created_at >= req.period_start,
        models.VitalLog.created_at <= req.period_end,
    ).all()

    activities = db.query(models.ActivityLog).filter(
        models.ActivityLog.user_id == current_user.id,
        models.ActivityLog.date >= req.period_start,
        models.ActivityLog.date <= req.period_end,
    ).all()

    symptoms = db.query(models.SymptomAssessment).filter(
        models.SymptomAssessment.user_id == current_user.id,
        models.SymptomAssessment.created_at >= req.period_start,
        models.SymptomAssessment.created_at <= req.period_end,
    ).all()

    profile = current_user.profile

    vital_list = []
    for v in vitals:
        vital_list.append({
            "systolic_bp": v.systolic_bp,
            "diastolic_bp": v.diastolic_bp,
            "blood_glucose": v.blood_glucose,
            "heart_rate": v.heart_rate,
            "temperature": float(v.temperature) if v.temperature else None,
            "weight": float(v.weight) if v.weight else None,
            "timestamp": v.created_at.isoformat()
        })

    activity_list = []
    for a in activities:
        activity_list.append({
            "steps": a.steps,
            "calories_burned": a.calories_burned,
            "water_intake": a.water_intake,
            "sleep_hours": float(a.sleep_hours) if a.sleep_hours else None,
            "calories_consumed": a.calories_consumed,
            "meal_notes": a.meal_notes,
            "date": a.date.isoformat()
        })

    symptom_list = []
    for s in symptoms:
        symptom_list.append({
            "symptoms": s.symptoms,
            "notes": s.notes,
            "risk_level": s.risk_level,
            "possible_conditions": s.possible_conditions,
            "recommended_action": s.recommended_action,
            "timestamp": s.created_at.isoformat()
        })

    profile_data = {
        "allergies": profile.allergies if profile else None,
        "known_conditions": profile.known_conditions if profile else None,
        "medical_history": profile.medical_history if profile else None,
    }

    snapshot = {
        "vitals": vital_list,
        "activities": activity_list,
        "symptoms": symptom_list,
        "profile": profile_data
    }
    import uuid
    from datetime import datetime

    # Local structured report builder (produces instantaneous response in <1ms)
    fallback_obj = {
        "report_metadata": {
            "report_id": str(uuid.uuid4()),
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "confidentiality_level": "Confidential"
        },
        "patient_summary": {
            "age": current_user.age or (profile.age if profile else None),
            "gender": current_user.gender or (profile.gender if profile else None),
            "chief_complaint": f"Health monitoring for period from {req.period_start.date()} to {req.period_end.date()}"
        },
        "clinical_vitals": {
            "blood_pressure": "Not recorded",
            "heart_rate": "Not recorded",
            "temperature": "Not recorded",
            "spO2": "Not recorded"
        },
        "history_of_present_illness": {
            "onset": "Periodic",
            "duration": f"{(req.period_end - req.period_start).days} days",
            "severity": "Mild",
            "description": f"Periodic health monitoring summary. Logged data snapshot: {len(vitals)} vitals, {len(activities)} activities, {len(symptoms)} symptom checker logs."
        },
        "assessment_and_findings": {
            "physical_examination": None,
            "primary_diagnosis": "Routine Clinical Follow-up",
            "differential_diagnoses": [],
            "icd_10_code": "Z00.00"
        },
        "plan_and_recommendations": {
            "medications": [],
            "diagnostic_tests_ordered": [],
            "lifestyle_advice": [
                "Maintain steady hydration",
                "Keep logs updated regularly",
                "Schedule check-ups as recommended"
            ],
            "follow_up": "Check back in 7 days or sooner if symptoms arise."
        },
        "red_flags": [
            "Difficulty breathing or chest pain",
            "Uncontrolled high fever or persistent vomiting",
            "Altered mental status or extreme lethargy"
        ]
    }
    
    # Pre-fill vitals dynamically
    if vital_list:
        last_vital = vital_list[-1]
        if last_vital.get("systolic_bp") and last_vital.get("diastolic_bp"):
            fallback_obj["clinical_vitals"]["blood_pressure"] = f"{last_vital['systolic_bp']}/{last_vital['diastolic_bp']} mmHg"
        if last_vital.get("heart_rate"):
            fallback_obj["clinical_vitals"]["heart_rate"] = f"{last_vital['heart_rate']} bpm"
        if last_vital.get("temperature"):
            fallback_obj["clinical_vitals"]["temperature"] = f"{last_vital['temperature']} °C"

    # Pre-fill symptom history dynamically
    if symptom_list:
        last_symptom = symptom_list[-1]
        fallback_obj["history_of_present_illness"]["onset"] = "Recent days"
        fallback_obj["history_of_present_illness"]["severity"] = last_symptom["risk_level"].capitalize()
        sympt_text = last_symptom.get("symptoms", "General symptoms")
        fallback_obj["history_of_present_illness"]["description"] = f"Patient presented with symptoms: {sympt_text}. Notes: {last_symptom.get('notes', 'None')}."
        
        # Primary Diagnosis and differentials
        possible = last_symptom.get("possible_conditions")
        if possible:
            try:
                conditions_list = json.loads(possible) if possible.startswith("[") else [possible]
                if conditions_list:
                    fallback_obj["assessment_and_findings"]["primary_diagnosis"] = conditions_list[0]
                    fallback_obj["assessment_and_findings"]["differential_diagnoses"] = conditions_list[1:]
            except Exception:
                fallback_obj["assessment_and_findings"]["primary_diagnosis"] = possible
        
        rec = last_symptom.get("recommended_action")
        if rec:
            fallback_obj["plan_and_recommendations"]["follow_up"] = rec

    # Pre-fill activities and habits advice
    if activity_list:
        total_steps = sum(a.get("steps") or 0 for a in activity_list)
        avg_steps = total_steps // len(activity_list)
        fallback_obj["plan_and_recommendations"]["lifestyle_advice"].append(f"Maintain daily average step target (current average: {avg_steps} steps).")

    summary_text = json.dumps(fallback_obj)

    title = f"{req.report_type.capitalize()} Health Report ({req.period_start.date()} to {req.period_end.date()})"

    report = models.HealthReport(
        user_id=current_user.id,
        report_type=req.report_type,
        period_start=req.period_start,
        period_end=req.period_end,
        title=title,
        summary=summary_text,
        data_snapshot=json.dumps(snapshot),
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return _report_to_dict(report)


@app.get("/reports")
async def list_health_reports(
    patient_id: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    target_user_id = current_user.id
    if patient_id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, patient_id):
            raise HTTPException(status_code=403, detail="Not authorized to view this patient's reports")
        target_user_id = patient_id

    reports = db.query(models.HealthReport).filter(
        models.HealthReport.user_id == target_user_id
    ).order_by(models.HealthReport.created_at.desc()).all()
    return [_report_to_dict(r) for r in reports]


@app.get("/reports/{report_id}")
async def get_health_report(
    report_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    report = db.query(models.HealthReport).filter(models.HealthReport.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
        
    if report.user_id != current_user.id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, report.user_id):
            raise HTTPException(status_code=403, detail="Not authorized to view this report")
            
    return _report_to_dict(report)


@app.delete("/reports/{report_id}")
async def delete_health_report(
    report_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    report = db.query(models.HealthReport).filter(
        models.HealthReport.id == report_id,
        models.HealthReport.user_id == current_user.id,
    ).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    db.delete(report)
    db.commit()
    return {"message": "Report deleted"}


# ─── Records Endpoints ───────────────────────────────────────────────────────

@app.post("/records")
async def upload_medical_record(
    req: MedicalRecordCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    # Calculate bytes size from base64 string
    size_in_bytes = int(len(req.file_data) * 3 / 4)

    record = models.MedicalRecord(
        user_id=current_user.id,
        record_type=req.record_type,
        title=req.title,
        notes=req.notes,
        file_name=req.file_name,
        file_data=req.file_data,
        file_mime=req.file_mime,
        file_size=size_in_bytes,
        provider_name=req.provider_name,
        record_date=req.record_date,
    )
    db.add(record)
    db.commit()
    db.refresh(record)
    return _record_to_dict(record)


@app.get("/records")
async def list_medical_records(
    patient_id: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    target_user_id = current_user.id
    if patient_id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, patient_id):
            raise HTTPException(status_code=403, detail="Not authorized to view this patient's records")
        target_user_id = patient_id

    records = db.query(models.MedicalRecord).filter(
        models.MedicalRecord.user_id == target_user_id
    ).order_by(models.MedicalRecord.record_date.desc()).all()
    return [_record_to_dict(r, include_data=False) for r in records]


@app.get("/records/{record_id}")
async def get_medical_record(
    record_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    record = db.query(models.MedicalRecord).filter(models.MedicalRecord.id == record_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
        
    if record.user_id != current_user.id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, record.user_id):
            raise HTTPException(status_code=403, detail="Not authorized to view this record")
            
    return _record_to_dict(record, include_data=True)


@app.delete("/records/{record_id}")
async def delete_medical_record(
    record_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    record = db.query(models.MedicalRecord).filter(
        models.MedicalRecord.id == record_id,
        models.MedicalRecord.user_id == current_user.id,
    ).first()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
    db.delete(record)
    db.commit()
    return {"message": "Record deleted"}


# ─── Share Links Endpoints ───────────────────────────────────────────────────

@app.post("/share")
async def create_share_link(
    req: RecordShareLinkCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    # Verify target exists and is owned by user
    if req.share_type == "report":
        tgt = db.query(models.HealthReport).filter(
            models.HealthReport.id == req.target_id,
            models.HealthReport.user_id == current_user.id
        ).first()
        if not tgt:
            raise HTTPException(status_code=404, detail="Target report not found")
    elif req.share_type == "record":
        tgt = db.query(models.MedicalRecord).filter(
            models.MedicalRecord.id == req.target_id,
            models.MedicalRecord.user_id == current_user.id
        ).first()
        if not tgt:
            raise HTTPException(status_code=404, detail="Target record not found")

    token = secrets.token_hex(32)
    expiry = datetime.utcnow() + timedelta(days=req.expires_in_days)

    share = models.RecordShareLink(
        user_id=current_user.id,
        share_token=token,
        share_type=req.share_type,
        target_id=req.target_id,
        recipient_name=req.recipient_name,
        recipient_email=req.recipient_email,
        expires_at=expiry,
    )
    db.add(share)
    db.commit()
    db.refresh(share)
    return _share_to_dict(share)


@app.get("/share")
async def list_share_links(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    shares = db.query(models.RecordShareLink).filter(
        models.RecordShareLink.user_id == current_user.id
    ).order_by(models.RecordShareLink.created_at.desc()).all()
    return [_share_to_dict(s) for s in shares]


@app.delete("/share/{share_id}")
async def revoke_share_link(
    share_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    share = db.query(models.RecordShareLink).filter(
        models.RecordShareLink.id == share_id,
        models.RecordShareLink.user_id == current_user.id,
    ).first()
    if not share:
        raise HTTPException(status_code=404, detail="Share link not found")
    db.delete(share)
    db.commit()
    return {"message": "Share link revoked"}


@app.get("/shared/{token}")
async def get_shared_content(
    token: str,
    db: Session = Depends(get_db)
):
    share = db.query(models.RecordShareLink).filter(
        models.RecordShareLink.share_token == token
    ).first()
    if not share or share.is_revoked or share.expires_at < datetime.utcnow():
        raise HTTPException(status_code=404, detail="Share link is invalid or expired")

    # Increment access count
    share.access_count += 1
    db.commit()

    # Retrieve shared data
    if share.share_type == "report":
        report = db.query(models.HealthReport).filter(
            models.HealthReport.id == share.target_id
        ).first()
        if not report:
            raise HTTPException(status_code=404, detail="Shared report not found")
        return {
            "share_type": "report",
            "recipient_name": share.recipient_name,
            "created_at": share.created_at.isoformat(),
            "expires_at": share.expires_at.isoformat(),
            "data": _report_to_dict(report)
        }

    elif share.share_type == "record":
        record = db.query(models.MedicalRecord).filter(
            models.MedicalRecord.id == share.target_id
        ).first()
        if not record:
            raise HTTPException(status_code=404, detail="Shared record not found")
        return {
            "share_type": "record",
            "recipient_name": share.recipient_name,
            "created_at": share.created_at.isoformat(),
            "expires_at": share.expires_at.isoformat(),
            "data": _record_to_dict(record, include_data=True)
        }

    elif share.share_type == "all_reports":
        reports = db.query(models.HealthReport).filter(
            models.HealthReport.user_id == share.user_id
        ).order_by(models.HealthReport.created_at.desc()).all()
        return {
            "share_type": "all_reports",
            "recipient_name": share.recipient_name,
            "created_at": share.created_at.isoformat(),
            "expires_at": share.expires_at.isoformat(),
            "data": [_report_to_dict(r) for r in reports]
        }

    elif share.share_type == "all_records":
        records = db.query(models.MedicalRecord).filter(
            models.MedicalRecord.user_id == share.user_id
        ).order_by(models.MedicalRecord.record_date.desc()).all()
        return {
            "share_type": "all_records",
            "recipient_name": share.recipient_name,
            "created_at": share.created_at.isoformat(),
            "expires_at": share.expires_at.isoformat(),
            "data": [_record_to_dict(r, include_data=False) for r in records]
        }

    raise HTTPException(status_code=400, detail="Invalid share link type")


def _serialize_reminder(reminder: models.ReminderAlert) -> dict:
    return {
        "id": str(reminder.id),
        "type": reminder.type,
        "title": reminder.title,
        "body": reminder.body,
        "trigger_time": reminder.trigger_time,
        "is_enabled": reminder.is_enabled,
        "metadata_json": reminder.metadata_json,
        "created_at": reminder.created_at,
        "updated_at": reminder.updated_at,
    }


@app.get("/reminders", response_model=list[ReminderAlertResponse])
def list_reminders(
    patient_id: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    target_user_id = current_user.id
    if patient_id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, patient_id):
            raise HTTPException(status_code=403, detail="Not authorized to view this patient's reminders")
        target_user_id = patient_id

    reminders = (
        db.query(models.ReminderAlert)
        .filter(models.ReminderAlert.user_id == target_user_id)
        .order_by(models.ReminderAlert.trigger_time.asc())
        .all()
    )
    return [_serialize_reminder(r) for r in reminders]


@app.post("/reminders", response_model=ReminderAlertResponse, status_code=status.HTTP_201_CREATED)
def create_reminder(
    payload: ReminderAlertCreate,
    patient_id: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    target_user_id = current_user.id
    if patient_id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, patient_id):
            raise HTTPException(status_code=403, detail="Not authorized to prescribe to this patient")
        target_user_id = patient_id

    reminder = models.ReminderAlert(
        user_id=target_user_id,
        type=payload.type.strip(),
        title=payload.title.strip(),
        body=payload.body.strip(),
        trigger_time=payload.trigger_time,
        is_enabled=True,
        metadata_json=payload.metadata_json,
    )
    db.add(reminder)
    db.commit()
    db.refresh(reminder)
    return _serialize_reminder(reminder)


@app.patch("/reminders/{reminder_id}/toggle", response_model=ReminderAlertResponse)
def toggle_reminder(
    reminder_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    reminder = (
        db.query(models.ReminderAlert)
        .filter(models.ReminderAlert.id == reminder_id)
        .first()
    )
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    if reminder.user_id != current_user.id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, reminder.user_id):
            raise HTTPException(status_code=403, detail="Not authorized to edit this reminder")
    reminder.is_enabled = not reminder.is_enabled
    db.commit()
    db.refresh(reminder)
    return _serialize_reminder(reminder)


@app.put("/reminders/{reminder_id}", response_model=ReminderAlertResponse)
def update_reminder(
    reminder_id: str,
    payload: ReminderAlertCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    reminder = (
        db.query(models.ReminderAlert)
        .filter(models.ReminderAlert.id == reminder_id)
        .first()
    )
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    if reminder.user_id != current_user.id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, reminder.user_id):
            raise HTTPException(status_code=403, detail="Not authorized to edit this reminder")
    reminder.type = payload.type.strip()
    reminder.title = payload.title.strip()
    reminder.body = payload.body.strip()
    reminder.trigger_time = payload.trigger_time
    reminder.metadata_json = payload.metadata_json
    db.commit()
    db.refresh(reminder)
    return _serialize_reminder(reminder)


@app.delete("/reminders/{reminder_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_reminder(
    reminder_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_active_user),
):
    reminder = (
        db.query(models.ReminderAlert)
        .filter(models.ReminderAlert.id == reminder_id)
        .first()
    )
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    if reminder.user_id != current_user.id:
        if current_user.role != "provider" or not check_provider_access_to_patient(db, current_user.id, reminder.user_id):
            raise HTTPException(status_code=403, detail="Not authorized to edit this reminder")
    db.delete(reminder)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)



# ==========================================
# WebRTC Signaling WebSocket Endpoint
# ==========================================
from fastapi import WebSocket, WebSocketDisconnect
import json

class ConnectionManager:
    def __init__(self):
        # Maps user_id to their active WebSocket connection
        self.active_connections: dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, user_id: str):
        await websocket.accept()
        self.active_connections[user_id] = websocket
        print(f"User {user_id} connected to signaling server.")

    def disconnect(self, user_id: str):
        if user_id in self.active_connections:
            del self.active_connections[user_id]
            print(f"User {user_id} disconnected from signaling server.")

    async def send_personal_message(self, message: dict, user_id: str):
        if user_id in self.active_connections:
            websocket = self.active_connections[user_id]
            try:
                await websocket.send_json(message)
            except Exception as e:
                print(f"Error sending message to {user_id}: {e}")
                self.disconnect(user_id)
        else:
            print(f"User {user_id} not found in active connections.")

manager = ConnectionManager()

@app.websocket("/ws/call/{token}")
async def websocket_call_endpoint(websocket: WebSocket, token: str, db: Session = Depends(get_db)):
    # Authenticate the user via the JWT token
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id_str = payload.get("sub")
        if user_id_str is None:
            await websocket.close(code=1008, reason="Invalid Token")
            return
    except JWTError:
        await websocket.close(code=1008, reason="Invalid Token")
        return

    # Connection accepted
    await manager.connect(websocket, user_id_str)

    try:
        while True:
            # Receive WebRTC signaling messages
            data = await websocket.receive_text()
            try:
                message = json.loads(data)
                target_user_id = message.get("target_id")
                
                # We forward the message to the target user
                if target_user_id:
                    # Inject the sender's ID so the receiver knows who the message is from
                    message["sender_id"] = user_id_str
                    await manager.send_personal_message(message, str(target_user_id))
                else:
                    print(f"Received message without target_id from {user_id_str}")
            except json.JSONDecodeError:
                print("Received non-JSON message")
                
    except WebSocketDisconnect:
        manager.disconnect(user_id_str)
