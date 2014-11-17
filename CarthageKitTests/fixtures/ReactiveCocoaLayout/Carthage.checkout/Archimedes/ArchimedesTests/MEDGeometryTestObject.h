//
//  MEDGeometryTestObject.h
//  Archimedes
//
//  Created by Justin Spahr-Summers on 2012-10-15.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface MEDGeometryTestObject : NSObject

@property (nonatomic, assign) CGRect slice;
@property (nonatomic, assign) CGRect remainder;

@end
