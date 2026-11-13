import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'auth_screens.dart';

/// The account's round picture: the uploaded one, else the username's first
/// letter on a colour from the username; a person icon when signed out.
class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(accountStateProvider).value;
    if (state is! SignedIn) {
      return SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.person_outline_rounded,
          size: size * 0.8,
          color: colors.text,
        ),
      );
    }
    final profile = state.profile;
    return PersonAvatar(
      name: profile.username,
      url: profile.avatarUrl,
      size: size,
      imageKey: const Key('account.avatar.image'),
    );
  }
}

/// A person's round picture: [url], else [name]'s first letter on a colour
/// from the name (also when the picture fails to load).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    required this.name,
    required this.url,
    required this.size,
    this.imageKey,
    super.key,
  });

  final String name;
  final String? url;
  final double size;

  /// The picture's key, when there is one.
  final Key? imageKey;

  @override
  Widget build(BuildContext context) {
    final initial = _Initial(username: name, size: size);
    final url = this.url;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: url == null
            ? initial
            : Image.network(
                url,
                key: imageKey,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorBuilder: (_, _, _) => initial,
              ),
      ),
    );
  }
}

/// The username's first letter on its colour.
class _Initial extends StatelessWidget {
  const _Initial({required this.username, required this.size});

  final String username;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: avatarColor(username),
      child: Center(
        child: Text(
          username.isEmpty ? '?' : username.characters.first.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.45,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// A colour picked from [username]'s hash: the same name gets the same colour
/// on every device (FNV-1a, not `hashCode`, which may change between runs).
Color avatarColor(String username) {
  var hash = 0x811c9dc5;
  for (final unit in username.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.5, 0.42).toColor();
}

/// The account button (key `shell.account`): your avatar, opening your
/// profile; signed out, a person icon opening Log in.
class AccountButton extends ConsumerWidget {
  const AccountButton({this.push = false, super.key});

  /// Whether the profile opens on top of the current page (with Back), as
  /// from Home on a phone, rather than in its place.
  final bool push;

  static const double size = 28;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountStateProvider).value;
    return Tooltip(
      message: state is SignedIn ? state.profile.username : 'Log in',
      child: InkResponse(
        key: const Key('shell.account'),
        radius: size / 2 + 6,
        onTap: () => state is! SignedIn
            ? showAuthScreen(context, AuthStart.logIn)
            : push
            ? context.push('/profile')
            : context.go('/profile'),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: AccountAvatar(size: size),
        ),
      ),
    );
  }
}
