import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../account/username.dart';
import '../../core/log.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../shell/adaptive_shell.dart' show phoneBreakpoint;

/// Which screen the account screens open on.
enum AuthStart { signUp, logIn }

/// Opens the sign-up / log-in screens: a dialog on wide windows, a full page
/// on the root navigator on narrow ones (as the bug report form).
Future<void> showAuthScreen(BuildContext context, AuthStart start) {
  final screen = AuthScreen(start: start);
  if (MediaQuery.sizeOf(context).width >= phoneBreakpoint) {
    return showDialog<void>(
      context: context,
      // Cancel closes it; a stray tap must not drop what was typed.
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(child: screen),
        ),
      ),
    );
  }
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        body: SafeArea(child: SingleChildScrollView(child: screen)),
      ),
    ),
  );
}

enum _Step { signUp, logIn, confirm, forgot, reset }

/// Sign up, log in, the emailed code, forgot password and the new password,
/// one step at a time in one route.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({required this.start, super.key});

  final AuthStart start;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  late _Step _step = widget.start == AuthStart.signUp
      ? _Step.signUp
      : _Step.logIn;
  bool _busy = false;
  bool _usernameTaken = false;
  bool _showPassword = false;

  /// The code step came from sign-up, so confirming it sets the password
  /// and username typed there (still in their fields, in memory only).
  bool _fromSignUp = false;

  /// An action's failure, shown above the buttons.
  String? _error;

  /// A note about the current step, such as why the code is asked for.
  String? _note;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _emailOk => _email.text.trim().contains('@');
  bool get _codeOk => _code.text.trim().length == 6;

  bool get _canSubmit {
    if (_busy) return false;
    return switch (_step) {
      _Step.signUp =>
        _emailOk &&
            usernameProblem(normalizeUsername(_username.text)) == null &&
            !_usernameTaken &&
            passwordProblem(_password.text) == null,
      _Step.logIn => _emailOk && _password.text.isNotEmpty,
      _Step.confirm => _codeOk,
      _Step.forgot => _emailOk,
      _Step.reset => _codeOk && passwordProblem(_password.text) == null,
    };
  }

  void _go(_Step step, {String? note}) {
    setState(() {
      _step = step;
      _error = null;
      _note = note;
      if (step == _Step.confirm || step == _Step.reset) _code.clear();
      if (step == _Step.reset) _password.clear();
    });
  }

  /// Runs [action] with the buttons off; its failure shows inline.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.error.message);
    } catch (e) {
      AppLog.w('Account action failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = AccountError.unknown.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final service = ref.read(accountServiceProvider);
    final islands = Islands.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final email = _email.text;

    void signedIn({String? keptUsername}) {
      if (keptUsername == null) {
        islands.show('Signed in', kind: IslandKind.success);
      } else {
        islands.show(
          'Your account uses the username @$keptUsername. You can change it '
          'on your profile.',
          kind: IslandKind.info,
        );
      }
      // Only close our own route; never whatever is on top by now.
      if (route != null && route.isCurrent) {
        navigator.pop();
      } else if (route != null && route.isActive) {
        navigator.removeRoute(route);
      }
    }

    await _run(() async {
      switch (_step) {
        case _Step.signUp:
          final step = await service.signUp(
            email,
            _password.text,
            _username.text,
          );
          if (step == AuthStep.done) {
            signedIn();
          } else if (mounted) {
            _fromSignUp = true;
            _go(_Step.confirm);
          }
        case _Step.logIn:
          final step = await service.logIn(email, _password.text);
          if (step == AuthStep.done) {
            signedIn();
          } else if (mounted) {
            _fromSignUp = false;
            // A log-in sends no code; send one. If that's refused (too
            // many tries), the step still opens with the error.
            _go(_Step.confirm, note: AccountError.emailNotConfirmed.message);
            await service.resendSignup(email);
          }
        case _Step.confirm:
          final String? kept;
          try {
            kept = await service.verifySignup(
              email,
              _code.text,
              password: _fromSignUp ? _password.text : null,
              username: _fromSignUp ? _username.text : null,
            );
          } on PasswordNotSetException {
            // Confirmed but signed out again: log in with that password.
            if (mounted) {
              _fromSignUp = false;
              _go(_Step.logIn);
            }
            rethrow;
          }
          _fromSignUp = false;
          if (mounted) _password.clear();
          signedIn(keptUsername: kept);
        case _Step.forgot:
          await service.sendReset(email);
          if (mounted) _go(_Step.reset);
        case _Step.reset:
          try {
            await service.resetPassword(email, _code.text, _password.text);
          } on AccountException catch (e) {
            // The code was used up before the password was refused.
            if ((e.error == AccountError.samePassword ||
                    e.error == AccountError.weakPassword) &&
                mounted) {
              setState(() {
                _code.clear();
                _note = 'Send a new code, then try another password.';
              });
            }
            rethrow;
          }
          signedIn();
      }
    });
  }

  /// "Send a new code": the sign-up code on the confirm step, the reset
  /// code on the reset step.
  Future<void> _resend() async {
    final service = ref.read(accountServiceProvider);
    final email = _email.text;
    final step = _step;
    await _run(() async {
      if (step == _Step.reset) {
        await service.sendReset(email);
      } else {
        await service.resendSignup(email);
      }
      if (mounted) setState(() => _note = 'We sent a new code.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final email = _email.text.trim();
    final (title, intro, action) = switch (_step) {
      _Step.signUp => ('Sign up', null, 'Sign up'),
      _Step.logIn => ('Log in', null, 'Log in'),
      _Step.confirm => (
        'Confirm your email',
        'Enter the 6-digit code we sent to $email.',
        'Continue',
      ),
      _Step.forgot => (
        'Reset password',
        "Enter your account's email and we'll send you a code.",
        'Send code',
      ),
      _Step.reset => (
        'Choose a new password',
        'Enter the code we sent to $email and a new password.',
        'Continue',
      ),
    };
    final askEmail =
        _step == _Step.signUp || _step == _Step.logIn || _step == _Step.forgot;
    final askPassword = _step != _Step.confirm && _step != _Step.forgot;
    final askCode = _step == _Step.confirm || _step == _Step.reset;
    void changed(_) => setState(() {});

    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (intro != null) ...[
                const SizedBox(height: 8),
                Text(intro, style: TextStyle(color: colors.mutedText)),
              ],
              if (_note != null) ...[
                const SizedBox(height: 8),
                Text(_note!, style: TextStyle(color: colors.text)),
              ],
              const SizedBox(height: 16),
              if (askEmail) ...[
                TextField(
                  key: const Key('auth.email'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: _step == _Step.logIn
                      ? const [AutofillHints.email, AutofillHints.username]
                      : const [AutofillHints.email],
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: changed,
                ),
                const SizedBox(height: 12),
              ],
              if (_step == _Step.signUp) ...[
                UsernameField(
                  fieldKey: const Key('auth.username'),
                  controller: _username,
                  enabled: !_busy,
                  onChanged: () => setState(() {}),
                  onTaken: (taken) => setState(() => _usernameTaken = taken),
                ),
                const SizedBox(height: 12),
              ],
              if (askCode) ...[
                TextField(
                  key: const Key('auth.code'),
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: changed,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
              ],
              if (askPassword)
                TextField(
                  key: const Key('auth.password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: !_showPassword,
                  autofillHints: [
                    _step == _Step.logIn
                        ? AutofillHints.password
                        : AutofillHints.newPassword,
                  ],
                  decoration: InputDecoration(
                    labelText: _step == _Step.reset
                        ? 'New password'
                        : 'Password',
                    helperText: _step == _Step.logIn ? null : kPasswordHint,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      key: const Key('auth.showPassword'),
                      tooltip: _showPassword
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  onChanged: changed,
                  onSubmitted: (_) => _submit(),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('auth.error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                children: [
                  if (_step == _Step.signUp)
                    _Link(
                      key: const Key('auth.toLogIn'),
                      label: 'I have an account',
                      onPressed: _busy ? null : () => _go(_Step.logIn),
                    ),
                  if (_step == _Step.logIn) ...[
                    _Link(
                      key: const Key('auth.forgot'),
                      label: 'Forgot password?',
                      onPressed: _busy ? null : () => _go(_Step.forgot),
                    ),
                    _Link(
                      key: const Key('auth.toSignUp'),
                      label: 'Create an account',
                      onPressed: _busy ? null : () => _go(_Step.signUp),
                    ),
                  ],
                  if (_step == _Step.confirm || _step == _Step.reset)
                    _Link(
                      key: const Key('auth.resend'),
                      label: 'Send a new code',
                      onPressed: _busy ? null : _resend,
                    ),
                  if (_step == _Step.confirm)
                    _Link(
                      key: const Key('auth.differentEmail'),
                      label: 'Use a different email',
                      onPressed: _busy
                          ? null
                          : () => _go(
                              _Step.signUp,
                              note:
                                  'Your first sign-up holds that username for '
                                  'an hour. Pick another one, or try again '
                                  'later.',
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('auth.cancel'),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('auth.submit'),
                    onPressed: _canSubmit ? _submit : null,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(action),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: onPressed, child: Text(label));
}

/// A username field: shows the rule, and after a pause in typing asks the
/// server whether the name is free ("That username is taken."). [current]
/// (the user's own name, in any capitals) is never reported as taken.
class UsernameField extends ConsumerStatefulWidget {
  const UsernameField({
    required this.controller,
    required this.onTaken,
    this.onChanged,
    this.current,
    this.enabled = true,
    this.fieldKey,
    this.autofocus = false,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<bool> onTaken;

  /// Enter in the field.
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onChanged;
  final String? current;
  final bool enabled;
  final Key? fieldKey;
  final bool autofocus;

  /// How long typing must pause before the name is checked.
  static const checkDelay = Duration(milliseconds: 400);

  @override
  ConsumerState<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends ConsumerState<UsernameField> {
  Timer? _timer;
  bool _taken = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setTaken(bool taken) {
    if (_taken == taken) return;
    setState(() => _taken = taken);
    widget.onTaken(taken);
  }

  void _changed(String text) {
    _timer?.cancel();
    _setTaken(false);
    widget.onChanged?.call();
    final name = normalizeUsername(text);
    final current = widget.current;
    // Your own name in other capitals is yours, never taken.
    if (usernameProblem(name) != null ||
        (current != null && sameUsername(name, current))) {
      return;
    }
    _timer = Timer(UsernameField.checkDelay, () async {
      final service = ref.read(accountServiceProvider);
      try {
        final free = await service.usernameAvailable(name);
        // Only for what is still typed.
        if (!mounted || normalizeUsername(widget.controller.text) != name) {
          return;
        }
        _setTaken(!free);
      } catch (_) {
        // Offline or the like: the server checks again on submit.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = normalizeUsername(widget.controller.text);
    final broken = name.isNotEmpty && usernameProblem(name) != null;
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      autocorrect: false,
      autofillHints: const [AutofillHints.newUsername],
      inputFormatters: [LengthLimitingTextInputFormatter(20)],
      decoration: InputDecoration(
        labelText: 'Username',
        helperText: broken || _taken ? null : kUsernameHint,
        errorText: broken
            ? kUsernameHint
            : _taken
            ? AccountError.usernameTaken.message
            : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: _changed,
      onSubmitted: widget.onSubmitted,
    );
  }
}
