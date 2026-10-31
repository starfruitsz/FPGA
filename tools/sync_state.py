# -*- coding: utf-8 -*-
import shutil
src=r'C:/Users/Administrator/Desktop/task'
dst=r'C:/Users/Administrator/Desktop/task/_remote'
for a in ['PROJECT_STATE.md','README.md']:
    shutil.copy2(src+'/'+a, dst+'/'+a)
print('synced')
