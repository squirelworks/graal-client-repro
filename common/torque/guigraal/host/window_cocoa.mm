// Window on macOS (Cocoa): one 32-bit image drawn into a flipped NSView
// each frame. Built with -fobjc-arc.

#include "window.hpp"

#import <Cocoa/Cocoa.h>

#include <chrono>
#include <cstdlib>
#include <set>

namespace Torque {
class CocoaWindow;
}

// The events the view and the window delegate see, handed to the C++ side.
@interface GraalTorqueView : NSView
@property(nonatomic, assign) Torque::CocoaWindow* owner;
@property(nonatomic) CGImageRef image;
@end

@interface GraalTorqueDelegate : NSObject <NSWindowDelegate>
@property(nonatomic, assign) Torque::CocoaWindow* owner;
@end

namespace Torque {
namespace {

// Torque key names by the Mac's virtual key code (layout independent) for
// the named keys, else by the key's unmodified character.
std::string key_name(unsigned short code, NSString* chars) {
  switch (code) {
    case 0x7E: return "up";
    case 0x7D: return "down";
    case 0x7B: return "left";
    case 0x7C: return "right";
    case 0x35: return "escape";
    case 0x24: return "return";
    case 0x4C: return "numpadenter";
    case 0x33: return "backspace";
    case 0x75: return "delete";
    case 0x73: return "home";
    case 0x77: return "end";
    case 0x30: return "tab";
    case 0x31: return "space";
    case 0x74: return "pageup";
    case 0x79: return "pagedown";
    case 0x72: return "insert";  // the Help key, where Mac keyboards have Insert
    case 0x38: return "lshift";
    case 0x3C: return "rshift";
    case 0x3B: return "lcontrol";
    case 0x3E: return "rcontrol";
    case 0x3A: return "lalt";
    case 0x3D: return "ralt";
    case 0x7A: return "f1";
    case 0x78: return "f2";
    case 0x63: return "f3";
    case 0x76: return "f4";
    case 0x60: return "f5";
    case 0x61: return "f6";
    case 0x62: return "f7";
    case 0x64: return "f8";
    case 0x65: return "f9";
    case 0x6D: return "f10";
    case 0x67: return "f11";
    case 0x6F: return "f12";
    default: break;
  }
  if (chars.length != 1) return std::string();
  const unichar c = [chars characterAtIndex:0];
  if (c >= 'a' && c <= 'z') return std::string(1, char(c));
  if (c >= 'A' && c <= 'Z') return std::string(1, char(c - 'A' + 'a'));
  if (c >= '0' && c <= '9') return std::string(1, char(c));
  return c < 128 ? punctuation_key_name(char(c)) : std::string();
}

unsigned modifiers(NSEventModifierFlags flags) {
  unsigned m = 0;
  if (flags & NSEventModifierFlagShift) m |= InputEvent::shift;
  if (flags & NSEventModifierFlagControl) m |= InputEvent::ctrl;
  if (flags & NSEventModifierFlagOption) m |= InputEvent::alt;
  return m;
}

// The device-dependent bit of each modifier key in NSEvent.modifierFlags,
// to tell a press from a release in flagsChanged.
NSEventModifierFlags modifier_bit(unsigned short code) {
  switch (code) {
    case 0x38: return 0x02;  // left shift
    case 0x3C: return 0x04;  // right shift
    case 0x3B: return 0x01;  // left control
    case 0x3E: return 0x2000;  // right control
    case 0x3A: return 0x20;  // left option
    case 0x3D: return 0x40;  // right option
    default: return 0;
  }
}

} // namespace

class CocoaWindow : public Window {
 public:
  ~CocoaWindow() override {
    if (view_.image) CGImageRelease(view_.image);
    view_.image = nullptr;
    [window_ setDelegate:nil];
    [window_ close];
  }

