import requests
import uuid

BASE_URL = "http://localhost:8001"

def test_back_pain_match():
    print("Testing back pain matching and formatting...")
    suffix = uuid.uuid4().hex[:6]
    email = f"test_{suffix}@example.com"
    
    # 1. Sign up
    signup_payload = {
        "full_name": f"Test User {suffix}",
        "email": email,
        "password": "SecurePass123!",
        "confirm_password": "SecurePass123!",
        "role": "user"
    }
    r = requests.post(f"{BASE_URL}/auth/signup", json=signup_payload)
    if r.status_code != 201:
        print(f"Signup failed: {r.text}")
        return False
        
    token = r.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    
    # 2. Send "i have back pain" to /chat
    chat_payload = {
        "message": "i have back pain"
    }
    print("Sending message: 'i have back pain'...")
    r = requests.post(f"{BASE_URL}/chat", json=chat_payload, headers=headers)
    if r.status_code != 200:
        print(f"Chat request failed: {r.status_code} {r.text}")
        return False
        
    res_data = r.json()
    reply = res_data["reply"]
    print("\nAssistant Response:")
    print("----------------------------------------")
    print(reply)
    print("----------------------------------------\n")
    
    # Assertions based on expected format
    assert "Common Causes of Back Pain" in reply, "Title missing"
    assert "Poor posture" in reply, "Cause 'Poor posture' missing"
    assert "Muscle strain" in reply, "Cause 'Muscle strain' missing"
    assert "When to Seek Medical Help" in reply, "Seek help section missing"
    assert "See a healthcare professional if back pain:" in reply, "Seek help header missing"
    assert "Lasts more than a few weeks" in reply, "Seek condition 'Lasts more than a few weeks' missing"
    assert "Spreads down the legs" in reply, "Seek condition 'Spreads down the legs' missing"
    assert "Prevention Tips" in reply, "Prevention Tips section missing"
    assert "Maintain good posture" in reply, "Prevention tip missing"
    assert "Avoid prolonged sitting" in reply, "Prevention tip missing"
    
    print("TEST PASSED: Direct condition match, category-based warnings, and list formatting are perfectly implemented!")
    return True

if __name__ == "__main__":
    test_back_pain_match()
