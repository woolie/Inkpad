//
//  WDDrawing.m
//  Inkpad
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  Copyright (c) 2009-2013 Steve Sprang
//

#if !TARGET_OS_IPHONE
#import "NSCoderAdditions.h"
#endif

#import "UIColor+Additions.h"
#import "WDColor.h"
#import "WDDocumentProtocol.h"
#import "WDImage.h"
#import "WDImageData.h"
#import "WDLayer.h"
#import "WDPath.h"
#import "WDRulerUnit.h"
#import "WDSVGHelper.h"
#import "WDUtilities.h"

const float kMinimumDrawingDimension = 16;
const float kMaximumDrawingDimension = 16000;
const float kMaximumBitmapImageArea = 4096 * 4096;
const float kMaximumCopiedBitmapImageDimension = 2048;
const float kMaximumThumbnailDimension = 120;

// encoder keys
NSString* const WDDrawingKey = @"WDDrawingKey";
NSString* const WDThumbnailKey = @"WDThumbnailKey";
NSString* const WDLayersKey = @"WDLayersKey";
NSString* const WDDimensionsKey = @"WDDimensionsKey";
NSString* const WDImageDatasKey = @"WDImageDatasKey";
NSString* const WDSettingsKey = @"WDSettingsKey";
NSString* const WDActiveLayerKey = @"WDActiveLayerKey";
NSString* const WDUnitsKey = @"WDUnitsKey";

// Setting Keys
NSString* const WDSnapToPoints = @"WDSnapToPoints";
NSString* const WDSnapToEdges = @"WDSnapToEdges";
NSString* const WDIsolateActiveLayer = @"WDIsolateActiveLayer";
NSString* const WDOutlineMode = @"WDOutlineMode";
NSString* const WDSnapToGrid = @"WDSnapToGrid";
NSString* const WDDynamicGuides = @"WDDynamicGuides";
NSString* const WDShowGrid = @"WDShowGrid";
NSString* const WDGridSpacing = @"WDGridSpacing";
NSString* const WDRulersVisible = @"WDRulersVisible";
NSString* const WDUnits = @"WDUnits";
NSString* const WDCustomSizeWidth = @"WDCustomSizeWidth";
NSString* const WDCustomSizeHeight = @"WDCustomSizeHeight";
NSString* const WDCustomSizeUnits = @"WDCustomSizeUnits";

// Notifications
NSString* const WDDrawingChangedNotification = @"WDDrawingChangedNotification";
NSString* const WDLayersReorderedNotification = @"WDLayersReorderedNotification";
NSString* const WDLayerAddedNotification = @"WDLayerAddedNotification";
NSString* const WDLayerDeletedNotification = @"WDLayerDeletedNotification";
NSString* const WDIsolateActiveLayerSettingChangedNotification = @"WDIsolateActiveLayerSettingChangedNotification";
NSString* const WDOutlineModeSettingChangedNotification = @"WDOutlineModeSettingChangedNotification";
NSString* const WDRulersVisibleSettingChangedNotification = @"WDRulersVisibleSettingChangedNotification";
NSString* const WDUnitsChangedNotification = @"WDUnitsChangedNotification";
NSString* const WDActiveLayerChanged = @"WDActiveLayerChanged";
NSString* const WDDrawingDimensionsChanged = @"WDDrawingDimensionsChanged";
NSString* const WDGridSpacingChangedNotification = @"WDGridSpacingChangedNotification";

WDRenderingMetaData WDRenderingMetaDataMake(float scale, UInt32 flags)
{
	WDRenderingMetaData metaData;

	metaData.scale = scale;
	metaData.flags = flags;

	return metaData;
}

BOOL WDRenderingMetaDataOutlineOnly(WDRenderingMetaData metaData)
{
	return (metaData.flags & WDRenderOutlineOnly) ? YES : NO;
}

@implementation WDDrawing

#pragma mark - Setup

