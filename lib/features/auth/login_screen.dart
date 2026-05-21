import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/utils/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: isWide ? _WideLayout(state: this) : _NarrowLayout(state: this),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wordmark
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: AppRadius.sharp,
              ),
              child:
                  const Icon(Icons.inventory_2, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              'Ma5zony',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ]),
          const SizedBox(height: 32),
          Text('SIGN IN', style: AppTextStyles.eyebrow),
          const SizedBox(height: 8),
          Text('Welcome back', style: AppTextStyles.h1),
          const SizedBox(height: 6),
          Text(
            'Enter your credentials to continue.',
            style:
                AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Work email'),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              ),
            ),
            autofillHints: const [AutofillHints.password],
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              return null;
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _handleForgotPassword,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Forgot password?', style: AppTextStyles.bodySmall),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Don't have an account?",
                  style: AppTextStyles.bodySmall),
              const SizedBox(width: 2),
              TextButton(
                onPressed: () => context.go('/register'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Create account',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => context.push('/privacy'),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text('Privacy', style: AppTextStyles.bodySmall),
              ),
              Text(' · ',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSubdued)),
              TextButton(
                onPressed: () => context.push('/terms'),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text('Terms', style: AppTextStyles.bodySmall),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final appState = context.read<AppState>();
    final success = await appState.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.go('/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appState.authError ?? 'Login failed')),
      );
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first')),
      );
      return;
    }
    try {
      await context.read<AppState>().resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password reset email sent. Check your inbox.')),
        );
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not send reset email. Check the address and try again.')),
        );
      }
    }
  }
}

// ─── Wide (2-column) layout ────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final _LoginScreenState state;
  const _WideLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left 45%: brand panel — dark, editorial
        Flexible(
          flex: 45,
          child: Container(
            color: AppColors.sidebarBg,
            padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wordmark
                Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: AppRadius.sharp,
                    ),
                    child: const Icon(Icons.inventory_2,
                        color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ma5zony',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sidebarTextActive,
                    ),
                  ),
                ]),
                const Spacer(),
                // Editorial headline
                Text(
                  'INVENTORY INTELLIGENCE',
                  style: AppTextStyles.eyebrow.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Stop stockouts.\nForecast demand.\nGrow profit.',
                  style: AppTextStyles.display.copyWith(
                    color: AppColors.sidebarTextActive,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'The inventory intelligence platform built for growing SMEs. '
                  'Know what to order, when to order, and exactly how much.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.sidebarText,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 36),
                // Feature pills
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _FeaturePill('Demand forecasting'),
                    _FeaturePill('ABC-XYZ classification'),
                    _FeaturePill('Shopify sync'),
                    _FeaturePill('Purchase orders'),
                    _FeaturePill('Manufacturing workflow'),
                  ],
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        // Right 55%: form panel
        Flexible(
          flex: 55,
          child: Container(
            color: AppColors.canvas,
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: state._buildForm(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final String label;
  const _FeaturePill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.sidebarBgHover,
        borderRadius: AppRadius.pill,
        border: Border.all(color: AppColors.sidebarAccent),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.sidebarText,
        ),
      ),
    );
  }
}

// ─── Narrow (single-column) layout ────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final _LoginScreenState state;
  const _NarrowLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: state._buildForm(context),
        ),
      ),
    );
  }
}

