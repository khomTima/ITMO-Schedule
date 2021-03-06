//
//  FXBlurView.m
//
//  Version 1.4.4
//
//  Created by Nick Lockwood on 25/08/2013.
//  Copyright (c) 2013 Charcoal Design
//
//  Distributed under the permissive zlib License
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/FXBlurView
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//


#import "FXBlurView.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>


#import <Availability.h>
#if !__has_feature(objc_arc)
#error This class requires automatic reference counting
#endif


@implementation UIImage (FXBlurView)

- (UIImage *)blurredImageWithRadius:(CGFloat)radius iterations:(NSUInteger)iterations tintColor:(UIColor *)tintColor {
	//image must be nonzero size
	if (floorf(self.size.width) * floorf(self.size.height) <= 0.0f) {
        return self;
    }

	//boxsize must be an odd integer
	uint32_t boxSize = radius * self.scale;
	if (boxSize % 2 == 0) boxSize++;

	//create image buffers
	CGImageRef imageRef = self.CGImage;
	vImage_Buffer buffer1, buffer2;
	buffer1.width = buffer2.width = CGImageGetWidth(imageRef);
	buffer1.height = buffer2.height = CGImageGetHeight(imageRef);
	buffer1.rowBytes = buffer2.rowBytes = CGImageGetBytesPerRow(imageRef);
	CFIndex bytes = buffer1.rowBytes * buffer1.height;
	buffer1.data = malloc(bytes);
	buffer2.data = malloc(bytes);

	//create temp buffer
	void *tempBuffer = malloc(vImageBoxConvolve_ARGB8888(&buffer1, &buffer2, NULL, 0, 0, boxSize, boxSize,
	                                                     NULL, kvImageEdgeExtend + kvImageGetTempBufferSize));

	//copy image data
	CFDataRef dataSource = CGDataProviderCopyData(CGImageGetDataProvider(imageRef));
	memcpy(buffer1.data, CFDataGetBytePtr(dataSource), bytes);
    if (dataSource) CFRelease(dataSource);

	for (NSUInteger i = 0; i < iterations; i++) {
		//perform blur
		vImageBoxConvolve_ARGB8888(&buffer1, &buffer2, tempBuffer, 0, 0, boxSize, boxSize, NULL, kvImageEdgeExtend);

		//swap buffers
		void *temp = buffer1.data;
		buffer1.data = buffer2.data;
		buffer2.data = temp;
	}

	//free buffers
	free(buffer2.data);
	free(tempBuffer);

	//create image context from buffer
	CGContextRef ctx = CGBitmapContextCreate(buffer1.data, buffer1.width, buffer1.height,
	                                         8, buffer1.rowBytes, CGImageGetColorSpace(imageRef),
	                                         CGImageGetBitmapInfo(imageRef));

    // деалем приемлимый оттенок блюра
    tintColor = [UIColor whiteColor];
    CGContextSetFillColorWithColor(ctx, [tintColor colorWithAlphaComponent:0.25].CGColor);
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    CGContextFillRect(ctx, CGRectMake(0, 0, buffer1.width, buffer1.height));

    tintColor = [UIColor blackColor];
    CGContextSetFillColorWithColor(ctx, [tintColor colorWithAlphaComponent:0.35].CGColor);
    CGContextSetBlendMode(ctx, kCGBlendModeSourceAtop);
    CGContextFillRect(ctx, CGRectMake(0, 0, buffer1.width, buffer1.height));

	//create image from context
	imageRef = CGBitmapContextCreateImage(ctx);
	UIImage *image = [UIImage imageWithCGImage:imageRef scale:self.scale orientation:self.imageOrientation];
	CGImageRelease(imageRef);
	CGContextRelease(ctx);
	free(buffer1.data);
    return image;
}

@end


@interface FXBlurScheduler : NSObject

