//
//  WDDrawing.h
//  Inkpad
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  Copyright (c) 2009-2013 Steve Sprang
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#import "WDDocumentProtocol.h"
#import "WDStrokeStyle.h"

@class WDColor;
@class WDDrawing;
@class WDElement;
@class WDGradient;
@class WDImageData;
@class WDLayer;
@class WDPickResult;
@class WDRulerUnit;

extern const float kMinimumDrawingDimension;
extern const float kMaximumDrawingDimension;

enum
{
	WDRenderDefault	  = 0x0,
	WDRenderOutlineOnly  = 0x1,
	WDRenderThumbnail	= 0x1 << 1,
	WDRenderFlipped	  = 0x1 << 2
};

typedef struct
{
	float   scale;
	UInt32  flags;
} WDRenderingMetaData;

WDRenderingMetaData WDRenderingMetaDataMake(float scale, UInt32 flags);
BOOL WDRenderingMetaDataOutlineOnly(WDRenderingMetaData metaData);

@protocol WDDocumentProtocol;
@protocol WDPathPainter;

@interface WDDrawing : NSObject <NSCoding, NSCopying>
{
	NSMutableDictionary*	_imageDatas;
	NSInteger				_suppressNotifications;
}

@property (nonatomic, readonly) CGSize dimensions;
@property (nonatomic, readonly) NSMutableArray* layers;
@property (weak, nonatomic, readonly) WDLayer* activeLayer;
@property (nonatomic, readonly) NSMutableDictionary* settings;
@property (nonatomic, assign) BOOL deleted;
@property (nonatomic, strong) NSUndoManager* undoManager;
@property (nonatomic, weak) id<WDDocumentProtocol> document;

@property (nonatomic, assign) float width;
@property (nonatomic, assign) float height;
@property (nonatomic, readonly) CGRect bounds;
@property (nonatomic, readonly) NSUInteger indexOfActiveLayer;
@property (nonatomic, assign) BOOL snapToEdges;
@property (nonatomic, assign) BOOL snapToPoints;
@property (nonatomic, assign) BOOL snapToGrid;
@property (nonatomic, assign) BOOL dynamicGuides;
@property (nonatomic, assign) BOOL showGrid;
@property (nonatomic, assign) BOOL isolateActiveLayer;
@property (nonatomic, assign) BOOL outlineMode;
@property (nonatomic, assign) BOOL rulersVisible;
@property (nonatomic, weak) NSString* units;
@property (weak, nonatomic, readonly) WDRulerUnit* rulerUnit;
@property (nonatomic, assign) float gridSpacing;
@property (nonatomic, readonly) BOOL isSuppressingNotifications;
@property (nonatomic, readonly) NSArray* allElements;
@property (nonatomic, readonly) NSUInteger snapFlags;
@property (nonatomic, readonly) UIImage* image;
@property (nonatomic, readonly) NSData* inkpadRepresentation;
@property (nonatomic, readonly) NSData* PDFRepresentation;
@property (nonatomic, readonly) NSData* SVGRepresentation;
@property (nonatomic, readonly) NSData* thumbnailData;
@property (nonatomic, readonly) UIImage* thumbnailImage;
@property (nonatomic, readonly) BOOL canDeleteLayer;
@property (nonatomic, readonly) NSString* uniqueLayerName;

- (instancetype) initWithUnits:(NSString*) units; // for use with SVG import only
- (instancetype) initWithSize:(CGSize) size andUnits:(NSString*) units;

- (void) beginSuppressingNotifications;
- (void) endSuppressingNotifications;

- (void) purgeUnreferencedImageDatas;
- (WDImageData*) trackedImageData:(WDImageData*) imageData;

- (void) renderInContext:(CGContextRef) ctx clipRect:(CGRect) clip metaData:(WDRenderingMetaData) metaData;

- (void) activateLayerAtIndex:(NSUInteger)ix;
- (void) addLayer:(WDLayer*) layer;
- (void) deleteActiveLayer;
- (void) insertLayer:(WDLayer*) layer atIndex:(NSUInteger)index;
- (void) moveLayerAtIndex:(NSUInteger)src toIndex:(NSUInteger)dest;
- (void) duplicateActiveLayer;

- (void) addObject:(id)obj;

- (instancetype) initWithImage:(UIImage*) image imageName:(NSString*) imageName;
- (WDImageData*) imageDataForUIImage:(UIImage*)image;
+ (UIImage*) imageForElements:(NSArray*) elements scale:(float) scale;

- (void) setSetting:(NSString*) name value:(NSString*) value;

@end

// Setting keys
extern NSString* const WDSnapToPoints;
extern NSString* const WDSnapToEdges;
extern NSString* const WDSnapToGrid;
extern NSString* const WDDynamicGuides;
extern NSString* const WDShowGrid;
extern NSString* const WDGridSpacing;
extern NSString* const WDIsolateActiveLayer;
extern NSString* const WDOutlineMode;
extern NSString* const WDRulersVisible;
extern NSString* const WDUnits;
extern NSString* const WDCustomSizeWidth;
extern NSString* const WDCustomSizeHeight;
extern NSString* const WDCustomSizeUnits;

// Notifications
extern NSString* const WDLayersReorderedNotification;
extern NSString* const WDLayerAddedNotification;
extern NSString* const WDLayerDeletedNotification;
extern NSString* const WDIsolateActiveLayerSettingChangedNotification;
extern NSString* const WDOutlineModeSettingChangedNotification;
extern NSString* const WDActiveLayerChanged;
extern NSString* const WDDrawingChangedNotification;
extern NSString* const WDRulersVisibleSettingChangedNotification;
extern NSString* const WDUnitsChangedNotification;
extern NSString* const WDDrawingDimensionsChanged;
extern NSString* const WDGridSpacingChangedNotification;

// encoder keys
extern NSString* const WDDrawingKey;
extern NSString* const WDThumbnailKey;
