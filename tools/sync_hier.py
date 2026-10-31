# -*- coding: utf-8 -*-
import shutil, os
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
pairs=[
 ('.vscode/settings.json','.vscode/settings.json'),
 ('.vscode/tasks.json','.vscode/tasks.json'),
 ('HIERARCHY.md','HIERARCHY.md'),
 ('tools/gen_hierarchy.py','tools/gen_hierarchy.py'),
 ('tools/get_ctags.ps1','tools/get_ctags.ps1'),
 ('CODE_READING_GUIDE.md','CODE_READING_GUIDE.md'),
 ('tags','tags'),
 ('vscode_hierarchy_preview.jpg','vscode_hierarchy_preview.jpg'),
]
for a,b in pairs:
    d=os.path.dirname(dst+'/'+b)
    if d: os.makedirs(d, exist_ok=True)
    shutil.copy2(src+'/'+a, dst+'/'+b)
print('synced')
