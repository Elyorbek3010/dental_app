import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/auth_controller.dart';
import '../theme/app_theme.dart';
import '../utils/error_localizer.dart';
import '../widgets/dental_logo.dart';
import '../widgets/dental_surfaces.dart';

/// Patient Registration Screen.
///
/// Collects exact backend fields:
/// - full_name (Ism va familiya)
/// - phone (Telefon raqam)
/// - password (Parol, min 8 characters)
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.authController,
  });

  final AuthController authController;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitRegister() async {
    widget.authController.clearError();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final success = await widget.authController.register(
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
    );

    if (success && mounted) {
      // Upon successful registration and auto-login, pop back or let AuthGate redirect
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } else if (!success && mounted && widget.authController.errorMessage != null) {
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizeError(widget.authController.errorMessage, l10n)),
          backgroundColor: context.dentalColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.authController.isLoading;
    final l10n = context.l10n;
    final colors = context.dentalColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.registerTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backTooltip,
          onPressed: () {
            widget.authController.clearError();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DentalWaveBackdrop(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            const DentalLogo(size: 48),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.registerHeading,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: colors.textPrimary,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.registerSubtitle,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Error Message Box
                          ListenableBuilder(
                            listenable: widget.authController,
                            builder: (context, _) {
                              final error = widget.authController.errorMessage;
                              if (error == null || error.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.errorSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colors.error.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: colors.error,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        localizeError(error, l10n),
                                        style: TextStyle(
                                          color: colors.error,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          // Full Name Field
                          TextFormField(
                            key: const Key('register_name_field'),
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: l10n.fullNameLabel,
                              hintText: l10n.fullNameHint,
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.fullNameRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Phone Field
                          TextFormField(
                            key: const Key('register_phone_field'),
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: l10n.phoneLabel,
                              hintText: l10n.phoneHint,
                              prefixIcon: const Icon(Icons.phone_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.phoneRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password Field
                          TextFormField(
                            key: const Key('register_password_field'),
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: l10n.passwordLabelWithMin,
                              hintText: l10n.newPasswordHint,
                              prefixIcon: const Icon(Icons.lock_outline),
                              helperText: l10n.passwordMinLengthHelper,
                              suffixIcon: IconButton(
                                key: const Key('register_password_toggle'),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return l10n.passwordRequired;
                              }
                              if (value.length < 8) {
                                return l10n.passwordMinLengthError;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 22),

                          // Submit Button
                          ElevatedButton(
                            key: const Key('register_submit_button'),
                            onPressed: isLoading ? null : _submitRegister,
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(l10n.registerButton),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Login Link
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        Text(
                          l10n.haveAccount,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                        GestureDetector(
                          key: const Key('register_to_login_link'),
                          onTap: isLoading
                              ? null
                              : () {
                                  widget.authController.clearError();
                                  Navigator.of(context).pop();
                                },
                          child: Text(
                            l10n.loginLink,
                            style: TextStyle(
                              color: colors.teal,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
