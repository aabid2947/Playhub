// Color palette for the application — "Sports-Light" v1 identity.
// The app SHIPS LIGHT ONLY (per client). `darkColors` is retained but dormant.
// Energetic orange (#FF6A2C) leads CTAs; deep navy (#0F2540) is the ink; a
// broadcast blue (#1763E0) accents. This file mirrors design_tokens.dart.

export const darkColors = {
  primary: '#FF6A2C',        // orange (dormant — light-only app)
  verified: '#1D9BF0',
  secondary: '#373a43',      // default button bg
  accent: '#1763E0',         // broadcast blue

  background: '#141318',     // main app background
  surface: '#1c1d22',        // secondary background
  surfaceHover: '#212129',   // cards / raised surfaces
  card: '#212129',

  text: '#c1c2c7',
  textPrimary: '#FAFAFA',
  textSecondary: '#9CA3AF',

  border: '#2a2d34',
  error: '#EF4444',
  success: '#16A34A',
  warning: '#F59E0B',
};

export const lightColors = {
  primary: '#FF6A2C',        // energetic orange — every call-to-action
  verified: '#1D9BF0',
  secondary: '#1763E0',      // broadcast blue accent
  accent: '#1763E0',
  background: '#F4F7FB',     // near-white page
  surface: '#FFFFFF',        // cards
  surfaceHover: '#EFF4FA',   // inset / segment track
  card: '#FFFFFF',
  text: '#12283F',           // navy ink
  textPrimary: '#0F2540',
  textSecondary: '#5B6B7F',
  border: '#E6EDF5',
  error: '#EF4444',
  success: '#16A34A',
  warning: '#F59E0B',
};

export type ColorScheme = typeof darkColors;

export const colors = {
  dark: darkColors,
  light: lightColors,
} as const;

export type ThemeMode = keyof typeof colors;
