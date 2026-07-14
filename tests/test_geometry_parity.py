import unittest
from dataclasses import dataclass
@dataclass
class R: x:float; y:float; w:float; h:float
def union(rs):
 x=min(r.x for r in rs); y=min(r.y for r in rs); return R(x,y,max(r.x+r.w for r in rs)-x,max(r.y+r.h for r in rs)-y)
def placement(sw,sh,dw,dh,mode):
 if mode=='stretch': return R(0,0,dw,dh)
 if mode=='center': return R((dw-sw)/2,(dh-sh)/2,sw,sh)
 s=(max if mode=='fill' else min)(dw/sw,dh/sh); return R((dw-sw*s)/2,(dh-sh*s)/2,sw*s,sh*s)
class T(unittest.TestCase):
 def test_layouts(self):
  cases=[[R(0,0,1920,1080),R(1920,0,1920,1080)],[R(0,0,1512,982),R(1512,-99,1920,1080)],[R(0,0,1920,1080),R(0,1080,1920,1080)],[R(-1080,0,1080,1920),R(0,200,2560,1440)],[R(-1920,-200,1920,1080),R(0,0,2560,1440),R(2560,300,1200,1920)],[R(-1512,100,1512,982),R(0,0,1920,1080)],[R(0,0,1512,982),R(1512,0,1920,1080)],[R(-1600,240,1600,900),R(0,0,2560,1440)]]
  expected=[R(0,0,3840,1080),R(0,-99,3432,1081),R(0,0,1920,2160),R(-1080,0,3640,1920),R(-1920,-200,5680,2420),R(-1512,0,3432,1082),R(0,0,3432,1080),R(-1600,0,4160,1440)]
  self.assertEqual([union(x) for x in cases],expected)
 def test_fill_fit(self): self.assertEqual(placement(1000,1000,1920,1080,'fill'),R(0,-420,1920,1920)); self.assertEqual(placement(1000,1000,1920,1080,'fit'),R(420,0,1080,1080))
 def test_rounding(self): self.assertEqual(round(100.25*2)/2,100.0); self.assertAlmostEqual((round(100.34*1.5)/1.5)*1.5,round(100.34*1.5))
if __name__=='__main__': unittest.main()
