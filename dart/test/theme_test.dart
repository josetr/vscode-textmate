import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  test('Theme matching gives higher priority to deeper matches', () {
    final theme = Theme.createFromRawTheme(
      RawTheme(
        settings: <RawThemeSetting>[
          RawThemeSetting(
            settings: const RawThemeSettingData(
              foreground: '#100000',
              background: '#200000',
            ),
          ),
          RawThemeSetting(
            scope: 'punctuation.definition.string.begin.html',
            settings: const RawThemeSettingData(foreground: '#300000'),
          ),
          RawThemeSetting(
            scope: 'meta.tag punctuation.definition.string',
            settings: const RawThemeSettingData(foreground: '#400000'),
          ),
        ],
      ),
    );

    final actual = theme.match(
      ScopeStack.fromSegments(<String>[
        'punctuation.definition.string.begin.html',
      ]),
    );
    expect(theme.getColorMap()[actual!.foregroundId], '#300000');
  });

  test('Theme matching gives higher priority to parent matches', () {
    final theme = Theme.createFromRawTheme(
      RawTheme(
        settings: <RawThemeSetting>[
          RawThemeSetting(
            settings: const RawThemeSettingData(
              foreground: '#100000',
              background: '#200000',
            ),
          ),
          RawThemeSetting(
            scope: 'meta.tag entity',
            settings: const RawThemeSettingData(foreground: '#300000'),
          ),
          RawThemeSetting(
            scope: 'meta.selector.css entity.name.tag',
            settings: const RawThemeSettingData(foreground: '#400000'),
          ),
          RawThemeSetting(
            scope: 'entity',
            settings: const RawThemeSettingData(foreground: '#500000'),
          ),
        ],
      ),
    );

    final result = theme.match(
      ScopeStack.fromSegments(<String>[
        'text.html.cshtml',
        'meta.tag.structure.any.html',
        'entity.name.tag.structure.any.html',
      ]),
    );

    expect(theme.getColorMap()[result!.foregroundId], '#300000');
  });
}
