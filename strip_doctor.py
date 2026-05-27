import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Remove Doctor imports
    content = re.sub(r"import 'consultations_screen\.dart';\n", '', content)
    content = re.sub(r"import 'appointments_screen\.dart';\n", '', content)

    # Remove Doctor cards from main.dart
    card_pattern = r" +_buildDashboardCard\(\s*context,\s*title: '[^']+',\s*subtitle: '[^']+',\s*icon: [^,]+,\s*color: [^,]+,\s*onTap: \(\) => _navigate\(context, const (AppointmentsScreen|ConsultationsScreen)\(\)\),\s*\),\n"
    content = re.sub(card_pattern, '', content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

process_file('lib/main.dart')
process_file('lib/profile_screen.dart')
