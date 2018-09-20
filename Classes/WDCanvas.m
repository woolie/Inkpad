//
//  WDCanvas.m
//  Inkpad
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  Copyright (c) 2009-2013 Steve Sprang
//

#import "UIView+Additions.h"
#import "WDCanvas.h"
#import "WDCanvasController.h"
#import "WDDrawingController.h"
#import "WDColor.h"
#import "WDEraserPreviewView.h"
#import "WDEtchedLine.h"
#import "WDEyedropper.h"
#import "WDLayer.h"
#import "WDPalette.h"
#import "WDPath.h"
#import "WDPenTool.h"
#import "WDRulerView.h"
#import "WDSelectionView.h"
#import "WDToolButton.h"
#import "WDToolView.h"
#import "WDToolManager.h"
#import "WDUtilities.h"

#define kFitBuffer					30
#define kPrintSizeFactor			(72.0f / 132.0f)
#define kHundredPercentScale		(132.0f / 72.0f)
#define kMaxZoom					(64 * kHundredPercentScale)
#define kMessageFadeDelay			1
#define kDropperRadius				80
#define kDropperAnimationDuration   0.2f
#define DEBUG_DIRTY_RECTS			NO

NSString* WDCanvasBeganTrackingTouches = @"WDCanvasBeganTrackingTouches";

@interface WDCanvas (Private)
- (void) setTrueViewScale_:(float)scale;
- (void) rebuildViewTransform_;
@end

@implementation WDCanvas

- (instancetype) initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	
	if (self != nil)
	{
		_selectionView = [[WDSelectionView alloc] initWithFrame:self.bounds];
		[self addSubview:_selectionView];
		_selectionView.canvas = self;
	
		self.multipleTouchEnabled = YES;
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		self.contentMode = UIViewContentModeCenter;
		self.exclusiveTouch = YES;
		self.clearsContextBeforeDrawing = YES;
	
		_selectionTransform = CGAffineTransformIdentity;
		_canvasTransform = CGAffineTransformIdentity;
	
		self.backgroundColor = [UIColor whiteColor];
	
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(keyboardWillShow:)
													 name:UIKeyboardWillShowNotification
												   object:nil];
	}

	return self;
}

- (void) registerInvalidateNotifications:(NSArray*)array
{
	NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];

	for (NSString* name in array)
	{
		[nc addObserver:self
			   selector:@selector(invalidateFromNotification:)
				   name:name
				 object:_drawing];
	}
}

- (void) setDrawing:(WDDrawing*) drawing
{
	if (_drawing == drawing)
	{
		return;
	}
	
	NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
	
	if (_drawing)
	{
		// stop listening to old drawing
		[nc removeObserver:self name:nil object:_drawing];
		[nc removeObserver:self name:WDSelectionChangedNotification object:nil];
	}
	
	// assign the new drawing
	_drawing = drawing;
	
	// register for notifications
	NSArray* invalidations = @[WDElementChanged,
								  WDDrawingChangedNotification,
								  WDLayersReorderedNotification,
								  WDLayerAddedNotification, 
								  WDLayerDeletedNotification, 
								  WDIsolateActiveLayerSettingChangedNotification,
								  WDOutlineModeSettingChangedNotification,
								  WDLayerContentsChangedNotification,
								  WDLayerVisibilityChanged,
								  WDLayerOpacityChanged];
	
	[self registerInvalidateNotifications:invalidations];
	
	[nc addObserver:self
		   selector:@selector(unitsChanged:)
			   name:WDUnitsChangedNotification
			 object:_drawing];
	
	[nc addObserver:self
		   selector:@selector(drawingDimensionsChanged:)
			   name:WDDrawingDimensionsChanged
			 object:_drawing];
	
	[nc addObserver:self
		   selector:@selector(gridSpacingChanged:)
			   name:WDGridSpacingChangedNotification
			 object:_drawing];
	
	[nc addObserver:self
		   selector:@selector(selectionChanged:)
			   name:WDSelectionChangedNotification
			 object:self.drawingController];
	
	[self showRulers:_drawing.rulersVisible];
	[self showTools];
	
	[self scaleDocumentToFit];
}

- (WDDrawingController*) drawingController
{
	return _controller.drawingController;
}

- (void) drawingDimensionsChanged:(NSNotification*) aNotification
{
	[self scaleDocumentToFit];
}

- (void) unitsChanged:(NSNotification*) aNotification
{
	_horizontalRuler.units = _drawing.units;
	_verticalRuler.units = _drawing.units;
	
	[_controller updateTitle];
}

- (void) gridSpacingChanged:(NSNotification*) aNotification
{
	[self setNeedsDisplay];
}

