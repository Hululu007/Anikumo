import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/pages/about/about_page.dart';
import 'package:anikumo/pages/about/credits_page.dart';
import 'package:anikumo/pages/about/help_page.dart';
import 'package:anikumo/pages/my/my_controller.dart';

final aboutModule = createModule(
  path: '/about',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => AboutPage(
          onCheckUpdate: inject<MyController>().checkUpdate,
        ),
      )
      ..route('/credits', child: (context, state) => const CreditsPage())
      // Batch 276 (#65): built-in help.
      ..route('/help', child: (context, state) => const HelpPage());
  },
);
