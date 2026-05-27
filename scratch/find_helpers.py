import re

with open("backend/main.py", "r", encoding="utf-8") as f:
    content = f.read()

funcs = [
    "_matched_symptoms_from_text",
    "_build_fallback_advice",
    "_call_gemini_with_tools",
    "_parse_structured_advice",
    "_is_health_query",
    "_detect_emergency_keywords",
    "_build_reply_text",
]

for func in funcs:
    matches = list(re.finditer(r"def\s+" + func, content))
    for m in matches:
        start_pos = m.start()
        # Find the line number
        line_num = content[:start_pos].count("\n") + 1
        print(f"Found {func} at line {line_num}")
