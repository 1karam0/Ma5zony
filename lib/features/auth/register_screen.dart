import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/services/backend_api_service.dart';
import 'package:ma5zony/utils/constants.dart';

class RegisterScreen extends StatefulWidget {
  /// When non-null, the screen operates in "accept invite" mode:
  /// the role is locked to Inventory Manager and the email is pre-filled.
  final String? inviteToken;

  const RegisterScreen({super.key, this.inviteToken});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  String _selectedRole = 'Inventory Manager';
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  // Invite-mode state
  bool _inviteLoading = false;
  String? _inviteError;
  String? _ownerName;

  bool get _isInviteMode => widget.inviteToken != null;

  @override
  void initState() {
    super.initState();
    if (_isInviteMode) {
      _validateInvite();
    }
  }

  Future<void> _validateInvite() async {
    setState(() => _inviteLoading = true);
    try {
      final data = await BackendApiService().validateInvite(widget.inviteToken!);
      if (!mounted) return;
      setState(() {
        _emailController.text = data['email'] as String;
        _ownerName = data['ownerName'] as String?;
        _selectedRole = 'Inventory Manager';
        _inviteLoading = false;
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _inviteError = e.statusCode == 410
            ? 'This invitation has expired. Ask the owner to send a new one.'
            : 'Invalid invitation link. Please check the link and try again.';
        _inviteLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _inviteError = 'Could not validate invitation. Check your connection.';
        _inviteLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(32),
            child: _inviteLoading
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _inviteError != null
                    ? _InviteErrorView(
                        message: _inviteError!,
                        onBack: () => context.go('/login'),
                      )
                    : Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isInviteMode
                                  ? 'Accept Invitation'
                                  : 'Create Account',
                              style: AppTextStyles.h1,
                              textAlign: TextAlign.center,
                            ),
                            if (_isInviteMode && _ownerName != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.group_add,
                                        color: AppColors.primary, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$_ownerName has invited you to join their team as an Inventory Manager.',
                                        style: AppTextStyles.body.copyWith(
                                            fontSize: 13,
                                            color: AppColors.primary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (!_isInviteMode) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _RoleCard(
                                      title: 'SME Owner',
                                      icon: Icons.business,
                                      isSelected: _selectedRole == 'SME Owner',
                                      onTap: () => setState(
                                          () => _selectedRole = 'SME Owner'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _RoleCard(
                                      title: 'Inventory Manager',
                                      icon: Icons.inventory,
                                      isSelected:
                                          _selectedRole == 'Inventory Manager',
                                      onTap: () => setState(() =>
                                          _selectedRole = 'Inventory Manager'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                            ],
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Name is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              readOnly: _isInviteMode,
                              decoration: InputDecoration(
                                labelText: 'Email',
                                border: const OutlineInputBorder(),
                                prefixIcon:
                                    const Icon(Icons.email_outlined),
                                filled: _isInviteMode,
                                fillColor: _isInviteMode
                                    ? AppColors.border.withValues(alpha: 0.3)
                                    : null,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Email is required';
                                }
                                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(v.trim())) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Password is required';
                                }
                                if (v.length < 6) {
                                  return 'Must be at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Confirm Password',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (v) {
                                if (v != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleRegister,
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(_isInviteMode
                                      ? 'Accept & Create Account'
                                      : 'Create Account'),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("Already have an account?"),
                                TextButton(
                                  onPressed: () => context.go('/login'),
                                  child: const Text('Sign In'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final appState = context.read<AppState>();
    final success = await appState.register(
      _nameController.text,
      _emailController.text,
      _passwordController.text,
      _isInviteMode ? 'Inventory Manager' : _selectedRole,
    );
    if (!mounted) return;

    if (success && _isInviteMode) {
      // Link the new account to the owner via the invite token
      try {
        await BackendApiService().acceptInvite(widget.inviteToken!);
      } catch (_) {
        // Non-fatal — the user is registered but ownerId wasn't set.
        // They can still use the app; the owner can re-invite if needed.
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success && mounted) {
      context.go('/dashboard');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text(appState.authError ?? 'Registration failed')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}

class _InviteErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onBack;

  const _InviteErrorView({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.link_off, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text('Invalid Invitation', style: AppTextStyles.h1,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: onBack,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.white,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: AppTextStyles.body.copyWith(
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

