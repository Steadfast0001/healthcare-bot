from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Numeric, Boolean
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
import os
from .database import Base

# Use database-specific UUID type or fallback to String
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./wadocta.db")
if "postgresql" in DATABASE_URL:
    from sqlalchemy.dialects.postgresql import UUID
    UUIDType = UUID(as_uuid=True)
    def _uuid_default():
        return uuid.uuid4
else:
    # For SQLite and other databases, use String for UUID
    UUIDType = String(36)
    def _uuid_default():
        return lambda: str(uuid.uuid4())

class User(Base):
    __tablename__ = "users"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    full_name = Column(String(120), nullable=False)
    username = Column(String(120), unique=True, nullable=True, index=True)
    email = Column(String(120), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    phone_number = Column(String(30), nullable=True)
    role = Column(String(50), nullable=False, default="user")
    is_verified = Column(Boolean, default=False, nullable=False)
    verification_token = Column(String(255), unique=True, nullable=True)
    verification_token_expires = Column(DateTime, nullable=True)
    reset_token = Column(String(255), unique=True, nullable=True)
    reset_token_expires = Column(DateTime, nullable=True)
    failed_login_attempts = Column(Integer, default=0, nullable=False)
    locked_until = Column(DateTime, nullable=True)
    last_login_at = Column(DateTime, nullable=True)
    age = Column(Integer, nullable=True)
    gender = Column(String(20), nullable=True)
    country = Column(String(80), nullable=True, default="Cameroon")
    created_at = Column(DateTime, server_default=func.now())
    profile_picture = Column(Text, nullable=True)

    chats = relationship("Chat", back_populates="user", cascade="all, delete-orphan")
    profile = relationship(
        "PatientProfile",
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )
    care_provider = relationship(
        "CareProvider",
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )
    ai_logs = relationship("AiLog", back_populates="user", cascade="all, delete-orphan")
    appointments = relationship(
        "Appointment", back_populates="user", cascade="all, delete-orphan"
    )
    provider_reviews = relationship(
        "ProviderReview", back_populates="user", cascade="all, delete-orphan"
    )
    consultation_threads = relationship(
        "ConsultationThread", back_populates="user", cascade="all, delete-orphan"
    )

class Chat(Base):
    __tablename__ = "chats"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"))
    user_message = Column(Text, nullable=False)
    ai_response = Column(Text, nullable=False)
    risk_level = Column(String(20))
    possible_conditions = Column(Text, nullable=True)
    recommended_action = Column(Text, nullable=True)
    follow_up_question = Column(Text, nullable=True)
    disclaimer = Column(Text, nullable=True)
    warning = Column(Text, nullable=True)
    is_emergency = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User", back_populates="chats")

class Symptom(Base):
    __tablename__ = "symptoms"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), unique=True, nullable=False, index=True)
    description = Column(Text)

    condition_maps = relationship("SymptomConditionMap", back_populates="symptom", cascade="all, delete-orphan")

class AiLog(Base):
    __tablename__ = "ai_logs"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id"))
    prompt_tokens = Column(Integer)
    completion_tokens = Column(Integer)
    model_used = Column(String(50))
    response_time_ms = Column(Integer)
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User", back_populates="ai_logs")

class HealthTip(Base):
    __tablename__ = "health_tips"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(150))
    content = Column(Text)
    category = Column(String(80))
    created_at = Column(DateTime, server_default=func.now())

class PatientProfile(Base):
    __tablename__ = "patient_profiles"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    age = Column(Integer, nullable=True)
    gender = Column(String(40), nullable=True)
    country = Column(String(100), nullable=True, default="Cameroon")
    city = Column(String(100), nullable=True, default="Yaoundé")
    emergency_contact_name = Column(String(120), nullable=True)
    emergency_contact_phone = Column(String(30), nullable=True)
    allergies = Column(Text, nullable=True)
    known_conditions = Column(Text, nullable=True)
    medical_history = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="profile")
    emergency_contacts = relationship(
        "EmergencyContact",
        back_populates="profile",
        cascade="all, delete-orphan",
        order_by="EmergencyContact.sort_order",
    )


