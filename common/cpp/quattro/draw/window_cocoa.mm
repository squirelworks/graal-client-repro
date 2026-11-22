// The program's window on macOS: an NSWindow whose content view shows the
// software frame. The original Mac clients present through OpenGL in a
// Cocoa window (Graal_analysis client-internals/engine-600r2.md, the Mac
// builds); the rebuild draws the same software frame the Xlib and Win32
// windows show, with the same keys and GUI events.
//
// Built only on macOS (the Makefile adds this file and -framework Cocoa).
// Manual retain/release, so the C++ flags need no -fobjc-arc.
#include "window.hpp"

#ifdef __APPLE__
#import <Cocoa/Cocoa.h>

#include <map>
#include <set>
#include <vector>

namespace Quattro::Draw {
class CocoaWindow;
}

// The content view: draws the last frame, top-left origin like the other
// windows.
@interface QuattroView : NSView {
 @public
  std::vector<unsigned char>* rgba;
  int frameW;
  int frameH;
}
@end

@implementation QuattroView
- (BOOL)isFlipped {
  return YES;
}
- (BOOL)acceptsFirstResponder {
  return YES;
}
- (void)drawRect:(NSRect)dirty {
  (void)dirty;
  CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
  if (!ctx) return;
  if (!rgba || rgba->empty() || frameW <= 0 || frameH <= 0) {
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    CGContextFillRect(ctx, NSRectToCGRect([self bounds]));
    return;
  }
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGDataProviderRef dp = CGDataProviderCreateWithData(nullptr, rgba->data(), rgba->size(), nullptr);
  CGImageRef img = CGImageCreate(frameW, frameH, 8, 32, static_cast<size_t>(frameW) * 4, cs,
                                 static_cast<CGBitmapInfo>(kCGImageAlphaNoneSkipLast), dp, nullptr, false,
                                 kCGRenderingIntentDefault);
  CGContextSaveGState(ctx);
  // The view is flipped; CGImage draws bottom-up, so flip it back.
  CGContextTranslateCTM(ctx, 0, frameH);
  CGContextScaleCTM(ctx, 1, -1);
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  CGContextDrawImage(ctx, CGRectMake(0, 0, frameW, frameH), img);
  CGContextRestoreGState(ctx);
  CGImageRelease(img);
  CGDataProviderRelease(dp);
  CGColorSpaceRelease(cs);
}
@end

// Close and focus loss come through the delegate.
@interface QuattroWindowDelegate : NSObject <NSWindowDelegate> {
 @public
  Quattro::Draw::CocoaWindow* owner;
}
@end