// for use with SVG import only
- (instancetype) initWithUnits:(NSString*) units
{
	self = [super init];
	if (self != nil)
	{
		// create layers array
		_layers = [[NSMutableArray alloc] init];

		// create settings
		_settings = [[NSMutableDictionary alloc] init];
		_settings[WDUnits] = units;
		_settings[WDGridSpacing] = @([[NSUserDefaults standardUserDefaults] floatForKey:WDGridSpacing]);

		// image datas
		_imageDatas = [[NSMutableDictionary alloc] init];

		_undoManager = [[NSUndoManager alloc] init];
	}

	return self;
}

- (instancetype) initWithSize:(CGSize)size andUnits:(NSString *)units
{
	self = [super init];

	if (self != nil)
	{
		// we don't want to notify when we're initing
		[self beginSuppressingNotifications];

		_dimensions = size;

		_layers = [[NSMutableArray alloc] init];
		WDLayer *layer = [WDLayer layer];
		layer.drawing = self;
		[_layers addObject:layer];

		layer.name = [self uniqueLayerName];
		_activeLayer = layer;

		_settings = [[NSMutableDictionary alloc] init];

		// each drawing saves its own settings, but when a user alters them they become the default settings for new documents
		// since this is a new document, look up the values in the defaults...
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSArray *keyArray = @[WDShowGrid, WDSnapToGrid, WDSnapToPoints, WDSnapToEdges, WDDynamicGuides, WDRulersVisible];
		for (NSString *key in keyArray) {
			_settings[key] = @([defaults boolForKey:key]);
		}

		_settings[WDUnits] = units;
		_settings[WDGridSpacing] = @([defaults floatForKey:WDGridSpacing]);

		// NOTE: 'isolate active layer' is saved with the document, but that should always be turned off for a new document

		// for tracking redundant image data
		_imageDatas = [[NSMutableDictionary alloc] init];

		_undoManager = [[NSUndoManager alloc] init];

		[self endSuppressingNotifications];
	}

	return self;
}

- (instancetype) initWithImage:(UIImage *) image imageName:(NSString *) imageName
{
	self = [self initWithSize:image.size andUnits:@"Pixels"];

	if (self != nil)
	{
		// we don't want to notify when we're initing
		[self beginSuppressingNotifications];

		WDImage *imageElement = [WDImage imageWithUIImage:image inDrawing:self];

		[self addObject:imageElement];
		self.activeLayer.name = imageName;
		self.activeLayer.locked = YES;

		// add a new blank layer
		[self addLayer:[WDLayer layer]];

		[self endSuppressingNotifications];
	}

	return self;
}

- (instancetype) initWithCoder:(NSCoder *) coder
{
	self = [super init];
	if (self != nil)
	{
		_layers = [coder decodeObjectForKey:WDLayersKey];
		_dimensions = [coder decodeCGSizeForKey:WDDimensionsKey];
		_imageDatas = [coder decodeObjectForKey:WDImageDatasKey];
		_settings = [coder decodeObjectForKey:WDSettingsKey];

		if (!_settings[WDUnits]) {
			_settings[WDUnits] = [[NSUserDefaults standardUserDefaults] objectForKey:WDUnits];
		}

		_activeLayer = [coder decodeObjectForKey:WDActiveLayerKey];
		if (!_activeLayer) {
			_activeLayer = [_layers lastObject];
		}

		_undoManager = [[NSUndoManager alloc] init];

	#ifdef WD_DEBUG
		NSLog(@"Elements in drawing: %lu", (unsigned long)[self allElements].count);
	#endif
	}

	return self;
}

- (void)encodeWithCoder:(NSCoder *) coder
{
	// strip unused image datas
	[self purgeUnreferencedImageDatas];

	[coder encodeObject:_imageDatas forKey:WDImageDatasKey];
	[coder encodeObject:_layers forKey:WDLayersKey];
	[coder encodeObject:_activeLayer forKey:WDActiveLayerKey];
	[coder encodeCGSize:_dimensions forKey:WDDimensionsKey];

	[coder encodeObject:_settings forKey:WDSettingsKey];
}

