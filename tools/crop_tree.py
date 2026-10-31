# -*- coding: utf-8 -*-
from PIL import Image
im = Image.open(r'C:/Users/Administrator/Desktop/task/_td_now.jpg')
crop = im.crop((0, 80, 400, 260)).resize((800, 360))
crop.save(r'C:/Users/Administrator/Desktop/task/_td_tree.png')
print(im.size, '->', crop.size)
