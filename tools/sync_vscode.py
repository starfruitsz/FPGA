# -*- coding: utf-8 -*-
import shutil, os
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
pairs=[
 ('.vscode/settings.json','.vscode/settings.json'),
 ('.vscode/extensions.json','.vscode/extensions.json'),
 ('.vscode/tasks.json','.vscode/tasks.json'),
 ('CODE_READING_GUIDE.md','CODE_READING_GUIDE.md'),
 ('PROJECT_STATE.md','PROJECT_STATE.md'),
 ('README.md','README.md'),
 ('vscode_project.jpg','vscode_project.jpg'),
 ('vscode_scope_project.jpg','vscode_scope_project.jpg'),
]
for a,b in pairs:
    os.makedirs(os.path.dirname(dst+'/'+b), exist_ok=True) if os.path.dirname(b) else None
    shutil.copy2(src+'/'+a, dst+'/'+b)
print('synced')