- (id) copyWithZone:(NSZone *)zone
{
	WDDrawing *drawing = [[WDDrawing alloc] init];

	drawing->_dimensions = _dimensions;
	drawing->_settings = [_settings mutableCopy];
	drawing->_imageDatas = [_imageDatas mutableCopy];

	// copy layers
	drawing->_layers = [[NSMutableArray alloc] initWithArray:_layers copyItems:YES];
	[drawing->_layers makeObjectsPerformSelector:@selector(setDrawing:) withObject:drawing];

	// active layer
	drawing->_activeLayer = drawing->_layers[[_layers indexOfObject:_activeLayer]];

	[drawing purgeUnreferencedImageDatas];

	return drawing;
}

- (void) beginSuppressingNotifications
{
	_suppressNotifications++;
}

- (void) endSuppressingNotifications
{
	_suppressNotifications--;

	if (_suppressNotifications < 0)
	{
		NSLog(@"Unbalanced notification suppression: %d", (int) _suppressNotifications);
	}
}

- (BOOL) isSuppressingNotifications
{
	return (_suppressNotifications > 0) ? YES : NO;
}

#pragma mark - Drawing Attributes

// return all the elements in the drawing
- (NSArray *) allElements
{
	NSMutableArray *elements = [[NSMutableArray alloc] init];

	[_layers makeObjectsPerformSelector:@selector(addElementsToArray:) withObject:elements];

	return elements;
}

- (NSUInteger) snapFlags
{
	NSUInteger	  flags = 0;

	if ([_settings[WDSnapToGrid] boolValue]) {
		flags |= kWDSnapGrid;
	}

	if ([_settings[WDSnapToPoints] boolValue]) {
		flags |= kWDSnapNodes;
	}

	if ([_settings[WDSnapToEdges] boolValue]) {
		flags |= kWDSnapEdges;
	}

	return flags;
}

- (CGRect) bounds
{
	return CGRectMake(0, 0, _dimensions.width, _dimensions.height);
}

- (CGRect) styleBounds
{
	CGRect styleBounds = CGRectNull;

	for (WDLayer *layer in _layers) {
		styleBounds = CGRectUnion(styleBounds, layer.styleBounds);
	}

	return styleBounds;
}

#pragma mark - Image Data

- (void) purgeUnreferencedImageDatas
{
	WDImageData	 *imageData;
	NSData		  *digest;
	NSMutableArray  *images = [NSMutableArray array];

	_imageDatas = [[NSMutableDictionary alloc] init];

	for (WDImage *image in self.allElements)
	{
		if ([image isKindOfClass:[WDImage class]])
		{
			imageData = image.imageData;
			digest = WDSHA1DigestForData(imageData.data);
			_imageDatas[digest] = imageData;

			[images addObject:image];
		}
	}

	// we now only have unique image datas... ensure no image is pointing to one that's not tracked
	[images makeObjectsPerformSelector:@selector(useTrackedImageData) withObject:nil];
}

- (WDImageData *) imageDataForUIImage:(UIImage *)image
{
	WDImageData	 *imageData = nil;
	NSData		  *data;
	NSData		  *digest;

	CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(image.CGImage);
	if (alphaInfo == kCGImageAlphaNoneSkipLast) {
		// no alpha data, so let's make a JPEG
		data = UIImageJPEGRepresentation(image, 0.9);
	} else {
		data = UIImagePNGRepresentation(image);
	}

	digest = WDSHA1DigestForData(data);
	imageData = _imageDatas[digest];

	if (!imageData)
	{
		imageData = [WDImageData imageDataWithData:data];
		_imageDatas[digest] = imageData;
	}

	return imageData;
}

