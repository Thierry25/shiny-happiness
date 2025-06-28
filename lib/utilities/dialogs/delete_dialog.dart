import 'package:flutter/material.dart';
import 'package:mynotes/utilities/dialogs/generic_dialog.dart';

Future<bool> showDeleteDialog(
  BuildContext context,
) {
  return showGenericDialog<bool>(
      context: context,
      title: 'Delete',
      content: 'Are you sure you want to delete this item?',
      optionsBuilder: () => {
            'Yes': true,
            'Cancel ': false,
          }).then((value) => value ?? false);
}
