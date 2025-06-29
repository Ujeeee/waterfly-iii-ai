import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waterflyiii/auth.dart';
import 'package:waterflyiii/pages/ai_receipt_parser.dart';
import 'package:waterflyiii/pages/transaction.dart';

class NewTransactionFab extends StatefulWidget {
  const NewTransactionFab({super.key, required this.context, this.accountId});

  final BuildContext context;
  final String? accountId;

  @override
  State<NewTransactionFab> createState() => _NewTransactionFabState();
}

class _NewTransactionFabState extends State<NewTransactionFab> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // AI Transaction FAB
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: OpenContainer(
            openBuilder: (BuildContext context, Function closedContainer) {
              return AiReceiptParserPage(accountId: widget.accountId);
            },
            openColor: Theme.of(context).cardColor,
            closedColor: Theme.of(context).colorScheme.secondaryContainer,
            closedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16.0)),
            ),
            closedElevation: 6,
            closedBuilder: (BuildContext context, Function openContainer) {
              return FloatingActionButton(
                onPressed: () => openContainer(),
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onSecondaryContainer,
                heroTag: "aiTransaction",
                child: const Icon(Icons.smart_toy),
              );
            },
            onClosed: (bool? refresh) {
              if (refresh ?? false == true) {
                if (context.mounted) {
                  context.read<FireflyService>().transStock!.clear();
                }
              }
            },
          ),
        ),

        // Main Transaction FAB
        OpenContainer(
          openBuilder: (BuildContext context, Function closedContainer) {
            return TransactionPage(accountId: widget.accountId);
          },
          openColor: Theme.of(context).cardColor,
          closedColor: Theme.of(context).colorScheme.primaryContainer,
          closedShape: Theme.of(context).floatingActionButtonTheme.shape ??
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16.0)),
              ),
          closedElevation:
              Theme.of(context).floatingActionButtonTheme.elevation ?? 6,
          closedBuilder: (BuildContext context, Function openContainer) {
            return FloatingActionButton(
              onPressed: () => openContainer(),
              heroTag: "mainTransaction",
              child: const Icon(Icons.add),
            );
          },
          onClosed: (bool? refresh) {
            if (refresh ?? false == true) {
              if (context.mounted) {
                context.read<FireflyService>().transStock!.clear();
              }
            }
          },
        ),
      ],
    );
  }
}
