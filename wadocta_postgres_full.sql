-- =========================================================================
-- WADOCTA HEALTHCARE PLATFORM - COMPLETE POSTGRESQL DDL QUERY SCRIPT
-- =========================================================================
-- This script drops and recreates all database tables in the correct relational
-- order, applying structural normalization, index optimizations, UUID defaults,
-- timezone-aware timestamps, and native constraints.
-- =========================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -------------------------------------------------------------------------
-- 1. CLEANUP / DROP TABLES (IN REVERSE RELATIONAL ORDER)
-- -------------------------------------------------------------------------
DROP TABLE IF EXISTS patient_allergies CASCADE;
DROP TABLE IF EXISTS allergies CASCADE;
DROP TABLE IF EXISTS consultation_transactions CASCADE;
DROP TABLE IF EXISTS revoked_tokens CASCADE;
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS device_tokens CASCADE;
DROP TABLE IF EXISTS record_share_links CASCADE;
DROP TABLE IF EXISTS medical_records CASCADE;
DROP TABLE IF EXISTS health_reports CASCADE;
DROP TABLE IF EXISTS reminder_alerts CASCADE;
DROP TABLE IF EXISTS consultation_messages CASCADE;
DROP TABLE IF EXISTS consultation_threads CASCADE;
DROP TABLE IF EXISTS health_goals CASCADE;
DROP TABLE IF EXISTS activity_logs CASCADE;
DROP TABLE IF EXISTS vital_logs CASCADE;
DROP TABLE IF EXISTS provider_reviews CASCADE;
DROP TABLE IF EXISTS appointments CASCADE;
DROP TABLE IF EXISTS care_providers CASCADE;
DROP TABLE IF EXISTS emergency_keywords CASCADE;
DROP TABLE IF EXISTS symptom_condition_map CASCADE;
DROP TABLE IF EXISTS conditions CASCADE;
DROP TABLE IF EXISTS symptom_assessments CASCADE;
DROP TABLE IF EXISTS emergency_contacts CASCADE;
DROP TABLE IF EXISTS patient_profiles CASCADE;
DROP TABLE IF EXISTS ai_logs CASCADE;
DROP TABLE IF EXISTS chats CASCADE;
DROP TABLE IF EXISTS symptoms CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- -------------------------------------------------------------------------
-- 2. USER AUTHENTICATION & CORE PROFILES
-- -------------------------------------------------------------------------

-- Users Table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name VARCHAR(120) NOT NULL,
    username VARCHAR(120) UNIQUE NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone_number VARCHAR(30) NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'user',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_token VARCHAR(255) UNIQUE NULL,
    verification_token_expires TIMESTAMP WITH TIME ZONE NULL,
    reset_token VARCHAR(255) UNIQUE NULL,
    reset_token_expires TIMESTAMP WITH TIME ZONE NULL,
    failed_login_attempts INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE NULL,
    last_login_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Patient Profiles Table (Normalized: duplicate demographics removed)
CREATE TABLE patient_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    age INT NULL,
    gender VARCHAR(40) NULL,
    country VARCHAR(100) DEFAULT 'Cameroon',
    city VARCHAR(100) DEFAULT 'Yaoundé',
    allergies TEXT NULL, -- Retained legacy CSV string for backwards compatibility
    known_conditions TEXT NULL,
    medical_history TEXT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Emergency Contacts Table (Allows multiple entries per patient profile)
CREATE TABLE emergency_contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_profile_id UUID NOT NULL REFERENCES patient_profiles(id) ON DELETE CASCADE,
    name VARCHAR(120) NOT NULL,
    phone_number VARCHAR(30) NOT NULL,
    allow_call BOOLEAN NOT NULL DEFAULT TRUE,
    allow_whatsapp BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------
-- 3. AI CHAT ENGINE & DIAGNOSTICS
-- -------------------------------------------------------------------------

-- Chats Table
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    user_message TEXT NOT NULL,
    ai_response TEXT NOT NULL,
    risk_level VARCHAR(20) NULL,
    possible_conditions TEXT NULL,
    recommended_action TEXT NULL,
    follow_up_question TEXT NULL,
    disclaimer TEXT NULL,
    warning TEXT NULL,
    is_emergency BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Symptoms Catalog
CREATE TABLE symptoms (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT NULL
);

-- Conditions Catalog
CREATE TABLE conditions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) UNIQUE NOT NULL,
    description TEXT NULL,
    severity VARCHAR(20) NULL,
    advice TEXT NULL
);

