// lib/main.dart
//
// Boot order is deliberate:
//
//   consent gate  →  sign-in  →  shell
//
// The gate comes first because the Terms govern installation and use of the
// software itself, not just the clinical workflow. A user who has not accepted
// must not reach a screen that names the study, the hospital, or any patient.
//
// The gate is re-entered automatically whenever `kAgreementVersion` changes or
// consent has been withdrawn — `ConsentStore.hasValidConsent()` checks both.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/design/theme.dart';
import 'core/design/tokens.dart';
import 'data/local/consent_store.dart';
import 'data/local/stores.dart';
import 'features/auth/login_screen.dart';
import 'features/consent/consent_gate_screen.dart';
import 'features/shell.dart';
import 'state/controllers.dart';

/// Keep in step with `version:` in pubspec.yaml. Recorded on every acceptance.
const String kAppVersion = '1.0.0+1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  final consented = await ConsentStore.hasValidConsent();
  final signedIn = consented && await SecureStore.hasSession();

  runApp(ClinAnxApp(consented: consented, signedIn: signedIn));
}

class ClinAnxApp extends StatefulWidget {
  final bool consented;
  final bool signedIn;

  const ClinAnxApp({
    super.key,
    required this.consented,
    required this.signedIn,
  });

  @override
  State<ClinAnxApp> createState() => _ClinAnxAppState();
}

class _ClinAnxAppState extends State<ClinAnxApp> {
  late bool _consented = widget.consented;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RosterController()..init(),
      child: MaterialApp(
        title: 'ClinAnx',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
          child: ColoredBox(color: Ds.canvas, child: child!),
        ),
        home: !_consented
            ? ConsentGateScreen(
                appVersion: kAppVersion,
                onAccepted: () => setState(() => _consented = true),
              )
            : (widget.signedIn ? const AppShell() : const LoginScreen()),
      ),
    );
  }
}
