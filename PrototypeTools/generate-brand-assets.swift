import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
/// Recreate Bound's B-only vector and placeholder variants from native paths.
let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/bound-brand-assets"
let out = URL(fileURLWithPath: outputPath,isDirectory:true)
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let b=CGMutablePath()
b.move(to:CGPoint(x:292,y:232));b.addLine(to:CGPoint(x:546,y:232))
b.addCurve(to:CGPoint(x:734,y:376),control1:CGPoint(x:666,y:232),control2:CGPoint(x:734,y:278))
b.addCurve(to:CGPoint(x:659,y:502),control1:CGPoint(x:734,y:439),control2:CGPoint(x:708,y:481))
b.addCurve(to:CGPoint(x:767,y:644),control1:CGPoint(x:730,y:522),control2:CGPoint(x:767,y:571))
b.addCurve(to:CGPoint(x:567,y:792),control1:CGPoint(x:767,y:746),control2:CGPoint(x:697,y:792))
b.addLine(to:CGPoint(x:292,y:792));b.closeSubpath()
b.addRoundedRect(in:CGRect(x:417,y:340,width:187,height:114),cornerWidth:52,cornerHeight:52)
b.addRoundedRect(in:CGRect(x:417,y:557,width:218,height:122),cornerWidth:56,cornerHeight:56)
func mark(_ c:CGContext,white:Bool){c.setFillColor(white ? NSColor.white.cgColor:CGColor(red:0.16,green:0.135,blue:0.24,alpha:1));c.addPath(b);c.drawPath(using:.eoFill)}
func png(_ name:String,_ size:Int,background:Bool)throws{let c=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.translateBy(x:0,y:CGFloat(size));c.scaleBy(x:CGFloat(size)/1024,y:-CGFloat(size)/1024);if background{c.setFillColor(CGColor(red:0.961,green:0.945,blue:0.988,alpha:1));c.fill(CGRect(x:0,y:0,width:1024,height:1024));let colors:[CGColor]=[CGColor(red:1,green:0.72,blue:0.78,alpha:1),CGColor(red:0.72,green:0.62,blue:0.92,alpha:1),CGColor(red:0.63,green:0.79,blue:0.96,alpha:1)];for (i,color) in colors.enumerated(){c.setFillColor(color);c.fill(CGRect(x:224+i*192,y:224,width:192,height:576))}};mark(c,white:!background);let d=CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL,UTType.png.identifier as CFString,1,nil)!;CGImageDestinationAddImage(d,c.makeImage()!,nil);CGImageDestinationFinalize(d)}
for (n,s) in [("DeltaPlaceholder.png",200),("DeltaPlaceholder@2x.png",400),("DeltaPlaceholder@3x.png",600)]{try png(n,s,background:true)}
try png("mark-preview.png",1024,background:false)
var box=CGRect(x:0,y:0,width:1024,height:1024);let pdf=CGContext(out.appendingPathComponent("DeltaBoundMark.pdf") as CFURL,mediaBox:&box,nil)!;pdf.beginPDFPage(nil);pdf.translateBy(x:0,y:1024);pdf.scaleBy(x:1,y:-1);mark(pdf,white:true);pdf.endPDFPage();pdf.closePDF()
let svg="""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><path fill="white" fill-rule="evenodd" d="M292 232H546C666 232 734 278 734 376C734 439 708 481 659 502C730 522 767 571 767 644C767 746 697 792 567 792H292Z M469 340H552C581 340 604 363 604 392V402C604 431 581 454 552 454H469C440 454 417 431 417 402V392C417 363 440 340 469 340Z M473 557H579C610 557 635 582 635 613V623C635 654 610 679 579 679H473C442 679 417 654 417 623V613C417 582 442 557 473 557Z"/></svg>
"""
try (svg+"\n").write(to:out.appendingPathComponent("BoundMark.svg"),atomically:true,encoding:.utf8)
