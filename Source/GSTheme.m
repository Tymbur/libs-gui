/** <title>GSTheme</title>

   <abstract>Useful/configurable drawing functions</abstract>

   Copyright (C) 2004 Free Software Foundation, Inc.

   Author: Adam Fedor <fedor@gnu.org>
   Date: Jan 2004
   
   This file is part of the GNU Objective C User interface library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
   */

#include "Foundation/NSBundle.h"
#include "Foundation/NSDictionary.h"
#include "Foundation/NSFileManager.h"
#include "Foundation/NSNotification.h"
#include "Foundation/NSNull.h"
#include "Foundation/NSPathUtilities.h"
#include "Foundation/NSUserDefaults.h"
#include "GNUstepGUI/GSTheme.h"
#include "AppKit/NSApplication.h"
#include "AppKit/NSColor.h"
#include "AppKit/NSColorList.h"
#include "AppKit/NSGraphics.h"
#include "AppKit/NSImage.h"
#include "AppKit/NSMatrix.h"
#include "AppKit/NSMenu.h"
#include "AppKit/NSPanel.h"
#include "AppKit/NSScrollView.h"
#include "AppKit/NSView.h"
#include "AppKit/NSWindow.h"
#include "AppKit/NSBezierPath.h"
#include "AppKit/PSOperators.h"

#include <math.h>
#include <float.h>


NSString	*GSThemeDidActivateNotification
  = @"GSThemeDidActivateNotification";
NSString	*GSThemeDidDeactivateNotification
  = @"GSThemeDidDeactivateNotification";

/** These are the nine types of tile used to draw a rectangular object.
 */
typedef enum {
  TileTL = 0,	/** Top left corner */
  TileTM = 1,	/** Top middle section */
  TileTR = 2,	/** Top right corner */
  TileCL = 3,	/** Centerj left corner */
  TileCM = 4,	/** Centerj middle section */
  TileCR = 5,	/** Centerj right corner */
  TileBL = 6,	/** Bottom left corner */
  TileBM = 7,	/** Bottom middle section */
  TileBR = 8	/** Bottom right corner */
} GSThemeTileOffset;

/** This is a trivial class to hold the nine tiles needed to draw a rectangle
 */
@interface	GSDrawTiles : NSObject
{
@public
  NSImage	*images[9];	/** The tile images */
  NSRect	rects[9];	/** The rectangles to use when drawing */
}
- (id) initWithImage: (NSImage*)image;
- (id) initWithImage: (NSImage*)image horizontal: (float)x vertical: (float)y;
@end

/** This is the panel used to select and inspect themes.
 */
@interface	GSThemePanel : NSPanel
{
  NSMatrix	*matrix;	// Not retained.
}

/** Return the shared panel.
 */
+ (GSThemePanel*) sharedThemePanel;

/** Update current theme to the one clicked on in the matrix.
 */
- (void) changeSelection: (id)sender;

/** Update list of available themes.
 */
- (void) update: (id)sender;

@end

/** This category defines private methods for internal use by GSTheme
 */
@interface	GSTheme (internal)
/**
 * Called whenever user defaults are changed ... this checks for the
 * GSTheme user default and ensures that the specified theme is the
 * current active theme.
 */
+ (void) defaultsDidChange: (NSNotification*)n;

/**
 * Called to load specified theme.<br />
 * If aName is nil or an empty string or 'GNUstep',
 * this returns the default theme.<br />
 * If the named is a full path specification, this uses that path.<br />
 * Otherwise this method searches the standard locations.<br />
 * Returns nil on failure.
 */
+ (GSTheme*) loadThemeNamed: (NSString*)aName;
@end



@implementation GSTheme

static GSTheme			*defaultTheme = nil;
static NSString			*currentThemeName = nil;
static GSTheme			*theTheme = nil;
static NSMutableDictionary	*themes = nil;
static NSNull			*null = nil;

+ (void) defaultsDidChange: (NSNotification*)n
{
  NSUserDefaults	*defs;
  NSString		*name;

  defs = [NSUserDefaults standardUserDefaults];
  name = [defs stringForKey: @"GSTheme"];
  if (name != currentThemeName && [name isEqual: currentThemeName] == NO)
    {
      [self setTheme: [self loadThemeNamed: name]];
      ASSIGN(currentThemeName, name);	// Don't try to load again.
    }
}

+ (void) initialize
{
  if (themes == nil)
    {
      themes = [NSMutableDictionary new];
      [[NSNotificationCenter defaultCenter]
	addObserver: self
	selector: @selector(defaultsDidChange:)
	name: NSUserDefaultsDidChangeNotification
	object: nil];
    }
  if (null == nil)
    {
      null = RETAIN([NSNull null]);
    }
  if (defaultTheme == nil)
    {
      NSBundle		*aBundle = [NSBundle bundleForClass: self];

      defaultTheme = [[self alloc] initWithBundle: aBundle];
      ASSIGN(theTheme, defaultTheme);
    }
  /* Establish the theme specified by the user defaults (if any);
   */
  [self defaultsDidChange: nil];
}

