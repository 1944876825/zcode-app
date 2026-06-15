# Apple Design System Reference

## Design Philosophy

Apple's design language is defined by three core principles:

1. **Clarity** — Text is legible at every size, icons are precise and lucid, ornaments are subtle and appropriate, a sharpened focus on functionality motivates the design.
2. **Deference** — Fluid motion and a crisp, beautiful interface help people understand and interact with content while never competing with it.
3. **Depth** — Visual layers and realistic motion convey hierarchy, impart vitality, and facilitate understanding.

---

## Color System

### System Colors (iOS / macOS)

#### Dynamic System Colors
| Name | Light Mode | Dark Mode | Usage |
|------|-----------|-----------|-------|
| Blue | `#007AFF` | `#0A84FF` | Primary actions, links |
| Green | `#34C759` | `#30D158` | Success, confirmations |
| Indigo | `#5856D6` | `#5E5CE6` | Secondary actions |
| Orange | `#FF9500` | `#FF9F0A` | Warnings |
| Pink | `#FF2D55` | `#FF375F` | Favorites, hearts |
| Purple | `#AF52DE` | `#BF5AF2` | Creative, premium |
| Red | `#FF3B30` | `#FF453A` | Destructive, errors |
| Teal | `#5AC8FA` | `#64D2FF` | Communication |
| Yellow | `#FFCC00` | `#FFD60A` | Alerts, stars |

#### Neutral / Gray Scale
| Name | Light | Dark |
|------|-------|------|
| Label (Primary) | `#000000` | `#FFFFFF` |
| Label (Secondary) | `rgba(60,60,67,0.6)` | `rgba(235,235,245,0.6)` |
| Label (Tertiary) | `rgba(60,60,67,0.3)` | `rgba(235,235,245,0.3)` |
| Label (Quaternary) | `rgba(60,60,67,0.18)` | `rgba(235,235,245,0.18)` |
| System Background | `#FFFFFF` | `#000000` |
| Secondary Background | `#F2F2F7` | `#1C1C1E` |
| Tertiary Background | `#FFFFFF` | `#2C2C2E` |
| Grouped Background | `#F2F2F7` | `#000000` |
| Separator | `rgba(60,60,67,0.29)` | `rgba(84,84,88,0.65)` |
| Fill (Primary) | `rgba(120,120,128,0.2)` | `rgba(120,120,128,0.36)` |

#### macOS Specific
| Name | Value |
|------|-------|
| Window Background | `#ECECEC` (light) / `#1E1E1E` (dark) |
| Control Background | `#FFFFFF` (light) / `#1E1E1E` (dark) |
| Under Window Background | `#D6D6D6` (light) / `#282828` (dark) |

---

## Typography

### SF Pro (iOS / macOS System Font)

Apple uses **SF Pro** (San Francisco) as the system typeface. For web, fall back to `-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif`.

#### iOS Text Styles (Dynamic Type)
| Style | Weight | Size | Line Height | Letter Spacing |
|-------|--------|------|-------------|----------------|
| Large Title | Regular | 34pt | 41pt | +0.37pt |
| Title 1 | Regular | 28pt | 34pt | +0.36pt |
| Title 2 | Regular | 22pt | 28pt | +0.35pt |
| Title 3 | Regular | 20pt | 25pt | +0.38pt |
| Headline | Semibold | 17pt | 22pt | -0.43pt |
| Body | Regular | 17pt | 22pt | -0.43pt |
| Callout | Regular | 16pt | 21pt | -0.32pt |
| Subheadline | Regular | 15pt | 20pt | -0.23pt |
| Footnote | Regular | 13pt | 18pt | -0.08pt |
| Caption 1 | Regular | 12pt | 16pt | 0pt |
| Caption 2 | Regular | 11pt | 13pt | +0.07pt |

#### macOS Text Styles
| Style | Weight | Size |
|-------|--------|------|
| Large Title | Regular | 26pt |
| Title 1 | Regular | 22pt |
| Title 2 | Bold | 17pt |
| Title 3 | Regular | 15pt |
| Headline | Bold | 13pt |
| Body | Regular | 13pt |
| Callout | Regular | 12pt |
| Subheadline | Regular | 11pt |
| Footnote | Regular | 10pt |
| Caption 1 | Regular | 10pt |
| Caption 2 | Regular | 10pt |

#### SF Mono (Code)
Use `'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace` for code blocks.

#### SF Compact (watchOS)
Condensed variant for small displays.

### Font Weight Keywords
- Ultralight: 100
- Thin: 200
- Light: 300
- Regular: 400
- Medium: 500
- Semibold: 600
- Bold: 700
- Heavy: 800
- Black: 900

---

## Spacing & Layout

### Base Unit
**4pt grid system** — all spacing values are multiples of 4.

