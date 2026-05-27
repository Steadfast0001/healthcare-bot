import os
import re

def readd_tolist(content):
    # This is tricky because map() can span multiple lines.
    # Instead, let's just replace the specific broken occurrences based on a regex that captures the whole map block.
    # Or, simpler: we know they are mostly `children: something.map(...),` or `items: something.map(...),`.
    # Let's write a simple parenthesis balancer.
    
    out = []
    i = 0
    while i < len(content):
        # find .map(
        idx = content.find('.map(', i)
        if idx == -1:
            out.append(content[i:])
            break
        
        out.append(content[i:idx+5])
        i = idx + 5
        
        # balance parentheses
        depth = 1
        while depth > 0 and i < len(content):
            if content[i] == '(':
                depth += 1
            elif content[i] == ')':
                depth -= 1
            out.append(content[i])
            i += 1
            
        # now we are right after the closing parenthesis of map()
        # Check if the next non-whitespace characters are .toList()
        # If not, add .toList()
        
        # skip whitespace to check next tokens, but don't advance `i` permanently if we just need to append
        # Actually, let's just insert .toList() right here if the next text isn't .toList()
        
        rest = content[i:]
        if not rest.lstrip().startswith('.toList()'):
            out.append('.toList()')
            
    return "".join(out)

files_to_fix = [
    'lib/reports_records_screen.dart',
    'lib/health_tracker_screen.dart',
    'lib/patient_health_data_screen.dart',
    'lib/profile_screen.dart',
    'lib/chat_screen.dart',
    'lib/emergency_screen.dart',
    'lib/symptom_checker_screen.dart'
]

for f in files_to_fix:
    if os.path.exists(f):
        with open(f, 'r', encoding='utf-8') as file:
            content = file.read()
        
        new_content = readd_tolist(content)
        
        with open(f, 'w', encoding='utf-8') as file:
            file.write(new_content)
        print(f"Fixed {f}")
