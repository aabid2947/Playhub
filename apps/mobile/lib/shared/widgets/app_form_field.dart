import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:playhub/core/design_tokens.dart';

/// Labeled text input. Renders a small label above a [TextFormField] so the
/// floating-label dance is avoided. Internally still uses [TextFormField]
/// (which composes a [TextField]) so existing tests using
/// `find.byType(TextField)` continue to resolve.
class AppFormField extends StatelessWidget {
  const AppFormField({
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.maxLines = 1,
    this.enabled = true,
    this.textInputAction,
    this.onFieldSubmitted,
    this.inputFormatters,
    this.focusNode,
    this.initialValue,
    super.key,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int? maxLines;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final String? initialValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        TextFormField(
          controller: controller,
          initialValue: initialValue,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          autofocus: autofocus,
          maxLines: obscureText ? 1 : maxLines,
          enabled: enabled,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
