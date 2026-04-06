import 'package:flutter/material.dart';
import 'package:tmr_tau/l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/go_router_pop_safe.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/post_reports_repository_impl.dart';
import '../../state/post_report_form_cubit.dart';
import '../widgets/report_reason_picker.dart';

class ReportPostPage extends StatefulWidget {
  const ReportPostPage({super.key, required this.postId});

  final String postId;

  @override
  State<ReportPostPage> createState() => _ReportPostPageState();
}

class _ReportPostPageState extends State<ReportPostPage> {
  final _commentController = TextEditingController();
  String _selectedReason = 'spam';

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final reporterId = authState is AuthAuthenticated ? authState.user.id : null;

    if (reporterId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Пожаловаться'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Войдите, чтобы отправить жалобу'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/login'),
                child: const Text('Войти'),
              ),
            ],
          ),
        ),
      );
    }

    return BlocProvider<PostReportFormCubit>(
      create: (c) {
        final repo = PostReportsRepositoryImpl(Supabase.instance.client);
        return PostReportFormCubit(repo);
      },
      child: BlocListener<PostReportFormCubit, PostReportFormState>(
        listener: (context, state) {
          if (state is PostReportFormSuccess) {
            context.popOrGoHomeFeed(true);
          } else if (state is PostReportFormFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: Scaffold(
          backgroundColor: ThemedContentSurface.scaffold,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => context.popOrGoHomeFeed(),
            ),
            title: const Text('Пожаловаться'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                AppLocalizations.of(context)!.moderationReportHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ThemedContentSurface.profileTextSecondary,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: ThemedContentSurface.profileCardDecoration(radius: 18),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReportReasonPicker(
                        selectedReason: _selectedReason,
                        onReasonChanged: (v) => setState(() => _selectedReason = v),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Комментарий (необязательно)',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _commentController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Опишите, что именно нарушено',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      BlocBuilder<PostReportFormCubit, PostReportFormState>(
                        builder: (context, state) {
                          final isSubmitting = state is PostReportFormSubmitting;
                          return SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () {
                                      context.read<PostReportFormCubit>().submit(
                                            postId: widget.postId,
                                            reporterId: reporterId,
                                            reason: _selectedReason,
                                            comment: _commentController.text,
                                          );
                                    },
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: AppLoading(),
                                    )
                                  : const Text('Отправить жалобу'),
                            ),
                          );
                        },
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

