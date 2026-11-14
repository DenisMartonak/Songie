/// The username rule as the hint shows it.
const kUsernameHint = '3–20 letters, numbers, _ or .';

/// The password rule as the hint shows it.
const kPasswordHint = 'At least 8 characters';

/// Same rule as the database's `profiles_username_rule` check. Capitals are
/// kept as typed, but a name is unique in any case (the server's unique index
/// is on `lower(username)`).
final _usernameRule = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.]{1,18}[A-Za-z0-9_]$');

/// Null when [name] is a valid username, else the hint to show.
String? usernameProblem(String name) =>
    _usernameRule.hasMatch(name) ? null : kUsernameHint;

/// What a typed username is stored as: trimmed, capitals kept.
String normalizeUsername(String name) => name.trim();

/// Whether [a] and [b] are the same username to the server (any case).
bool sameUsername(String a, String b) => a.toLowerCase() == b.toLowerCase();

/// Null when [password] is long enough, else the hint to show.
String? passwordProblem(String password) =>
    password.length >= 8 ? null : kPasswordHint;