namespace Quattro::Draw {
namespace {

// macOS virtual key codes (Carbon's kVK_* values).
enum : unsigned short {
  kA = 0, kS = 1, kD = 2, kQ = 12, kReturn = 36, kTab = 48, kSpace = 49, kDelete = 51, kEscape = 53,
  kF5 = 96, kF6 = 97, kF7 = 98, kF3 = 99, kF8 = 100, kF9 = 101, kF11 = 103, kF10 = 109, kF12 = 111,
  kHome = 115, kForwardDelete = 117, kF4 = 118, kEnd = 119, kF2 = 120, kF1 = 122,
  kLeft = 123, kRight = 124, kDown = 125, kUp = 126,
};

Key game_key(unsigned short code) {
  switch (code) {
    case kLeft: return Key::Left;
    case kRight: return Key::Right;
    case kUp: return Key::Up;
    case kDown: return Key::Down;
    case kEscape: return Key::Escape;
    case kTab: return Key::Tab;
    case kA: return Key::A;
    case kS: return Key::S;
    case kD: return Key::D;
    case kQ: return Key::Q;
    default: return Key::NoKey;
  }
}

std::string special_name(unsigned short code) {
  switch (code) {
    case kLeft: return "left";
    case kRight: return "right";
    case kUp: return "up";
    case kDown: return "down";
    case kEscape: return "escape";
    case kTab: return "tab";
    case kReturn: return "enter";
    case kDelete: return "backspace";
    case kForwardDelete: return "delete";
    case kHome: return "home";
    case kEnd: return "end";
    case kSpace: return "space";
    case kF1: return "f1";
    case kF2: return "f2";
    case kF3: return "f3";
    case kF4: return "f4";
    case kF5: return "f5";
    case kF6: return "f6";
    case kF7: return "f7";
    case kF8: return "f8";
    case kF9: return "f9";
    case kF10: return "f10";
    case kF11: return "f11";
    case kF12: return "f12";
    default: return {};
  }
}

}  // namespace

class CocoaWindow final : public Window {
 public:
  CocoaWindow(int w, int h, const std::string& title) : title_(title) {
    @autoreleasepool {
      [NSApplication sharedApplication];
      [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
      [NSApp finishLaunching];
      NSRect r = NSMakeRect(0, 0, w, h);
      // Close and minimise only: the window keeps its size, as on Windows.
      NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
      window_ = [[NSWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];
      if (!window_) return;
      [window_ setReleasedWhenClosed:NO];
      view_ = [[QuattroView alloc] initWithFrame:r];
      view_->rgba = &rgba_;
      view_->frameW = 0;
      view_->frameH = 0;
      [window_ setContentView:view_];
      delegate_ = [[QuattroWindowDelegate alloc] init];
      delegate_->owner = this;
      [window_ setDelegate:delegate_];
      [window_ setAcceptsMouseMovedEvents:NO];
      [window_ setTitle:[NSString stringWithUTF8String:title.c_str()]];
      [window_ center];
      [window_ makeKeyAndOrderFront:nil];
      [window_ makeFirstResponder:view_];
      [NSApp activateIgnoringOtherApps:YES];
    }
  }

  ~CocoaWindow() override {
    @autoreleasepool {
      if (window_) {
        [window_ setDelegate:nil];
        [window_ orderOut:nil];
        [window_ close];
        [window_ release];
      }
      if (delegate_) [delegate_ release];
      if (view_) [view_ release];
    }
  }

  bool valid() const { return window_ != nil; }

  void set_title(const std::string& s) override {
    title_ = s;
    @autoreleasepool {
      NSString* t = [NSString stringWithUTF8String:s.c_str()];
      [window_ setTitle:t ? t : @""];
    }
  }
  const std::string& title() const override { return title_; }
  bool held(Key k) const override { return down_.count(k) != 0; }

  Key poll_key() override {
    pump();
    if (keys_.empty()) return Key::NoKey;
    Key k = keys_.front();
    keys_.pop_front();
    return k;
  }

  bool poll_input(InputEvent& e) override {
    if (input_.empty()) return false;
    e = input_.front();
    input_.pop_front();
    return true;
  }

  void present(const Torque::Gui::Image& frame) override {
    rgba_.resize(frame.pixels.size() * 4);
    for (size_t i = 0; i < frame.pixels.size(); ++i) {
      const auto c = frame.pixels[i];
      rgba_[4 * i] = c.r;
      rgba_[4 * i + 1] = c.g;
      rgba_[4 * i + 2] = c.b;
      rgba_[4 * i + 3] = 255;
    }
    view_->frameW = frame.width;
    view_->frameH = frame.height;
    @autoreleasepool {
      [view_ setNeedsDisplay:YES];
      [view_ displayIfNeeded];
    }
  }

  // The colour at (x, y) of what the view shows, read back through AppKit;
  // false when it cannot be read. For the window test.
  bool shown_pixel(int x, int y, unsigned char rgb[3]) {
    @autoreleasepool {
      NSBitmapImageRep* rep = [view_ bitmapImageRepForCachingDisplayInRect:[view_ bounds]];
      if (!rep) return false;
      [view_ cacheDisplayInRect:[view_ bounds] toBitmapImageRep:rep];
      // The rep may be at backing scale; scale the point to it.
      double sx = static_cast<double>([rep pixelsWide]) / [view_ bounds].size.width;
      double sy = static_cast<double>([rep pixelsHigh]) / [view_ bounds].size.height;
      NSColor* c = [[rep colorAtX:static_cast<NSInteger>(x * sx) y:static_cast<NSInteger>(y * sy)]
          colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
      if (!c) return false;
      rgb[0] = static_cast<unsigned char>([c redComponent] * 255.0 + 0.5);
      rgb[1] = static_cast<unsigned char>([c greenComponent] * 255.0 + 0.5);
      rgb[2] = static_cast<unsigned char>([c blueComponent] * 255.0 + 0.5);
      return true;
    }
  }

  // The window's number, for posting test events.
  long number() const { return window_ ? static_cast<long>([window_ windowNumber]) : 0; }

  // Delegate callbacks.
  void closed() { keys_.push_back(Key::Close); }
  // The close button as the window test presses it: through the delegate.
  void closed_by_test() {
    @autoreleasepool {
      [window_ performClose:nil];
    }
  }
  void lost_focus() {
    for (const auto& key : gui_down_) {
      InputEvent e = key.second;
      e.type = InputEvent::KeyUp;
      input_.push_back(e);
    }
    gui_down_.clear();
    pressed_.clear();
    down_.clear();
  }

  // One event the pump took off the queue; true when it was ours.
  bool handle(NSEvent* ev) {
    NSEventType t = [ev type];
    if (t == NSEventTypeKeyDown || t == NSEventTypeKeyUp) {
      // Keep the platform's Cmd+Q and Cmd+W.
      if (([ev modifierFlags] & NSEventModifierFlagCommand) != 0) {
        if (t == NSEventTypeKeyDown) {
          NSString* c = [ev charactersIgnoringModifiers];
          if ([c isEqualToString:@"q"] || [c isEqualToString:@"w"]) {
            keys_.push_back(Key::Close);
            return true;
          }
        }
        // Command may be pressed after an ordinary tracked key. Its release
        // must still end that original press, without consuming new shortcuts.
        if (t == NSEventTypeKeyUp && gui_down_.count([ev keyCode])) {
          key(ev, false);
          return true;
        }
        return false;
      }
      key(ev, t == NSEventTypeKeyDown);
      return true;
    }
    if (t == NSEventTypeLeftMouseDown) {
      if ([ev window] != window_) return false;
      NSPoint p = [view_ convertPoint:[ev locationInWindow] fromView:nil];
      InputEvent e;
      e.type = InputEvent::MouseDown;
      e.x = static_cast<int>(p.x);
      e.y = static_cast<int>(p.y);
      e.clicks = [ev clickCount] >= 2 ? 2 : 1;
      input_.push_back(e);
      return false;  // AppKit still activates the window
    }
    return false;
  }

 private:
  void pump() {
    @autoreleasepool {
      for (;;) {
        NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                         untilDate:[NSDate distantPast]
                                            inMode:NSDefaultRunLoopMode
                                           dequeue:YES];
        if (!ev) break;
        if (!handle(ev)) [NSApp sendEvent:ev];
      }
      [NSApp updateWindows];
    }
  }

  void key(NSEvent* ev, bool press) {
    unsigned short code = [ev keyCode];
    Key k = game_key(code);
    if (press) {
      bool first = pressed_.insert(code).second;
      if (k != Key::NoKey && first) {
        down_.insert(k);
        keys_.push_back(k);
      }
    } else {
      pressed_.erase(code);
      down_.erase(k);
    }
    InputEvent e;
    e.type = press ? InputEvent::KeyDown : InputEvent::KeyUp;
    e.key = special_name(code);
    NSString* typed = [ev characters];
    if (typed.length == 1) {
      unichar ch = [typed characterAtIndex:0];
      // AppKit gives the arrows and F keys private-use characters.
      if (ch >= 32 && ch != 127 && (ch < 0xF700 || ch > 0xF8FF)) e.ch = ch;
    }
    if (e.key.empty()) {
      NSString* bare = [ev charactersIgnoringModifiers];
      if (bare.length == 1) {
        unichar b = [bare characterAtIndex:0];
        if (b >= 'A' && b <= 'Z') b = static_cast<unichar>(b - 'A' + 'a');
        if (b > 32 && b < 127) e.key = std::string(1, static_cast<char>(b));
      }
    }
    NSEventModifierFlags f = [ev modifierFlags];
    auto mod = [&](const char* s) {
      if (!e.mods.empty()) e.mods += ' ';
      e.mods += s;
    };
    if (f & NSEventModifierFlagShift) mod("shift");
    if (f & NSEventModifierFlagControl) mod("ctrl");
    if (f & NSEventModifierFlagOption) mod("alt");
    if (press && !e.key.empty()) {
      const auto saved = gui_down_.emplace(code, e);
      e.key = saved.first->second.key; // keep release identity while retaining current text/modifiers
    }
    if (!press) {
      auto it = gui_down_.find(code);
      if (it != gui_down_.end()) {
        e.key = it->second.key;
        e.ch = it->second.ch;
        gui_down_.erase(it);
      }
    }
    if (!e.key.empty()) input_.push_back(e);
  }

  NSWindow* window_ = nil;
  QuattroView* view_ = nil;
  QuattroWindowDelegate* delegate_ = nil;
  std::string title_;
  std::set<Key> down_;
  std::set<unsigned short> pressed_;
  std::map<unsigned short, InputEvent> gui_down_;
  std::deque<Key> keys_;
  std::deque<InputEvent> input_;
  std::vector<unsigned char> rgba_;
};

std::unique_ptr<Window> open_cocoa_window(int w, int h, const std::string& title) {
  auto win = std::make_unique<CocoaWindow>(w, h, title);
  if (!win->valid()) return nullptr;
  return win;
}

bool cocoa_shown_pixel(Window& w, int x, int y, unsigned char rgb[3]) {
  auto* c = dynamic_cast<CocoaWindow*>(&w);
  return c && c->shown_pixel(x, y, rgb);
}

long cocoa_window_number(Window& w) {
  auto* c = dynamic_cast<CocoaWindow*>(&w);
  return c ? c->number() : 0;
}

void cocoa_post_key(Window& w, unsigned short code, const std::string& chars, bool down, bool repeat) {
  auto* c = dynamic_cast<CocoaWindow*>(&w);
  if (!c) return;
  @autoreleasepool {
    NSString* s = [NSString stringWithUTF8String:chars.c_str()];
    NSEvent* ev = [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp
                                   location:NSZeroPoint
                              modifierFlags:0
                                  timestamp:0
                               windowNumber:c->number()
                                    context:nil
                                 characters:s
                charactersIgnoringModifiers:s
                                  isARepeat:repeat ? YES : NO
                                    keyCode:code];
    [NSApp postEvent:ev atStart:NO];
  }
}

void cocoa_post_close(Window& w) {
  auto* c = dynamic_cast<CocoaWindow*>(&w);
  if (c) c->closed_by_test();
}

void cocoa_post_resign(Window& w) {
  auto* c = dynamic_cast<CocoaWindow*>(&w);
  if (c) c->lost_focus();
}

}  // namespace Quattro::Draw

@implementation QuattroWindowDelegate
- (BOOL)windowShouldClose:(NSWindow*)sender {
  (void)sender;
  if (owner) owner->closed();
  return NO;  // the program decides, as with WM_CLOSE
}
- (void)windowDidResignKey:(NSNotification*)note {
  (void)note;
  if (owner) owner->lost_focus();
}
@end

#endif  // __APPLE__
