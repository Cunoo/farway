// lib/auth/utils/auth_ui_helper.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

mixin AuthUiHelper<T extends StatefulWidget> on State<T> {
  bool isLoading_AuthUiHelper = false;

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> runAuthAction(
    Future<void> Function() action, {
    String? successMessage,
    bool popOnSuccess = false,
  }) async {
    setState(() => isLoading_AuthUiHelper = true);

    try {
      await action();
      if (successMessage != null) {
        showSuccess(successMessage);
      }
      if (popOnSuccess && mounted) {
        Navigator.pop(context);
      }
    } on AuthException catch (e) {
      showError(e.message);
    } catch (e) {
      showError('Nastala nečakaná chyba. Skontrolujte pripojenie.');
    } finally {
      if (mounted) {
        setState(() => isLoading_AuthUiHelper = false);
      }
    }
  }
}