+ (GSTheme*) loadThemeNamed: (NSString*)aName
{
  NSBundle	*bundle;
  Class		cls;
  GSTheme	*instance;
  NSString	*theme;

  if ([aName length] == 0)
    {
      return defaultTheme;
    }

  if ([aName isAbsolutePath] == NO)
    {
      aName = [aName lastPathComponent];

      /* Ensure that the theme name has the 'theme' extension.
       */
      if ([[aName pathExtension] isEqualToString: @"theme"] == YES)
	{
	  theme = aName;
	}
      else
	{
	  theme = [aName stringByAppendingPathExtension: @"theme"];
	}
      if ([aName isEqualToString: @"GNUstep.theme"] == YES)
	{
	  return defaultTheme;
	}
    }

  bundle = [themes objectForKey: theme];
  if (bundle == nil)
    {
      NSString		*path;
      NSFileManager	*mgr = [NSFileManager defaultManager];
      BOOL 		isDir;

      /* A theme may be either an absolute path or a filename to be located
       * in the Themes subdirectory of one of the standard Library directories.
       */
      if ([theme isAbsolutePath] == YES)
        {
	  if ([mgr fileExistsAtPath: theme isDirectory: &isDir] == YES
	    && isDir == YES)
	    {
	      path = theme;
	    }
	}
      else
        {
	  NSEnumerator	*enumerator;

	  enumerator = [NSSearchPathForDirectoriesInDomains
	    (NSAllLibrariesDirectory, NSAllDomainsMask, YES) objectEnumerator];
	  while ((path = [enumerator nextObject]) != nil)
	    {
	      path = [path stringByAppendingPathComponent: @"Themes"];
	      path = [path stringByAppendingPathComponent: theme];
	      if ([mgr fileExistsAtPath: path isDirectory: &isDir])
		{
		  break;
		}
	    }
	}

      if (path == nil)
	{
	  NSLog (@"No theme named '%@' found", aName);
	  return nil;
	}
      else
        {
	  bundle = [NSBundle bundleWithPath: path];
	  [themes setObject: bundle forKey: theme];
	  [bundle load];	// Ensure code is loaded.
	}
    }

  cls = [bundle principalClass];
  if (cls == 0)
    {
      cls = self;
    }
  instance = [[cls alloc] initWithBundle: bundle];
  return AUTORELEASE(instance);
}

+ (void) orderFrontSharedThemePanel: (id)sender
{
  GSThemePanel *panel;

  panel = [GSThemePanel sharedThemePanel];
  [panel update: self];
  [panel orderFront: self];
}

+ (void) setTheme: (GSTheme*)theme
{
  if (theme == nil)
    {
      theme = defaultTheme;
    }
  if (theme != theTheme)
    {
      [theTheme deactivate];
      ASSIGN (theTheme, theme);
      [theTheme activate];
    }
  ASSIGN(currentThemeName, [theTheme name]);
}

+ (GSTheme*) theme 
{
  return theTheme;
}

- (void) activate
{
  NSUserDefaults	*defs;
  NSMutableDictionary	*userInfo;
  NSMutableArray	*searchList;
  NSArray		*imagePaths;
  NSEnumerator		*enumerator;
  NSString		*imagePath;
  NSArray		*imageTypes;
  NSString		*colorsPath;
  NSDictionary		*infoDict;
  NSWindow		*window;

  userInfo = [NSMutableDictionary dictionary];
  colorsPath = [_bundle pathForResource: @"ThemeColors" ofType: @"clr"]; 
  if (colorsPath != nil)
    {
      NSColorList	*list = nil;

      list = [[NSColorList alloc] initWithName: @"System"
				      fromFile: colorsPath];
      if (list != nil)
	{
	  [userInfo setObject: list forKey: @"Colors"];
	  RELEASE(list);
	}
    }

  /*
   * We step through all the bundle image resources and load them in
   * to memory, setting their names so that they are visible to
   * [NSImage+imageNamed:] and storing them in our local array.
   */
  imageTypes = [NSImage imageFileTypes];
  imagePaths = [_bundle pathsForResourcesOfType: nil
				    inDirectory: @"ThemeImages"];
  enumerator = [imagePaths objectEnumerator];
  while ((imagePath = [enumerator nextObject]) != nil)
    {
      NSString	*ext = [imagePath pathExtension];

      if (ext != nil && [imageTypes containsObject: ext] == YES)
        {
	  NSImage	*image;

	  image = [[NSImage alloc] initWithContentsOfFile: imagePath];
	  if (image != nil)
	    {
	      NSString	*imageName;

	      imageName = [imagePath lastPathComponent];
	      imageName = [imageName stringByDeletingPathExtension];
	      [_images addObject: image];
	      [image setName: imageName];
	      RELEASE(image);
	    }
	}
    }

  /*
   * We could cache tile info here, but it's probabaly better for the
   * tilesNamed: method to do it lazily.
   */

  /*
   * Use the GSThemeDomain key in the info dictionary of the theme to
   * set a defaults domain which will establish user defaults values
   * but will not override any defaults set explicitly by the user.
   * NB. For subclasses, the theme info dictionary may not be the same
   * as that of the bundle, so we don't use the bundle method directly.
   */
  infoDict = [self infoDictionary];
  defs = [NSUserDefaults standardUserDefaults];
  searchList = [[defs searchList] mutableCopy];
  if ([[infoDict objectForKey: @"GSThemeDomain"] isKindOfClass:
    [NSDictionary class]] == YES)
    {
      [defs removeVolatileDomainForName: @"GSThemeDomain"];
      [defs setVolatileDomain: [infoDict objectForKey: @"GSThemeDomain"]
		      forName: @"GSThemeDomain"];
      if ([searchList containsObject: @"GSThemeDomain"] == NO)
	{
	  unsigned	index;

	  /*
	   * Higher priority than GSConfigDomain and NSRegistrationDomain,
	   * but lower than NSGlobalDomain, NSArgumentDomain, and others
	   * set by the user to be application specific.
	   */
	  index = [searchList indexOfObject: GSConfigDomain];
	  if (index == NSNotFound)
	    {
	      index = [searchList indexOfObject: NSRegistrationDomain];
	      if (index == NSNotFound)
	        {
		  index = [searchList count];
		}
	    }
	  [searchList insertObject: @"GSThemeDomain" atIndex: index];
	  [defs setSearchList: searchList];
	}
    }
  else
    {
      [searchList removeObject: @"GSThemeDomain"];
      [defs removeVolatileDomainForName: @"GSThemeDomain"];
    }
  RELEASE(searchList);

  /*
   * Tell all other classes that new theme information is present.
   */
  [[NSNotificationCenter defaultCenter]
   postNotificationName: GSThemeDidActivateNotification
   object: self
   userInfo: userInfo];

  /*
   * Reset main menu to change between styles if necessary
   */
  [[NSApp mainMenu] setMain: YES];

  /*
   * Mark all windows as needing redisplaying to thos the new theme.
   */
  enumerator = [[NSApp windows] objectEnumerator];
  while ((window = [enumerator nextObject]) != nil)
    {
      [[[window contentView] superview] setNeedsDisplay: YES];
    }
}

