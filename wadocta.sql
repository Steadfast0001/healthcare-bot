CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DROP TABLE IF EXISTS ai_logs CASCADE;
DROP TABLE IF EXISTS chats CASCADE;
DROP TABLE IF EXISTS symptom_condition_map CASCADE;
DROP TABLE IF EXISTS emergency_keywords CASCADE;
DROP TABLE IF EXISTS health_tips CASCADE;
DROP TABLE IF EXISTS conditions CASCADE;
DROP TABLE IF EXISTS symptoms CASCADE;
DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name VARCHAR(120) NOT NULL,
    username VARCHAR(120) UNIQUE,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone_number VARCHAR(30),
    role VARCHAR(50) NOT NULL DEFAULT 'user',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_token VARCHAR(255) UNIQUE,
    verification_token_expires TIMESTAMP,
    reset_token VARCHAR(255) UNIQUE,
    reset_token_expires TIMESTAMP,
    failed_login_attempts INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP,
    last_login_at TIMESTAMP,
    age INT,
    gender VARCHAR(20),
    country VARCHAR(80),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    user_message TEXT NOT NULL,
    ai_response TEXT NOT NULL,
    risk_level VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE symptoms (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE conditions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) UNIQUE NOT NULL,
    description TEXT,
    severity VARCHAR(20),
    advice TEXT
);

CREATE TABLE symptom_condition_map (
    id SERIAL PRIMARY KEY,
    symptom_id INT REFERENCES symptoms(id) ON DELETE CASCADE,
    condition_id INT REFERENCES conditions(id) ON DELETE CASCADE,
    weight DECIMAL(5,2) DEFAULT 0.50,
    UNIQUE (symptom_id, condition_id)
);

CREATE TABLE ai_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    prompt_tokens INT,
    completion_tokens INT,
    model_used VARCHAR(50),
    response_time_ms INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE health_tips (
    id SERIAL PRIMARY KEY,
    title VARCHAR(150),
    content TEXT,
    category VARCHAR(80),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE emergency_keywords (
    id SERIAL PRIMARY KEY,
    keyword VARCHAR(100) UNIQUE,
    level VARCHAR(20)
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_chats_user_id ON chats(user_id);
CREATE INDEX idx_chats_created_at ON chats(created_at);
CREATE INDEX idx_symptoms_name ON symptoms(name);
CREATE INDEX idx_conditions_name ON conditions(name);
CREATE INDEX idx_emergency_keywords_keyword ON emergency_keywords(keyword);

INSERT INTO symptoms (name, description) VALUES
('fever', 'Elevated body temperature'),
('headache', 'Pain in the head'),
('cough', 'Persistent coughing'),
('vomiting', 'Throwing up'),
('fatigue', 'Feeling tired'),
('chest pain', 'Pain or pressure in the chest'),
('shortness of breath', 'Difficulty breathing'),
('nausea', 'Feeling like vomiting');

INSERT INTO conditions (name, description, severity, advice) VALUES
('Malaria', 'Mosquito-borne disease common in tropical areas', 'high', 'Seek malaria testing and treatment immediately.'),
('Flu', 'Viral respiratory infection', 'medium', 'Rest, hydrate, and monitor symptoms.'),
('Typhoid', 'Bacterial infection often linked to contaminated food or water', 'high', 'Visit a hospital or clinic for diagnosis and treatment.'),
('Dehydration', 'Loss of body fluids', 'medium', 'Drink oral rehydration fluids and seek care if severe.'),
('Possible Emergency', 'Symptoms may indicate an urgent medical emergency', 'high', 'Seek emergency medical care immediately.');

INSERT INTO symptom_condition_map (symptom_id, condition_id, weight) VALUES
(1, 1, 0.90),
(1, 2, 0.60),
(1, 3, 0.70),
(2, 1, 0.65),
(2, 2, 0.50),
(3, 2, 0.75),
(4, 3, 0.65),
(4, 4, 0.70),
(5, 4, 0.85),
(6, 5, 1.00),
(7, 5, 1.00);

INSERT INTO emergency_keywords (keyword, level) VALUES
('chest pain', 'emergency'),
('severe bleeding', 'emergency'),
('unconscious', 'emergency'),
('cannot breathe', 'emergency'),
('difficulty breathing', 'emergency'),
('shortness of breath', 'emergency'),
('stroke', 'emergency'),
('seizure', 'emergency');

INSERT INTO health_tips (title, content, category) VALUES
('Malaria Prevention', 'Use insecticide-treated mosquito nets, wear long sleeves, and remove stagnant water around your home.', 'Prevention'),
('Hydration Advice', 'Drink enough clean water daily and use oral rehydration solution when dehydrated.', 'Wellness'),
('Balanced Nutrition', 'Eat fruits, vegetables, whole grains, and lean proteins while limiting excess sugar and salt.', 'Nutrition'),
('Sleep Hygiene', 'Keep a regular sleep schedule and avoid screens close to bedtime.', 'Wellness');

SELECT
    s.name AS symptom,
    c.name AS possible_condition,
    c.severity,
    c.advice,
    scm.weight
FROM symptom_condition_map scm
JOIN symptoms s ON s.id = scm.symptom_id
JOIN conditions c ON c.id = scm.condition_id
WHERE LOWER(s.name) = LOWER('fever')
ORDER BY scm.weight DESC;
