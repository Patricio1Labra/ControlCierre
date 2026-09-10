import 'package:flutter/services.dart';

/// Formatea el texto con separador de miles chileno (punto) mientras se escribe.
/// Escribe "1000" -> "1.000". Sin decimales.
class PesoInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) {
      return TextEditingValue.empty;
    }

    // Solo conservar dígitos
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return TextEditingValue.empty;
    }

    final formatted = _withThousandSeparators(digits);

    // Calcular el cursor preservando la cantidad de dígitos a la izquierda
    final cursorDigits = _digitsBeforeCursor(
        text,
        newValue.selection.isValid
            ? newValue.selection.baseOffset
            : text.length);

    final caret = _caretAfterNCifras(formatted, cursorDigits);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  /// Inserta '.' cada 3 dígitos desde la derecha ("12345" -> "12.345").
  static String _withThousandSeparators(String digits) {
    final buffer = StringBuffer();
    final len = digits.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static int _digitsBeforeCursor(String text, int offset) {
    var count = 0;
    final bound = offset < 0 ? text.length : offset;
    for (int i = 0; i < bound && i < text.length; i++) {
      if (RegExp(r'\d').hasMatch(text[i])) count++;
    }
    return count;
  }

  static int _caretAfterNCifras(String formatted, int n) {
    var count = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) count++;
      if (count == n) return i + 1;
    }
    return formatted.length;
  }
}