- (NSArray*) authors
{
  return [[self infoDictionary] objectForKey: @"GSThemeAuthors"];
}

- (NSBundle*) bundle
{
  return _bundle;
}

- (void) deactivate
{
  NSEnumerator	*enumerator;
  NSImage	*image;

  /*
   * Remove all cached bundle images from both NSImage's name dictionary
   * and our cache array.
   */
  enumerator = [_images objectEnumerator];
  while ((image = [enumerator nextObject]) != nil)
    {
      [image setName: nil];
    }
  [_images removeAllObjects];

  [[NSNotificationCenter defaultCenter]
   postNotificationName: GSThemeDidDeactivateNotification
   object: self
   userInfo: nil];

}

- (void) dealloc
{
  RELEASE(_bundle);
  RELEASE(_images);
  RELEASE(_tiles);
  RELEASE(_icon);
  [super dealloc];
}

- (NSImage*) icon
{
  if (_icon == nil)
    {
      NSString	*path;

      path = [[self infoDictionary] objectForKey: @"GSThemeIcon"];
      if (path != nil)
        {
	  NSString	*ext = [path pathExtension];

	  path = [path stringByDeletingPathExtension];
	  path = [_bundle pathForResource: path ofType: ext];
	  if (path != nil)
	    {
	      _icon = [[NSImage alloc] initWithContentsOfFile: path];
	    }
	}
      if (_icon == nil)
        {
	  _icon = RETAIN([NSImage imageNamed: @"GNUstep"]);
	}
    }
  return _icon;
}

- (id) initWithBundle: (NSBundle*)bundle
{
  ASSIGN(_bundle, bundle);
  _images = [NSMutableArray new];
  _tiles = [NSMutableDictionary new];
  return self;
}

- (NSDictionary*) infoDictionary
{
  return [_bundle infoDictionary];
}

- (NSString*) name
{
  if (self == defaultTheme)
    {
      return @"GNUstep";
    }
  return
    [[[_bundle bundlePath] lastPathComponent] stringByDeletingPathExtension];
}

- (NSWindow*) themeInspector
{
  return nil;
}

- (GSDrawTiles*) tilesNamed: (NSString*)aName
{
  GSDrawTiles	*tiles = [_tiles objectForKey: aName];

  if (tiles == nil)
    {
      NSDictionary	*info;
      NSImage		*image;

      /* The GSThemeTiles entry in the info dictionary should be a
       * dictionary containing information about each set of tiles.
       * Keys are:
       * FileName		Name of the file in the ThemeTiles directory
       * HorizontalDivision	Where to divide the image into columns.
       * VerticalDivision	Where to divide the image into rows.
       */
      info = [self infoDictionary];
      info = [[info objectForKey: @"GSThemeTiles"] objectForKey: aName];
      if ([info isKindOfClass: [NSDictionary class]] == YES)
        {
	  float		x;
	  float		y;
	  NSString	*path;
	  NSString	*file;
	  NSString	*ext;

	  x = [[info objectForKey: @"HorizontalDivision"] floatValue];
	  y = [[info objectForKey: @"VerticalDivision"] floatValue];
	  file = [info objectForKey: @"FileName"];
	  ext = [file pathExtension];
	  file = [file stringByDeletingPathExtension];
	  path = [_bundle pathForResource: file
				   ofType: ext
			      inDirectory: @"ThemeTiles"];
	  if (path == nil)
	    {
	      NSLog(@"File %@.%@ not found in ThemeTiles", file, ext);
	    }
	  else
	    {
	      image = [[NSImage alloc] initWithContentsOfFile: path];
	      if (image != nil)
		{
		  tiles = [[GSDrawTiles alloc] initWithImage: image
						  horizontal: x
						    vertical: y];
		  RELEASE(image);
		}
	    }
	}
      else
        {
	  NSArray	*imageTypes;
	  NSString	*imagePath;
	  unsigned	count;

	  imageTypes = [NSImage imageFileTypes];
	  for (count = 0; image == nil && count < [imageTypes count]; count++)
	    {
	      NSString	*ext = [imageTypes objectAtIndex: count];

	      imagePath = [_bundle pathForResource: aName
					    ofType: ext
				       inDirectory: @"ThemeTiles"];
	      if (imagePath != nil)
		{
		  image = [[NSImage alloc] initWithContentsOfFile: imagePath];
		  if (image != nil)
		    {
		      tiles = [[GSDrawTiles alloc] initWithImage: image];
		      RELEASE(image);
		      break;
		    }
		}
	    }
	}

      if (tiles == nil)
        {
	  [_tiles setObject: null forKey: aName];
	}
      else
        {
	  [_tiles setObject: tiles forKey: aName];
	  RELEASE(_tiles);
	}
    }
  if (tiles == (id)null)
    {
      tiles = nil;
    }
  return tiles;
}

@end


@implementation	GSTheme (Drawing)

- (NSRect) drawButton: (NSRect) frame 
                   in: (NSButtonCell*) cell 
                 view: (NSView*) view 
                style: (int) style 
                state: (int) state
{
  /* computes the interior frame rect */

  NSRect interiorFrame = [cell drawingRectForBounds: frame];

  /* Draw the button background */

  if (state == 0) /* default state, unpressed */
    {
      [[NSColor controlBackgroundColor] set];
      NSRectFill(frame);
      [self drawButton: frame withClip: NSZeroRect];
    }
  else if (state == 1) /* highlighted state */
    {
      [[NSColor selectedControlColor] set];
      NSRectFill(frame);
      [self drawGrayBezel: frame withClip: NSZeroRect];
    }
  else if (state == 2) /* pushed state */
    {
      [[NSColor selectedControlColor] set];
      NSRectFill(frame);
      [self drawGrayBezel: frame withClip: NSZeroRect];
      interiorFrame
	= NSOffsetRect(interiorFrame, 1.0, [view isFlipped] ? 1.0 : -1.0);
    }

  /* returns the interior frame rect */

  return interiorFrame;
}

