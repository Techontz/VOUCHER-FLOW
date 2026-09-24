// Company branding: the interface palettes and the company profile the
// branding screen edits.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouchflow/app/core/theme.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/models.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('offers the same four palettes as the web, blue for anything else', () {
    expect(VfAccentPalette.all.map((p) => p.key), [
      'blue',
      'emerald',
      'violet',
      'rose',
    ]);
    expect(VfAccentPalette.of('violet'), VfAccentPalette.violet);
    expect(VfAccentPalette.of('neon'), VfAccentPalette.blue);
    expect(VfAccentPalette.of(null), VfAccentPalette.blue);
  });

  test('button ink stays readable on every palette', () {
    for (final p in VfAccentPalette.all) {
      expect(
        _contrast(VfColors.accentInk, p.solid),
        greaterThanOrEqualTo(4.5),
        reason: '${p.key} button',
      );
      expect(
        _contrast(p.onLight, VfColors.lightBg),
        greaterThanOrEqualTo(3.0),
        reason: '${p.key} accent on light',
      );
      expect(
        _contrast(p.onDark, VfColors.bg),
        greaterThanOrEqualTo(4.5),
        reason: '${p.key} accent on dark',
      );
    }
  });

  test('the themes follow the chosen palette', () {
    addTearDown(() => VfColors.palette = VfAccentPalette.blue);
    VfColors.palette = VfAccentPalette.emerald;
    expect(VfTheme.dark().colorScheme.primary, VfAccentPalette.emerald.onDark);
    expect(
      VfTheme.light().colorScheme.primary,
      VfAccentPalette.emerald.onLight,
    );
  });

  test('a company without color_theme reads as blue', () {
    final company = Company.fromJson({'id': 1, 'name': 'Acme'});
    expect(company.colorTheme, 'blue');
  });

  test('a user without a stored theme reads as dark', () {
    final user = AppUser.fromJson({
      'id': 1,
      'name': 'A',
      'email': 'a@b.c',
      'role': 'employee',
    });
    expect(user.theme, 'dark');
  });

  test('saving the company profile changes what the session sees', () async {
    final api = MockApi();
    await api.handle(
      'POST',
      '/auth/login',
      body: {'email': 'admin@watercom.test', 'password': 'Password123!'},
    );

    await api.handle(
      'PUT',
      '/company',
      body: {'color_theme': 'rose', 'bank_branch': 'Mlimani Branch'},
    );

    final me = await api.handle('GET', '/auth/me') as Map<String, dynamic>;
    final company = Company.fromJson(me['company'] as Map<String, dynamic>);
    expect(company.colorTheme, 'rose');
    expect(company.bankBranch, 'Mlimani Branch');

    // The fixture's company is shared; put it back for other tests.
    await api.handle(
      'PUT',
      '/company',
      body: {'color_theme': 'blue', 'bank_branch': 'Tower Branch'},
    );
  });
}
