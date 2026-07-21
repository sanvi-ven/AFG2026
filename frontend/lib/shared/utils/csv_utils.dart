/// Pure helper that turns a table of rows into delimited text (CSV/TSV).
///
/// No external `csv` package — the format is simple enough to hand-roll,
/// matching this codebase's minimal-dependency style. Used for both real CSV
/// (`,`) and a clipboard-friendly tab-delimited variant (`\t`, which Google
/// Sheets/Excel auto-split into columns on paste).
library;

import 'package:intl/intl.dart';

final DateFormat _csvDateFormat = DateFormat('yyyy-MM-dd');
final DateFormat _csvDateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

/// Stringify a single cell for delimited output.
///   * `null`     → empty string
///   * `DateTime` → `yyyy-MM-dd` for date-only values, else `yyyy-MM-dd HH:mm`
///   * `double`   → fixed 2 decimals (money-friendly)
///   * anything else → `toString()`
String _stringifyCell(Object? cell) {
  if (cell == null) return '';
  if (cell is DateTime) {
    final isMidnight = cell.hour == 0 && cell.minute == 0 && cell.second == 0;
    return isMidnight
        ? _csvDateFormat.format(cell)
        : _csvDateTimeFormat.format(cell);
  }
  if (cell is double) return cell.toStringAsFixed(2);
  return cell.toString();
}

/// Quote a cell (wrap in `"..."`, doubling any internal `"`) when it contains
/// the delimiter, a quote, or a newline — otherwise leave it as-is.
String _quoteIfNeeded(String value, String delimiter) {
  final needsQuoting =
      value.contains(delimiter) || value.contains('"') || value.contains('\n') || value.contains('\r');
  if (!needsQuoting) return value;
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

/// Build delimited text from [rows]. Each cell is stringified, then quoted when
/// needed; cells in a row are joined with [delimiter] and rows joined with `\n`.
String buildDelimitedText(List<List<Object?>> rows, {String delimiter = ','}) {
  return rows.map((row) {
    return row.map((cell) => _quoteIfNeeded(_stringifyCell(cell), delimiter)).join(delimiter);
  }).join('\n');
}
