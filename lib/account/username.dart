/// The username rule as the hint shows it.
const kUsernameHint = '3–20 letters, numbers, _ or .';

/// The password rule as the hint shows it.
const kPasswordHint = 'At least 8 characters';

/// Same rule as the database's `profiles_username_rule` check.
final _usernameRule = RegExp(r'^[a-z0-9_][a-z0-9_.]{1,18}[a-z0-9_]$');

/// Null when [name] is a valid username, else the hint to show.
String? usernameProblem(String name) =>
    _usernameRule.hasMatch(name) ? null : kUsernameHint;

/// What a typed username is stored as: trimmed and lowercased.
String normalizeUsername(String name) => name.trim().toLowerCase();

/// Null when [password] is long enough, else the hint to show.
String? passwordProblem(String password) =>
    password.length >= 8 ? null : kPasswordHint;
