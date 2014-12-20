//
//	ResizingWindowController.m
//	ResizingWindow
//
//	Created by Justin Spahr-Summers on 2012-12-12.
//	Copyright (c) 2012 GitHub. All rights reserved.
//

#import "ResizingWindowController.h"
#import <ReactiveCocoa/EXTScope.h>

@interface ResizingWindowController ()

@property (nonatomic, strong, readonly) NSView *contentView;

@property (nonatomic, assign) CGFloat labelWidth;

@property (nonatomic, strong, readonly) RACSignal *horizontalPadding;
@property (nonatomic, strong, readonly) RACSignal *verticalPadding;

@property (nonatomic, weak) NSTextField *emailLabel;
@property (nonatomic, weak) NSTextField *emailField;
@property (nonatomic, copy) NSString *email;

@property (nonatomic, assign, getter = isConfirmEmailVisible) BOOL confirmEmailVisible;
@property (nonatomic, weak) NSTextField *confirmEmailLabel;
@property (nonatomic, weak) NSTextField *confirmEmailField;

@property (nonatomic, weak) NSTextField *nameLabel;
@property (nonatomic, weak) NSTextField *nameField;

// Horizontally lays out the given label and text field from the CGRects of the
// given signal.
- (void)layoutField:(NSTextField *)field label:(NSTextField *)label fromSignal:(RACSignal *)signal;

@end

@implementation ResizingWindowController

#pragma mark Properties

- (NSView *)contentView {
	return self.window.contentView;
}

- (RACSignal *)horizontalPadding {
	return RCLBox(8);
}

- (RACSignal *)verticalPadding {
	return RCLBox(8);
}

#pragma mark Lifecycle

- (id)init {
	return [self initWithWindowNibName:@"ResizingWindow"];
}

- (void)windowDidLoad {
	[super windowDidLoad];

	self.emailLabel = [self labelWithString:NSLocalizedString(@"Email Address", @"")];
	self.confirmEmailLabel = [self labelWithString:NSLocalizedString(@"Confirm Email Address", @"")];
	self.nameLabel = [self labelWithString:NSLocalizedString(@"Name", @"")];

	self.emailField = [self textFieldWithString:@""];
	self.confirmEmailField = [self textFieldWithString:@""];
	self.nameField = [self textFieldWithString:@""];

	// The confirmation field should only be visible when some text is entered
	// in the email field.
	RAC(self, confirmEmailVisible) = [[self.emailField.rac_textSignal
		skip:1]
		map:^(NSString *str) {
			return @(str.length > 0);
		}];

	// For the confirmation field, start with an alpha of 0, and then animate
	// any changes thereafter.
	RACSignal *confirmAlpha = [[RACSignal zero] concat:[RACObserve(self, confirmEmailVisible) animate]];

	RAC(self.confirmEmailLabel, rcl_alphaValue) = confirmAlpha;
	RAC(self.confirmEmailField, rcl_alphaValue) = confirmAlpha;

	// We want to align all the text fields with the longest label.
	RAC(self, labelWidth) = [RACSignal max:@[
		self.nameLabel.rcl_intrinsicWidthSignal,
		self.emailLabel.rcl_intrinsicWidthSignal,
		self.confirmEmailLabel.rcl_intrinsicWidthSignal,
	]];

	// Inset the available rect, then cut out enough space for the email field
	// vertically.
	RACTupleUnpack(RACSignal *emailRect, RACSignal *possibleConfirmEmailRect) = [[self.contentView.rcl_frameSignal
		// Purposely misaligned to demonstrate automatic pixel alignment when
		// binding to RCL's NSView properties.
		insetWidth:RCLBox(32.25) height:RCLBox(16.75) nullRect:CGRectZero]
		divideWithAmount:self.emailField.rcl_intrinsicHeightSignal padding:self.verticalPadding fromEdge:NSLayoutAttributeTop];

	[self layoutField:self.emailField label:self.emailLabel fromSignal:emailRect];

	// Make the height of the confirmation email field depend on whether it's
	// supposed to be visible.
	//
	// First, choose the appropriate signal based on the BOOL…
	RACSignal *confirmHeightPlusPadding = [[[[[RACSignal if:RACObserve(self, confirmEmailVisible)
		then:[self.confirmEmailField.rcl_intrinsicHeightSignal plus:self.verticalPadding]
		else:[RACSignal zero]]
		// Then animate all changes.
		animatedSignals]
		map:^(RACSignal *animation) {
			return [[animation
				doNext:^(NSNumber *height) {
					NSLog(@"Animating confirmEmailField to height %@", height);
				}]
				doCompleted:^{
					NSLog(@"confirmEmailField is done animating");
				}];
		}]
		switchToLatest]
		replayLast];

	// Cut out space for the confirmation email field.
	RACTupleUnpack(RACSignal *confirmEmailRect, RACSignal *nameRect) = [possibleConfirmEmailRect divideWithAmount:confirmHeightPlusPadding fromEdge:NSLayoutAttributeTop];

	// Remove the padding that we included for the purposes of animation.
	confirmEmailRect = [confirmEmailRect remainderAfterSlicingAmount:self.verticalPadding fromEdge:NSLayoutAttributeBottom];
	[self layoutField:self.confirmEmailField label:self.confirmEmailLabel fromSignal:confirmEmailRect];

	// Only use the height that the name field actually requires.
	nameRect = [nameRect sliceWithAmount:self.nameField.rcl_intrinsicHeightSignal fromEdge:NSLayoutAttributeTop];
	[self layoutField:self.nameField label:self.nameLabel fromSignal:nameRect];
}

#pragma mark Layout

- (void)layoutField:(NSTextField *)field label:(NSTextField *)label fromSignal:(RACSignal *)signal {
	// Split the rect horizontally, into a rect for the label and a rect for the
	// text field.
	RACTupleUnpack(RACSignal *labelRect, RACSignal *fieldRect) = [signal divideWithAmount:RACObserve(self, labelWidth) padding:self.horizontalPadding fromEdge:NSLayoutAttributeLeading];

	RAC(field, rcl_alignmentRect) = fieldRect;
	RCLAlignment(label) = @{
		rcl_origin: labelRect.origin,
		rcl_baseline: field
	};
}

#pragma mark View Creation

- (NSTextField *)labelWithString:(NSString *)string {
	NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
	label.wantsLayer = YES;
	label.editable = NO;
	label.selectable = NO;
	label.bezeled = NO;
	label.drawsBackground = NO;
	label.stringValue = string;
	label.font = [NSFont systemFontOfSize:8];
	[label sizeToFit];

	// We don't actually use autoresizing to move these views, but rather to
	// keep them pinned in the absence of any movement.
	label.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;

	[self.contentView addSubview:label];
	return label;
}

- (NSTextField *)textFieldWithString:(NSString *)string {
	NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	textField.wantsLayer = YES;
	textField.stringValue = string;
	[textField sizeToFit];

	// We don't actually use autoresizing to move these views, but rather to
	// keep them pinned in the absence of any movement.
	textField.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;

	[self.contentView addSubview:textField];
	return textField;
}

@end
