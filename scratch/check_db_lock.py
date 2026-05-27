import sqlite3

try:
    print("Opening wadocta.db...")
    conn = sqlite3.connect("wadocta.db", timeout=2)
    cursor = conn.cursor()
    print("Writing a dummy row to health_tips...")
    cursor.execute("INSERT INTO health_tips (title, content, category) VALUES ('test', 'test', 'test')")
    conn.commit()
    print("Write successful!")
    print("Cleaning up dummy row...")
    cursor.execute("DELETE FROM health_tips WHERE title='test'")
    conn.commit()
    print("Cleanup successful!")
    conn.close()
except Exception as e:
    print("Error:", e)