- (void) setRulerAlpha:(float)alpha
{	
	_horizontalRuler.alpha = alpha;
	_verticalRuler.alpha = alpha;
	_cornerView.alpha = alpha;
}

- (void) showRulers:(BOOL)flag
{
	[self showRulers:flag animated:YES];
}

- (void) showRulers:(BOOL)flag animated:(BOOL) animated
{
	if (flag && !_horizontalRuler)
	{
		CGRect horizontalFrame = self.frame;
		horizontalFrame.origin.y = 0;
		horizontalFrame.size.height = kWDRulerThickness;
		horizontalFrame.origin.x = kWDRulerThickness;
		horizontalFrame.size.width -= kWDRulerThickness;
		_horizontalRuler = [[WDRulerView alloc] initWithFrame:horizontalFrame];
		_horizontalRuler.clientView = self;
		_horizontalRuler.orientation = WDHorizontalRuler;
		_horizontalRuler.units = _drawing.units;
		
		if (_toolPalette)
		{
			[self insertSubview:_horizontalRuler belowSubview:_toolPalette];
		}
		else
		{
			[self addSubview:_horizontalRuler];
		}
		
		CGRect verticalFrame = self.frame;
		verticalFrame.origin.y = kWDRulerThickness;
		verticalFrame.size.height -= kWDRulerThickness;
		verticalFrame.origin.x = 0;
		verticalFrame.size.width = kWDRulerThickness;
		_verticalRuler = [[WDRulerView alloc] initWithFrame:verticalFrame];
		_verticalRuler.clientView = self;
		_verticalRuler.orientation = WDVerticalRuler;
		_verticalRuler.units = _drawing.units;
		
		if (_toolPalette)
		{
			[self insertSubview:_verticalRuler belowSubview:_toolPalette];
		}
		else
		{
			[self addSubview:_verticalRuler];
		}
		
		_cornerView = [[WDRulerCornerView alloc] initWithFrame:CGRectMake(0,0,kWDRulerThickness,kWDRulerThickness)];
		if (_toolPalette)
		{
			[self insertSubview:_cornerView belowSubview:_toolPalette];
		}
		else
		{
			[self addSubview:_cornerView];
		}
		
		if (animated)
		{
			[self setRulerAlpha:0.0f]; // to animate, start transparent
			[UIView animateWithDuration:0.2f animations:^{ [self setRulerAlpha:0.5f]; }];
		}
	}
	else if (!flag)
	{
		if (animated)
		{
			[UIView animateWithDuration:0.2f
							 animations:^{ [self setRulerAlpha:0.0f]; }
							 completion:^(BOOL finished)
			{
				[_horizontalRuler removeFromSuperview];
				[_verticalRuler removeFromSuperview];
				[_cornerView removeFromSuperview];

				_horizontalRuler = nil;
				_verticalRuler = nil;
				_cornerView = nil;
			}];
		}
		else
		{
			[_horizontalRuler removeFromSuperview];
			[_verticalRuler removeFromSuperview];
			[_cornerView removeFromSuperview];
			
			_horizontalRuler = nil;
			_verticalRuler = nil;
			_cornerView = nil;
		}
		
	}
}

- (void) displayEyedropperAtPoint:(CGPoint) pt
{
	if (_eyedropper)
	{
		return;
	}
	
	_eyedropper = [[WDEyedropper alloc] initWithFrame:CGRectMake(0, 0, kDropperRadius * 2, kDropperRadius * 2)];
	
	pt = [self convertPointFromDocumentSpace:pt];
	_eyedropper.center = WDRoundPoint(pt);
	[_eyedropper setBorderWidth:20];
	
	[self insertSubview:_eyedropper belowSubview:_toolPalette];
}

- (void) moveEyedropperToPoint:(CGPoint) pt
{
	pt = [self convertPointFromDocumentSpace:pt];
	_eyedropper.center = WDRoundPoint(pt);
}

- (void) dismissEyedropper
{
	[UIView animateWithDuration:kDropperAnimationDuration
					 animations:^{ _eyedropper.alpha = 0.0f; _eyedropper.transform = CGAffineTransformMakeScale(0.1f, 0.1f); }
					 completion:^(BOOL finished)
	{
		[_eyedropper removeFromSuperview];
		_eyedropper = nil;
	}];
}

- (void) invalidateSelectionView
{
	[_selectionView drawView];
}

