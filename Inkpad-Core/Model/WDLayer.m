//
//  WDLayer.m
//  Inkpad
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  Copyright (c) 2010-2013 Steve Sprang
//

#import "UIColor+Additions.h"
#import "WDElement.h"
#import "WDLayer.h"
#import "WDSVGHelper.h"
#import "WDUtilities.h"

#define kDrawPreviewBorder		  NO

const CGFloat kPreviewInset = 0;
const CGFloat kDefaultThumbnailDimension = 50;

NSString* const WDLayerVisibilityChanged = @"WDLayerVisibilityChanged";
NSString* const WDLayerLockedStatusChanged = @"WDLayerLockedStatusChanged";
NSString* const WDLayerOpacityChanged = @"WDLayerOpacityChanged";
NSString* const WDLayerContentsChangedNotification = @"WDLayerContentsChangedNotification";
NSString* const WDLayerThumbnailChangedNotification = @"WDLayerThumbnailChangedNotification";
NSString* const WDLayerNameChanged = @"WDLayerNameChanged";

NSString* const WDElementsKey = @"WDElementsKey";
NSString* const WDVisibleKey = @"WDVisibleKey";
NSString* const WDLockedKey = @"WDLockedKey";
NSString* const WDNameKey = @"WDNameKey";
NSString* const WDHighlightColorKey = @"WDHighlightColorKey";
NSString* const WDOpacityKey = @"WDOpacityKey";

@implementation WDLayer

+ (instancetype) layer
{
	return [[WDLayer alloc] init];
}

- (instancetype) init
{
	NSMutableArray* elements = [[NSMutableArray alloc] init];
	return [self initWithElements:elements];
}

- (instancetype) initWithElements:(NSMutableArray*) elements
{
	self = [super init];
	
	if (self != nil)
	{
		_elements = elements;
		[_elements makeObjectsPerformSelector:@selector(setLayer:) withObject:self];
		self.highlightColor = [UIColor saturatedRandomColor];
		self.visible = YES;
		_opacity = 1.0f;
	}

	return self;
}

- (void) encodeWithCoder:(NSCoder*) coder
{
	[coder encodeObject:_elements forKey:WDElementsKey];
	[coder encodeConditionalObject:_drawing forKey:WDDrawingKey];
	[coder encodeBool:_visible forKey:WDVisibleKey];
	[coder encodeBool:_locked forKey:WDLockedKey];
	[coder encodeObject:_name forKey:WDNameKey];
#if TARGET_OS_IPHONE
	[coder encodeObject:_highlightColor forKey:WDHighlightColorKey];
#endif
	
	if (_opacity != 1.0f)
	{
		[coder encodeFloat:_opacity forKey:WDOpacityKey];
	}
}

- (instancetype) initWithCoder:(NSCoder *) coder
{
	self = [super init];
	
	_elements = [coder decodeObjectForKey:WDElementsKey];
	_drawing = [coder decodeObjectForKey:WDDrawingKey];
	_visible = [coder decodeBoolForKey:WDVisibleKey];
	_locked = [coder decodeBoolForKey:WDLockedKey];
	self.name = [coder decodeObjectForKey:WDNameKey];
#if TARGET_OS_IPHONE
	self.highlightColor = [coder decodeObjectForKey:WDHighlightColorKey];
#endif
	
	if ([coder containsValueForKey:WDOpacityKey]) {
		self.opacity = [coder decodeFloatForKey:WDOpacityKey];
	} else {
		self.opacity = 1.0f;
	}
	
	if (!self.highlightColor) {
		self.highlightColor = [UIColor saturatedRandomColor];
	}
	
	return self; 
}

- (void) awakeFromEncoding
{
	[_elements makeObjectsPerformSelector:@selector(awakeFromEncoding) withObject:nil];
}

- (BOOL) isSuppressingNotifications
{
	if (!_drawing || _drawing.isSuppressingNotifications)
	{
		return YES;
	}
	
	return NO;
}