-- Symptom-Condition Probability Weights
CREATE TABLE symptom_condition_map (
    id SERIAL PRIMARY KEY,
    symptom_id INT NOT NULL REFERENCES symptoms(id) ON DELETE CASCADE,
    condition_id INT NOT NULL REFERENCES conditions(id) ON DELETE CASCADE,
    weight NUMERIC(5, 2) DEFAULT 0.50,
    UNIQUE (symptom_id, condition_id)
);

-- AI API Logs (Token Usage Tracker)
CREATE TABLE ai_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    prompt_tokens INT NULL,
    completion_tokens INT NULL,
    model_used VARCHAR(50) NULL,
    response_time_ms INT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Symptom Assessment Checker Submissions
CREATE TABLE symptom_assessments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    symptoms TEXT NOT NULL,
    notes TEXT NULL,
    risk_level VARCHAR(20) NOT NULL,
    possible_conditions TEXT NULL,
    recommended_action TEXT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Emergency Triggers Catalog
CREATE TABLE emergency_keywords (
    id SERIAL PRIMARY KEY,
    keyword VARCHAR(100) UNIQUE NOT NULL,
    level VARCHAR(20) NULL
);

-- -------------------------------------------------------------------------
-- 4. CLINICAL NETWORK & CONSULTATIONS
-- -------------------------------------------------------------------------

-- Care Providers (Hospitals, Doctors, Clinics)
CREATE TABLE care_providers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(160) NOT NULL,
    provider_type VARCHAR(20) NOT NULL, -- e.g., 'doctor' | 'clinic' | 'hospital'
    specialty VARCHAR(120) NULL,
    city VARCHAR(100) NULL,
    country VARCHAR(100) NULL,
    address VARCHAR(255) NULL,
    phone_number VARCHAR(30) NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Appointments Table
CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id UUID NOT NULL REFERENCES care_providers(id) ON DELETE CASCADE,
    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    reason TEXT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'booked',
    reminder_minutes_before INT NOT NULL DEFAULT 60,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Doctor / Care Provider Reviews
CREATE TABLE provider_reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider_id UUID NOT NULL REFERENCES care_providers(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_text TEXT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Consultation Messaging Threads
CREATE TABLE consultation_threads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id UUID NOT NULL REFERENCES care_providers(id) ON DELETE CASCADE,
    subject VARCHAR(255) NULL,
    consultation_type VARCHAR(30) NOT NULL DEFAULT 'chat', -- 'chat' | 'video_request' | 'voice_request'
    status VARCHAR(30) NOT NULL DEFAULT 'active', -- 'active' | 'closed'
    scheduled_call_at TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Consultation Chat Transcript Messages
CREATE TABLE consultation_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id UUID NOT NULL REFERENCES consultation_threads(id) ON DELETE CASCADE,
    sender_role VARCHAR(20) NOT NULL DEFAULT 'patient', -- 'patient' | 'provider' | 'system'
    body TEXT NULL,
    attachment_name VARCHAR(255) NULL,
    attachment_data TEXT NULL, -- Base64 attachment payload
    attachment_mime VARCHAR(100) NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------
-- 5. TELEMETRY logs, METRICS & REMINDERS
-- -------------------------------------------------------------------------

-- Vital Signs Logs
CREATE TABLE vital_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    systolic_bp INT NULL,
    diastolic_bp INT NULL,
    blood_glucose INT NULL,
    heart_rate INT NULL,
    temperature NUMERIC(4, 1) NULL,
    weight NUMERIC(5, 2) NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Daily Fitness & Diet Activity Logs
CREATE TABLE activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date TIMESTAMP WITH TIME ZONE NOT NULL,
    steps INT NULL,
    calories_burned INT NULL,
    water_intake INT NULL,
    sleep_hours NUMERIC(3, 1) NULL,
    calories_consumed INT NULL,
    meal_notes TEXT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Health Fitness & Metrics Goals
CREATE TABLE health_goals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    goal_type VARCHAR(50) NOT NULL, -- e.g., 'steps' | 'sleep' | 'water' | 'weight'
    target_value NUMERIC(8, 2) NOT NULL,
    current_value NUMERIC(8, 2) NOT NULL DEFAULT 0.0,
    start_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    target_date TIMESTAMP WITH TIME ZONE NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Reminders, Medications & Alerts Calendar
CREATE TABLE reminder_alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(30) NOT NULL, -- 'appointment' | 'medication' | 'health_check'
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    trigger_time TIMESTAMP WITH TIME ZONE NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    metadata_json TEXT NULL, -- Stores schedule config, dosage patterns
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------
-- 6. HEALTH CLINICAL REPORTS, RECORDS & PORTAL ACCESS
-- -------------------------------------------------------------------------

-- Compiled AI Health Reports
CREATE TABLE health_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    report_type VARCHAR(30) NOT NULL, -- 'vitals' | 'activity' | 'symptoms' | 'comprehensive'
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end TIMESTAMP WITH TIME ZONE NOT NULL,
    title VARCHAR(255) NOT NULL,
    summary TEXT NOT NULL,
    data_snapshot TEXT NOT NULL, -- JSON snapshot of vital records
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Uploaded Patient Medical Documents
CREATE TABLE medical_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    record_type VARCHAR(30) NOT NULL, -- 'lab_result' | 'prescription' | 'imaging'
    title VARCHAR(255) NOT NULL,
    notes TEXT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_data TEXT NULL, -- Nullable to allow transitioning to file URL storage
    file_url VARCHAR(512) NULL, -- S3/Object Storage bucket path
    file_mime VARCHAR(100) NOT NULL,
    file_size INT NOT NULL, -- File footprint in bytes
    provider_name VARCHAR(160) NULL,
    record_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- External Doctor Secure Share Links
CREATE TABLE record_share_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    share_token VARCHAR(64) UNIQUE NOT NULL,
    share_type VARCHAR(20) NOT NULL, -- 'report' | 'record' | 'all_reports'
    target_id UUID NULL,
    recipient_name VARCHAR(120) NOT NULL,
    recipient_email VARCHAR(120) NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    access_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Global Health Tips Catalog
CREATE TABLE health_tips (
    id SERIAL PRIMARY KEY,
    title VARCHAR(150) NULL,
    content TEXT NULL,
    category VARCHAR(80) NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------
-- 7. AUDITING, SECURITY & INTEGRATION TABLES
-- -------------------------------------------------------------------------

-- Mobile Device Tokens (Push Notifications Hub)
CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL, -- 'android' | 'ios' | 'web'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, device_token)
);