- (WDImageData *) trackedImageData:(WDImageData *)imageData
{
	NSData		  *digest = WDSHA1DigestForData(imageData.data);
	WDImageData	 *existingData = _imageDatas[digest];

	if (!existingData)
	{
		_imageDatas[digest] = imageData;
		return imageData;
	} else {
		return existingData;
	}
}

#pragma mark - Layers

- (void) addObject:(id)obj
{
	[_activeLayer addObject:obj];
}

- (void) setActiveLayer:(WDLayer *)layer
{
	if (_activeLayer == layer) {
		return;
	}

	NSUInteger oldIndex = self.indexOfActiveLayer;

	_activeLayer = layer;

	if (!self.isSuppressingNotifications) {
		NSDictionary *userInfo = @{@"old index": @(oldIndex)};
		[[NSNotificationCenter defaultCenter] postNotificationName:WDActiveLayerChanged object:self userInfo:userInfo];
	}
}

- (void) activateLayerAtIndex:(NSUInteger)ix
{
	self.activeLayer = _layers[ix];
}

- (NSUInteger) indexOfActiveLayer
{
	return _layers.count ? [_layers indexOfObject:_activeLayer] : -1;
}

- (void) removeLayer:(WDLayer *)layer
{
	[[_undoManager prepareWithInvocationTarget:self] insertLayer:layer atIndex:[_layers indexOfObject:layer]];

	NSUInteger index = [_layers indexOfObject:layer];
	NSValue *dirtyRect = [NSValue valueWithCGRect:layer.styleBounds];
	[_layers removeObject:layer];

	if (!self.isSuppressingNotifications) {
		NSDictionary *userInfo = @{@"index": @(index), @"rect": dirtyRect, @"layer": layer};
		[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:WDLayerDeletedNotification object:self userInfo:userInfo]];
	}
}

- (void) insertLayer:(WDLayer *)layer atIndex:(NSUInteger)index
{
	[[_undoManager prepareWithInvocationTarget:self] removeLayer:layer];

	[_layers insertObject:layer atIndex:index];

	if (!self.isSuppressingNotifications) {
		NSDictionary *userInfo = @{@"layer": layer, @"rect": [NSValue valueWithCGRect:layer.styleBounds]};
		[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:WDLayerAddedNotification object:self userInfo:userInfo]];
	}
}

- (NSString *) uniqueLayerName
{
	NSMutableSet *layerNames = [NSMutableSet set];

	for (WDLayer *layer in _layers) {
		if (!layer.name) {
			continue;
		}

		[layerNames addObject:layer.name];
	}

	NSString	*unique = nil;
	int		 uniqueIx = 1;

	do {
		unique = [NSString stringWithFormat:NSLocalizedString(@"Layer %d", @"Layer %d"), uniqueIx];
		uniqueIx++;
	} while ([layerNames containsObject:unique]);

	return unique;
}

- (void) addLayer:(WDLayer *)layer;
{
	layer.drawing = self;

	if (!layer.name) {
		layer.name = [self uniqueLayerName];
	}

	[self insertLayer:layer atIndex:self.indexOfActiveLayer+1];
	self.activeLayer = layer;
}

- (void) duplicateActiveLayer
{
	NSMutableData   *data = [NSMutableData data];
	NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];

	// encode
	[archiver encodeObject:self.activeLayer forKey:@"layer"];
	[archiver finishEncoding];

	// decode
	NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
	WDLayer *layer = [unarchiver decodeObjectForKey:@"layer"];
	[unarchiver finishDecoding];

	layer.drawing = self;
	layer.highlightColor = [UIColor saturatedRandomColor];

	[layer awakeFromEncoding];

	[self insertLayer:layer atIndex:self.indexOfActiveLayer+1];
	self.activeLayer = layer;
}

- (BOOL) canDeleteLayer
{
	return (_layers.count > 1) ? YES : NO;
}

