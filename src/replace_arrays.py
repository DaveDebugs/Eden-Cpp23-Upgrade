import os
import re

pattern = re.compile(r'Common::(g_scm_branch|g_scm_desc|g_build_fullname|g_build_name|g_build_date|g_build_version|g_build_id|g_scm_rev)')
replacement = r'static_cast<const char*>(Common::\1)'

count = 0
for root, dirs, files in os.walk('.'):
    for f in files:
        if f.endswith('.cpp') and 'scm_rev.cpp' not in f and 'fatal.cpp' not in f:
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8', errors='ignore') as file:
                data = file.read()
            
            new_data = pattern.sub(replacement, data)
            if new_data != data:
                with open(path, 'w', encoding='utf-8') as file:
                    file.write(new_data)
                count += 1
                print(f"Replaced in {path}")

print(f"Total files updated: {count}")