- (void) drawFocusFrame: (NSRect) frame view: (NSView*) view
{
  NSDottedFrameRect(frame);
}

- (void) drawWindowBackground: (NSRect) frame view: (NSView*) view
{
  NSColor *c;

  c = [[view window] backgroundColor];
  [c set];
  NSRectFill (frame);
}

@end



@implementation	GSTheme (MidLevelDrawing)

- (NSRect) drawButton: (NSRect)border withClip: (NSRect)clip
{
  NSRectEdge up_sides[] = {NSMaxXEdge, NSMinYEdge, 
			   NSMinXEdge, NSMaxYEdge, 
			   NSMaxXEdge, NSMinYEdge};
  NSRectEdge dn_sides[] = {NSMaxXEdge, NSMaxYEdge, 
			   NSMinXEdge, NSMinYEdge, 
			   NSMaxXEdge, NSMaxYEdge};
  // These names are role names not the actual colours
  NSColor *black = [NSColor controlDarkShadowColor];
  NSColor *dark = [NSColor controlShadowColor];
  NSColor *white = [NSColor controlLightHighlightColor];
  NSColor *colors[] = {black, black, white, white, dark, dark};

  if ([[NSView focusView] isFlipped] == YES)
    {
      return NSDrawColorTiledRects(border, clip, dn_sides, colors, 6);
    }
  else
    {
      return NSDrawColorTiledRects(border, clip, up_sides, colors, 6);
    }
}

- (NSRect) drawDarkBezel: (NSRect)border withClip: (NSRect)clip
{
  NSRectEdge up_sides[] = {NSMaxXEdge, NSMinYEdge, NSMinXEdge, NSMaxYEdge,
			   NSMinXEdge, NSMaxYEdge, NSMaxXEdge, NSMinYEdge};
  NSRectEdge dn_sides[] = {NSMaxXEdge, NSMaxYEdge, NSMinXEdge, NSMinYEdge,
			   NSMinXEdge, NSMinYEdge, NSMaxXEdge, NSMaxYEdge};
  // These names are role names not the actual colours
  NSColor *black = [NSColor controlDarkShadowColor];
  NSColor *dark = [NSColor controlShadowColor];
  NSColor *light = [NSColor controlColor];
  NSColor *white = [NSColor controlLightHighlightColor];
  NSColor *colors[] = {white, white, dark, dark, black, black, light, light};
  NSRect rect;

  if ([[NSView focusView] isFlipped] == YES)
    {
      rect = NSDrawColorTiledRects(border, clip, dn_sides, colors, 8);
  
      [dark set];
      PSrectfill(NSMinX(border) + 1., NSMinY(border) - 2., 1., 1.);
      PSrectfill(NSMaxX(border) - 2., NSMaxY(border) + 1., 1., 1.);
    }
  else
    {
      rect = NSDrawColorTiledRects(border, clip, up_sides, colors, 8);
  
      [dark set];
      PSrectfill(NSMinX(border) + 1., NSMinY(border) + 1., 1., 1.);
      PSrectfill(NSMaxX(border) - 2., NSMaxY(border) - 2., 1., 1.);
    }
  return rect;
}

- (NSRect) drawDarkButton: (NSRect)border withClip: (NSRect)clip
{
  NSRectEdge up_sides[] = {NSMaxXEdge, NSMinYEdge, 
			   NSMinXEdge, NSMaxYEdge}; 
  NSRectEdge dn_sides[] = {NSMaxXEdge, NSMaxYEdge, 
			   NSMinXEdge, NSMinYEdge}; 
  // These names are role names not the actual colours
  NSColor *black = [NSColor controlDarkShadowColor];
  NSColor *white = [NSColor controlHighlightColor];
  NSColor *colors[] = {black, black, white, white};

  if ([[NSView focusView] isFlipped] == YES)
    {
      return NSDrawColorTiledRects(border, clip, dn_sides, colors, 4);
    }
  else
    {
      return NSDrawColorTiledRects(border, clip, up_sides, colors, 4);
    }
}

- (NSRect) drawFramePhoto: (NSRect)border withClip: (NSRect)clip
{
  NSRectEdge up_sides[] = {NSMaxXEdge, NSMinYEdge, 
			   NSMinXEdge, NSMaxYEdge, 
			   NSMaxXEdge, NSMinYEdge};
  NSRectEdge dn_sides[] = {NSMaxXEdge, NSMaxYEdge, 
			   NSMinXEdge, NSMinYEdge, 
			   NSMaxXEdge, NSMaxYEdge};
  // These names are role names not the actual colours
  NSColor *black = [NSColor controlDarkShadowColor];
  NSColor *dark = [NSColor controlShadowColor];
  NSColor *colors[] = {dark, dark, dark, dark, 
		       black,black};

  if ([[NSView focusView] isFlipped] == YES)
    {
      return NSDrawColorTiledRects(border, clip, dn_sides, colors, 6);
    }
  else
    {
      return NSDrawColorTiledRects(border, clip, up_sides, colors, 6);
    }
}

- (NSRect) drawGradientBorder: (NSGradientType)gradientType 
		       inRect: (NSRect)border 
		     withClip: (NSRect)clip
{
  NSRectEdge up_sides[] = {NSMaxXEdge, NSMinYEdge, 
			   NSMinXEdge, NSMaxYEdge};
  NSRectEdge dn_sides[] = {NSMaxXEdge, NSMaxYEdge, 
			   NSMinXEdge, NSMinYEdge};
  NSColor *black = [NSColor controlDarkShadowColor];
  NSColor *dark = [NSColor controlShadowColor];
  NSColor *light = [NSColor controlColor];
  NSColor **colors;
  NSColor *concaveWeak[] = {dark, dark, light, light};
  NSColor *concaveStrong[] = {black, black, light, light};
  NSColor *convexWeak[] = {light, light, dark, dark};
  NSColor *convexStrong[] = {light, light, black, black};
  NSRect rect;
  
  switch (gradientType)
    {
      case NSGradientConcaveWeak:
	colors = concaveWeak;
	break;
      case NSGradientConcaveStrong:
	colors = concaveStrong;
	break;
      case NSGradientConvexWeak:
	colors = convexWeak;
	break;
      case NSGradientConvexStrong:
	colors = convexStrong;
	break;
      case NSGradientNone:
      default:
	return border;
    }

  if ([[NSView focusView] isFlipped] == YES)
    {
      rect = NSDrawColorTiledRects(border, clip, dn_sides, colors, 4);
    }
  else
    {
      rect = NSDrawColorTiledRects(border, clip, up_sides, colors, 4);
    }
 
  return rect;
}

