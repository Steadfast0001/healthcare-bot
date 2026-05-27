import os
import re

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Fix withOpacity
    content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)

    # Fix multiple underscores: (_, __) -> (_, _) - actually the warning says "Unnecessary use of multiple underscores. Try using '_'."
    # In Dart 3, you can just use `_` multiple times. So `(__, ___) =>` becomes `(_, _) =>`
    # Let's just blindly replace `__` with `_` if it's isolated as a parameter?
    # Better regex: `\b__+\b` -> `_`
    content = re.sub(r'\b__+\b', '_', content)

    # Fix avoid_print
    # Skip for now, print is fine for local. Actually let's change `print(` to `debugPrint(`
    # But then we need `import 'package:flutter/foundation.dart';`
    if 'print(' in content:
        content = content.replace('print(', 'debugPrint(')
        if 'package:flutter/foundation.dart' not in content:
            # add import after the first import
            content = content.replace("import '", "import 'package:flutter/foundation.dart';\nimport '", 1)

    # Fix use_null_aware_elements (Use the null-aware marker '?' rather than a null check via an 'if')
    # This is harder to regex, it's usually `if (foo != null) foo` inside a collection `[ if (foo != null) foo ]` -> `[ foo? ]`
    
    # Fix unnecessary_to_list_in_spreads (Unnecessary use of 'toList' in a spread)
    content = re.sub(r'\.toList\(\)(?=\s*[,\]\}])', '', content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            fix_file(os.path.join(root, file))

print("Fixed warnings in all dart files.")
