# -*- coding: utf-8 -*-
import io, glob, collections, unicodedata
bad = collections.Counter()
where = collections.defaultdict(set)
for p in glob.glob(r'C:/Users/Administrator/Desktop/task/doc/*.tex'):
    if p.split('/')[-1].startswith('_'):
        continue
    s = io.open(p, encoding='utf-8').read()
    for ch in s:
        o = ord(ch)
        if o < 128:
            continue
        # CJK ideographs, CJK punctuation, fullwidth forms
        if 0x4E00 <= o <= 0x9FFF: continue
        if 0x3000 <= o <= 0x303F: continue
        if 0xFF00 <= o <= 0xFFEF: continue
        if o in (0x2018,0x2019,0x201C,0x201D,0x2014,0x2013,0x2026,0x00B7,0x00D7,0x00B1,0x00A0): continue
        bad[ch] += 1
        where[ch].add(p.split('/')[-1])
for ch, n in bad.most_common(30):
    print('U+%04X %s x%d  in %s' % (ord(ch), ch, n, ','.join(sorted(where[ch]))[:80]))
print('distinct:', len(bad))