- (void) scaleDocumentToFit
{
	if (!_drawing)
	{
		return;
	}
	
	float   documentAspect = _drawing.dimensions.width / _drawing.dimensions.height;
	float   boundsAspect = CGRectGetWidth(self.bounds) / CGRectGetHeight(self.bounds);
	float   scale;
	
	if (documentAspect > boundsAspect)
	{
		scale = (CGRectGetWidth(self.bounds) - (kFitBuffer * 2)) / _drawing.dimensions.width;
	}
	else
	{
		scale = (CGRectGetHeight(self.bounds) - (kFitBuffer * 2)) / _drawing.dimensions.height;
	}
	
	[self setTrueViewScale_:scale];
	
	_userSpacePivot = CGPointMake(_drawing.dimensions.width / 2, _drawing.dimensions.height / 2);
	_deviceSpacePivot = WDCenterOfRect(self.bounds);
	
	[self rebuildViewTransform_];
}

- (void) setViewScale:(float)scale
{
	_viewScale = scale;
	[_controller updateTitle];
}

- (CGSize) documentSize
{
	return _drawing.dimensions;
}

- (CGRect) visibleRect
{
	CGRect				rect = self.bounds;
	CGAffineTransform	invert = _canvasTransform;

	invert = CGAffineTransformInvert(invert);
	rect = CGRectApplyAffineTransform(rect, invert);

	return rect;
}

- (float) backgroundGrayLevel
{
	return 0.9f;
}

- (float) backgroundOpacity
{
	return 0.8f;
}

- (float) effectiveBackgroundGray
{
	// opaque version of the background gray blended over white
	return self.backgroundGrayLevel * self.backgroundOpacity + (1.0f - self.backgroundOpacity);
}

- (void) drawDocumentBorder:(CGContextRef)ctx
{
	// draw the document border
	CGRect docBounds = CGRectMake(0, 0, _drawing.dimensions.width, _drawing.dimensions.height);
	docBounds = CGContextConvertRectToDeviceSpace(ctx, docBounds);
	docBounds = CGRectIntegral(docBounds);
	docBounds = CGRectInset(docBounds, 0.5f, 0.5f);
	docBounds = CGContextConvertRectToUserSpace(ctx, docBounds);
	
	CGContextAddRect(ctx, [self visibleRect]);
	CGContextAddRect(ctx, docBounds);
	CGContextSetGrayFillColor(ctx, [self backgroundGrayLevel], [self backgroundOpacity]);
	CGContextEOFillPath(ctx);
	
	CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 1);
	CGContextSetLineWidth(ctx, 1.0f / (_viewScale * UIScreen.mainScreen.scale));
	CGContextStrokeRect(ctx, docBounds);
}	

// don't draw gridlines too close together
- (float) effectiveGridSpacing:(CGContextRef)ctx
{
	float   gridSpacing = _drawing.gridSpacing;
	CGRect  testRect = CGRectMake(0, 0, gridSpacing, gridSpacing);
	float   adjustmentFactor = 1;
	
	testRect = CGContextConvertRectToDeviceSpace(ctx, testRect);
	if (CGRectGetWidth(testRect) < 10)
	{
		adjustmentFactor = 10.0f / CGRectGetWidth(testRect);
	}
	
	return gridSpacing * adjustmentFactor;
}

- (void) drawGrid:(CGContextRef)ctx
{
	CGRect	  docBounds = CGRectMake(0, 0, _drawing.dimensions.width, _drawing.dimensions.height);
	CGRect	  visibleRect = self.visibleRect;
	float	   gridSpacing = [self effectiveGridSpacing:ctx];
	CGPoint	 pt;
	
	// just draw lines in the portion of the document that's actually visible
	visibleRect = CGRectIntersection(visibleRect, docBounds);
	if (CGRectEqualToRect(visibleRect, CGRectNull))
	{
		// if there's no intersection, bail early
		return;
	}
	
	CGContextSaveGState(ctx);
	CGContextSetLineWidth(ctx, 1.0f / (_viewScale * [UIScreen mainScreen].scale));
	
	float startY = floor(CGRectGetMinY(visibleRect) / gridSpacing);
	float startX = floor(CGRectGetMinX(visibleRect) / gridSpacing);
	
	startX *= gridSpacing;
	startY *= gridSpacing;
	
	for (float y = startY; y <= CGRectGetMaxY(visibleRect); y += gridSpacing)
	{
		pt = WDSharpPointInContext(CGPointMake(0, y), ctx);
		CGContextMoveToPoint(ctx, pt.x, pt.y);
		
		pt = WDSharpPointInContext(CGPointMake(CGRectGetWidth(docBounds), y), ctx);
		CGContextAddLineToPoint(ctx, pt.x, pt.y);
	}
	
	for (float x = startX; x <= CGRectGetMaxX(visibleRect); x += gridSpacing)
	{
		pt = WDSharpPointInContext(CGPointMake(x, 0), ctx);
		CGContextMoveToPoint(ctx, pt.x, pt.y);
		
		pt = WDSharpPointInContext(CGPointMake(x, CGRectGetHeight(docBounds)), ctx);
		CGContextAddLineToPoint(ctx, pt.x, pt.y);
	}
	
	CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.125);
	CGContextStrokePath(ctx);
	CGContextRestoreGState(ctx);
}