- (void) renderInContext:(CGContextRef)ctx clipRect:(CGRect)clip metaData:(WDRenderingMetaData)metaData
{
	BOOL useTransparencyLayer = (!WDRenderingMetaDataOutlineOnly(metaData) && _opacity != 1.0f) ? YES : NO;
	
	if (useTransparencyLayer)
	{
		CGContextSaveGState(ctx);
		CGContextSetAlpha(ctx, _opacity);
		CGContextBeginTransparencyLayer(ctx, NULL);
	}
	
	for (WDElement *element in _elements)
	{
		if (CGRectIntersectsRect(element.styleBounds, clip))
		{
			[element renderInContext:ctx metaData:metaData];
		}
	}
	
	if (useTransparencyLayer) {
		CGContextEndTransparencyLayer(ctx);
		CGContextRestoreGState(ctx);
	}
}

- (void) setOpacity:(float)opacity
{
	if (opacity == _opacity)
	{
		return;
	}
	
	[[[self.drawing undoManager] prepareWithInvocationTarget:self] setOpacity:_opacity];
	
	_opacity = WDClamp(0.0f, 1.0f, opacity);
	
	if (!self.isSuppressingNotifications) {
		NSDictionary *userInfo = @{@"layer": self,
								  @"rect": [NSValue valueWithCGRect:self.styleBounds]};
		
		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerOpacityChanged
															object:self.drawing
														  userInfo:userInfo];
	}
}

- (WDXMLElement *) SVGElement
{
	if (_elements.count == 0)
	{
		// no reason to add this layer
		return nil;
	}
	
	WDXMLElement* layer = [WDXMLElement elementWithName:@"g"];
	NSString* uniqueName = [[WDSVGHelper sharedSVGHelper] uniqueIDWithPrefix:
							[@"Layer$" stringByAppendingString:_name]];
	[layer setAttribute:@"id" value:[uniqueName substringFromIndex:6]];
	[layer setAttribute:@"inkpad:layerName" value:_name];
	
	if (self.hidden)
	{
		[layer setAttribute:@"visibility" value:@"hidden"];
	}
	
	if (self.opacity != 1.0f)
	{
		[layer setAttribute:@"opacity" floatValue:_opacity];
	}
	
	for (WDElement* element in _elements)
	{
		[layer addChild:element.svgElement];
	}
	
	return layer;
}

- (void) addElementsToArray:(NSMutableArray *)elements
{
	[_elements makeObjectsPerformSelector:@selector(addElementsToArray:) withObject:elements];
}

- (void) addObject:(WDElement*) obj
{
	[[self.drawing.undoManager prepareWithInvocationTarget:self] removeObject:obj];
	 
	[_elements addObject:obj];
	obj.layer = self;
	
	[self invalidateThumbnail];
	
	if (!self.isSuppressingNotifications)
	{
		NSDictionary* userInfo = @{ @"layer" : self,
									@"rect" : [NSValue valueWithCGRect:obj.styleBounds] };
		
		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerContentsChangedNotification
															object:self.drawing
														  userInfo:userInfo];  
	}
}

- (void) addObjects:(NSArray<WDElement*>*) objects
{
	for (WDElement* element in objects)
	{
		[self addObject:element];
	}
}

- (void) removeObject:(WDElement*) obj
{
	[[self.drawing.undoManager prepareWithInvocationTarget:self] insertObject:obj atIndex:[_elements indexOfObject:obj]];

	[_elements removeObject:obj];
	
	[self invalidateThumbnail];
	
	if (!self.isSuppressingNotifications)
	{
		NSDictionary* userInfo = @{ @"layer" : self,
									@"rect" : [NSValue valueWithCGRect:obj.styleBounds]};
		
		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerContentsChangedNotification
															object:self.drawing
														  userInfo:userInfo];
	}
}

- (void) insertObject:(WDElement*) element atIndex:(NSUInteger) index
{
	[[self.drawing.undoManager prepareWithInvocationTarget:self] removeObject:element];
	
	element.layer = self;
	[_elements insertObject:element atIndex:index];

	[self invalidateThumbnail];

	if (!self.isSuppressingNotifications)
	{
		NSDictionary *userInfo = @{@"layer": self,
								  @"rect": [NSValue valueWithCGRect:element.styleBounds]};
		
		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerContentsChangedNotification
															object:self.drawing
														  userInfo:userInfo];
	}
}

