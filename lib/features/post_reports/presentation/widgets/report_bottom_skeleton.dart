import 'package:flutter/material.dart';

class ReportBottomSkeleton extends StatelessWidget {
  const ReportBottomSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: SizedBox(
          height: 100,
          child: Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

