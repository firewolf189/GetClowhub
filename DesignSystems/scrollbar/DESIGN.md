# Scrollbar Design System

## 1. Visual Theme & Atmosphere

The GetClawHub scrollbar is a transient reading-position affordance rather than permanent chrome. It should stay quiet while content is still, appear immediately during wheel or trackpad movement, and fade out after the user stops scrolling. The design follows macOS expectations: the content remains the focus, the scrollbar does not reserve layout width, and the indicator sits as a slim overlay near the trailing edge.

The component name is `SmoothScrollView`. It should be the default wrapper for SwiftUI pages that need scrolling, especially dashboard tabs, marketplace pages, persona pages, and long settings surfaces.

**Key Characteristics:**
- Hide native `ScrollView` indicators by default.
- Overlay a narrow rounded capsule on the trailing edge.
- Show the capsule only while the user scrolls or while programmatic movement is active.
- Keep the indicator about 38pt tall with a 3pt width.
- Use semantic `Color.primary.opacity(...)` so Light and Dark mode remain automatic.
- Do not replace specialized `NSScrollView` text editors or terminal/log surfaces unless their interaction model is reviewed.

## 2. Component Contract

### SmoothScrollView

`SmoothScrollView` owns scroll metrics and indicator visibility. It should expose a SwiftUI-friendly wrapper:

```swift
SmoothScrollView {
    content
}
```

The component should:
- Create an internal `ScrollView(showsIndicators: false)`.
- Track content offset, viewport height, and content height through `PreferenceKey` metrics.
- Place the custom indicator in an overlay aligned to the trailing edge.
- Clamp indicator progress between 0 and 1.
- Debounce hiding with a short `DispatchWorkItem`.
- Disable hit testing for the indicator.

## 3. Indicator Styling

| Property | Value |
| --- | --- |
| Width | 3pt |
| Minimum height | 38pt |
| Horizontal inset | 8pt from trailing edge |
| Vertical inset | 12pt |
| Shape | `Capsule(style: .continuous)` |
| Light color | `Color.primary.opacity(0.22)` |
| Dark color | `Color.primary.opacity(0.30)` |
| Show animation | easeInOut, 0.12s |
| Hide animation | easeInOut, 0.22s |
| Position animation | easeOut, 0.08s |

## 4. Usage Rules

- Use `SmoothScrollView` for ordinary vertical scrolling pages.
- Keep `ScrollViewReader` at the call site when the page needs `scrollTo`.
- Do not use the component for horizontally scrolling strips unless a horizontal variant is designed.
- Do not wrap text editors, terminal emulators, or AppKit-backed scroll containers without checking selection, keyboard, and auto-scroll behavior.
- Prefer migrating pages incrementally, with source-level verification and an Xcode build after each batch.

## 5. Implementation Location

The reusable SwiftUI component should live at:

`OpenClawInstaller/DesignSystem/Components/SmoothScrollView.swift`

Shared metrics and preference keys should stay in the same file unless they become useful outside the component.
