# -*- coding: utf-8 -*-
import shutil
src=r'C:/Users/Administrator/Desktop/task/README.md'
dst=r'C:/Users/Administrator/Desktop/task/_remote/README.md'
shutil.copy2(src,dst)
print('README synced')