- (NSRect) drawGrayBezel: (NSRect)border withClip: (NSRect)clip
{
  NSRectEdge up_sides[] = {NSMaxXEdge, NSMinYEdge, NSMinXEdge, NSMaxYEdge,
			   NSMaxXEdge, NSMinYEdge, NSMinXEdge, NSMaxYEdge};
  NSRectEdge dn_sides[] = {NSMaxXEdge, NSMaxYEdge, NSMinXEdge, NSMinYEdge,
			     NSMaxXEdge, NSMaxYEdge, NSMinXEdge, NSMinYEdge};
  // These names are role names not the actual colours
  NSColor *black = [NSColor controlDarkShadowColor];
  NSColor *dark = [NSColor controlShadowColor];
  NSColor *light = [NSColor controlColor];
  NSColor *white = [NSColor controlLightHighlightColor];
  NSColor *colors[] = {white, white, dark, dark,
		       light, light, black, black};
  NSRect rect;

  if ([[NSView focusView] isFlipped] == YES)
    {
      rect = NSDrawColorTiledRects(border, clip, dn_sides, colors, 8);
      [dark set];
      PSrectfill(NSMinX(border) + 1., NSMaxY(border) - 2., 1., 1.);
      PSrectfill(NSMaxX(border) - 2., NSMinY(border) + 1., 1., 1.);
    }
  else
    {
      rect = NSDrawColorTiledRects(border, clip, up_sides, colors, 8);
      [dark set];
      PSrectfill(NSMinX(border) + 1., NSMinY(border) + 1., 1., 1.);
      PSrectfill(NSMaxX(border) - 2., NSMaxY(border) - 2., 1., 1.);
    }
  return rect;
}

- (NSRect) drawGroove: (NSRect)border withClip: (NSRect)clip
{
  // go clockwise from the top twice -- makes the groove come out right
  NSRectEdge up_sides[] = {NSMaxYEdge, NSMaxXEdge, NSMinYEdge, NSMinXEdge,
			   NSMaxYEdge, NSMaxXEdge, NSMinYEdge, NSMinXEdge};
  NSRectEdge dn_sides[] = {NSMinYEdge, NSMaxXEdge, NSMaxYEdge, NSMinXEdge,
			   NSMinYEdge, NSMaxXEdge, NSMaxYEdge, NSMinXEdge};
  // These names are role names not the actual colours
  NSColor *dark = [NSColor controlShadowColor];
  NSColor *white = [NSColor controlLightHighlightColor];
  NSColor *colors[] = {dark, white, white, dark,
		       white, dark, dark, white};

  if ([[NSView focusView] isFlipped] == YES)
    {
      return NSDrawColorTiledRects(border, clip, dn_sides, colors, 8);
    }
  else
    {
      return NSDrawColorTiledRects(border, clip, up_sides, colors, 8);
    }
}

- (NSRect) drawLightBezel: (NSRect)border withClip: (NSRect)clip
{
  NSRectEdge up_sides[] = {NSMaxXEdge, NSMinYEdge, NSMinXEdge, NSMaxYEdge, 
  			   NSMaxXEdge, NSMinYEdge, NSMinXEdge, NSMaxYEdge};
  NSRectEdge dn_sides[] = {NSMaxXEdge, NSMaxYEdge, NSMinXEdge, NSMinYEdge, 
			   NSMaxXEdge, NSMaxYEdge, NSMinXEdge, NSMinYEdge};
  // These names are role names not the actual colours
  NSColor *dark = [NSColor controlShadowColor];
  NSColor *light = [NSColor controlColor];
  NSColor *white = [NSColor controlLightHighlightColor];
  NSColor *colors[] = {white, white, dark, dark,
		       light, light, dark, dark};

  if ([[NSView focusView] isFlipped] == YES)
    {
      return NSDrawColorTiledRects(border, clip, dn_sides, colors, 8);
    }
  else
    {
      return NSDrawColorTiledRects(border, clip, up_sides, colors, 8);
    }
}

- (NSRect) drawWhiteBezel: (NSRect)border withClip: (NSRect)clip
{
  NSRectEdge up_sides[] = {NSMaxYEdge, NSMaxXEdge, NSMinYEdge, NSMinXEdge,
  			   NSMaxYEdge, NSMaxXEdge, NSMinYEdge, NSMinXEdge};
  NSRectEdge dn_sides[] = {NSMinYEdge, NSMaxXEdge, NSMaxYEdge, NSMinXEdge, 
  			     NSMinYEdge, NSMaxXEdge, NSMaxYEdge, NSMinXEdge};
  // These names are role names not the actual colours
  NSColor *dark = [NSColor controlShadowColor];
  NSColor *light = [NSColor controlColor];
  NSColor *white = [NSColor controlLightHighlightColor];
  NSColor *colors[] = {dark, white, white, dark,
		       dark, light, light, dark};

  if ([[NSView focusView] isFlipped] == YES)
    {
      return NSDrawColorTiledRects(border, clip, dn_sides, colors, 8);
    }
  else
    {
      return NSDrawColorTiledRects(border, clip, up_sides, colors, 8);
    }
}

@end



@implementation	GSTheme (LowLevelDrawing)