- (void) deleteActiveLayer
{
	if (_layers.count < 2) {
		return;
	}

	//[activeLayer_ deselectAll];

	NSUInteger index = self.indexOfActiveLayer;

	// do this before decrementing index
	[self removeLayer:_activeLayer];

	if (index >= 1) {
		index--;
	}

	self.activeLayer = _layers[index];
}

- (void) moveLayerAtIndex:(NSUInteger)src toIndex:(NSUInteger)dest
{
	[self beginSuppressingNotifications];

	WDLayer *layer = _layers[src];
	[self removeLayer:layer];
	[self insertLayer:layer atIndex:dest];

	[self endSuppressingNotifications];

	if (!self.isSuppressingNotifications) {
		[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:WDLayersReorderedNotification object:self]];
	}
}

#pragma mark - Representations

- (void) renderInContext:(CGContextRef)ctx clipRect:(CGRect)clip metaData:(WDRenderingMetaData)metaData
{
	// make sure blending modes behave correctly
	CGContextBeginTransparencyLayer(ctx, NULL);

	for (WDLayer *layer in _layers) {
		if (!layer.hidden) {
			[layer renderInContext:ctx clipRect:clip metaData:metaData];
		}
	}

	CGContextEndTransparencyLayer(ctx);
}

- (UIImage *) pixelImage
{
	CGSize  dimensions = self.dimensions;
	double  scale = 1.0f;
	double  area = dimensions.width * dimensions.height;

	// make sure we don't use all the memory generating this bitmap
	if (area > kMaximumBitmapImageArea) {
		scale = sqrt(kMaximumBitmapImageArea) / sqrt(area);
		dimensions = WDMultiplySizeScalar(dimensions, scale);
		// whole pixel size
		dimensions = WDRoundSize(dimensions);
	}

	UIGraphicsBeginImageContext(dimensions);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextScaleCTM(ctx, scale, scale);
	[self renderInContext:ctx clipRect:self.bounds metaData:WDRenderingMetaDataMake(1, WDRenderDefault)];
	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return result;
}

- (UIImage *) image
{
	if ([self.units isEqualToString:@"Pixels"]) {
		// for pixel units, include the entire drawing bounds
		return [self pixelImage];
	}

	// for any other unit, crop to the style bounds of the drawing content
	CGRect styleBounds = self.styleBounds;
	CGRect docBounds = self.bounds;

	if (CGRectEqualToRect(styleBounds, CGRectNull)) {
		styleBounds = docBounds;
	} else {
		styleBounds = CGRectIntersection(styleBounds, docBounds);
	}

	// there's no canonical mapping from units to pixels: we'll double the resolution
	double  scale = 2.0f;
	CGSize  dimensions = WDMultiplySizeScalar(styleBounds.size, scale);
	double  area = dimensions.width * dimensions.height;

	// make sure we don't use all the memory generating this bitmap
	if (area > kMaximumBitmapImageArea) {
		double shrink = sqrt(kMaximumBitmapImageArea) / sqrt(area);
		dimensions = WDMultiplySizeScalar(dimensions, shrink);
		// whole pixel size
		dimensions = WDRoundSize(dimensions);

		// update the scale since it will have changed (approximately the same as scale *= shrink)
		scale = dimensions.width / styleBounds.size.width;
	}

	UIGraphicsBeginImageContext(dimensions);

	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextScaleCTM(ctx, scale, scale);
	CGContextTranslateCTM(ctx, -styleBounds.origin.x, -styleBounds.origin.y);
	[self renderInContext:ctx clipRect:self.bounds metaData:WDRenderingMetaDataMake(scale, WDRenderDefault)];

	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return result;
}

