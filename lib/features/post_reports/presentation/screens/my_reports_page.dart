import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repositories/post_reports_repository_impl.dart';
import '../../state/my_reports_cubit.dart';
import '../widgets/post_report_item.dart';
import '../widgets/report_bottom_skeleton.dart';

class MyReportsPage extends StatelessWidget {
  const MyReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final reporterId = authState is AuthAuthenticated ? authState.user.id : null;

    if (reporterId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Мои жалобы'),
        ),
        body: const Center(
          child: Text('Войдите, чтобы посмотреть ваши жалобы'),
        ),
      );
    }

    return BlocProvider<MyReportsCubit>(
      create: (c) {
        final repo = PostReportsRepositoryImpl(Supabase.instance.client);
        return MyReportsCubit(repo, reporterId: reporterId)..loadInitial();
      },
      child: const _MyReportsList(),
    );
  }
}

class _MyReportsList extends StatefulWidget {
  const _MyReportsList();

  @override
  State<_MyReportsList> createState() => _MyReportsListState();
}

class _MyReportsListState extends State<_MyReportsList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent - pos.pixels <= 300) {
      context.read<MyReportsCubit>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои жалобы'),
        centerTitle: true,
      ),
      body: BlocBuilder<MyReportsCubit, MyReportsState>(
        builder: (context, state) {
          if (state is MyReportsLoading || state is MyReportsInitial) {
            return const Center(child: AppLoading());
          }
          if (state is MyReportsFailure) {
            return AppErrorView(
              message: state.message,
              onRetry: () => context.read<MyReportsCubit>().loadInitial(),
            );
          }
          if (state is MyReportsSuccess) {
            final items = state.items;
            if (items.isEmpty) {
              return const Center(
                child: Text('Пока нет отправленных жалоб'),
              );
            }

            final showBottom = state.isLoadingMore && state.hasMore;
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length + (showBottom ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= items.length) {
                  return const ReportBottomSkeleton();
                }
                return PostReportItem(item: items[index]);
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