class EmergencyContact(Base):
    __tablename__ = "emergency_contacts"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    patient_profile_id = Column(
        UUIDType,
        ForeignKey("patient_profiles.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name = Column(String(120), nullable=False)
    phone_number = Column(String(30), nullable=False)
    allow_call = Column(Boolean, nullable=False, default=True)
    allow_whatsapp = Column(Boolean, nullable=False, default=False)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    profile = relationship("PatientProfile", back_populates="emergency_contacts")

class SymptomAssessment(Base):
    __tablename__ = "symptom_assessments"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"))
    symptoms = Column(Text, nullable=False)
    notes = Column(Text, nullable=True)
    risk_level = Column(String(20), nullable=False)
    possible_conditions = Column(Text, nullable=True)
    recommended_action = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User")

class Condition(Base):
    __tablename__ = "conditions"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(120), unique=True, nullable=False, index=True)
    description = Column(Text)
    severity = Column(String(20))
    advice = Column(Text)

    symptom_maps = relationship("SymptomConditionMap", back_populates="condition", cascade="all, delete-orphan")

class SymptomConditionMap(Base):
    __tablename__ = "symptom_condition_map"

    id = Column(Integer, primary_key=True, index=True)
    symptom_id = Column(Integer, ForeignKey("symptoms.id", ondelete="CASCADE"))
    condition_id = Column(Integer, ForeignKey("conditions.id", ondelete="CASCADE"))
    weight = Column(Numeric(5, 2), default=0.50)

    symptom = relationship("Symptom", back_populates="condition_maps")
    condition = relationship("Condition", back_populates="symptom_maps")

class EmergencyKeyword(Base):
    __tablename__ = "emergency_keywords"

    id = Column(Integer, primary_key=True, index=True)
    keyword = Column(String(100), unique=True)
    level = Column(String(20))


class CareProvider(Base):
    __tablename__ = "care_providers"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    name = Column(String(160), nullable=False, index=True)
    provider_type = Column(String(20), nullable=False, index=True)
    specialty = Column(String(120), nullable=True)
    city = Column(String(100), nullable=True, index=True)
    country = Column(String(100), nullable=True, index=True)
    address = Column(String(255), nullable=True)
    phone_number = Column(String(30), nullable=True)
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, unique=True)
    license_number = Column(String(50), nullable=True)
    working_experience = Column(String(200), nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User", back_populates="care_provider")
    appointments = relationship(
        "Appointment", back_populates="provider", cascade="all, delete-orphan"
    )
    reviews = relationship(
        "ProviderReview", back_populates="provider", cascade="all, delete-orphan"
    )
    consultation_threads = relationship(
        "ConsultationThread", back_populates="provider", cascade="all, delete-orphan"
    )


class Appointment(Base):
    __tablename__ = "appointments"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    provider_id = Column(
        UUIDType, ForeignKey("care_providers.id", ondelete="CASCADE"), nullable=False
    )
    scheduled_at = Column(DateTime, nullable=False)
    reason = Column(Text, nullable=True)
    status = Column(String(20), nullable=False, default="booked", index=True)
    reminder_minutes_before = Column(Integer, nullable=False, default=60)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="appointments")
    provider = relationship("CareProvider", back_populates="appointments")


class ProviderReview(Base):
    __tablename__ = "provider_reviews"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    provider_id = Column(
        UUIDType, ForeignKey("care_providers.id", ondelete="CASCADE"), nullable=False
    )
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    rating = Column(Integer, nullable=False)
    review_text = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    provider = relationship("CareProvider", back_populates="reviews")
    user = relationship("User", back_populates="provider_reviews")


class VitalLog(Base):
    __tablename__ = "vital_logs"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    systolic_bp = Column(Integer, nullable=True)  # mmHg
    diastolic_bp = Column(Integer, nullable=True)  # mmHg
    blood_glucose = Column(Integer, nullable=True)  # mg/dL
    heart_rate = Column(Integer, nullable=True)  # bpm
    temperature = Column(Numeric(4, 1), nullable=True)  # °C or °F
    weight = Column(Numeric(5, 2), nullable=True)  # kg
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User")


class ActivityLog(Base):
    __tablename__ = "activity_logs"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    date = Column(DateTime, nullable=False, default=func.now())
    steps = Column(Integer, nullable=True)
    calories_burned = Column(Integer, nullable=True)  # kcal
    water_intake = Column(Integer, nullable=True)  # ml
    sleep_hours = Column(Numeric(3, 1), nullable=True)  # hours
    calories_consumed = Column(Integer, nullable=True)  # kcal
    meal_notes = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User")


class HealthGoal(Base):
    __tablename__ = "health_goals"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    goal_type = Column(String(50), nullable=False)  # 'steps', 'sleep', 'water', 'weight', 'calories_burned'
    target_value = Column(Numeric(8, 2), nullable=False)
    current_value = Column(Numeric(8, 2), nullable=False, default=0.0)
    start_date = Column(DateTime, nullable=False, default=func.now())
    target_date = Column(DateTime, nullable=False)
    is_completed = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User")