- (void) fillHorizontalRect: (NSRect)rect
		  withImage: (NSImage*)image
		   fromRect: (NSRect)source
		    flipped: (BOOL)flipped
{
  NSGraphicsContext	*ctxt = GSCurrentContext();
  NSBezierPath		*path;
  unsigned		repetitions;
  unsigned		count;
  float			y;

  DPSgsave (ctxt);
  path = [NSBezierPath bezierPathWithRect: rect];
  [path addClip];
  repetitions = (rect.size.width / source.size.width) + 1;
  y = rect.origin.y;

  if (flipped) y = rect.origin.y + rect.size.height;
  
  for (count = 0; count < repetitions; count++)
    {
      NSPoint p = NSMakePoint (rect.origin.x + count * source.size.width, y);

      [image compositeToPoint: p
		     fromRect: source
		    operation: NSCompositeSourceOver];
    }
  DPSgrestore (ctxt);	
}

- (void) fillRect: (NSRect)rect
withRepeatedImage: (NSImage*)image
	 fromRect: (NSRect)source
	   center: (BOOL)center
{
  NSGraphicsContext	*ctxt = GSCurrentContext ();
  NSBezierPath		*path;
  NSSize		size;
  unsigned		xrepetitions;
  unsigned		yrepetitions;
  unsigned		x;
  unsigned		y;

  DPSgsave (ctxt);
  path = [NSBezierPath bezierPathWithRect: rect];
  [path addClip];
  size = [image size];
  xrepetitions = (rect.size.width / size.width) + 1;
  yrepetitions = (rect.size.height / size.height) + 1;

  for (x = 0; x < xrepetitions; x++)
    {
      for (y = 0; y < yrepetitions; y++)
	{
	  NSPoint p;

	  p = NSMakePoint (rect.origin.x + x * size.width,
	    rect.origin.y + y * size.height);
	  [image compositeToPoint: p
			 fromRect: source
			operation: NSCompositeSourceOver];
      }
  }
  DPSgrestore (ctxt);	
}

- (void) fillRect: (NSRect)rect
	withTiles: (GSDrawTiles*)tiles
       background: (NSColor*)color
	fillStyle: (GSThemeFillStyle)style
{
  NSGraphicsContext	*ctxt = GSCurrentContext();
  NSSize		tls = tiles->rects[TileTL].size;
  NSSize		tms = tiles->rects[TileTM].size;
  NSSize		trs = tiles->rects[TileTR].size;
  NSSize		cls = tiles->rects[TileCL].size;
  NSSize		crs = tiles->rects[TileCR].size;
  NSSize		bls = tiles->rects[TileBL].size;
  NSSize		bms = tiles->rects[TileBM].size;
  NSSize		brs = tiles->rects[TileBR].size;
  NSRect		inFill;
  BOOL			flipped = [[ctxt focusView] isFlipped];

  if (color == nil)
    {
      [[NSColor redColor] set];
    }
  else
    {
      [color set];
    }
  NSRectFill(rect);

  if (flipped)
    {
      [self fillHorizontalRect:
	NSMakeRect (rect.origin.x + bls.width,
	  rect.origin.y + rect.size.height - bms.height,
	  rect.size.width - bls.width - brs.width,
	  bms.height)
	withImage: tiles->images[TileBM]
	fromRect: tiles->rects[TileBM]
	flipped: YES];
      [self fillHorizontalRect:
	NSMakeRect (rect.origin.x + tls.width,
	  rect.origin.y,
	  rect.size.width - tls.width - trs.width,
	  tms.height)
	withImage: tiles->images[TileTM]
	fromRect: tiles->rects[TileTM]
	flipped: YES];
      [self fillVerticalRect:
	NSMakeRect (rect.origin.x,
	  rect.origin.y + bls.height,
	  cls.width,
	  rect.size.height - bls.height - tls.height)
	withImage: tiles->images[TileCL]
	fromRect: tiles->rects[TileCL]
	flipped: NO];
      [self fillVerticalRect:
	NSMakeRect (rect.origin.x + rect.size.width - crs.width,
	  rect.origin.y + brs.height,
	  crs.width,
	  rect.size.height - brs.height - trs.height)
	withImage: tiles->images[TileCR]
	fromRect: tiles->rects[TileCR]
	flipped: NO];

      [tiles->images[TileTL] compositeToPoint:
	NSMakePoint (rect.origin.x,
	  rect.origin.y)
	fromRect: tiles->rects[TileTL]
	operation: NSCompositeSourceOver];
      [tiles->images[TileTR] compositeToPoint:
	NSMakePoint (rect.origin.x + rect.size.width - tls.width,
	rect.origin.y)
	fromRect: tiles->rects[TileTR]
	operation: NSCompositeSourceOver];
      [tiles->images[TileBL] compositeToPoint:
	NSMakePoint (rect.origin.x,
	  rect.origin.y + rect.size.height - tls.height)
	fromRect: tiles->rects[TileBL]
	operation: NSCompositeSourceOver];
      [tiles->images[TileBR] compositeToPoint:
	NSMakePoint (rect.origin.x + rect.size.width - brs.width,
	  rect.origin.y + rect.size.height - tls.height)
	fromRect: tiles->rects[TileBR]
	operation: NSCompositeSourceOver];

      inFill = NSMakeRect (rect.origin.x +cls.width,
        rect.origin.y + bms.height,
	rect.size.width - cls.width - crs.width,
	rect.size.height - bms.height - tms.height);
      if (style == FillStyleCenter)
	{
	  [self fillRect: inFill
	    withRepeatedImage: tiles->images[TileCM]
	    fromRect: tiles->rects[TileCM]
	    center: NO];
	}
      else if (style == FillStyleRepeat)
	{
	  [self fillRect: inFill
	    withRepeatedImage: tiles->images[TileCM]
	    fromRect: tiles->rects[TileCM]
	    center: NO];
	}
      else if (style == FillStyleScale)
        {
	  [tiles->images[TileCM] setScalesWhenResized: YES];
	  [tiles->images[TileCM] setSize: inFill.size];
	  [tiles->images[TileCM] compositeToPoint: inFill.origin
					 fromRect: tiles->rects[TileCM]
					operation: NSCompositeSourceOver];
	}
    }
  else
    {
      [self fillHorizontalRect:
	NSMakeRect(
	  rect.origin.x + tls.width,
	  rect.origin.y + rect.size.height - tms.height,
	  rect.size.width - bls.width - brs.width,
	  tms.height)
	withImage: tiles->images[TileTM]
	fromRect: tiles->rects[TileTM]
	flipped: NO];
      [self fillHorizontalRect:
	NSMakeRect(
	  rect.origin.x + bls.width,
	  rect.origin.y,
	  rect.size.width - bls.width - brs.width,
	  bms.height)
	withImage: tiles->images[TileBM]
	fromRect: tiles->rects[TileBM]
	flipped: NO];
      [self fillVerticalRect:
	NSMakeRect(
	  rect.origin.x,
	  rect.origin.y + bls.height,
	  cls.width,
	  rect.size.height - tls.height - bls.height)
	withImage: tiles->images[TileCL]
	fromRect: tiles->rects[TileCL]
	flipped: NO];
      [self fillVerticalRect:
	NSMakeRect(
	  rect.origin.x + rect.size.width - crs.width,
	  rect.origin.y + brs.height,
	  crs.width,
	  rect.size.height - trs.height - brs.height)
	withImage: tiles->images[TileCR]
	fromRect: tiles->rects[TileCR]
	flipped: NO];

      [tiles->images[TileTL] compositeToPoint:
	NSMakePoint (
	  rect.origin.x,
	  rect.origin.y + rect.size.height - tls.height)
	fromRect: tiles->rects[TileTL]
	operation: NSCompositeSourceOver];
      [tiles->images[TileTR] compositeToPoint:
	NSMakePoint(
	  rect.origin.x + rect.size.width - trs.width,
	  rect.origin.y + rect.size.height - trs.height)
	fromRect: tiles->rects[TileTR]
	operation: NSCompositeSourceOver];
      [tiles->images[TileBL] compositeToPoint:
	NSMakePoint(
	  rect.origin.x,
	  rect.origin.y)
	fromRect: tiles->rects[TileBL]
	operation: NSCompositeSourceOver];
      [tiles->images[TileBR] compositeToPoint:
	NSMakePoint(
	  rect.origin.x + rect.size.width - brs.width,
	  rect.origin.y)
	fromRect: tiles->rects[TileBR]
	operation: NSCompositeSourceOver];

      inFill = NSMakeRect (rect.origin.x +cls.width,
        rect.origin.y + bms.height,
	rect.size.width - cls.width - crs.width,
	rect.size.height - bms.height - tms.height);

      if (style == FillStyleCenter)
	{
	  [self fillRect: inFill
	    withRepeatedImage: tiles->images[TileCM]
	    fromRect: tiles->rects[TileCM]
	    center: NO];
	}
      else if (style == FillStyleRepeat)
	{
	  [self fillRect: inFill
	    withRepeatedImage: tiles->images[TileCM]
	    fromRect: tiles->rects[TileCM]
	    center: YES];
	}
      else if (style == FillStyleScale)
	{
	  [tiles->images[TileCM] setScalesWhenResized: YES];
	  [tiles->images[TileCM] setSize: inFill.size];
	  [tiles->images[TileCM] compositeToPoint: inFill.origin
					 fromRect: tiles->rects[TileCM]
					operation: NSCompositeSourceOver];
	}
    }
}

