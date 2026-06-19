import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/navigation_helper.dart';
import '../widgets/auth_ui.dart';
import 'login_page.dart';
import 'signup_page.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    const SizedBox(height: 108),
                    Image.asset(
                      'assets/images/2x/savlet_logo@2x.png',
                      height: 248,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Manage your money smarter',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AuthColors.muted,
                        letterSpacing: -0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    AuthAnimatedPrimaryButton(
                      label: 'Log In',
                      onPressed: () =>
                          NavigationHelper.push(context, const LoginPage()),
                    ),
                    const SizedBox(height: 12),
                    AuthAnimatedPrimaryButton(
                      label: 'Sign Up',
                      secondary: true,
                      delay: const Duration(milliseconds: 350),
                      onPressed: () =>
                          NavigationHelper.push(context, const SignUpPage()),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