- (void) drawIsolationInContext:(CGContextRef)ctx rect:(CGRect) rect
{
	if (!_isolationColor)
	{
		_isolationColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"isolate.png"]];
		_isolationColor = [_isolationColor colorWithAlphaComponent:0.9];
	}
	
	[_isolationColor set];
	CGContextFillRect(ctx, rect);
}

- (float) thinWidth
{
	return 1.0f / (_viewScale * [UIScreen mainScreen].scale);
}

- (void)drawRect:(CGRect) rect
{
	if (!_drawing)
	{
		CGContextRef	ctx = UIGraphicsGetCurrentContext();
		
		CGContextSetRGBFillColor(ctx, 0.941f, 0.941f, 0.941f, 1.0f);
		CGContextFillRect(ctx, self.bounds);

		return;
	}
	
	if (_controlGesture)
	{
		[self invalidateSelectionView];
		return;
	}
	
	CGContextRef	ctx = UIGraphicsGetCurrentContext();
	BOOL			drawingIsolatedLayer = (!_controlGesture && _drawing.isolateActiveLayer);
	BOOL			outlineMode = _drawing.outlineMode;
	
#ifdef WD_DEBUG
	NSDate*			date = [NSDate date];
#endif
	
	if (DEBUG_DIRTY_RECTS)
	{
		[[WDColor randomColor] set];
		CGContextFillRect(ctx, rect);
	}
	
	// map the clip rect back into document space
	CGAffineTransform   invert = _canvasTransform;
	invert = CGAffineTransformInvert(invert);
	rect = CGRectApplyAffineTransform(rect, invert);
	
	CGContextSaveGState(ctx);
	CGContextConcatCTM(ctx, _canvasTransform);

	if (_drawing.showGrid && !drawingIsolatedLayer)
	{
		[self drawGrid:ctx];
	}
	
	if (outlineMode)
	{
		[[UIColor darkGrayColor] set];
		CGContextSetLineWidth(ctx, self.thinWidth);
	}
	
	WDLayer* activeLayer = _drawing.activeLayer;
	
	if (!_controlGesture)
	{
		CGContextSaveGState(ctx);
		
		// make sure blending modes behave correctly
		if (!outlineMode)
		{
			CGContextBeginTransparencyLayer(ctx, NULL);
		}

		for (WDLayer* layer in _drawing.layers){
			if (layer.hidden || (drawingIsolatedLayer && (layer == activeLayer)))
			{
				continue;
			}
			
			[layer renderInContext:ctx
						  clipRect:rect
						  metaData:WDRenderingMetaDataMake(_viewScale, outlineMode ? WDRenderOutlineOnly : WDRenderDefault)];
		}

		if (drawingIsolatedLayer)
		{
			// gray out lower contents
			[self drawIsolationInContext:ctx rect:rect];
			
			if (_drawing.showGrid)
			{
				[self drawGrid:ctx];
			}
			
			// draw the active layer
			if (activeLayer.visible)
			{
				if (outlineMode)
				{
					[[UIColor darkGrayColor] set];
					CGContextSetLineWidth(ctx, self.thinWidth);
				}
				
				[activeLayer renderInContext:ctx
									clipRect:rect
									metaData:WDRenderingMetaDataMake(_viewScale, outlineMode ? WDRenderOutlineOnly : WDRenderDefault)];
			}
		}
		
		if (!outlineMode)
		{
			CGContextEndTransparencyLayer(ctx);
		}
		
		CGContextRestoreGState(ctx);
	}
	
	[self drawDocumentBorder:ctx];
	
	CGContextRestoreGState(ctx);

#ifdef WD_DEBUG
	NSLog(@"Canvas render time: %f", -[date timeIntervalSinceNow]);
#endif
	
	// this needs to redraw too... do it at the end of the runloop to avoid an occassional flash after pinch zooming
	[_selectionView performSelector:@selector(drawView) withObject:nil afterDelay:0];
}

