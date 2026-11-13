// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QRectF>
namespace SoftGraphite {
inline qreal columnSplit(const QRectF &r,int side,qreal base){return (side==0?r.x()+r.width()+4:r.x()-4)-base;}
inline QRectF columnRect(const QRectF &original,int side,qreal base,qreal split){
 auto r=original;
 if(side==0)r.setWidth(base+split-4-original.x());
 else {r.setX(base+split+4);r.setWidth(original.x()+original.width()-r.x());}
 return r;
}
inline QRectF resolveColumn(const QRectF &original,const QRectF &wanted,int side,qreal base,qreal low,qreal high){
 return columnRect(original,side,base,qBound(low,columnSplit(wanted,side,base),high));
}
}