@property (nonatomic, strong) NSMutableArray *views;
@property (nonatomic, assign) NSInteger viewIndex;
@property (nonatomic, assign) NSInteger updatesEnabled;
@property (nonatomic, assign) BOOL blurEnabled;
@property (nonatomic, assign) BOOL updating;

@end


@interface FXBlurView ()

@property (nonatomic, assign) BOOL iterationsSet;
@property (nonatomic, assign) BOOL blurRadiusSet;
@property (nonatomic, assign) BOOL dynamicSet;
@property (nonatomic, assign) BOOL blurEnabledSet;
@property (nonatomic, strong) NSDate *lastUpdate;

- (UIImage *)snapshotOfSuperview:(UIView *)superview;

@end


@implementation FXBlurScheduler

+ (instancetype)sharedInstance {
	static FXBlurScheduler *sharedInstance = nil;
	if (!sharedInstance) {
		sharedInstance = [[FXBlurScheduler alloc] init];
	}
	return sharedInstance;
}

- (instancetype)init {
	if (self = [super init]) {
		_updatesEnabled = 1;
		_blurEnabled = YES;
		_views = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)setBlurEnabled:(BOOL)blurEnabled {
	_blurEnabled = blurEnabled;
	if (blurEnabled) {
		for (FXBlurView *view in self.views) {
			[view setNeedsDisplay];
		}
		[self updateAsynchronously];
	}
}

- (void)setUpdatesEnabled {
	_updatesEnabled++;
	[self updateAsynchronously];
}

- (void)setUpdatesDisabled {
	_updatesEnabled--;
}

- (void)addView:(FXBlurView *)view {
	if (![self.views containsObject:view]) {
		[self.views addObject:view];
		[self updateAsynchronously];
	}
}

- (void)removeView:(FXBlurView *)view {
	NSInteger index = [self.views indexOfObject:view];
	if (index != NSNotFound) {
		if (index <= self.viewIndex) {
			self.viewIndex--;
		}
		[self.views removeObjectAtIndex:index];
	}
}

- (void)updateAsynchronously {
	if (self.blurEnabled && !self.updating && self.updatesEnabled > 0 && [self.views count]) {

		//loop through until we find a view that's ready to be drawn
		self.viewIndex = self.viewIndex % [self.views count];

		for (NSUInteger i = self.viewIndex; i < [self.views count]; i++) {
			FXBlurView *view = self.views[i];

			if (view.blurEnabled && view.dynamic && view.window &&
			    (!view.lastUpdate || [view.lastUpdate timeIntervalSinceNow] < -view.updateInterval) &&
			    !CGRectIsEmpty(view.bounds) && !CGRectIsEmpty(view.viewToBlur.bounds)) {




				self.updating = YES;

                UIImage *snapshot = [view snapshotOfSuperview:view.viewToBlur];

				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{

                    UIImage *blurredImage = [snapshot blurredImageWithRadius:view.blurRadius
                                                                  iterations:view.iterations
                                                                   tintColor:view.tintColor];

				    dispatch_sync(dispatch_get_main_queue(), ^{

                        //set image
                        self.updating = NO;
                        if (view.dynamic) {
                            view.layer.contents = (id)blurredImage.CGImage;
                            view.layer.contentsScale = blurredImage.scale;
                        }

                        //render next view
                        self.viewIndex = i + 1;

                        [self performSelectorOnMainThread:@selector(updateAsynchronously)
                                               withObject:nil
                                            waitUntilDone:NO
                                                    modes:@[NSDefaultRunLoopMode, UITrackingRunLoopMode]];
                    });
				});
				return;
			}
		}

		//try again
		self.viewIndex = 0;
		[self performSelectorOnMainThread:@selector(updateAsynchronously)
                               withObject:nil
		                    waitUntilDone:NO
                                    modes:@[NSDefaultRunLoopMode, UITrackingRunLoopMode]];
	}
}

@end


@implementation FXBlurView

+ (void)setBlurEnabled:(BOOL)blurEnabled {
	[FXBlurScheduler sharedInstance].blurEnabled = blurEnabled;
}

