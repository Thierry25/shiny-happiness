import 'package:flutter/material.dart' show BuildContext, ModalRoute;

extension GetArgument on BuildContext {
  T? getArgument<T>() {
    final modalRoute = ModalRoute.of(this);
    if (modalRoute != null) {
      // get arguments passed from a view to another
      final args = modalRoute.settings.arguments;
      if (args != null && args is T) {
        return args as T;
      }
      return null;
    }
    return null;
  }
}
