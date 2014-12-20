//
//  ViewController.m
//  DeviceRotation
//
//  Created by Justin Spahr-Summers on 2012-12-13.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "ViewController.h"
#import <ReactiveCocoa/EXTScope.h>

@interface ViewController () {
	RACSubject *_rotationSignal;
}

// Sends the new interface orientation every time a rotation occurs.
@property (nonatomic, strong, readonly) RACSignal *rotationSignal;

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UITextField *nameTextField;

@end

@implementation ViewController

#pragma mark Lifecycle

- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
	self = [super initWithNibName:nibName bundle:bundle];
	if (self == nil) return nil;

	_rotationSignal = [RACSubject subject];

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.lightGrayColor;

	self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.nameLabel.font = [UIFont systemFontOfSize:30];

	self.nameTextField = [[UITextField alloc] initWithFrame:CGRectZero];
	self.nameTextField.text = @"Some sample text";
	self.nameTextField.backgroundColor = UIColor.whiteColor;
	self.nameTextField.borderStyle = UITextBorderStyleRoundedRect;

	[self.view addSubview:self.nameLabel];
	[self.view addSubview:self.nameTextField];

	// Purposely misaligned to demonstrate automatic pixel alignment when
	// binding to RCL's UIView properties.
	RACSignal *insetRect = [self.view.rcl_boundsSignal insetWidth:RCLBox(16.25) height:RCLBox(24.75) nullRect:CGRectNull];

	// Dynamically change the text of nameLabel based on the current
	// orientation.
	RAC(self.nameLabel, text) = [[[self.rotationSignal
		map:^(NSNumber *orientation) {
			return @(UIInterfaceOrientationIsPortrait(orientation.integerValue));
		}]
		startWith:@YES]
		map:^(NSNumber *isPortait) {
			return (isPortait.boolValue ? NSLocalizedString(@"Portrait!", @"") : NSLocalizedString(@"Landscape awww yeaahhh", @""));
		}];

	// Horizontally divide the available space into a rect for the label and
	// a rect for the text field.
	RACTupleUnpack(RACSignal *labelRect, RACSignal *textFieldRect) = [insetRect divideWithAmount:self.nameLabel.rcl_intrinsicWidthSignal padding:RCLBox(8) fromEdge:NSLayoutAttributeLeading];

	// Make the text field a constant 28 points high.
	textFieldRect = [textFieldRect sliceWithAmount:RCLBox(28) fromEdge:NSLayoutAttributeTop];

	// Size the label to its intrinsic size, and align it to the text field.
	//
	// FIXME: Baseline alignment is a bit broken for iOS at the moment. See
	// https://github.com/github/ReactiveCocoaLayout/issues/12.
	RCLAlignment(self.nameLabel) = @{
		rcl_rect: labelRect,
		rcl_size: self.nameLabel.rcl_intrinsicContentSizeSignal,
		rcl_baseline: self.nameTextField
	};

	// Animate the initial appearance of the text field, but not any changes due
	// to rotation.
	RACSignal *initialRect = [[textFieldRect take:1] animateWithDuration:1 curve:RCLAnimationCurveEaseOut];
	RAC(self.nameTextField, rcl_alignmentRect) = [initialRect concat:textFieldRect];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[_rotationSignal sendNext:@(self.interfaceOrientation)];
}

#pragma mark Rotation

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration {
	[_rotationSignal sendNext:@(interfaceOrientation)];
}

@end