### Common Spacing Values
| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4pt | Minimal gaps |
| `sm` | 8pt | Inner padding |
| `md` | 12pt | Component gap |
| `lg` | 16pt | Section padding |
| `xl` | 20pt | Card padding |
| `2xl` | 24pt | Large gaps |
| `3xl` | 32pt | Section margins |
| `4xl` | 44pt | Touch target minimum |

### Safe Areas (iOS)
- Status bar height: 44pt (notch devices: 47–59pt)
- Home indicator: 34pt
- Tab bar height: 49pt
- Navigation bar height: 44pt

### Touch Targets
Minimum touch target size: **44 × 44pt**

---

## Corner Radius

| Element | Radius |
|---------|--------|
| App Icon (iOS) | 22.5% of width (continuous curve) |
| Cards | 12–16pt |
| Buttons | 10–12pt |
| Input fields | 10pt |
| Alerts | 14pt |
| Sheets | 16pt (top corners) |
| Tags / Chips | Fully rounded (pill) |

Apple uses **continuous (squircle) corner curves**, not circular arcs. In CSS: `border-radius` alone is insufficient; use SVG path or the `smooth-corners` polyfill for pixel-perfect results.

---

## Iconography (SF Symbols)

- Icon library: **SF Symbols** (6000+ icons)
- Scales: Small, Medium, Large
- Weights: matches text weight (Ultralight → Black)
- Rendering modes: Monochrome, Hierarchical, Palette, Multicolor
- Alignment: Optical center, not geometric center
- Stroke width: consistent with paired text weight

### Icon Sizing Guidelines
| Context | Size |
|---------|------|
| Navigation bar | 22–24pt |
| Tab bar | 25–28pt |
| Toolbar | 22pt |
| Inline with body text | Match font size |
| Hero / feature | 56–96pt |

---

## Elevation & Materials

### iOS Materials (vibrancy + blur)
| Material | Blur Radius | Usage |
|----------|-------------|-------|
| Ultra Thin | Low | Subtle overlays |
| Thin | Light | Notification banners |
| Regular | Medium | Sheets, cards |
| Thick | High | Modals, alerts |
| Chrome | System | Navigation bars |

### Shadow Tokens (approximate CSS)
| Level | CSS |
|-------|-----|
| 0 (flat) | none |
| 1 (card) | `0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.08)` |
| 2 (elevated) | `0 4px 6px rgba(0,0,0,0.10), 0 2px 4px rgba(0,0,0,0.08)` |
| 3 (modal) | `0 10px 20px rgba(0,0,0,0.12), 0 6px 6px rgba(0,0,0,0.08)` |
| 4 (overlay) | `0 20px 40px rgba(0,0,0,0.15)` |

---

## Motion & Animation

### Core Principles
- **Purposeful**: Every animation communicates meaning
- **Responsive**: Animations feel instant (<100ms feedback)
- **Natural**: Physics-based (spring), not linear

### Timing Functions
| Name | CSS Equivalent | Usage |
|------|---------------|-------|
| Default | `cubic-bezier(0.25, 0.1, 0.25, 1.0)` | General transitions |
| Ease In | `cubic-bezier(0.42, 0, 1.0, 1.0)` | Elements leaving |
| Ease Out | `cubic-bezier(0, 0, 0.58, 1.0)` | Elements entering |
| Spring (approx.) | `cubic-bezier(0.34, 1.56, 0.64, 1.0)` | Bouncy, tactile |

### Duration Guidelines
| Interaction | Duration |
|-------------|----------|
| Micro (icon tap) | 100–150ms |
| Button press | 150ms |
| View transition | 300–400ms |
| Modal present | 400ms |
| Page transition | 350ms |
| Expand / collapse | 250–300ms |

### Reduced Motion
Always respect `prefers-reduced-motion: reduce` — replace motion with crossfade or instant transitions.

---

## Component Patterns

### Buttons

#### Filled (Primary)
- Background: System Blue `#007AFF`
- Text: White, Semibold 17pt
- Corner radius: 12pt continuous
- Height: 50pt
- Horizontal padding: 20pt

#### Tinted (Secondary)
- Background: `rgba(0,122,255,0.12)`
- Text: System Blue
- Same dimensions as filled

#### Gray
- Background: `rgba(120,120,128,0.12)`
- Text: Label (primary)

#### Plain (Tertiary)
- No background
- Text: System Blue

#### Destructive
- Text / tint: System Red `#FF3B30`

### Input Fields
- Height: 44pt
- Background: Secondary Fill `rgba(120,120,128,0.12)`
- Corner radius: 10pt
- Placeholder: Tertiary label color
- Font: Body (17pt Regular)
- Focus ring: System Blue, 2pt

