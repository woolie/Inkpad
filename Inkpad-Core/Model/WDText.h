//
//  WDText.h
//  Inkpad
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  Copyright (c) 2009-2013 Steve Sprang
//

#if TARGET_OS_MAC
#import <UIKit/UIKit.h>
#endif

#import <CoreText/CoreText.h>
#import "WDStylable.h"
#import "WDTextRenderer.h"

@class WDAbstractPath;
@class WDStrokeStyle;
@protocol WDPathPainter;

@interface WDText : WDStylable <NSCoding, NSCopying, WDTextRenderer>
{
    CGMutablePathRef    _pathRef;
    
    BOOL                _needsLayout;
    NSMutableArray*		_glyphs;
    CGRect              _styleBounds;
    
    NSString*			_cachedText;
    CGAffineTransform   _cachedTransform;
    float               _cachedWidth;
    BOOL                _cachingWidth;
    
    BOOL                _naturalBoundsDirty;
}

@property (nonatomic, assign) float width;
@property (nonatomic, strong) NSString *fontName;
@property (nonatomic, assign) float fontSize;
@property (nonatomic, assign) CGAffineTransform transform;
@property (nonatomic, strong) NSString *text;
@property (nonatomic, assign) NSTextAlignment alignment;
@property (nonatomic, readonly) CGRect naturalBounds;
@property (nonatomic, readonly) CTFontRef fontRef;
@property (nonatomic, readonly, strong) NSAttributedString *attributedString;

// An array of WDPath objects representing each glyph in the text object
@property (nonatomic, readonly) NSArray<WDAbstractPath*>* outlines;

@property (class, readonly) CGFloat minimumWidth;

- (void) moveHandle:(NSUInteger)handle toPoint:(CGPoint)pt;

- (void) cacheOriginalText;
- (void) registerUndoWithCachedText;

- (void) cacheTransformAndWidth;
- (void) registerUndoWithCachedTransformAndWidth;

- (void) drawOpenGLTextOutlinesWithTransform:(CGAffineTransform)transform viewTransform:(CGAffineTransform)viewTransform;

- (void) setFontNameQuiet:(NSString *)fontName;
- (void) setFontSizeQuiet:(float)fontSize;
- (void) setTextQuiet:(NSString *)text;
- (void) setTransformQuiet:(CGAffineTransform)transform;
- (void) setWidthQuiet:(float)width;

@end