- (void) rotateToInterfaceOrientation
{
	if (!_selectionView)
	{
		_selectionView = [[WDSelectionView alloc] initWithFrame:self.bounds];
		[self addSubview:_selectionView];
		[self sendSubviewToBack:_selectionView];
		_selectionView.canvas = self;
	}

	if (!_eraserPreview && _eraserPath)
	{
		_eraserPreview = [[WDEraserPreviewView alloc] initWithFrame:self.bounds];
		[self insertSubview:_eraserPreview aboveSubview:_selectionView];
		_eraserPreview.canvas = self;
	}
	
	[self positionToolOptionsView];
	
	[self rebuildViewTransform_];
}

- (void) offsetUserSpacePivot:(CGPoint)delta
{
	_userSpacePivot = WDAddPoints(_userSpacePivot, delta);
}

- (void) rebuildViewTransform_
{	
	_canvasTransform = CGAffineTransformMakeTranslation(_deviceSpacePivot.x, _deviceSpacePivot.y);
	_canvasTransform = CGAffineTransformScale(_canvasTransform, _viewScale, _viewScale);
	_canvasTransform = CGAffineTransformTranslate(_canvasTransform, -_userSpacePivot.x, -_userSpacePivot.y);
	
	[_horizontalRuler setNeedsDisplay];
	[_verticalRuler setNeedsDisplay];
	
	[self setNeedsDisplay];
	
	if (_pivotView)
	{
		_pivotView.sharpCenter = CGPointApplyAffineTransform(_pivot, _canvasTransform);
	}
}

- (void) offsetByDelta:(CGPoint)delta
{
	_deviceSpacePivot = WDAddPoints(_deviceSpacePivot, delta);
	[self rebuildViewTransform_];
}

- (float) displayableScale
{	
	float printSizeFactor = [_drawing.units isEqualToString:@"Pixels"] ? 1.0f : kPrintSizeFactor;
  
	return round(self.viewScale * 100 * printSizeFactor);
}

- (void) setTrueViewScale_:(float)scale
{
	_trueViewScale = scale;
	
	float hundredPercentScale = [_drawing.units isEqualToString:@"Pixels"] ? 1.0f : kHundredPercentScale;
	
	if (_trueViewScale > (hundredPercentScale * 0.95f) && _trueViewScale < (hundredPercentScale * 1.05))
	{
		self.viewScale = hundredPercentScale;
	}
	else
	{
		self.viewScale = _trueViewScale;
	}
}

- (void) scaleBy:(double)scale
{
	float   maxDimension = MAX(self.drawing.width, self.drawing.height);
	// at the minimum zoom, the drawing will be 200 effective screen pixels wide (or tall)
	double  minZoom = (200 / maxDimension);

	if (scale * _viewScale > kMaxZoom)
	{
		scale = kMaxZoom / _viewScale;
	}
	else if (scale * _viewScale < minZoom)
	{
		scale = minZoom / _viewScale;
	}
	
	[self setTrueViewScale_:_trueViewScale * scale];
	[self rebuildViewTransform_];
}

//
// called from within touchesMoved:withEvent:
//
- (void) gestureMovedWithEvent:(UIEvent*) event
{
	UIView* superview = self.superview;
	NSSet*	touches = event.allTouches;
	
	if ([touches count] == 1)
	{
		// with 1 finger down, pan only
		UITouch* touch = [touches anyObject];
		
		CGPoint delta = WDSubtractPoints([touch locationInView:superview], [touch previousLocationInView:superview]);
		[self offsetByDelta:delta];
		
		return;
	}
	
	NSArray* allTouches = [touches allObjects];
	UITouch* first = allTouches[0];
	UITouch* second = allTouches[1];
	
	// compute the scaling
	double oldDistance = WDDistance([first previousLocationInView:superview], [second previousLocationInView:superview]);
	double distance = WDDistance([first locationInView:superview], [second locationInView:superview]);
	
	// ignore touches that are too close together -- seems to confuse the phone
	if (distance > 80 && oldDistance > 80)
	{
		_deviceSpacePivot = WDAveragePoints([first locationInView:self], [second locationInView:self]);
		[self scaleBy:(distance / oldDistance)]; 
	}
}

- (CGRect) convertRectToView:(CGRect) rect
{
	return CGRectApplyAffineTransform(rect, _canvasTransform);
}

- (CGPoint) convertPointToDocumentSpace:(CGPoint) pt
{
	CGAffineTransform invert = _canvasTransform;
	invert = CGAffineTransformInvert(invert);
	return CGPointApplyAffineTransform(pt, invert); 
}
		  
- (CGPoint) convertPointFromDocumentSpace:(CGPoint) pt
{
	return CGPointApplyAffineTransform(pt, _canvasTransform);
}

