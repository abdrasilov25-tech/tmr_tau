import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class ConnectedAccountsPage extends StatefulWidget {
  const ConnectedAccountsPage({super.key});

  @override
  State<ConnectedAccountsPage> createState() => _ConnectedAccountsPageState();
}

class _ConnectedAccountsPageState extends State<ConnectedAccountsPage> {
  final _phoneController = TextEditingController();
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We only need current auth state to drive the OTP step.
    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Подключенные аккаунты'),
        centerTitle: true,
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
          if (state is AuthAuthenticated) {
            // After successfully adding/connecting an account, just return.
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.pop();
          }
        },
        builder: (context, state) {
          final authLoading = state is AuthLoading;
          final smsState = state is AuthSmsOtpSent ? state : null;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.g_mobiledata_outlined),
                  title: const Text('Google'),
                  trailing: authLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: authLoading
                      ? null
                      : () => context
                          .read<AuthBloc>()
                          .add(const AuthSignInWithGoogleRequested()),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.apple_outlined),
                  title: const Text('Apple'),
                  trailing: authLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: authLoading
                      ? null
                      : () => context
                          .read<AuthBloc>()
                          .add(const AuthSignInWithAppleRequested()),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Телефон (SMS OTP)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (smsState == null) ...[
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Номер телефона',
                            hintText: '+77001234567',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: authLoading
                              ? null
                              : () {
                                  final phone = _phoneController.text.trim();
                                  if (phone.isEmpty) return;
                                  context
                                      .read<AuthBloc>()
                                      .add(AuthSignInWithSmsOtpRequested(
                                        phone: phone,
                                      ));
                                },
                          child: const Text('Отправить код'),
                        ),
                      ] else ...[
                        Text(
                          'Код отправлен на: ${smsState.phone}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _tokenController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Код из SMS',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: authLoading
                              ? null
                              : () {
                                  final phone = smsState.phone;
                                  final token = _tokenController.text.trim();
                                  if (token.isEmpty) return;
                                  context.read<AuthBloc>().add(
                                        AuthVerifySmsOtpRequested(
                                          phone: phone,
                                          token: token,
                                        ),
                                      );
                                },
                          child: const Text('Подтвердить'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: authLoading
                              ? null
                              : () {
                                  _phoneController.clear();
                                  _tokenController.clear();
                                  // We can't force-auth state reset here; user can resend.
                                  // UI will update after another AuthSmsOtpSent.
                                },
                          child: const Text('Отправить код ещё раз'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