-- JWT Logout Revoked Tokens Blacklist
CREATE TABLE revoked_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token_jti VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Compliance Audit Log (Records Data Mutations & Shares)
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- Actor (sets null if deleted)
    action_type VARCHAR(100) NOT NULL, -- e.g., 'GENERATE_REPORT', 'REVOKE_SHARE_LINK'
    ip_address VARCHAR(45) NULL,
    user_agent VARCHAR(255) NULL,
    details TEXT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Master Allergies (Normalized)
CREATE TABLE allergies (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    category VARCHAR(50) DEFAULT 'other', -- e.g., 'food' | 'drug' | 'environmental'
    severity_level VARCHAR(20) DEFAULT 'unknown'
);

-- Patient Allergies Mapping (Normalized)
CREATE TABLE patient_allergies (
    patient_profile_id UUID NOT NULL REFERENCES patient_profiles(id) ON DELETE CASCADE,
    allergy_id INT NOT NULL REFERENCES allergies(id) ON DELETE CASCADE,
    noted_reaction TEXT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (patient_profile_id, allergy_id)
);

-- Consultation Billing & Transactions (Mobile Money integration)
CREATE TABLE consultation_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    appointment_id UUID REFERENCES appointments(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount NUMERIC(10, 2) NOT NULL, -- In XAF (Cameroon Central African CFA franc)
    currency VARCHAR(10) DEFAULT 'XAF',
    payment_method VARCHAR(50) NOT NULL, -- e.g., 'momo', 'om', 'card'
    payment_status VARCHAR(30) DEFAULT 'pending', -- 'pending' | 'success' | 'failed'
    transaction_reference VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------
-- 8. COMPOSITE INDEXES & PERFORMANCE OPTIMIZATIONS
-- -------------------------------------------------------------------------

-- Fast user lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- Telemetry query performance (Vitals and activity logs loaded on home dashboard)
CREATE INDEX IF NOT EXISTS idx_vital_logs_composite ON vital_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_logs_composite ON activity_logs(user_id, date DESC);

-- Push alerts query lookup
CREATE INDEX IF NOT EXISTS idx_reminder_alerts_schedule ON reminder_alerts(user_id, trigger_time ASC) WHERE is_enabled = TRUE;

-- Share Link validation speed index
CREATE INDEX IF NOT EXISTS idx_share_links_lookup ON record_share_links(share_token) WHERE is_revoked = FALSE;

-- Consultation chat threads speed index
CREATE INDEX IF NOT EXISTS idx_consultation_messages_thread ON consultation_messages(thread_id, created_at ASC);

-- Billing & audit queries speed indexes
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_user ON consultation_transactions(user_id, created_at DESC);

-- Junction mapping query acceleration
CREATE INDEX IF NOT EXISTS idx_symptom_map_condition ON symptom_condition_map(condition_id);
CREATE INDEX IF NOT EXISTS idx_symptom_map_symptom ON symptom_condition_map(symptom_id);
