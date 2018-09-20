//
//  WDDocument.h
//  Inkpad
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  Copyright (c) 2011-2013 Steve Sprang
//

#import <Foundation/Foundation.h>
#import "WDDocumentProtocol.h"

@class WDDrawing;
@class WDDrawingController;

@interface WDDocument : UIDocument <WDDocumentProtocol>

@property (nonatomic, strong) WDDrawing* drawing;
@property (nonatomic, weak, readonly) NSString* filename;
@property (nonatomic, strong) UIImage *thumbnail;
@property (nonatomic, weak, readonly) NSString* displayName;
@property (nonatomic, assign) BOOL loadOnlyThumbnail;
@property (nonatomic, copy) NSString* fileTypeOverride;

@end

extern NSString* const WDDocumentDidLoadNotification;