//
// Used for copying an image of the selection to the clipboard
//
+ (UIImage *) imageForElements:(NSArray *)elements scale:(float)scaleFactor
{
	CGRect contentBounds = CGRectNull;
	for (WDElement *element in elements) {
		contentBounds = CGRectUnion(contentBounds, element.styleBounds);
	}

	// apply the requested scale factor
	CGSize size = WDMultiplySizeScalar(contentBounds.size, scaleFactor);

	// make sure we didn't exceed the maximum dimension
	size = WDClampSize(size, kMaximumCopiedBitmapImageDimension);

	// ... and make sure the scale factor is still accurate
	scaleFactor = size.width / contentBounds.size.width;

	UIGraphicsBeginImageContext(size);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	// scale and offset the elements to render in the new image
	CGPoint origin = WDMultiplyPointScalar(contentBounds.origin, -scaleFactor);
	CGContextTranslateCTM(ctx, origin.x, origin.y);
	CGContextScaleCTM(ctx, scaleFactor, scaleFactor);
	for (WDElement *element in elements) {
		[element renderInContext:ctx metaData:WDRenderingMetaDataMake(scaleFactor, WDRenderDefault)];
	}

	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return result;
}

- (NSData *) PDFRepresentation
{
	CGRect			  mediaBox = CGRectMake(0, 0, _dimensions.width, _dimensions.height);
	CFMutableDataRef	data = CFDataCreateMutable(NULL, 0);
	CGDataConsumerRef	consumer = CGDataConsumerCreateWithCFData(data);
	CGContextRef		pdfContext = CGPDFContextCreate(consumer, &mediaBox, NULL);

	CGDataConsumerRelease(consumer);
	CGPDFContextBeginPage(pdfContext, NULL);

	// flip!
	CGContextTranslateCTM(pdfContext, 0, _dimensions.height);
	CGContextScaleCTM(pdfContext, 1, -1);

	[self renderInContext:pdfContext clipRect:self.bounds metaData:WDRenderingMetaDataMake(1, WDRenderFlipped)];
	CGPDFContextEndPage(pdfContext);

	CGContextRelease(pdfContext);

	NSData *nsdata = (NSData *)CFBridgingRelease(data);
	return nsdata;
}

- (NSData *) SVGRepresentation
{
	NSMutableString	 *svg = [NSMutableString string];
	WDSVGHelper		 *sharedHelper = [WDSVGHelper sharedSVGHelper];

	[sharedHelper beginSVGGeneration];

	[svg appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
	[svg appendString:@"<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\"\n"];
	[svg appendString:@"  \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n"];
	[svg appendString:@"<!-- Created with Inkpad (http://www.taptrix.com/) -->"];

	WDXMLElement *svgElement = [WDXMLElement elementWithName:@"svg"];
	[svgElement setAttribute:@"version" value:@"1.1"];
	[svgElement setAttribute:@"xmlns" value:@"http://www.w3.org/2000/svg"];
	[svgElement setAttribute:@"xmlns:xlink" value:@"http://www.w3.org/1999/xlink"];
	[svgElement setAttribute:@"xmlns:inkpad" value:@"http://taptrix.com/inkpad/svg_extensions"];
	[svgElement setAttribute:@"width" value:[NSString stringWithFormat:@"%gpt", _dimensions.width]];
	[svgElement setAttribute:@"height" value:[NSString stringWithFormat:@"%gpt", _dimensions.height]];
	[svgElement setAttribute:@"viewBox" value:[NSString stringWithFormat:@"0,0,%g,%g", _dimensions.width, _dimensions.height]];
	
	NSData *thumbnailData = [self thumbnailData];
	WDXMLElement *metadataElement = [WDXMLElement elementWithName:@"metadata"];
	WDXMLElement *thumbnailElement = [WDXMLElement elementWithName:@"inkpad:thumbnail"];
	[thumbnailElement setAttribute:@"xlink:href" value:[NSString stringWithFormat:@"data:%@;base64,\n%@", @"image/jpeg",
														[thumbnailData base64EncodedStringWithOptions:0]]];
	[metadataElement addChild:thumbnailElement];
	[svgElement addChild:metadataElement];

	for (WDImageData *imgData in _imageDatas.allValues)
	{
		NSString		*unique = [[WDSVGHelper sharedSVGHelper] uniqueIDWithPrefix:@"Image"];
		WDXMLElement	*image = [WDXMLElement elementWithName:@"image"];

		[image setAttribute:@"id" value:unique];
		[image setAttribute:@"overflow" value:@"visible"];
		[image setAttribute:@"width" floatValue:imgData.image.size.width];
		[image setAttribute:@"height" floatValue:imgData.image.size.height];

		NSString *base64encoding = [NSString stringWithFormat:@"data:%@;base64,\n%@", imgData.mimetype, [imgData.data base64EncodedStringWithOptions:0]];
		[image setAttribute:@"xlink:href" value:base64encoding];

		[sharedHelper addDefinition:image];
		[sharedHelper setImageID:unique forDigest:imgData.digest];
	}

	WDXMLElement *drawingMetadataElement = [WDXMLElement elementWithName:@"metadata"];
	[_settings enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		WDXMLElement *settingElement = [WDXMLElement elementWithName:@"inkpad:setting"];
		[settingElement setAttribute:@"key" value:[key substringFromIndex:2]];
		[settingElement setAttribute:@"value" value:[NSString stringWithFormat:@"%@", obj]];
		[drawingMetadataElement addChild:settingElement];
	}];

	[svgElement addChild:drawingMetadataElement];
	[svgElement addChild:[sharedHelper definitions]];

	for (WDLayer *layer in _layers) {
		WDXMLElement *layerSVG = [layer SVGElement];

		if (layerSVG) {
			[svgElement addChild:layerSVG];
		}
	}
	
	[svg appendString:[svgElement XMLValue]];
	NSData *result = [svg dataUsingEncoding:NSUTF8StringEncoding];

	[sharedHelper endSVGGeneration];

	return result;
}