+ (void)setUpdatesEnabled {
	[[FXBlurScheduler sharedInstance] setUpdatesEnabled];
}

+ (void)setUpdatesDisabled {
	[[FXBlurScheduler sharedInstance] setUpdatesDisabled];
}

- (void)setUp {
	if (!_iterationsSet) _iterations = 3;
	if (!_blurRadiusSet) _blurRadius = 40.0f;
	if (!_dynamicSet) _dynamic = YES;
	if (!_blurEnabledSet) _blurEnabled = YES;
	self.updateInterval = _updateInterval;
	self.layer.magnificationFilter = @"linear"; //kCAFilterLinear;
}

- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		[self setUp];
		self.clipsToBounds = YES;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
	if ((self = [super initWithCoder:aDecoder])) {
		[self setUp];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setIterations:(NSUInteger)iterations {
	_iterationsSet = YES;
	_iterations = iterations;
	[self setNeedsDisplay];
}

- (void)setBlurRadius:(CGFloat)blurRadius {
	_blurRadiusSet = YES;
	_blurRadius = blurRadius;
	[self setNeedsDisplay];
}

- (void)setBlurEnabled:(BOOL)blurEnabled {
	_blurEnabledSet = YES;
	if (_blurEnabled != blurEnabled) {
		_blurEnabled = blurEnabled;
		[self schedule];
		if (_blurEnabled) {
			[self setNeedsDisplay];
		}
	}
}

- (void)setDynamic:(BOOL)dynamic {
	_dynamicSet = YES;
	if (_dynamic != dynamic) {
		_dynamic = dynamic;
		[self schedule];
		if (!dynamic) {
			[self setNeedsDisplay];
		}
	}
}

- (void)setUpdateInterval:(NSTimeInterval)updateInterval {
	_updateInterval = updateInterval;
	if (_updateInterval <= 0) _updateInterval = 1.0 / 60;
}

- (void)didMoveToSuperview {
	[super didMoveToSuperview];
	[self.layer setNeedsDisplay];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	[self schedule];
}

- (void)schedule {
	if (self.window && self.dynamic && self.blurEnabled) {
		[[FXBlurScheduler sharedInstance] addView:self];
	} else {
		[[FXBlurScheduler sharedInstance] removeView:self];
	}
}

- (void)setNeedsDisplay {
	[super setNeedsDisplay];
	[self.layer setNeedsDisplay];
}

- (void)displayLayer:(__unused CALayer *)layer {

	if ([FXBlurScheduler sharedInstance].blurEnabled && self.blurEnabled && self.viewToBlur &&
	    !CGRectIsEmpty(self.bounds) && !CGRectIsEmpty(self.viewToBlur.bounds)) {
		UIImage *snapshot = [self snapshotOfSuperview:self.viewToBlur];
        UIImage *blurredImage = [snapshot blurredImageWithRadius:self.blurRadius
                                                      iterations:self.iterations
                                                       tintColor:self.tintColor];
		self.layer.contents = (id)blurredImage.CGImage;
		self.layer.contentsScale = blurredImage.scale;
	}
}

- (UIImage *)snapshotOfSuperview:(UIView *)superview {

	self.lastUpdate = [NSDate date];

	UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, [UIScreen mainScreen].scale);
	CGContextRef context = UIGraphicsGetCurrentContext();

    CGRect rect = [self convertRect:self.bounds toView:superview];
    CGContextTranslateCTM(context, -rect.origin.x, -rect.origin.y);

    [self hideViews];

    [superview.layer renderInContext:context];

    [self showViews];

	UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return snapshot;
}

- (void)hideViews {
    for (UIView *view in _viewsToHide) {
        view.hidden = YES;
    }
    self.hidden = YES;
}

- (void)showViews {
    for (UIView *view in _viewsToHide) {
        view.hidden = NO;
    }
    self.hidden = NO;
}

@end
