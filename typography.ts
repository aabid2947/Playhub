// Typography definitions for the application
// Instagram-inspired scale, responsive to screen size.
import { Dimensions, PixelRatio, TextStyle } from 'react-native';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

// Baseline: 390 pt (iPhone 14 / 15). Scales fonts and spacing up on larger
// devices and down on smaller ones, clamped so extremes stay readable.
const BASELINE_WIDTH = 390;
const rawScale = SCREEN_WIDTH / BASELINE_WIDTH;
const SCALE = Math.min(Math.max(rawScale, 0.85), 1.25);

/**
 * Normalize a design value (font size, spacing) to the current device width.
 * Rounds to the nearest physical pixel for crisp rendering.
 */
export const normalize = (size: number): number =>
  Math.round(PixelRatio.roundToNearestPixel(size * SCALE));

// ---------------------------------------------------------------------------
// Screen-size breakpoints — use these in components when behaviour (not just
// size) needs to differ, e.g. showing two columns on a tablet.
// ---------------------------------------------------------------------------
export const breakpoints = {
  small: 360,   // iPhone SE, small Androids
  medium: 390,  // iPhone 14 / 15 (baseline)
  large: 430,   // iPhone Pro Max, large Androids
  tablet: 768,  // iPad, foldables
} as const;

export const isSmallScreen = SCREEN_WIDTH < breakpoints.small;
export const isTablet = SCREEN_WIDTH >= breakpoints.tablet;

// ---------------------------------------------------------------------------
// Font sizes — Instagram-matched scale.
// ---------------------------------------------------------------------------
export const fontSize = {
  xs:   normalize(11),  // timestamps, meta labels
  sm:   normalize(12),  // captions, secondary text
  md:   normalize(13),  // comments, sub-body
  base: normalize(14),  // default body, usernames
  lg:   normalize(15),  // post content, primary text
  xl:   normalize(17),  // section headers
  xxl:  normalize(20),  // screen titles
  h2:   normalize(24),  // large headings
  h1:   normalize(30),  // hero / onboarding headings
  display: normalize(36), // splash / marketing displays
} as const;

// ---------------------------------------------------------------------------
// Font weights — React Native only reliably supports 400/500/600/700.
// ---------------------------------------------------------------------------
export const fontWeight = {
  regular:  '400',
  medium:   '500',
  semibold: '600',
  bold:     '700',
  heavy:    '800',
} as const satisfies Record<string, TextStyle['fontWeight']>;

// ---------------------------------------------------------------------------
// Line heights — roughly 1.3–1.4× font size for body, tighter for headings.
// ---------------------------------------------------------------------------
export const lineHeight = {
  xs:      normalize(14),
  sm:      normalize(16),
  md:      normalize(18),
  base:    normalize(20),
  lg:      normalize(22),
  xl:      normalize(24),
  xxl:     normalize(28),
  h2:      normalize(32),
  h1:      normalize(36),
  display: normalize(44),
} as const;

// ---------------------------------------------------------------------------
// Letter spacing — negative values tighten headings, positive widens labels.
// ---------------------------------------------------------------------------
export const letterSpacing = {
  tighter: -0.5,
  tight:   -0.3,
  normal:   0,
  wide:     0.3,
  wider:    0.5,
  widest:   1.0,
} as const;

// ---------------------------------------------------------------------------
// Spacing scale — 4 pt grid, scaled to the device. Use for margin, padding,
// gap. Stays consistent with the font scale above.
// ---------------------------------------------------------------------------
export const spacing = {
  xxs: normalize(2),
  xs:  normalize(4),
  sm:  normalize(8),
  md:  normalize(12),
  base: normalize(16),
  lg:  normalize(20),
  xl:  normalize(24),
  xxl: normalize(32),
  xxxl: normalize(40),
  huge: normalize(56),
} as const;

// ---------------------------------------------------------------------------
// Border radius — Instagram uses generous rounding on cards and pills.
// ---------------------------------------------------------------------------
export const radius = {
  none: 0,
  xs:   normalize(4),
  sm:   normalize(6),
  md:   normalize(8),
  base: normalize(12),
  lg:   normalize(16),
  xl:   normalize(20),
  pill: 999,
  full: 9999,
} as const;

