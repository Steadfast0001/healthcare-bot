CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(120) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number VARCHAR(30);
ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(50) NOT NULL DEFAULT 'user';
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS verification_token VARCHAR(255) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS verification_token_expires TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_token VARCHAR(255) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_token_expires TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_attempts INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP;

CREATE TABLE IF NOT EXISTS chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    user_message TEXT NOT NULL,
    ai_response TEXT NOT NULL,
    risk_level VARCHAR(20),
    possible_conditions TEXT,
    recommended_action TEXT,
    follow_up_question TEXT,
    disclaimer TEXT,
    warning TEXT,
    is_emergency BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE chats ADD COLUMN IF NOT EXISTS `possible_conditions` TEXT;
ALTER TABLE chats ADD COLUMN IF NOT EXISTS recommended_action TEXT;
ALTER TABLE chats ADD COLUMN IF NOT EXISTS follow_up_question TEXT;
ALTER TABLE chats ADD COLUMN IF NOT EXISTS disclaimer TEXT;
ALTER TABLE chats ADD COLUMN IF NOT EXISTS warning TEXT;
ALTER TABLE chats ADD COLUMN IF NOT EXISTS is_emergency BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS symptoms (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS conditions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) UNIQUE NOT NULL,
    description TEXT,
    severity VARCHAR(20),
    advice TEXT
);

CREATE TABLE IF NOT EXISTS symptom_condition_map (
    id SERIAL PRIMARY KEY,
    symptom_id INT REFERENCES symptoms(id) ON DELETE CASCADE,
    condition_id INT REFERENCES conditions(id) ON DELETE CASCADE,
    weight DECIMAL(5,2) DEFAULT 0.50,
    UNIQUE (symptom_id, condition_id)
);

CREATE TABLE IF NOT EXISTS ai_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    prompt_tokens INT,
    completion_tokens INT,
    model_used VARCHAR(50),
    response_time_ms INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS health_tips (
    id SERIAL PRIMARY KEY,
    title VARCHAR(150),
    content TEXT,
    category VARCHAR(80),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS emergency_keywords (
    id SERIAL PRIMARY KEY,
    keyword VARCHAR(100) UNIQUE,
    level VARCHAR(20)
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_chats_user_id ON chats(user_id);
CREATE INDEX IF NOT EXISTS idx_chats_created_at ON chats(created_at);
CREATE INDEX IF NOT EXISTS idx_symptoms_name ON symptoms(name);
CREATE INDEX IF NOT EXISTS idx_conditions_name ON conditions(name);
CREATE INDEX IF NOT EXISTS idx_emergency_keywords_keyword ON emergency_keywords(keyword);

INSERT INTO emergency_keywords (keyword, level) VALUES
('chest pain', 'emergency'),
('severe bleeding', 'emergency'),
('unconscious', 'emergency'),
('cannot breathe', 'emergency'),
('difficulty breathing', 'emergency'),
('shortness of breath', 'emergency'),
('stroke', 'emergency'),
('seizure', 'emergency'),
('suicidal thoughts', 'emergency'),
('pregnancy bleeding', 'emergency')
ON CONFLICT (keyword) DO NOTHING;

INSERT INTO health_tips (title, content, category) VALUES
('Malaria Prevention', 'Use insecticide-treated mosquito nets, wear long sleeves, and remove stagnant water around your home.', 'Prevention'),
('Hydration Advice', 'Drink enough clean water daily and use oral rehydration solution when dehydrated.', 'Wellness'),
('Balanced Nutrition', 'Eat fruits, vegetables, whole grains, and lean proteins while limiting excess sugar and salt.', 'Nutrition'),
('Mental Health Check-In', 'Make time for rest, supportive conversations, and professional help if stress feels overwhelming.', 'Mental Health'),
('Sleep Hygiene', 'Keep a regular sleep schedule and reduce screen use before bedtime.', 'Wellness')
ON CONFLICT DO NOTHING;