class ConsultationThread(Base):
    """A consultation thread between a patient and a care provider."""
    __tablename__ = "consultation_threads"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    provider_id = Column(UUIDType, ForeignKey("care_providers.id", ondelete="CASCADE"), nullable=False, index=True)
    subject = Column(String(255), nullable=True)
    # type: 'chat' | 'video_request' | 'voice_request'
    consultation_type = Column(String(30), nullable=False, default="chat")
    # status: 'active' | 'closed' | 'video_scheduled' | 'voice_scheduled'
    status = Column(String(30), nullable=False, default="active")
    scheduled_call_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="consultation_threads")
    provider = relationship("CareProvider", back_populates="consultation_threads")
    messages = relationship(
        "ConsultationMessage",
        back_populates="thread",
        cascade="all, delete-orphan",
        order_by="ConsultationMessage.created_at",
    )


class ConsultationMessage(Base):
    """An individual message in a consultation thread."""
    __tablename__ = "consultation_messages"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    thread_id = Column(UUIDType, ForeignKey("consultation_threads.id", ondelete="CASCADE"), nullable=False, index=True)
    # sender_role: 'patient' | 'provider' | 'system'
    sender_role = Column(String(20), nullable=False, default="patient")
    body = Column(Text, nullable=True)
    attachment_name = Column(String(255), nullable=True)
    attachment_data = Column(Text, nullable=True)   # base64-encoded
    attachment_mime = Column(String(100), nullable=True)
    is_read = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, server_default=func.now())

    thread = relationship("ConsultationThread", back_populates="messages")


class HealthReport(Base):
    __tablename__ = "health_reports"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    report_type = Column(String(30), nullable=False) # 'vitals' | 'activity' | 'symptoms' | 'comprehensive'
    period_start = Column(DateTime, nullable=False)
    period_end = Column(DateTime, nullable=False)
    title = Column(String(255), nullable=False)
    summary = Column(Text, nullable=False)
    data_snapshot = Column(Text, nullable=False) # JSON blob string
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User")


class MedicalRecord(Base):
    __tablename__ = "medical_records"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    record_type = Column(String(30), nullable=False) # 'lab_result' | 'prescription' | 'imaging' | 'discharge' | 'other'
    title = Column(String(255), nullable=False)
    notes = Column(Text, nullable=True)
    file_name = Column(String(255), nullable=False)
    file_data = Column(Text, nullable=False) # base64 string
    file_mime = Column(String(100), nullable=False)
    file_size = Column(Integer, nullable=False) # in bytes
    provider_name = Column(String(160), nullable=True)
    record_date = Column(DateTime, nullable=False, default=func.now())
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User")


class RecordShareLink(Base):
    __tablename__ = "record_share_links"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    share_token = Column(String(64), unique=True, nullable=False, index=True)
    share_type = Column(String(20), nullable=False) # 'report' | 'record' | 'all_reports' | 'all_records'
    target_id = Column(UUIDType, nullable=True) # ID of report or record, or null for "all"
    recipient_name = Column(String(120), nullable=False)
    recipient_email = Column(String(120), nullable=True)
    expires_at = Column(DateTime, nullable=False)
    is_revoked = Column(Boolean, default=False, nullable=False)
    access_count = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User")


class ReminderAlert(Base):
    __tablename__ = "reminder_alerts"

    id = Column(UUIDType, primary_key=True, default=_uuid_default())
    user_id = Column(UUIDType, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    type = Column(String(30), nullable=False, index=True) # 'appointment' | 'medication' | 'health_check'
    title = Column(String(255), nullable=False)
    body = Column(Text, nullable=False)
    trigger_time = Column(DateTime, nullable=False)
    is_enabled = Column(Boolean, default=True, nullable=False)
    metadata_json = Column(Text, nullable=True) # JSON blob for dynamic parameters
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User")


class RevokedToken(Base):
    __tablename__ = "revoked_tokens"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String(500), unique=True, index=True, nullable=False)
    revoked_at = Column(DateTime, default=func.now(), nullable=False)
    expires_at = Column(DateTime, nullable=False)


class DiseaseEmbedding(Base):
    __tablename__ = "disease_embeddings"

    id = Column(Integer, primary_key=True, index=True)
    condition_id = Column(Integer, ForeignKey("conditions.id", ondelete="CASCADE"), nullable=False)
    content = Column(Text, nullable=False)
    embedding = Column(Text, nullable=False)  # JSON-serialized list of floats
    created_at = Column(DateTime, server_default=func.now())

    condition = relationship("Condition")


class SemanticCache(Base):
    __tablename__ = "semantic_caches"

    id = Column(Integer, primary_key=True, index=True)
    query_text = Column(Text, nullable=False)
    query_embedding = Column(Text, nullable=False)  # JSON-serialized list of floats
    response_json = Column(Text, nullable=False)  # JSON string of ChatReplyResponse
    created_at = Column(DateTime, server_default=func.now())



