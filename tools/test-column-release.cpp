// SPDX-License-Identifier: GPL-2.0-or-later
// Build from repo root with Qt6Core cflags/libs; execute the resulting test binary.
#include "../core/native/resize-outline/column-resize.h"
#include <cassert>
#include <iostream>
using namespace SoftGraphite;
int main(){
 int count=0;
 for(qreal base:{-1920.,0.,1536.})for(qreal total:{1536.,1920.})for(int side:{0,1}){
  const qreal low=612,high=total-712,split=total/2;
  const QRectF original=side==0?QRectF(base+8,158,split-12,736.4):QRectF(base+split+4,158,total-split-12,736.4);
  for(qreal requested:{13.,300.,612.,700.,total-712.,total-13.}){
   const QRectF wanted=columnRect(original,side,base,requested);
   assert(qAbs(columnSplit(wanted,side,base)-requested)<1e-8);
   const QRectF result=resolveColumn(original,wanted,side,base,low,high);
   assert(qAbs(columnSplit(result,side,base)-qBound(low,requested,high))<1e-8);
   assert(result.y()==original.y()&&result.height()==736.4);
   assert(side==0?result.left()==original.left():result.right()==original.right());
   assert(result.width()>= (side==0?600.:700.)-1e-8);++count;
  }
 }
 std::cout<<"PASS: "<<count<<" release resolutions, both sides, negative origins and fractional height\n";
}