- (void) insertObject:(WDElement *)element above:(WDElement *)above
{
	[self insertObject:element atIndex:[_elements indexOfObject:above]];
}

- (void) exchangeObjectAtIndex:(NSUInteger) src
			 withObjectAtIndex:(NSUInteger) dest
{
	[[self.drawing.undoManager prepareWithInvocationTarget:self] exchangeObjectAtIndex:src withObjectAtIndex:dest];

	[_elements exchangeObjectAtIndex:src withObjectAtIndex:dest];

	WDElement* srcElement = _elements[src];
	WDElement* destElement = _elements[dest];

	CGRect dirtyRect = CGRectIntersection(srcElement.styleBounds, destElement.styleBounds);

	[self invalidateThumbnail];

	if (!self.isSuppressingNotifications)
	{
		NSDictionary *userInfo = @{@"layer": self,
								  @"rect": [NSValue valueWithCGRect:dirtyRect]};
		
		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerContentsChangedNotification
															object:self.drawing
														  userInfo:userInfo];
	}
}

- (void) sendBackward:(NSSet*)elements
{
	NSUInteger top = _elements.count;

	for (NSUInteger i = 1; i < top; i++)
	{
		WDElement *curr = (WDElement*) _elements[i];
		WDElement *below = (WDElement*) _elements[i-1];
		
		if ([elements containsObject:curr] && ![elements containsObject:below])
		{
			[self exchangeObjectAtIndex:i withObjectAtIndex:(i-1)];
		}
	}
}

- (void) sendToBack:(NSArray<WDElement*>*) sortedElements
{
	for (WDElement* e in sortedElements.reverseObjectEnumerator)
	{
		[self removeObject:e];
		[self insertObject:e atIndex:0];
	}
}

- (void) bringForward:(NSSet*) elements
{
	NSInteger top = _elements.count - 1;

	for (NSInteger i = top - 1; i >= 0; i--)
	{
		WDElement* curr = (WDElement*) _elements[i];
		WDElement* above = (WDElement*) _elements[i+1];

		if ([elements containsObject:curr] && ![elements containsObject:above])
		{
			[self exchangeObjectAtIndex:i withObjectAtIndex:(i+1)];
		}
	}
}

- (void) bringToFront:(NSArray<WDElement*>*) sortedElements
{
	NSInteger top = _elements.count - 1;
	
	for (WDElement* e in sortedElements)
	{
		[self removeObject:e];
		[self insertObject:e atIndex:top];
	}
}

- (CGRect) styleBounds 
{
	CGRect styleBounds = CGRectNull;
	for (WDElement* element in _elements)
	{
		styleBounds = CGRectUnion(styleBounds, element.styleBounds);
	}

	return styleBounds;
}

- (void) notifyThumbnailChanged:(id) obj
{
	if (!self.isSuppressingNotifications)
	{
		NSDictionary *userInfo = @{@"layer": self};
		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerThumbnailChangedNotification object:self.drawing userInfo:userInfo];
	}
}

- (void) invalidateThumbnail
{
	if (self.thumbnail)
	{
		self.thumbnail = nil;
	
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(notifyThumbnailChanged:) object:nil];
		[self performSelector:@selector(notifyThumbnailChanged:) withObject:nil afterDelay:0];
	}
}

- (UIImage *) thumbnail
{
	if (!_thumbnail)
	{
		_thumbnail = [self previewInRect:CGRectMake(0, 0, kDefaultThumbnailDimension, kDefaultThumbnailDimension)];
	}
	
	return _thumbnail;
}