// ---------------------------------------------------------------------------
// Pre-built text styles — drop-in for any `<Text style={...} />`.
// Colors are intentionally omitted; apply `theme.text` etc. at the call site.
// ---------------------------------------------------------------------------
export const textStyles = {
  // Meta
  timestamp: {
    fontSize: fontSize.xs,
    lineHeight: lineHeight.xs,
    fontWeight: fontWeight.regular,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,
  metaLabel: {
    fontSize: fontSize.xs,
    lineHeight: lineHeight.xs,
    fontWeight: fontWeight.medium,
    letterSpacing: letterSpacing.wide,
    textTransform: 'uppercase',
  } as TextStyle,

  // Body
  caption: {
    fontSize: fontSize.sm,
    lineHeight: lineHeight.sm,
    fontWeight: fontWeight.regular,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,
  comment: {
    fontSize: fontSize.md,
    lineHeight: lineHeight.md,
    fontWeight: fontWeight.regular,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,
  body: {
    fontSize: fontSize.base,
    lineHeight: lineHeight.base,
    fontWeight: fontWeight.regular,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,
  bodyBold: {
    fontSize: fontSize.base,
    lineHeight: lineHeight.base,
    fontWeight: fontWeight.semibold,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,
  postContent: {
    fontSize: fontSize.lg,
    lineHeight: lineHeight.lg,
    fontWeight: fontWeight.regular,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,

  // Identity
  username: {
    fontSize: fontSize.base,
    lineHeight: lineHeight.base,
    fontWeight: fontWeight.semibold,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,
  displayName: {
    fontSize: fontSize.base,
    lineHeight: lineHeight.base,
    fontWeight: fontWeight.semibold,
    letterSpacing: letterSpacing.tight,
  } as TextStyle,
  handle: {
    fontSize: fontSize.sm,
    lineHeight: lineHeight.sm,
    fontWeight: fontWeight.regular,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,

  // Stats — follower counts, post counts
  statNumber: {
    fontSize: fontSize.lg,
    lineHeight: lineHeight.lg,
    fontWeight: fontWeight.bold,
    letterSpacing: letterSpacing.tight,
  } as TextStyle,
  statLabel: {
    fontSize: fontSize.xs,
    lineHeight: lineHeight.xs,
    fontWeight: fontWeight.regular,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,

  // Buttons
  buttonSm: {
    fontSize: fontSize.sm,
    lineHeight: lineHeight.sm,
    fontWeight: fontWeight.semibold,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,
  buttonMd: {
    fontSize: fontSize.base,
    lineHeight: lineHeight.base,
    fontWeight: fontWeight.semibold,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,
  buttonLg: {
    fontSize: fontSize.lg,
    lineHeight: lineHeight.lg,
    fontWeight: fontWeight.bold,
    letterSpacing: letterSpacing.normal,
  } as TextStyle,

  // Headings
  sectionHeader: {
    fontSize: fontSize.xl,
    lineHeight: lineHeight.xl,
    fontWeight: fontWeight.semibold,
    letterSpacing: letterSpacing.tight,
  } as TextStyle,
  screenTitle: {
    fontSize: fontSize.xxl,
    lineHeight: lineHeight.xxl,
    fontWeight: fontWeight.bold,
    letterSpacing: letterSpacing.tight,
  } as TextStyle,
  h2: {
    fontSize: fontSize.h2,
    lineHeight: lineHeight.h2,
    fontWeight: fontWeight.bold,
    letterSpacing: letterSpacing.tight,
  } as TextStyle,
  h1: {
    fontSize: fontSize.h1,
    lineHeight: lineHeight.h1,
    fontWeight: fontWeight.heavy,
    letterSpacing: letterSpacing.tight,
  } as TextStyle,
  display: {
    fontSize: fontSize.display,
    lineHeight: lineHeight.display,
    fontWeight: fontWeight.heavy,
    letterSpacing: letterSpacing.tighter,
  } as TextStyle,
} as const;

// ---------------------------------------------------------------------------
// Legacy export — preserved for backward compatibility with existing screens
// and components. Prefer `textStyles` for new code.
// ---------------------------------------------------------------------------
export const typography = {
  h1: textStyles.h1,
  h2: textStyles.h2,
  body: textStyles.body,
  caption: textStyles.caption,
} as const;

export type TypographyVariant = keyof typeof typography;
export type TextStyleVariant = keyof typeof textStyles;
