import os

count = 0
for root, dirs, files in os.walk('.'):
    for f in files:
        if f.endswith('.cpp') or f.endswith('.h'):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8', errors='ignore') as file:
                data = file.read()
            
            if 'std::print(' in data and '#include <print>' not in data:
                # Find a good place to insert it. After <format> is ideal, or just anywhere near top.
                if '#include <format>' in data:
                    new_data = data.replace('#include <format>', '#include <format>\n#include <print>')
                else:
                    new_data = '#include <print>\n' + data
                
                with open(path, 'w', encoding='utf-8') as file:
                    file.write(new_data)
                count += 1
                print(f"Added <print> to {path}")

print(f"Total files updated: {count}")
