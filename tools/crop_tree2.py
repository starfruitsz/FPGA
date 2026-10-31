# -*- coding: utf-8 -*-
from PIL import Image
im = Image.open(r'C:/Users/Administrator/Desktop/task/_td_after.jpg')
crop = im.crop((0, 110, 320, 230)).resize((1280, 480))
crop.save(r'C:/Users/Administrator/Desktop/task/_td_tree2.png')
print(crop.size)