### Navigation Bars
- Height: 44pt (large title: 96pt)
- Background: Chrome material (translucent blur)
- Title: Headline (Semibold 17pt) or Large Title (Regular 34pt)
- Back button: System Blue

### Tab Bars
- Height: 49pt + safe area
- Selected: System Blue
- Unselected: Tertiary label
- Icons: SF Symbols, 25pt

### Lists / Table Views
- Row height: min 44pt
- Separator inset: 16pt left
- Disclosure chevron: `chevron.right`, Secondary label

### Cards
- Background: Secondary system background
- Corner radius: 16pt
- Shadow: Level 1–2
- Padding: 16pt

### Alerts
- Width: ~270pt (fixed)
- Corner radius: 14pt
- Title: Headline
- Message: Footnote / Callout
- Button separator: Separator color

---

## Accessibility

### Contrast Ratios (WCAG AA minimum)
- Normal text: 4.5:1
- Large text (18pt+): 3:1
- UI components: 3:1

### Dynamic Type
Always support Dynamic Type — use relative units (pt / em), never fixed px for text.

### VoiceOver
- All interactive elements must have accessibility labels
- Custom components need `accessibilityRole` and `accessibilityState`

### Color Independence
Never convey information with color alone — pair with icon, text, or pattern.

---

## Glassmorphism (Apple-style)

Apple's characteristic frosted glass effect:

```css
.glass-card {
  background: rgba(255, 255, 255, 0.72);
  backdrop-filter: saturate(180%) blur(20px);
  -webkit-backdrop-filter: saturate(180%) blur(20px);
  border: 0.5px solid rgba(255, 255, 255, 0.3);
  border-radius: 16px;
}

/* Dark mode */
@media (prefers-color-scheme: dark) {
  .glass-card {
    background: rgba(28, 28, 30, 0.72);
    border-color: rgba(255, 255, 255, 0.08);
  }
}
```

---

## CSS Custom Properties (Web Implementation)

```css
:root {
  /* Brand Colors */
  --apple-blue: #007AFF;
  --apple-green: #34C759;
  --apple-indigo: #5856D6;
  --apple-orange: #FF9500;
  --apple-pink: #FF2D55;
  --apple-purple: #AF52DE;
  --apple-red: #FF3B30;
  --apple-teal: #5AC8FA;
  --apple-yellow: #FFCC00;

  /* Backgrounds */
  --bg-primary: #FFFFFF;
  --bg-secondary: #F2F2F7;
  --bg-tertiary: #FFFFFF;

  /* Labels */
  --label-primary: #000000;
  --label-secondary: rgba(60, 60, 67, 0.6);
  --label-tertiary: rgba(60, 60, 67, 0.3);

  /* Typography */
  --font-system: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif;
  --font-mono: 'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace;

  /* Spacing */
  --space-xs: 4px;
  --space-sm: 8px;
  --space-md: 12px;
  --space-lg: 16px;
  --space-xl: 20px;
  --space-2xl: 24px;
  --space-3xl: 32px;
  --space-4xl: 44px;

  /* Radius */
  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;
  --radius-xl: 20px;
  --radius-full: 9999px;

  /* Shadows */
  --shadow-sm: 0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.08);
  --shadow-md: 0 4px 6px rgba(0,0,0,0.10), 0 2px 4px rgba(0,0,0,0.08);
  --shadow-lg: 0 10px 20px rgba(0,0,0,0.12), 0 6px 6px rgba(0,0,0,0.08);
  --shadow-xl: 0 20px 40px rgba(0,0,0,0.15);
}

@media (prefers-color-scheme: dark) {
  :root {
    --apple-blue: #0A84FF;
    --apple-green: #30D158;
    --apple-indigo: #5E5CE6;
    --apple-orange: #FF9F0A;
    --apple-pink: #FF375F;
    --apple-purple: #BF5AF2;
    --apple-red: #FF453A;
    --apple-teal: #64D2FF;
    --apple-yellow: #FFD60A;

    --bg-primary: #000000;
    --bg-secondary: #1C1C1E;
    --bg-tertiary: #2C2C2E;

    --label-primary: #FFFFFF;
    --label-secondary: rgba(235, 235, 245, 0.6);
    --label-tertiary: rgba(235, 235, 245, 0.3);
  }
}
```

---

## DESIGN.md Template (for Apple-style UI)

When creating a DESIGN.md for an Apple-style project, use these tokens and reference this system for all UI decisions.

**Key differentiators from generic design:**
- Always use SF Pro font stack
- Always support light/dark mode with the above tokens
- Prefer system colors over custom colors
- Use 4pt grid for all spacing
- Minimum 44pt touch targets
- Continuous (squircle) corner curves
- Glassmorphism for overlays and floating elements
- Spring-based animations (not linear easing)
- SF Symbols for iconography