- (BOOL) canSendTouchToActiveTool
{
	WDTool* activeTool = [WDToolManager sharedInstance].activeTool;
	BOOL	locked = _drawing.activeLayer.locked;
	BOOL	hidden = _drawing.activeLayer.hidden;
	
	if (activeTool.createsObject && (locked || hidden))
	{
		if (locked && hidden)
		{
			[self showMessage:NSLocalizedString(@"The active layer is locked and hidden.", @"The active layer is locked and hidden.")];
		}
		else if (locked)
		{
			[self showMessage:NSLocalizedString(@"The active layer is locked.", @"The active layer is locked.")];
		}
		else
		{
			[self showMessage:NSLocalizedString(@"The active layer is hidden.", @"The active layer is hidden.")];
		}
		
		return NO;
	}
	
	return YES;
}

- (void) touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
	NSSet* eventTouches = event.allTouches;
	
	[_controller hidePopovers];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:WDCanvasBeganTrackingTouches object:self];
	
	BOOL resetPivots = NO;

	if (!_moved && eventTouches.count == 2)
	{
		_controlGesture = YES;
		resetPivots = YES;
		
		[self setNeedsDisplay];
	}
	else if (_controlGesture && eventTouches.count == 2)
	{
		resetPivots = YES;
	}
	else if (!_controlGesture && _moved && self.canSendTouchToActiveTool)
	{
		[[WDToolManager sharedInstance].activeTool touchesBegan:touches withEvent:event inCanvas:self];
	}

	if (resetPivots)
	{
		NSArray* allTouches = eventTouches.allObjects;
		UITouch* first = allTouches[0];
		UITouch* second = allTouches[1];
		
		_deviceSpacePivot = WDAveragePoints([first locationInView:self], [second locationInView:self]);
		CGAffineTransform invert = _canvasTransform;
		invert = CGAffineTransformInvert(invert);
		_userSpacePivot = CGPointApplyAffineTransform(_deviceSpacePivot, invert);
	}
}

- (void) touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event
{
	if (!_moved)
	{
		_moved = YES;

		if (!_controlGesture && [self canSendTouchToActiveTool])
		{
			if (![[WDToolManager sharedInstance].activeTool isKindOfClass:[WDPenTool class]])
			{
				self.drawingController.activePath = nil;
			}
			
			[[WDToolManager sharedInstance].activeTool touchesBegan:touches withEvent:event inCanvas:self];
			return;
		}
	}

	if (_controlGesture)
	{
		[self gestureMovedWithEvent:event];
	}
	else if ([self canSendTouchToActiveTool])
	{
		[[WDToolManager sharedInstance].activeTool touchesMoved:touches withEvent:event inCanvas:self];
	}
}

- (void) touchesEnded:(NSSet*) touches
			withEvent:(UIEvent*) event
{
	BOOL allTouchesAreEnding = YES;
	
	for (UITouch* touch in event.allTouches)
	{
		if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled)
		{
			allTouchesAreEnding = NO;
			break;
		}
	}
	
	if (!_controlGesture && [self canSendTouchToActiveTool])
	{
		if (!_moved)
		{
			[[WDToolManager sharedInstance].activeTool touchesBegan:touches withEvent:event inCanvas:self];
		}
		[[WDToolManager sharedInstance].activeTool touchesEnded:touches withEvent:event inCanvas:self];
	}

	if (allTouchesAreEnding)
	{
		if (_controlGesture)
		{
			_controlGesture = NO;
			[self setNeedsDisplay];
		}
		
		_moved = NO;
	}
}
	
- (void) touchesCancelled:(NSSet*) touches
			    withEvent:(UIEvent*) event
{
	[self touchesEnded:touches withEvent:event];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self nixMessageLabel];
}

- (BOOL) isZooming
{
	return _controlGesture;
}

- (void) hideAccessoryViews
{
	[self hideTools];
	_toolOptionsView.hidden = YES;
	_pivotView.hidden = YES;
}

- (void) showAccessoryViews
{
	[self showTools];
	_toolOptionsView.hidden = NO;
	_pivotView.hidden = NO;
}

- (void) hideTools
{
	if (!_toolPalette)
	{
		return;
	}
	
	_toolPalette.hidden = YES;
}