- (UIImage *) thumbnailImage
{
	float   width = kMaximumThumbnailDimension, height = kMaximumThumbnailDimension;
	float   aspectRatio = _dimensions.width / _dimensions.height;

	if (_dimensions.height > _dimensions.width) {
		width = round(kMaximumThumbnailDimension * aspectRatio);
	} else {
		height = round(kMaximumThumbnailDimension / aspectRatio);
	}

	CGSize  size = CGSizeMake(width, height);

	// always generate the 2x icon
	UIGraphicsBeginImageContextWithOptions(size, NO, 2);
	CGContextRef ctx = UIGraphicsGetCurrentContext();

	CGContextSetGrayFillColor(ctx, 1, 1);
	CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));

	float scale = width / _dimensions.width;
	CGContextScaleCTM(ctx, scale, scale);
	[self renderInContext:ctx clipRect:self.bounds metaData:WDRenderingMetaDataMake(scale, WDRenderThumbnail)];

	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return result;
}

- (NSData *) thumbnailData
{
	return UIImageJPEGRepresentation([self thumbnailImage], 0.9f);
}

- (NSData *) inkpadRepresentation
{
#if WD_DEBUG
	NSDate *date = [NSDate date];
#endif

	NSMutableData *data = [NSMutableData data];
	NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];

	// Customize archiver here
	[archiver encodeObject:self forKey:WDDrawingKey];
	[archiver encodeObject:[self thumbnailData] forKey:WDThumbnailKey];

	[archiver finishEncoding];

#if WD_DEBUG
	NSLog(@"Encoding time: %f", -[date timeIntervalSinceNow]);
#endif

	return data;
}

#pragma mark - Settings

- (void) setSetting:(NSString *)name value:(NSString *)value
{
	if ([name hasPrefix:@"WD"])
	{
		[_settings setValue:value forKey:name];
	}
	else
	{
		[_settings setValue:value forKey:[@"WD" stringByAppendingString:name]];
	}
}

- (BOOL) snapToPoints
{
	return [_settings[WDSnapToPoints] boolValue];
}

