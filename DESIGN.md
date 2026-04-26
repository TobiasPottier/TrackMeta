---
name: Modern Refinement
colors:
  surface: '#131315'
  surface-dim: '#131315'
  surface-bright: '#39393b'
  surface-container-lowest: '#0e0e10'
  surface-container-low: '#1c1b1d'
  surface-container: '#201f22'
  surface-container-high: '#2a2a2c'
  surface-container-highest: '#353437'
  on-surface: '#e5e1e4'
  on-surface-variant: '#d3c5ac'
  inverse-surface: '#e5e1e4'
  inverse-on-surface: '#313032'
  outline: '#9c8f79'
  outline-variant: '#4f4633'
  surface-tint: '#f9bd22'
  primary: '#ffe1a7'
  on-primary: '#402d00'
  primary-container: '#fbbf24'
  on-primary-container: '#6c4f00'
  inverse-primary: '#795900'
  secondary: '#c6c6c7'
  on-secondary: '#2f3132'
  secondary-container: '#454748'
  on-secondary-container: '#b4b5b6'
  tertiary: '#e4e3ed'
  on-tertiary: '#2f3037'
  tertiary-container: '#c8c7d1'
  on-tertiary-container: '#52535b'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffdf9f'
  primary-fixed-dim: '#f9bd22'
  on-primary-fixed: '#261a00'
  on-primary-fixed-variant: '#5c4300'
  secondary-fixed: '#e2e2e3'
  secondary-fixed-dim: '#c6c6c7'
  on-secondary-fixed: '#1a1c1d'
  on-secondary-fixed-variant: '#454748'
  tertiary-fixed: '#e2e1eb'
  tertiary-fixed-dim: '#c6c6cf'
  on-tertiary-fixed: '#1a1b22'
  on-tertiary-fixed-variant: '#45464e'
  background: '#131315'
  on-background: '#e5e1e4'
  surface-variant: '#353437'
typography:
  display:
    fontFamily: Inter
    fontSize: 64px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.04em
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
    letterSpacing: 0em
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
    letterSpacing: 0em
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: '1.4'
    letterSpacing: 0.05em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  unit: 8px
  container-max: 1200px
  gutter: 24px
  margin-mobile: 16px
  section-gap: 128px
  element-gap: 32px
---

## Brand & Style

The design system is rooted in high-end minimalism with a focus on editorial precision and digital craftsmanship. It targets an audience that values clarity, professional authority, and sophisticated aesthetics. The brand personality is confident but quiet, allowing the work to take center stage while the interface provides a premium, "gallery-like" frame.

The visual style combines **Minimalism** with **Modern Corporate** influences. It utilizes heavy whitespace to create a sense of luxury and breathing room. Every element is intentional, avoiding unnecessary decorative flourishes in favor of structural integrity and typographic excellence. The emotional response should be one of trust, technical proficiency, and effortless elegance.

## Colors

The palette is anchored by a deep, monochromatic foundation that provides a high-contrast environment for content. 

- **Primary:** The amber gold (#FBBF24) is used sparingly as a "high-fidelity" highlight for calls to action, active states, and critical branding moments.
- **Neutral:** The core background is a rich, near-black (#09090B), which creates a sophisticated depth and reduces eye strain.
- **Typography & Accents:** Light grays and off-whites (#F4F4F5 and #A1A1AA) create a hierarchy of information. Use the lighter shade for primary content and the muted gray for secondary metadata or deactivated states.

Maintain high contrast ratios to ensure the premium feel translates into exceptional accessibility.

## Typography

This design system utilizes **Inter** exclusively to achieve a systematic, utilitarian, and modern feel. The hierarchy is established through drastic weight changes and intentional letter spacing rather than font variety.

Headlines should be set with tight tracking to feel cohesive and impactful, while body text requires generous line-height to maintain readability against the dark background. Labels use an uppercase treatment with increased letter spacing to provide a technical, architectural feel to the interface's metadata.

## Layout & Spacing

The layout philosophy follows a **Fixed Grid** model for desktop, centered within the viewport, transitioning to a fluid model for mobile devices. A 12-column grid provides the structural framework, with content typically spanning 6, 8, or 12 columns to maintain focus.

Spacing is governed by an 8px rhythmic scale. To achieve the premium feel, use "oversized" vertical margins (Section Gaps) to separate distinct content blocks, ensuring that the user's eye is never overwhelmed. Use the 32px element gap for internal component spacing to maintain a clean, airy aesthetic.

## Elevation & Depth

Depth in this design system is achieved through **Tonal Layering** and **Low-Contrast Outlines** rather than traditional shadows. 

1.  **Base Layer:** The primary background color (#09090B).
2.  **Surface Layer:** Subtle elevation is created by using a slightly lighter neutral (approx. 5-8% lighter than the base) for cards or containers.
3.  **Outlines:** Elements are defined by 1px solid borders using the muted gray (#A1A1AA) at low opacity (10-20%). This creates a sharp, architectural boundary that feels high-end and precise.
4.  **Interaction:** On hover or active states, the border opacity should increase, or the primary color (#FBBF24) should be introduced as a hair-line stroke.

## Shapes

The shape language is "Soft" (0.25rem / 4px base radius). This subtle rounding takes the edge off the brutalist tendencies of a pure dark-mode grid, making the professional environment feel more modern and approachable without losing its serious tone. 

- **Buttons & Inputs:** Use the base 4px radius.
- **Large Cards:** May utilize `rounded-lg` (8px) to emphasize their role as primary content containers.
- **Icons:** Use linear, 2px stroke icons with slightly rounded caps to match the UI's geometry.

## Components

### Buttons
Primary buttons are solid #FBBF24 with black text for maximum prominence. Secondary buttons should be "ghost" style with a 1px border (#F4F4F5 at 20% opacity) and white text. Transitions must be smooth (200ms) with a subtle lift in border brightness on hover.

### Cards
Cards should not have backgrounds by default; instead, use the low-contrast 1px border to define the shape. This keeps the layout feeling light. Background fills on cards should only be used to group highly complex information.

### Input Fields
Inputs are minimalist—bottom borders only or very subtle 4px rounded frames. Focus states should transition the border color to #FBBF24. Labels should use the `label-sm` typographic style, sitting just above the input field.

### Chips & Tags
Used for categories or skills. These should have a dark gray background (#F4F4F5 at 10% opacity) with `label-sm` text color. They remain small and unobtrusive, acting as subtle metadata.

### Navigation
The navigation should be "sticky" with a backdrop blur (Glassmorphism effect) to allow content to flow underneath while maintaining legibility. Use simple text links that underline on hover using the primary color.