  bool init(const std::string& title, int w, int h, std::string& error) {
    @autoreleasepool {
      [NSApplication sharedApplication];
      [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
      [NSApp finishLaunching];
      const NSRect frame = NSMakeRect(0, 0, w, h);
      // Fixed size, as the X11 window's min = max size hints.
      window_ = [[NSWindow alloc]
          initWithContentRect:frame
                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                      backing:NSBackingStoreBuffered
                        defer:NO];
      if (!window_) {
        error = "cannot create the window";
        return false;
      }
      window_.releasedWhenClosed = NO;
      window_.title = [NSString stringWithUTF8String:title.c_str()];
      view_ = [[GraalTorqueView alloc] initWithFrame:frame];
      view_.owner = this;
      delegate_ = [[GraalTorqueDelegate alloc] init];
      delegate_.owner = this;
      window_.delegate = delegate_;
      window_.contentView = view_;
      [window_ makeFirstResponder:view_];
      [window_ center];
      [window_ makeKeyAndOrderFront:nil];
      [NSApp activateIgnoringOtherApps:YES];
    }
    width_ = w;
    height_ = h;
    pixels_.assign(std::size_t(w) * h, 0);
    return true;
  }

  std::vector<WindowEvent> pump() override {
    @autoreleasepool {
      for (;;) {
        NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                         untilDate:[NSDate distantPast]
                                            inMode:NSDefaultRunLoopMode
                                           dequeue:YES];
        if (!ev) break;
        [NSApp sendEvent:ev];
      }
      [NSApp updateWindows];
    }
    std::vector<WindowEvent> out;
    out.swap(events_);
    return out;
  }

  void present(const Gui::Image& img) override {
    const int w = std::min(width_, img.width), h = std::min(height_, img.height);
    for (int y = 0; y < h; ++y)
      for (int x = 0; x < w; ++x) {
        const Gui::Color& c = img.at(x, y);
        pixels_[std::size_t(y) * width_ + x] =
            0xFF000000u | (std::uint32_t(c.r) << 16) | (std::uint32_t(c.g) << 8) | c.b;
      }
    @autoreleasepool {
      CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
      CGDataProviderRef data = CGDataProviderCreateWithData(nullptr, pixels_.data(), pixels_.size() * 4, nullptr);
      // Copy now: the provider reads pixels_, which the next frame overwrites.
      CGImageRef shared = CGImageCreate(std::size_t(width_), std::size_t(height_), 8, 32, std::size_t(width_) * 4, space,
                                        kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little, data, nullptr, false,
                                        kCGRenderingIntentDefault);
      CGImageRef copy = shared ? CGImageCreateCopy(shared) : nullptr;
      if (shared) CGImageRelease(shared);
      CGDataProviderRelease(data);
      CGColorSpaceRelease(space);
      if (view_.image) CGImageRelease(view_.image);
      view_.image = copy;
      [view_ setNeedsDisplay:YES];
      [view_ displayIfNeeded];
    }
  }

  void push_close() {
    WindowEvent we;
    we.kind = WindowEvent::Kind::close;
    events_.push_back(we);
  }

  void key(NSEvent* ev, bool make) {
    const std::string name = key_name(ev.keyCode, ev.charactersIgnoringModifiers);
    if (name.empty()) return;
    WindowEvent we;
    we.key.key = name;
    we.key.modifiers = modifiers(ev.modifierFlags);
    we.key.make = make;
    we.key.repeat = make && (ev.isARepeat || held_.count(name) != 0);
    if (make) held_.insert(name); else held_.erase(name);
    if (make && !(ev.modifierFlags & NSEventModifierFlagCommand)) {
      NSString* chars = ev.characters;
      if (chars.length == 1) {
        const unichar c = [chars characterAtIndex:0];
        if (c >= 32 && c < 127) we.key.ascii = char(c);
      }
    }
    events_.push_back(we);
  }