- (void) fillVerticalRect: (NSRect)rect
		withImage: (NSImage*)image
		 fromRect: (NSRect)source
		  flipped: (BOOL)flipped
{
  NSGraphicsContext	*ctxt = GSCurrentContext();
  NSBezierPath		*path;
  unsigned		repetitions;
  unsigned		count;
  NSPoint		p;

  DPSgsave (ctxt);
  path = [NSBezierPath bezierPathWithRect: rect];
  [path addClip];
  repetitions = (rect.size.height / source.size.height) + 1;

  if (flipped)
    {
      for (count = 0; count < repetitions; count++)
	{
	  p = NSMakePoint (rect.origin.x,
	    rect.origin.y + rect.size.height - count * source.size.height);
	  [image compositeToPoint: p
			 fromRect: source
			operation: NSCompositeSourceOver];
	}
    }
  else
    {
      for (count = 0; count < repetitions; count++)
	{
	  p = NSMakePoint (rect.origin.x,
	    rect.origin.y + count * source.size.height);
	  [image compositeToPoint: p
			 fromRect: source
			operation: NSCompositeSourceOver];
	}
    }
  DPSgrestore (ctxt);	
}

@end



@implementation	GSDrawTiles
- (void) dealloc
{
  unsigned	i;

  for (i = 0; i < 9; i++)
    {
      RELEASE(images[i]);
    }
  [super dealloc];
}

/**
 * Simple initialiser, assume the single image is split into nine equal tiles.
 * If the image size is not divisible by three, the corners are made equal
 * in size and the central parts slightly smaller.
 */
- (id) initWithImage: (NSImage*)image
{
  NSSize	s = [image size];

  return [self initWithImage: image
		  horizontal: s.width / 3.0
		    vertical: s.height / 3.0];
}

- (id) initWithImage: (NSImage*)image horizontal: (float)x vertical: (float)y
{
  unsigned	i;
  NSSize	s = [image size];

  x = floor(x);
  y = floor(y);

  rects[TileTL] = NSMakeRect(0.0, s.height - y, x, y);
  rects[TileTM] = NSMakeRect(x, s.height - y, s.width - 2.0 * x, y);
  rects[TileTR] = NSMakeRect(s.width - x, s.height - y, x, y);
  rects[TileCL] = NSMakeRect(0.0, y, x, s.height - 2.0 * y);
  rects[TileCM] = NSMakeRect(x, y, s.width - 2.0 * x, s.height - 2.0 * y);
  rects[TileCR] = NSMakeRect(s.width - x, y, x, s.height - 2.0 * y);
  rects[TileBL] = NSMakeRect(0.0, 0.0, x, y);
  rects[TileBM] = NSMakeRect(x, 0.0, s.width - 2.0 * x, y);
  rects[TileBR] = NSMakeRect(s.width - x, 0.0, x, y);

  for (i = 0; i < 9; i++)
    {
      if (rects[i].origin.x < 0.0 || rects[i].origin.y < 0.0
	|| rects[i].size.width <= 0.0 || rects[i].size.height <= 0.0)
        {
	  images[i] = nil;
	  rects[i] = NSZeroRect;
	}
      else
        {
	  images[i] = RETAIN(image);
	}
    }  

  return self;
}
@end



