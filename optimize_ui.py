import os
import re
import glob

files = glob.glob('/Users/mudassirs472/StudioProjects/infiplus_opd/lib/manage_patient/*.dart')

for file in files:
    with open(file, 'r') as f:
        content = f.read()

    # Replace AnimatedContainer with Container
    content = content.replace('AnimatedContainer(', 'Container(')
    
    # Remove duration: const Duration(milliseconds: 200),
    content = re.sub(r'duration:\s*(const\s*)?Duration\([^)]+\),?\s*', '', content)
    
    # Remove boxShadow: [...]
    # We'll use a regex that matches boxShadow: up to the closing bracket of the list.
    # Be careful with nested brackets. Since shadows are usually just one level of list, we can try:
    # boxShadow: [...] or boxShadow: isSelected ? [...] : []
    content = re.sub(r'boxShadow:\s*\[[^\]]*\]\s*,?', '', content)
    content = re.sub(r'boxShadow:\s*[^:]*\?[^:]*:\s*\[\]\s*,?', '', content)
    
    with open(file, 'w') as f:
        f.write(content)
print("Optimization complete.")
