import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ma5zony/utils/constants.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/login');
          }
        }),
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy Policy', style: AppTextStyles.h1),
              const SizedBox(height: 8),
              Text(
                'Last updated: April 2026',
                style: AppTextStyles.label,
              ),
              const SizedBox(height: 32),
              _Section(
                title: '1. Information We Collect',
                body: 'We collect information you provide directly to us, such as '
                    'when you create an account, add products, or connect integrations. '
                    'This includes your name, email address, business data (products, '
                    'orders, supplier information), and usage data.',
              ),
              _Section(
                title: '2. How We Use Your Information',
                body: 'We use your information to provide and improve Ma5zony, '
                    'process transactions, send you technical notices, and respond to '
                    'your requests. We do not sell your personal information to third parties.',
              ),
              _Section(
                title: '3. Data Storage',
                body: 'Your data is stored securely using Google Firebase services, '
                    'which are hosted on Google Cloud infrastructure. Data is encrypted '
                    'in transit and at rest.',
              ),
              _Section(
                title: '4. Shopify Integration',
                body: 'If you connect your Shopify store, we access product, inventory, '
                    'and order data via the Shopify API using OAuth 2.0. We only request '
                    'the minimum scopes necessary to provide the service. You may disconnect '
                    'at any time from the Integrations page.',
              ),
              _Section(
                title: '5. Data Retention',
                body: 'We retain your account data for as long as your account is active. '
                    'You may request deletion of your account and all associated data at '
                    'any time from the Settings page.',
              ),
              _Section(
                title: '6. Third-Party Services',
                body: 'Ma5zony uses the following third-party services:\n'
                    '• Google Firebase (Authentication, Firestore, Hosting)\n'
                    '• Shopify API (optional integration)\n'
                    '• Sentry (error monitoring, if configured)\n'
                    '\nEach service has its own privacy policy.',
              ),
              _Section(
                title: '7. Your Rights (GDPR)',
                body: 'If you are located in the European Economic Area, you have the right '
                    'to access, correct, or delete your personal data. To exercise these '
                    'rights, contact us at privacy@ma5zony.com.',
              ),
              _Section(
                title: '8. Contact',
                body: 'For privacy-related questions, contact us at privacy@ma5zony.com.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/login');
          }
        }),
        title: const Text('Terms of Service'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Terms of Service', style: AppTextStyles.h1),
              const SizedBox(height: 8),
              Text(
                'Last updated: April 2026',
                style: AppTextStyles.label,
              ),
              const SizedBox(height: 32),
              _Section(
                title: '1. Acceptance of Terms',
                body: 'By accessing or using Ma5zony, you agree to be bound by these '
                    'Terms of Service. If you do not agree to these terms, do not use '
                    'the service.',
              ),
              _Section(
                title: '2. Description of Service',
                body: 'Ma5zony is an inventory management and demand forecasting platform '
                    'designed for small and medium-sized businesses. We provide tools for '
                    'managing products, suppliers, purchase orders, and production workflows.',
              ),
              _Section(
                title: '3. User Accounts',
                body: 'You are responsible for maintaining the confidentiality of your '
                    'account credentials and for all activities that occur under your account. '
                    'You must provide accurate information when creating your account.',
              ),
              _Section(
                title: '4. Acceptable Use',
                body: 'You agree not to use Ma5zony to:\n'
                    '• Violate any applicable laws or regulations\n'
                    '• Infringe on the intellectual property rights of others\n'
                    '• Transmit any harmful, offensive, or illegal content\n'
                    '• Attempt to gain unauthorized access to the service or its systems',
              ),
              _Section(
                title: '5. Data Ownership',
                body: 'You retain full ownership of all data you enter into Ma5zony. '
                    'We do not claim any intellectual property rights over your business data.',
              ),
              _Section(
                title: '6. Limitation of Liability',
                body: 'Ma5zony is provided "as is" without warranties of any kind. '
                    'We are not liable for any indirect, incidental, or consequential damages '
                    'arising from your use of the service. Our total liability shall not '
                    'exceed the amount paid by you in the 12 months preceding the claim.',
              ),
              _Section(
                title: '7. Termination',
                body: 'You may terminate your account at any time from the Settings page. '
                    'We reserve the right to suspend or terminate accounts that violate '
                    'these terms.',
              ),
              _Section(
                title: '8. Changes to Terms',
                body: 'We may update these terms from time to time. We will notify you '
                    'of significant changes by email or in-app notification.',
              ),
              _Section(
                title: '9. Governing Law',
                body: 'These terms are governed by applicable law. Any disputes shall '
                    'be resolved through binding arbitration.',
              ),
              _Section(
                title: '10. Contact',
                body: 'For questions about these terms, contact us at legal@ma5zony.com.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.h3.copyWith(fontSize: 16)),
          const SizedBox(height: 8),
          Text(body,
              style: AppTextStyles.body.copyWith(
                height: 1.7,
                color: AppColors.textSecondary,
              )),
        ],
      ),
    );
  }
}
