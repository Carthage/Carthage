//
//  CGGeometry+MEDConvenienceAdditions.h
//  Archimedes
//
//  Created by Justin Spahr-Summers on 18.01.12.
//  Copyright 2012 GitHub. All rights reserved.
//

/*

Portions copyright (c) 2012, Bitswift, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Neither the name of the Bitswift, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

#import <CoreGraphics/CoreGraphics.h>

// Extends CGRectDivide() to accept the following additional types for the
// `SLICE` and `REMAINDER` arguments:
//
//  - A `CGRect` property
//  - A `CGRect` variable
//  - `NULL`
#define MEDRectDivide(RECT, SLICE, REMAINDER, AMOUNT, EDGE) \
	do { \
		CGRect _slice, _remainder; \
		CGRectDivide((RECT), &_slice, &_remainder, (AMOUNT), (EDGE)); \
		\
		_MEDAssignToRectByReference(SLICE, _slice); \
		_MEDAssignToRectByReference(REMAINDER, _remainder); \
	} while (0)

// Returns the exact center point of the given rectangle.
CGPoint MEDRectCenterPoint(CGRect rect);

// Chops the given amount off of a rectangle's edge.
//
// Returns the remainder of the rectangle, or `CGRectZero` if `amount` is
// greater than or equal to size of the rectangle along the axis being chopped.
CGRect MEDRectRemainder(CGRect rect, CGFloat amount, CGRectEdge edge);

// Returns a slice consisting of the given amount starting from a rectangle's
// edge, or the entire rectangle if `amount` is greater than or equal to the
// size of the rectangle along the axis being sliced.
CGRect MEDRectSlice(CGRect rect, CGFloat amount, CGRectEdge edge);

// Adds the given amount to a rectangle's edge.
//
// rect   - The rectangle to grow.
// amount - The amount of points to add.
// edge   - The edge from which to grow. Growing is always outward (i.e., using
//          `CGRectMaxXEdge` will increase the width of the rectangle and leave
//          the origin unmodified).
CGRect MEDRectGrow(CGRect rect, CGFloat amount, CGRectEdge edge);

// Divides a source rectangle into two component rectangles, skipping the given
// amount of padding in between them.
//
// This functions like CGRectDivide(), but omits the specified amount of padding
// between the two rectangles. This results in a remainder that is `padding`
// points smaller from `edge` than it would be with CGRectDivide().
//
// rect        - The rectangle to divide.
// slice       - Upon return, the portion of `rect` starting from `edge` and
//               continuing for `sliceAmount` points. This argument may be NULL
//               to not return the slice.
// remainder   - Upon return, the portion of `rect` beginning `padding` points
//               after the end of the `slice`. If `rect` is not large enough to
//               leave a remainder, this will be `CGRectZero`. This argument may
//               be NULL to not return the remainder.
// sliceAmount - The number of points to include in `slice`, starting from the
//               given edge.
// padding     - The number of points of padding to omit between `slice` and
//               `remainder`.
// edge        - The edge from which division begins, proceeding toward the
//               opposite edge.
void MEDRectDivideWithPadding(CGRect rect, CGRect *slice, CGRect *remainder, CGFloat sliceAmount, CGFloat padding, CGRectEdge edge);

// Extends MEDRectDivideWithPadding() to accept the following additional types
// for the `SLICE` and `REMAINDER` arguments:
//
//  - A `CGRect` property
//  - A `CGRect` variable
#define MEDRectDivideWithPadding(RECT, SLICE, REMAINDER, AMOUNT, PADDING, EDGE) \
	do { \
		CGRect _slice, _remainder; \
		MEDRectDivideWithPadding((RECT), &_slice, &_remainder, (AMOUNT), (PADDING), (EDGE)); \
		\
		_MEDAssignToRectByReference(SLICE, _slice); \
		_MEDAssignToRectByReference(REMAINDER, _remainder); \
	} while (0)

// Aligns a rectangle with on edge of another rectangle.
//
// rect          - The rectangle that should be aligned.
// referenceRect - The rectangle to align `rect` with.
// edge          - The edge that `rect` should share with `referenceRect`.
//
// Returns a rectangle with the dimensions of `rect` that shares the edge
// specified by `edge` with `referenceRect`. The remaining coordinate of `rect`
// is left unchanged.
CGRect MEDRectAlignWithRect(CGRect rect, CGRect referenceRect, CGRectEdge edge);

// Centers a rectangle in another rectangle.
//
// inner - The rectangle that will be centered.
// outer - The rectangle in which to center `inner`.
//
// Returns a rectangle with the dimensions of `inner` centered in `outer`.
CGRect MEDRectCenterInRect(CGRect inner, CGRect outer);

// Round a rectangle to integral numbers.
//
// The rect will be moved up and left in native view coordinates (not accounting
// for flippedness or transformed coordinate systems). To accomplish this:
//
//  - On OS X, this function will round down fractional X origins and round up
//    fractional Y origins.
//  - On iOS, this function will round down fractional X origins and round down
//    fractional Y origins.
//
// On both platforms, this function will round down fractional sizes, such that
// the size of the rectangle will never increase just from use of this method.
// Among other things, this avoids stretching images that need a precise size.
//
// This function differs from CGRectIntegral() in that the resultant rectangle
// may not completely encompass `rect`. CGRectIntegral() will ensure that its
// resultant rectangle encompasses the original, but may increase the size of
// the result to accomplish this.
CGRect MEDRectFloor(CGRect rect);

// Creates a rectangle for a coordinate system originating in the bottom-left.
//
// containingRect - The rectangle that will "contain" the created rectangle,
//                  used as a reference to vertically flip the coordinate system.
// x              - The X origin of the rectangle, starting from the left.
// y              - The Y origin of the rectangle, starting from the top.
// width          - The width of the rectangle.
// height         - The height of the rectangle.
CGRect MEDRectMakeInverted(CGRect containingRect, CGFloat x, CGFloat y, CGFloat width, CGFloat height);

// Vertically inverts the coordinates of `rect` within `containingRect`.
//
// This can effectively be used to change the coordinate system of a rectangle.
// For example, if `rect` is defined for a coordinate system starting at the
// top-left, the result will be a rectangle relative to the bottom-left.
//
// containingRect - The rectangle that will "contain" the created rectangle,
//                  used as a reference to vertically flip the coordinate system.
// rect           - The rectangle to vertically flip within `containingRect`.
CGRect MEDRectInvert(CGRect containingRect, CGRect rect);

// Returns a rectangle with an origin of `CGPointZero` and the given size.
CGRect MEDRectWithSize(CGSize size);

// Converts a rectangle to one in the unit coordinate space.
//
// Unit rectangles are an abstraction from screen sizes that range from 0-1
// along both axes.  This function will attempt to find the nearest fractional
// representation of the components of the given rectangle.
CGRect MEDRectConvertToUnitRect(CGRect rect);

// Converts a unit rectangle into the coordinate space of a destination
// rectangle.
//
// This is the exact opposite of `MEDRectConvertToUnitRect`, however a
// destination rect is required because unit coordinate systems are
// size agnostic.
//
// rect           - The rectangle, in unit coordinates, to be "converted" to
//                  the destination rect's coordinate system.
// destRect       - The rectangle that represents the size of the screen the
//                  unit rect will be converted to.
CGRect MEDRectConvertFromUnitRect(CGRect rect, CGRect destRect);

// Returns whether every side of `rect` is within `epsilon` distance of `rect2`.
bool MEDRectEqualToRectWithAccuracy(CGRect rect, CGRect rect2, CGFloat epsilon);

// Returns whether `size` is within `epsilon` points of `size2`.
bool MEDSizeEqualToSizeWithAccuracy(CGSize size, CGSize size2, CGFloat epsilon);

// Scales the components of `size` by `scale`.
CGSize MEDSizeScale(CGSize size, CGFloat scale);

// Scales a size a size to fit within a different size.
//
// size    - The size to scale.
// maxSize - The size to fit original size within.
//
// Returns a new CGSize that has the same aspect ratio as the provided size, but
// is resized fit inside the maxSize.
CGSize MEDSizeScaleAspectFit(CGSize size, CGSize maxSize);

// Scales a size a size to fill (and possibly exceed) a different size.
//
// size    - The size to scale.
// minSize - The size to fill.
//
// Returns a new CGSize that has the same aspect ratio as the provided size, but
// is resized to fill (and possibly exceed) the minSize.
CGSize MEDSizeScaleAspectFill(CGSize size, CGSize minSize);

// Round a point to integral numbers.
//
// The point will be moved up and left in native view coordinates (not
// accounting for flippedness or transformed coordinate systems). To accomplish
// this:
//
//  - On OS X, this function will round down fractional X values and round up
//    fractional Y values.
//  - On iOS, this function will round down fractional X values and round down
//    fractional Y values.
CGPoint MEDPointFloor(CGPoint point);

// Returns whether `point` is within `epsilon` distance of `point2`.
bool MEDPointEqualToPointWithAccuracy(CGPoint point, CGPoint point2, CGFloat epsilon);

// Returns the dot product of two points.
CGFloat MEDPointDotProduct(CGPoint point, CGPoint point2);

// Returns `point` scaled by `scale`.
CGPoint MEDPointScale(CGPoint point, CGFloat scale);

// Returns the length of `point`.
CGFloat MEDPointLength(CGPoint point);

// Returns the unit vector of `point`.
CGPoint MEDPointNormalize(CGPoint point);

// Returns a projected point in the specified direction.
CGPoint MEDPointProject(CGPoint point, CGPoint direction);

// Returns the angle of a vector.
CGFloat MEDPointAngleInDegrees(CGPoint point);

// Projects a point along a specified angle.
CGPoint MEDPointProjectAlongAngle(CGPoint point, CGFloat angleInDegrees);

// Add `p1` and `p2`.
CGPoint MEDPointAdd(CGPoint p1, CGPoint p2);

// Subtracts `p2` from `p1`.
CGPoint MEDPointSubtract(CGPoint p1, CGPoint p2);

// For internal use only.
//
// Returns a pointer to a new empty rectangle, suitable for storing unused
// values.
#define _MEDEmptyRectPointer \
	(&(CGRect){ .origin = CGPointZero, .size = CGSizeZero })

// For internal use only.
//
// Assigns `RECT` into the first argument, which may be a property, `CGRect`
// variable, or a pointer to a `CGRect`. If the argument is a pointer and is
// `NULL`, nothing happens.
#define _MEDAssignToRectByReference(RECT_OR_PTR, RECT) \
	/* Switches based on the type of the first argument. */ \
	(_Generic((RECT_OR_PTR), \
			CGRect *: *({ \
				/* Copy the argument into a union so this code compiles even
				 * when it's not a pointer. */ \
				union { \
					__typeof__(RECT_OR_PTR) copy; \
					CGRect *ptr; \
				} _u = { .copy = (RECT_OR_PTR) }; \
				\
				/* If the argument is NULL, assign into an empty rect instead. */ \
				_u.ptr ?: _MEDEmptyRectPointer; \
			}), \
			\
			/* void * should only occur for NULL. */ \
			void *: *_MEDEmptyRectPointer, \
			\
			/* For all other cases, assign into the given variable or property
			 * normally. */ \
			default: RECT_OR_PTR \
		) = (RECT))