- (UIImage *) previewInRect:(CGRect)dest
{
	CGRect  contentBounds = self.styleBounds;
	float   contentAspect = CGRectGetWidth(contentBounds) / CGRectGetHeight(contentBounds);
	float   destAspect = CGRectGetWidth(dest)  / CGRectGetHeight(dest);
	float   scaleFactor = 1.0f;
	CGPoint offset = CGPointZero;
	
	UIGraphicsBeginImageContextWithOptions(dest.size, NO, 0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	
	dest = CGRectInset(dest, kPreviewInset, kPreviewInset);
	
	if (contentAspect > destAspect) {
		scaleFactor = CGRectGetWidth(dest) / CGRectGetWidth(contentBounds);
		offset.y = CGRectGetHeight(dest) - (scaleFactor * CGRectGetHeight(contentBounds));
		offset.y /= 2;
	} else {
		scaleFactor = CGRectGetHeight(dest) / CGRectGetHeight(contentBounds);
		offset.x = CGRectGetWidth(dest) - (scaleFactor * CGRectGetWidth(contentBounds));
		offset.x /= 2;
	}
	
	// scale and offset the layer contents to render in the new image
	CGContextSaveGState(ctx);
	CGContextTranslateCTM(ctx, offset.x + kPreviewInset, offset.y + kPreviewInset);
	CGContextScaleCTM(ctx, scaleFactor, scaleFactor);
	CGContextTranslateCTM(ctx, -contentBounds.origin.x, -contentBounds.origin.y);

	for (WDElement* element in _elements)
	{
		[element renderInContext:ctx metaData:WDRenderingMetaDataMake(scaleFactor, WDRenderThumbnail)];   
	}
	CGContextRestoreGState(ctx);

	if (kDrawPreviewBorder)
	{
		[[UIColor colorWithWhite:0.75 alpha:1] set];
		UIRectFrame(CGRectInset(dest, -kPreviewInset, -kPreviewInset));
	}

	UIImage* result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return result;
}

- (void) toggleLocked
{
	self.locked = !self.locked;
}

- (void) toggleVisibility
{
	self.visible = !self.visible;
}

- (BOOL) editable
{
	return (!self.locked && self.visible);
}

- (BOOL) hidden 
{
	return !_visible;
}

- (void) setHidden:(BOOL)hidden
{
	[self setVisible:!hidden];
}

- (void) setVisible:(BOOL)visible
{
	[[[self.drawing undoManager] prepareWithInvocationTarget:self] setVisible:_visible];
	
	_visible = visible;
	
	if (!self.isSuppressingNotifications) {
		NSDictionary *userInfo = @{@"layer": self,
								  @"rect": [NSValue valueWithCGRect:self.styleBounds]};
		
		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerVisibilityChanged
															object:self.drawing
														  userInfo:userInfo];
	}
}

- (void) setLocked:(BOOL)locked
{
	[[[self.drawing undoManager] prepareWithInvocationTarget:self] setLocked:_locked];
	
	_locked = locked;

	if (!self.isSuppressingNotifications)
	{
		
		NSDictionary *userInfo = @{@"layer": self};

		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerLockedStatusChanged
															object:self.drawing
														  userInfo:userInfo];
	}
}

- (void) setName:(NSString*)name
{
	[(WDLayer*) [[self.drawing undoManager] prepareWithInvocationTarget:self] setName:_name];
	
	_name = name;

	if (!self.isSuppressingNotifications)
	{
		NSDictionary* userInfo = @{ @"layer" : self };
		
		[[NSNotificationCenter defaultCenter] postNotificationName:WDLayerNameChanged object:self.drawing userInfo:userInfo];
	}
}

- (instancetype) copyWithZone:(NSZone*) zone
{
	WDLayer* layer = [[WDLayer alloc] init];

	layer->_opacity = self->_opacity;
	layer->_locked = self->_locked;
	layer->_visible = self->_visible;
	layer->_name = [self.name copy];
	layer.highlightColor = self.highlightColor;

	// copy elements
	layer->_elements = [[NSMutableArray alloc] initWithArray:_elements copyItems:YES];
	[layer->_elements makeObjectsPerformSelector:@selector(setLayer:) withObject:layer];

	return layer;
}

@end