@implementation	GSThemePanel

static GSThemePanel	*sharedPanel = nil;

+ (GSThemePanel*) sharedThemePanel
{
  if (sharedPanel == nil)
    {
      sharedPanel = [self new];
    }
  return sharedPanel;
}

- (id) init
{
  NSRect	winFrame;
  NSRect	frame;
  NSScrollView	*scrollView;
  NSView	*container;
  NSView	*inspector;
  NSButtonCell	*proto;

  /* FIXME - should actually autosave the memory panel position and frame ! */
  winFrame.size = NSMakeSize(300,300);
  winFrame.origin = NSMakePoint (100, 200);
  
  self = [super initWithContentRect: winFrame
    styleMask: (NSTitledWindowMask | NSClosableWindowMask
      | NSMiniaturizableWindowMask | NSResizableWindowMask)
    backing: NSBackingStoreBuffered
    defer: NO];
  
  [self setReleasedWhenClosed: NO];
  container = [self contentView];
  frame = [container frame];
  frame.origin = NSZeroPoint;
  frame.size.width = 95;
  scrollView = [[NSScrollView alloc] initWithFrame: frame];
  [scrollView setHasHorizontalScroller: NO];
  [scrollView setHasVerticalScroller: YES];
  [scrollView setBorderType: NSBezelBorder];
  [scrollView setAutoresizingMask: (NSViewHeightSizable)];
  [container addSubview: scrollView];
  RELEASE(scrollView);
  frame = [scrollView frame];
  frame.origin = NSZeroPoint;

  proto = [[NSButtonCell alloc] init];
  [proto setBordered: NO];
  [proto setAlignment: NSCenterTextAlignment];
  [proto setImagePosition: NSImageAbove];
  [proto setSelectable: NO];
  [proto setEditable: NO];
  [matrix setPrototype: proto];

  matrix = [[NSMatrix alloc] initWithFrame: frame
				      mode: NSRadioModeMatrix
				 prototype: proto
			      numberOfRows: 1
			   numberOfColumns: 1];
  RELEASE(proto);
  [matrix setAutosizesCells: NO];
  [matrix setCellSize: NSMakeSize(72,72)];
  [matrix setIntercellSpacing: NSMakeSize(8,8)];
  [matrix setAutoresizingMask: NSViewHeightSizable];
  [matrix setMode: NSRadioModeMatrix];
  [matrix setAction: @selector(changeSelection:)];
  [matrix setTarget: self];

  [scrollView setDocumentView: matrix];
  RELEASE(matrix);

  [self update: self];

  [self setTitle: @"Theme Panel"];
  
  return self;
}

- (void) changeSelection: (id)sender
{
  NSButtonCell	*cell = [sender selectedCell];
  NSString	*name = [cell title];

  [GSTheme setTheme: [GSTheme loadThemeNamed: name]];
}

- (void) update: (id)sender
{
  NSArray		*array;
  NSMutableSet		*set = [NSMutableSet set];
  NSString		*selected = RETAIN([[matrix selectedCell] title]);
  unsigned		existing = [[matrix cells] count];
  NSFileManager		*mgr = [NSFileManager defaultManager];
  NSEnumerator		*enumerator;
  NSString		*path;
  NSButtonCell		*cell;
  unsigned		count = 0;

  /* Ensure the first cell contains the default theme.
   */
  [set addObject: [defaultTheme name]];
  cell = [matrix cellAtRow: count++ column: 0];
  [cell setImage: [defaultTheme icon]];
  [cell setTitle: [defaultTheme name]];

  /* Go through all the themes in the standard locations,
   * load them, and add them to the matrix.
   */
  enumerator = [NSSearchPathForDirectoriesInDomains
    (NSAllLibrariesDirectory, NSAllDomainsMask, YES) objectEnumerator];
  while ((path = [enumerator nextObject]) != nil)
    {
      NSEnumerator	*files;
      NSString		*file;

      path = [path stringByAppendingPathComponent: @"Themes"];
      files = [[mgr directoryContentsAtPath: path] objectEnumerator];
      while ((file = [files nextObject]) != nil)
        {
	  NSString	*ext = [file pathExtension];
	  NSString	*name = [file stringByDeletingPathExtension];

	  if ([ext isEqualToString: @"theme"] == YES
	    && [set member: name] == nil)
	    {
	      GSTheme	*loaded;
	      NSString	*fullName;

	      fullName = [path stringByAppendingPathComponent: file];
	      loaded = [GSTheme loadThemeNamed: fullName];
	      if (loaded != nil)
	        {
		  if (count >= existing)
		    {
		      [matrix addRow];
		      existing++;
		    }
		  cell = [matrix cellAtRow: count column: 0];
		  [cell setImage: [loaded icon]];
		  [cell setTitle: [loaded name]];
		  count++;
		}
	    }
	}
    }

  /* Empty any unused cells.
   */
  while (count < existing)
    {
      cell = [matrix cellAtRow: count column: 0];
      [cell setImage: nil];
      [cell setTitle: @""];
      count++;
    }

  /* Restore the selected cell.
   */
  array = [matrix cells];
  count = [array count];
  while (count-- > 0)
    {
      cell = [matrix cellAtRow: count column: 0];
      if ([[cell title] isEqual: selected])
        {
	  [matrix selectCellAtRow: count column: 0];
	  break;
	}
    }
  RELEASE(selected);
  [matrix sizeToCells];
  [matrix setNeedsDisplay: YES];
}

@end