  void flags(NSEvent* ev) {
    const NSEventModifierFlags bit = modifier_bit(ev.keyCode);
    if (!bit) return;
    const std::string name = key_name(ev.keyCode, nil);
    const bool make = (ev.modifierFlags & bit) != 0;
    if (make == (held_.count(name) != 0)) return;
    WindowEvent we;
    we.key.key = name;
    we.key.modifiers = modifiers(ev.modifierFlags);
    we.key.make = make;
    if (make) held_.insert(name); else held_.erase(name);
    events_.push_back(we);
  }

  void click(int x, int y) {
    const auto now = std::chrono::steady_clock::now();
    WindowEvent we;
    we.kind = WindowEvent::Kind::click;
    we.x = x;
    we.y = y;
    we.double_click = now - last_click_ < std::chrono::milliseconds(400) && std::abs(we.x - last_x_) < 5 &&
                      std::abs(we.y - last_y_) < 5;
    last_click_ = now;
    last_x_ = we.x;
    last_y_ = we.y;
    events_.push_back(we);
  }

  // Keys held when the window loses focus never see their release.
  void release_all() {
    for (const std::string& k : held_) {
      WindowEvent we;
      we.key.key = k;
      we.key.make = false;
      events_.push_back(we);
    }
    held_.clear();
  }

 private:
  NSWindow* window_ = nil;
  GraalTorqueView* view_ = nil;
  GraalTorqueDelegate* delegate_ = nil;
  int width_ = 0, height_ = 0;
  std::vector<std::uint32_t> pixels_;
  std::vector<WindowEvent> events_;
  std::set<std::string> held_;
  std::chrono::steady_clock::time_point last_click_{};
  int last_x_ = -100, last_y_ = -100;
};

std::unique_ptr<Window> Window::open(const std::string& title, int width, int height, std::string& error) {
  auto w = std::make_unique<CocoaWindow>();
  if (!w->init(title, width, height, error)) return nullptr;
  return w;
}

} // namespace Torque

@implementation GraalTorqueView
- (BOOL)isFlipped {
  return YES;
}
- (BOOL)acceptsFirstResponder {
  return YES;
}
- (BOOL)acceptsFirstMouse:(NSEvent*)event {
  (void)event;
  return YES;
}
- (void)drawRect:(NSRect)dirty {
  (void)dirty;
  CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
  if (!self.image) {
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    CGContextFillRect(ctx, NSRectToCGRect(self.bounds));
    return;
  }
  // The view is flipped; CGContextDrawImage draws bottom-up, so flip back.
  const CGRect r = NSRectToCGRect(self.bounds);
  CGContextSaveGState(ctx);
  CGContextTranslateCTM(ctx, 0, r.size.height);
  CGContextScaleCTM(ctx, 1, -1);
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  CGContextDrawImage(ctx, r, self.image);
  CGContextRestoreGState(ctx);
}
- (void)keyDown:(NSEvent*)event {
  if (event.modifierFlags & NSEventModifierFlagCommand) {
    // No menu bar: Cmd+Q and Cmd+W close the window like its close button.
    NSString* c = event.charactersIgnoringModifiers.lowercaseString;
    if ([c isEqualToString:@"q"] || [c isEqualToString:@"w"]) self.owner->push_close();
    return;
  }
  self.owner->key(event, true);
}
- (void)keyUp:(NSEvent*)event {
  self.owner->key(event, false);
}
- (void)flagsChanged:(NSEvent*)event {
  self.owner->flags(event);
}
- (void)mouseDown:(NSEvent*)event {
  const NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  self.owner->click(int(p.x), int(p.y));
}
@end

@implementation GraalTorqueDelegate
- (BOOL)windowShouldClose:(NSWindow*)sender {
  (void)sender;
  self.owner->push_close();
  return NO;  // the program closes the window when it ends
}
- (void)windowDidResignKey:(NSNotification*)note {
  (void)note;
  self.owner->release_all();
}
@end