- (void) setSnapToPoints:(BOOL)snap
{
	_settings[WDSnapToPoints] = @(snap);

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (BOOL) snapToEdges
{
	return [_settings[WDSnapToEdges] boolValue];
}

- (void) setSnapToEdges:(BOOL)snap
{
	_settings[WDSnapToEdges] = @(snap);

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (BOOL) snapToGrid
{
	return [_settings[WDSnapToGrid] boolValue];
}

- (void) setSnapToGrid:(BOOL)snap
{
	_settings[WDSnapToGrid] = @(snap);

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (BOOL) dynamicGuides
{
	return [_settings[WDDynamicGuides] boolValue];
}

- (void) setDynamicGuides:(BOOL)dynamicGuides
{
	_settings[WDDynamicGuides] = @(dynamicGuides);

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (BOOL) isolateActiveLayer
{
	return [_settings[WDIsolateActiveLayer] boolValue];
}

- (void) setIsolateActiveLayer:(BOOL)isolate
{
	_settings[WDIsolateActiveLayer] = @(isolate);
	[[NSNotificationCenter defaultCenter] postNotificationName:WDIsolateActiveLayerSettingChangedNotification object:self];

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (BOOL) outlineMode
{
	return [_settings[WDOutlineMode] boolValue];
}

- (void) setOutlineMode:(BOOL)outline
{
	_settings[WDOutlineMode] = @(outline);
	[[NSNotificationCenter defaultCenter] postNotificationName:WDOutlineModeSettingChangedNotification object:self];

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (void) setShowGrid:(BOOL)showGrid
{
	_settings[WDShowGrid] = @(showGrid);
	[[NSNotificationCenter defaultCenter] postNotificationName:WDDrawingChangedNotification object:self];

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (BOOL) showGrid
{
	return [_settings[WDShowGrid] boolValue];
}

- (float) gridSpacing
{
	return [_settings[WDGridSpacing] floatValue];
}

- (void) setGridSpacing:(float)spacing
{
	spacing = WDClamp(1, kMaximumDrawingDimension / 2, spacing);

	_settings[WDGridSpacing] = @(spacing);
	[[NSNotificationCenter defaultCenter] postNotificationName:WDGridSpacingChangedNotification object:self];

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (BOOL) rulersVisible
{
	return [_settings[WDRulersVisible] boolValue];
}

- (void) setRulersVisible:(BOOL)visible
{
	_settings[WDRulersVisible] = @(visible);
	[[NSNotificationCenter defaultCenter] postNotificationName:WDRulersVisibleSettingChangedNotification object:self];

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (NSString *) units
{
	return _settings[WDUnits];
}

- (void) setUnits:(NSString *)units
{
	_settings[WDUnits] = units;
	[[NSNotificationCenter defaultCenter] postNotificationName:WDUnitsChangedNotification object:self];

	// this isn't an undoable action so it does not dirty the document
	[self.document markChanged];
}

- (WDRulerUnit *) rulerUnit
{
	return [WDRulerUnit rulerUnits][self.units];
}

- (float) width
{
	return _dimensions.width;
}

- (void) setWidth:(float) width
{
	if (_dimensions.width == width)
	{
		return;
	}

	[(WDDrawing *)[_undoManager prepareWithInvocationTarget:self] setWidth:_dimensions.width];
	_dimensions.width = WDClamp(kMinimumDrawingDimension, kMaximumDrawingDimension, width);
	[[NSNotificationCenter defaultCenter] postNotificationName:WDDrawingDimensionsChanged object:self];
}

- (float) height
{
	return _dimensions.height;
}

- (void) setHeight:(float)height
{
	if (_dimensions.height == height)
	{
		return;
	}

	[[_undoManager prepareWithInvocationTarget:self] setHeight:_dimensions.height];
	_dimensions.height = WDClamp(kMinimumDrawingDimension, kMaximumDrawingDimension, height);
	[[NSNotificationCenter defaultCenter] postNotificationName:WDDrawingDimensionsChanged object:self];
}

@end