- (void) showTools
{
	if (_toolPalette)
	{
		_toolPalette.hidden = NO;
		return;
	}
	
	WDToolView* tools = [[WDToolView alloc] initWithTools:[WDToolManager sharedInstance].tools];
	tools.canvas = self;
	
	CGRect frame = tools.frame;
	frame.size.height += [WDToolButton dimension] + 4;
	float bottom = CGRectGetHeight(tools.frame);
	
	// create a base view for all the palette elements
	UIView* paletteView = [[UIView alloc] initWithFrame:frame];
	[paletteView addSubview:tools];
	
	// add a separator
	WDEtchedLine* line = [[WDEtchedLine alloc] initWithFrame:CGRectMake(2, bottom + 1, CGRectGetWidth(frame) - 4, 2)];
	[paletteView addSubview:line];
	
	// add a "delete" buttton
	_deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
	UIImage* icon = [[UIImage imageNamed:@"trash.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	_deleteButton.frame = CGRectMake(0, bottom + 3, [WDToolButton dimension], [WDToolButton dimension]);
	[_deleteButton setImage:icon forState:UIControlStateNormal];
	_deleteButton.tintColor = [UIColor colorWithRed:(166.0f / 255.0f) green:(51.0f / 255.0f) blue:(51.0 / 255.0f) alpha:1.0f];
	[_deleteButton addTarget:self.controller action:@selector(delete:) forControlEvents:UIControlEventTouchUpInside];
	_deleteButton.enabled = NO;
	[paletteView addSubview:_deleteButton];
	
	_toolPalette = [WDPalette paletteWithBaseView:paletteView defaultsName:@"tools palette"];
	[self addSubview:_toolPalette];
	
	[self ensureToolPaletteIsOnScreen];
}

- (void) transformSelection:(CGAffineTransform) transform
{
	_selectionTransform = transform;
	[self invalidateSelectionView];
}

- (void) setTransforming:(BOOL)transforming
{
	_transforming = transforming;
}

- (void) selectionChanged:(NSNotification*) aNotification
{
	_deleteButton.enabled = (self.drawingController.selectedObjects.count > 0) ? YES : NO;
	
	[self setShowsPivot:[WDToolManager sharedInstance].activeTool.needsPivot];
	[self invalidateSelectionView];
}

- (void) invalidateFromNotification:(NSNotification*) aNotification
{
	NSValue*	rectValue = [aNotification userInfo][@"rect"];
	NSArray*	rects = [aNotification userInfo][@"rects"];
	CGRect		dirtyRect;
	float		fudge = (-1.0f) / _viewScale;

	if (rectValue)
	{
		dirtyRect = [rectValue CGRectValue];

		if (!CGRectEqualToRect(dirtyRect, CGRectNull))
		{
			dirtyRect = CGRectApplyAffineTransform(dirtyRect, self.canvasTransform);
			if (_drawing.outlineMode)
			{
				dirtyRect = CGRectInset(dirtyRect, fudge, fudge);
			}
			[self setNeedsDisplayInRect:dirtyRect];
		}
	}
	else if (rects)
	{
		for (NSValue* rectValue in rects)
		{
			dirtyRect = [rectValue CGRectValue];
			
			if (!CGRectEqualToRect(dirtyRect, CGRectNull))
			{
				dirtyRect = CGRectApplyAffineTransform(dirtyRect, self.canvasTransform);
				if (_drawing.outlineMode)
				{
					dirtyRect = CGRectInset(dirtyRect, fudge, fudge);
				}
				[self setNeedsDisplayInRect:dirtyRect];
			}
		}
	}
	else
	{
		[self setNeedsDisplay];
	}
}

- (void) setPivot:(CGPoint)pivot
{
	if (self.drawingController.selectedObjects.count == 0)
	{
		return;
	}
	
	_pivot = pivot;
	
	if (!_pivotView)
	{
		_pivotView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pivot.png"]];
		[self insertSubview:_pivotView atIndex:0];
	}
	
	_pivotView.sharpCenter = CGPointApplyAffineTransform(pivot, _canvasTransform);
}

- (void) setShowsPivot:(BOOL)showsPivot
{
	if (self.drawingController.selectedObjects.count == 0)
	{
		showsPivot = NO;
	}
		
	if (showsPivot == _showingPivot)
	{
		return;
	}
	
	_showingPivot = showsPivot;
	
	if (showsPivot)
	{
		[self setPivot:WDCenterOfRect([self.drawingController selectionBounds])];
	}
	else if (_pivotView)
	{
		[_pivotView removeFromSuperview];
		_pivotView = nil;
	}
}

- (void) positionToolOptionsView
{
	_toolOptionsView.sharpCenter = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMaxY(self.bounds) - (CGRectGetHeight(_toolOptionsView.frame) / 2) - 15);
}

- (void) setToolOptionsView:(UIView*) toolOptionsView
{
	[_toolOptionsView removeFromSuperview];
	
	_toolOptionsView = toolOptionsView;
	[self positionToolOptionsView];
	
	[self insertSubview:_toolOptionsView belowSubview:_toolPalette];
}

- (void) setMarquee:(NSValue*) marquee
{
	_marquee = marquee;
	[self invalidateSelectionView];
}

- (void) setDynamicGuides:(NSArray*) dynamicGuides
{
	_dynamicGuides = dynamicGuides;
	[self invalidateSelectionView];
}

- (void) setShapeUnderConstruction:(WDPath*) path
{
	_shapeUnderConstruction = path;
	
	path.layer = _drawing.activeLayer;
	[self invalidateSelectionView];
}

- (void) setEraserPath:(WDPath*) eraserPath
{
	_eraserPath = eraserPath;
	
	if (eraserPath && !_eraserPreview)
	{
		_eraserPreview = [[WDEraserPreviewView alloc] initWithFrame:self.bounds];
		[self insertSubview:_eraserPreview aboveSubview:_selectionView];
		_eraserPreview.canvas = self;
	}
	
	if (!eraserPath && _eraserPreview)
	{
		[_eraserPreview removeFromSuperview];
		_eraserPreview = nil;
	}
	
	[_eraserPreview setNeedsDisplay];
}

- (void) startActivity
{
	if (!_activityView)
	{
		[[NSBundle mainBundle] loadNibNamed:@"Activity" owner:self options:nil];
	}
	
	_activityView.sharpCenter = WDCenterOfRect(self.bounds);
	[self addSubview:_activityView];
	
	CALayer* layer = _activityView.layer;
	layer.cornerRadius = CGRectGetWidth(_activityView.frame) / 2;
}

- (void) stopActivity
{
	if (_activityView)
	{
		[_activityView removeFromSuperview];
		_activityView = nil;
	}
}

- (void) cacheVisibleRectCenter
{
	_cachedCenter = WDCenterOfRect(self.visibleRect);
}

- (void) setVisibleRectCenterFromCached
{
	CGPoint delta = WDSubtractPoints(_cachedCenter, WDCenterOfRect(self.visibleRect));
	[self offsetUserSpacePivot:delta];
}

- (void) ensureToolPaletteIsOnScreen
{
	[_toolPalette bringOnScreen];
}

- (void) keyboardWillShow:(NSNotification*) aNotification
{
	NSValue* endFrame = [aNotification userInfo][UIKeyboardFrameEndUserInfoKey];
	CGRect frame = [endFrame CGRectValue];
	
	frame = [self convertRect:frame fromView:nil];
	
	if (self.drawingController.selectedObjects.count == 1)
	{
		WDElement* selectedObject = [self.drawingController.selectedObjects anyObject];
		
		if ([selectedObject hasEditableText])
		{
			CGPoint top = WDCenterOfRect(selectedObject.bounds);
			top = CGPointApplyAffineTransform(top, _canvasTransform);
			
			if (top.y > CGRectGetMinY(frame))
			{
				float offset = (CGRectGetMinY(frame) - top.y);
				_deviceSpacePivot.y += offset;
				[self rebuildViewTransform_];
			}
		}
	}
}

- (void) nixMessageLabel
{
	if (_messageTimer)
	{
		[_messageTimer invalidate];
		_messageTimer = nil;
	}
	
	if (_messageLabel)
	{
		[_messageLabel removeFromSuperview];
		_messageLabel = nil;
	}
}

- (void) hideMessage:(NSTimer*) timer
{
	[self nixMessageLabel];
}

- (void) showMessage:(NSString*)message
{
	if (!_messageLabel)
	{
		_messageLabel = [[UILabel alloc] init];
		_messageLabel.textColor = [UIColor blackColor];
		_messageLabel.font = [UIFont systemFontOfSize:32];
		_messageLabel.textAlignment = NSTextAlignmentCenter;
		_messageLabel.backgroundColor = [UIColor colorWithHue:0.0f saturation:0.4f brightness:1.0f alpha:0.8f];
		_messageLabel.shadowColor = [UIColor whiteColor];
		_messageLabel.shadowOffset = CGSizeMake(0, 1);
		_messageLabel.layer.cornerRadius = 16;
	}
	
	_messageLabel.text = message;
	[_messageLabel sizeToFit];
	
	CGRect frame = _messageLabel.frame;
	frame = CGRectInset(frame, -20, -15);
	_messageLabel.frame = frame;
	
	_messageLabel.sharpCenter = WDCenterOfRect(self.bounds);
	
	if (_messageLabel.superview != self)
	{
		[self insertSubview:_messageLabel belowSubview:_toolPalette];
	}
	
	// start message dismissal timer
	
	if (_messageTimer)
	{
		[_messageTimer invalidate];
	}
	
	_messageTimer = [NSTimer scheduledTimerWithTimeInterval:kMessageFadeDelay
													 target:self
												   selector:@selector(hideMessage:)
												   userInfo:nil
													repeats:NO];
}

@end
