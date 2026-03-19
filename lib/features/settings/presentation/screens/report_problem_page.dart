import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../state/support_ticket_form_cubit.dart';

class ReportProblemPage extends StatefulWidget {
  const ReportProblemPage({super.key});

  @override
  State<ReportProblemPage> createState() => _ReportProblemPageState();
}

class _ReportProblemPageState extends State<ReportProblemPage> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Сообщить о проблеме')),
        body: const Center(child: Text('Войдите, чтобы отправить обращение')),
      );
    }

    return BlocProvider(
      create: (c) {
        final repo = SettingsRepositoryImpl(Supabase.instance.client);
        return SupportTicketFormCubit(repo, userId: userId);
      },
      child: BlocListener<SupportTicketFormCubit, SupportTicketFormState>(
        listener: (context, state) {
          if (state is SupportTicketFormSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Спасибо! Обращение отправлено')),
            );
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(true);
            }
          }
          if (state is SupportTicketFormFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: Scaffold(
          backgroundColor: ThemedContentSurface.scaffold,
          appBar: AppBar(
            title: const Text('Сообщить о проблеме'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Тема',
                          hintText: 'Коротко о проблеме',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descController,
                        minLines: 6,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          labelText: 'Описание',
                          hintText: 'Что произошло? Когда? Как воспроизвести?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      BlocBuilder<SupportTicketFormCubit, SupportTicketFormState>(
                        builder: (context, state) {
                          final isSubmitting =
                              state is SupportTicketFormSubmitting;
                          return FilledButton(
                            onPressed: isSubmitting
                                ? null
                                : () {
                                    context
                                        .read<SupportTicketFormCubit>()
                                        .submit(
                                          title: _titleController.text,
                                          description: _descController.text,
                                        );
                                  },
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Отправить'),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Мы используем это обращение только для поддержки пользователей.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

