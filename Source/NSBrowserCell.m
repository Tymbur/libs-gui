/*
   NSBrowserCell.m

   Cell class for the NSBrowser

   Copyright (C) 1996, 1997, 1999 Free Software Foundation, Inc.

   Author:  Scott Christley <scottc@net-community.com>
   Date: 1996
   
   Author: Nicola Pero <n.pero@mi.flashnet.it>
   Date: December 1999

   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/

#include <gnustep/gui/config.h>

#include <AppKit/NSBrowserCell.h>
#include <AppKit/NSTextFieldCell.h>
#include <AppKit/NSColor.h>
#include <AppKit/NSFont.h>
#include <AppKit/NSImage.h>
#include <AppKit/NSGraphics.h>
#include <AppKit/NSEvent.h>
#include <AppKit/NSWindow.h>

/*
 * Class variables
 */
static NSImage	*_branch_image;
static NSImage	*_highlight_image;

static Class	_cellClass;
static Class	_colorClass;

// Color is not used now, but the code is here
// in case in the future we want to use it again
static BOOL _gsFontifyCells = NO;
//static NSColor *_nonLeafColor;
static NSFont *_nonLeafFont;
//static NSColor *_leafColor;
static NSFont *_leafFont;

/*****************************************************************************
 *
 * 		NSBrowserCell
 *
 *****************************************************************************/

@implementation NSBrowserCell

/*
 * Class methods
 */
+ (void) initialize
{
  if (self == [NSBrowserCell class])
    {
      [self setVersion: 1];
      ASSIGN(_branch_image, [NSImage imageNamed: @"common_3DArrowRight"]);
      ASSIGN(_highlight_image, [NSImage imageNamed: @"common_3DArrowRightH"]);
      /*
       * Cache classes to avoid overheads of poor compiler implementation.
       */
      _cellClass = [NSCell class];
      _colorClass = [NSColor class];

      // A GNUstep experimental feature
      if ([[NSUserDefaults standardUserDefaults] 
	    boolForKey: @"GSBrowserCellFontify"])
	{
	  _gsFontifyCells = YES;
	  _cellClass = [NSTextFieldCell class];
	  //_nonLeafColor = RETAIN ([_colorClass colorWithCalibratedWhite: 0.222
	  //				  alpha: 1.0]);
	  _nonLeafFont = RETAIN ([NSFont boldSystemFontOfSize: 0]);
	  //_leafColor = RETAIN ([_colorClass blackColor]);
	  _leafFont = RETAIN ([NSFont systemFontOfSize: 0]);
	}
    }
}

/*
 * Accessing Graphic Attributes
 */
+ (NSImage*) branchImage
{
  return _branch_image;
}

+ (NSImage*) highlightedBranchImage
{
  return _highlight_image;
}

/*
 * Instance methods
 */
- (id) init
{
  return [self initTextCell: @"aTitle"];
}

- (id) initTextCell: (NSString *)aString
{
  [super initTextCell: aString];
  _branchImage = RETAIN([isa branchImage]);
  _highlightBranchImage = RETAIN([isa highlightedBranchImage]);
  _cell.is_editable = NO;
  _cell.is_bordered = NO;
  _text_align = NSLeftTextAlignment;
  _alternateImage = nil;
  if (_gsFontifyCells)
    {
      // To make the [self setLeaf: NO] effective
      _isLeaf = YES; 
      [self setLeaf: NO];
    }
  else
    {
      _isLeaf = NO; 
    }
  _isLoaded = NO;

  return self;
}

- (void) dealloc
{
  RELEASE(_branchImage);
  RELEASE(_highlightBranchImage);
  TEST_RELEASE(_alternateImage);

  [super dealloc];
}

- (id) copyWithZone: (NSZone*)zone
{
  NSBrowserCell	*c = [super copyWithZone: zone];

  c->_branchImage = RETAIN(_branchImage);
  if (_alternateImage)
    c->_alternateImage = RETAIN(_alternateImage);
  c->_highlightBranchImage = RETAIN(_highlightBranchImage);
  c->_isLeaf = _isLeaf;
  c->_isLoaded = _isLoaded;

  return c;
}

/*
 * Accessing Graphic Attributes
 */
- (NSImage*) alternateImage
{
  return _alternateImage;
}

- (void) setAlternateImage: (NSImage *)anImage
{
  ASSIGN(_alternateImage, anImage);
}

/*
 * Placing in the Browser Hierarchy
 */
- (BOOL) isLeaf
{
  return _isLeaf;
}

- (void) setLeaf: (BOOL)flag
{
  if (_isLeaf == flag)
    return;

  _isLeaf = flag;
  
  if (_gsFontifyCells)
    {
      if (_isLeaf)
	{
	  ASSIGN (_cell_font, _leafFont);
	}
      else 
	{
	  ASSIGN (_cell_font, _nonLeafFont);
	}
    }
}

/*
 * Determining Loaded Status
 */
- (BOOL) isLoaded
{
  return _isLoaded;
}

- (void) setLoaded: (BOOL)flag
{
  _isLoaded = flag;
}

/*
 * Setting State
 */
- (void) reset
{
  _cell.is_highlighted = NO;
  _cell_state = NO;
}

- (void) set
{
  _cell.is_highlighted = YES;
  _cell_state = YES;
}

/*
 * Displaying
 */
- (void) drawInteriorWithFrame: (NSRect)cellFrame inView: (NSView *)controlView
{
  NSRect	title_rect = cellFrame;
  NSImage	*image = nil;
  NSColor	*backColor;
  NSWindow      *cvWin = [controlView window];

  if (!cvWin)
    return;

  [controlView lockFocus];

  if (_cell.is_highlighted || _cell_state)
    {
      backColor = [_colorClass selectedControlColor];
      [backColor set];
      if (!_isLeaf)
	image = _highlightBranchImage;
    }
  else
    {
      backColor = [cvWin backgroundColor];
      [backColor set];
      if (!_isLeaf)
	image = _branchImage;
    }
  
  NSRectFill(cellFrame);	// Clear the background

  if (image)
    {
      NSRect image_rect;

      image_rect.origin = cellFrame.origin;
      image_rect.size = [image size];
      image_rect.origin.x += cellFrame.size.width - image_rect.size.width - 4.0;
      image_rect.origin.y
	+= (cellFrame.size.height - image_rect.size.height) / 2.0;
      [image setBackgroundColor: backColor];
      /*
       * Images are always drawn with their bottom-left corner at the origin
       * so we must adjust the position to take account of a flipped view.
       */
      if ([controlView isFlipped])
	image_rect.origin.y += image_rect.size.height;
      [image compositeToPoint: image_rect.origin operation: NSCompositeCopy];

      title_rect.size.width -= image_rect.size.width + 8;	
    }
  [super drawInteriorWithFrame: title_rect inView: controlView];
  [controlView unlockFocus];
}

- (BOOL) isOpaque
{
  return YES;
}

/*
 * NSCoding protocol
 */
- (void) encodeWithCoder: (NSCoder*)aCoder
{
  [super encodeWithCoder: aCoder];

  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &_isLeaf];
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &_isLoaded];
}

- (id) initWithCoder: (NSCoder*)aDecoder
{
  [super initWithCoder: aDecoder];

  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &_isLeaf];
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &_isLoaded];
  _branchImage = RETAIN([isa branchImage]);
  _highlightBranchImage = RETAIN([isa highlightedBranchImage]);

  return self;
}

@end
