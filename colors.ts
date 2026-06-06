// Color palette for the application
// Supports both dark and light themes

export const darkColors = {
  primary: '#9933FF',        // use ONLY for critical actions
  verified: '#1D9BF0',
  secondary: '#373a43',      // default button bg
  accent: '#9933FF',         // same as primary, no extra accent color

  background: '#141318',     // main app background
  surface: '#1c1d22',        // secondary background
  surfaceHover: '#212129',   // cards / raised surfaces
  card: '#212129',

  text: '#c1c2c7',
  textPrimary: '#FAFAFA',
  textSecondary: '#9CA3AF',

  border: '#2a2d34',
  error: '#EF4444',
  success: '#22C55E',
  warning: '#F59E0B',
};

export const lightColors = {
  primary: '#9933FF',
  verified: '#1D9BF0',
  secondary: '#00BFFF',
  accent: '#E95FE9',
  background: '#FFFFFF',
  surface: '#F5F5F5',
  surfaceHover: '#E5E5E5',
  card: '#F5F5F5',
  text: '#111418',
  textPrimary: '#111418',
  textSecondary: '#4A5568',
  border: '#D1D5DB',
  error: '#EF4444',
  success: '#22C55E',
  warning: '#F59E0B',
};

export type ColorScheme = typeof darkColors;

export const colors = {
  dark: darkColors,
  light: lightColors,
} as const;

export type ThemeMode = keyof typeof colors;
