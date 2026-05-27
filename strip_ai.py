import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Remove AI imports
    content = re.sub(r"import 'chat_screen\.dart';\n", '', content)
    content = re.sub(r"import 'symptom_checker_screen\.dart';\n", '', content)

    # Remove AI cards from main.dart
    card_pattern = r" +_buildDashboardCard\(\s*context,\s*title: '[^']+',\s*subtitle: '[^']+',\s*icon: [^,]+,\s*color: [^,]+,\s*onTap: \(\) => _navigate\(context, const (ChatScreen|SymptomCheckerScreen)\(\)\),\s*\),\n"
    content = re.sub(card_pattern, '', content)

    if 'profile_screen' in filepath:
        chat_button_pattern = r" +ListTile\(\s*leading: const Icon\(Icons\.chat_bubble_outline\),\s*title: const Text\('Health Chat'\),\s*onTap: \(\) => Navigator\.of\(context\)\s*\.push\(MaterialPageRoute\(builder: \(_\) => const ChatScreen\(\)\)\),\s*\),\n"
        content = re.sub(chat_button_pattern, '', content)
        
        # Also fix the _buildHistoryCard chat navigation error we saw earlier
        chat_nav_pattern = r"push\(MaterialPageRoute\(builder: \(_\) => const ChatScreen\(\)\)\);"
        content = re.sub(chat_nav_pattern, "push(MaterialPageRoute(builder: (_) => Container()));", content)


    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

process_file('lib/main.dart')
process_file('lib/profile_screen.dart')
