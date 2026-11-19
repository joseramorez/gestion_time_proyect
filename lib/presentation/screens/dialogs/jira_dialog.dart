import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

Future<void> showJiraDialog(
  BuildContext context,
  JiraController jira,
  ProjectsController projects,
) => showFittedDialog<void>(
  context: context,
  builder: (_) => _JiraDialog(jira: jira, projects: projects),
);

class _JiraDialog extends StatefulWidget {
  const _JiraDialog({required this.jira, required this.projects});

  final JiraController jira;
  final ProjectsController projects;

  @override
  State<_JiraDialog> createState() => _JiraDialogState();
}

class _JiraDialogState extends State<_JiraDialog> {
  late final _clientId = TextEditingController(text: widget.jira.clientId);
  final _secret = TextEditingController();
  late bool _editing = !widget.jira.configured;

  JiraController get jira => widget.jira;

  @override
  void dispose() {
    _clientId.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: jira,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Jira'),
          content: AppDialogBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (jira.busy) const LinearProgressIndicator(),
                if (_editing || !jira.configured)
                  ..._credentialsForm()
                else if (!jira.signedIn)
                  ..._signedOut()
                else
                  ..._connected(),
                const SizedBox(height: AppSpacing.md),
                _callbackRow(),
                if (jira.error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(jira.error!, style: TextStyle(color: scheme.error)),
                ],
                if (jira.message != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(jira.message!),
                ],
              ],
            ),
          ),
          actions: _actions(context),
        );
      },
    );
  }

  bool _copied = false;
  String? _copyError;

  Future<void> _copyCallback() async {
    for (var i = 0; i < 5; i++) {
      try {
        await Clipboard.setData(
          const ClipboardData(text: JiraOAuth.defaultRedirectUri),
        );
        if (!mounted) return;
        setState(() {
          _copied = true;
          _copyError = null;
        });
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _copied = false);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    if (mounted) {
      setState(
        () =>
            _copyError = 'No se pudo copiar. Selecciona el texto y usa Ctrl+C.',
      );
    }
  }

  /// URL de callback que hay que registrar en la app de Atlassian. Siempre
  /// visible. El botón de copiar va junto al título y la URL debajo, a todo el
  /// ancho: si compartieran fila, en la ventana mínima la URL se partía en tres
  /// líneas.
  Widget _callbackRow() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'URL de callback para tu app de Atlassian',
              style: TextStyle(fontSize: AppFontSize.caption),
            ),
          ),
          TextButton.icon(
            onPressed: _copyCallback,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
            icon: Icon(_copied ? AppIcons.copied : AppIcons.copy, size: 16),
            label: Text(_copied ? 'Copiado' : 'Copiar'),
          ),
        ],
      ),
      const SelectableText(
        JiraOAuth.defaultRedirectUri,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: AppFontSize.caption,
        ),
      ),
      if (_copyError != null)
        Text(
          _copyError!,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
    ],
  );

  List<Widget> _credentialsForm() => [
    const Text(
      'Crea una app OAuth 2.0 (3LO) en developer.atlassian.com/console/myapps '
      'con los scopes read:jira-work y write:jira-work y la URL de callback de '
      'abajo. Para que otros usuarios puedan usarla, activa Sharing en Distribution:',
      style: TextStyle(fontSize: AppFontSize.label),
    ),
    const SizedBox(height: AppSpacing.sm),
    AppTextField(controller: _clientId, label: 'Client ID'),
    const SizedBox(height: AppSpacing.sm),
    AppTextField.secret(
      controller: _secret,
      label: 'Client Secret',
      helper: jira.configured ? 'Vacío = conservar el actual' : null,
    ),
    const SizedBox(height: AppSpacing.sm),
    Text(
      'Se guardan en el almacén seguro del sistema operativo. Si prefieres no '
      'escribirlas, compila la app con un archivo .env (ver docs/jira.md).',
      style: TextStyle(
        fontSize: AppFontSize.caption,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  ];

  /// Acciones secundarias (poco frecuentes). Van en el cuerpo y no entre los
  /// botones del pie para que allí solo estén "Cerrar" y la acción principal.
  ///
  /// "Credenciales" solo se ofrece si la compilación NO las trae: con un `.env` las
  /// credenciales ya están y no hay nada que cambiar desde aquí.
  Widget _secondaryActions({required bool signedIn}) {
    final buttons = <Widget>[
      if (!jira.hasBuildCredentials)
        TextButton(
          onPressed: jira.busy ? null : () => setState(() => _editing = true),
          child: const Text('Credenciales'),
        ),
      if (signedIn)
        TextButton(
          onPressed: jira.busy ? null : jira.signOut,
          child: const Text('Cerrar sesión'),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(spacing: AppSpacing.xs, children: buttons),
    );
  }

  /// Aviso de que las credenciales vienen incluidas en esta compilación.
  Widget _buildCredentialsNote() => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      'Las credenciales de la app vienen incluidas en esta compilación.',
      style: TextStyle(
        fontSize: AppFontSize.caption,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  List<Widget> _signedOut() => [
    const Text(
      'Se abrirá tu navegador para iniciar sesión en '
      'Atlassian. Solo se traen las tareas asignadas a tu usuario.',
    ),
    if (jira.hasBuildCredentials) _buildCredentialsNote(),
    _secondaryActions(signedIn: false),
  ];

  List<Widget> _connected() {
    final s = jira.session!;
    return [
      Text('Conectado a ${s.site.name}'),
      if (!s.canWrite) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Falta el permiso para registrar tiempo en Jira. Cierra sesión e '
          'inicia de nuevo para concederlo.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: AppFontSize.label,
          ),
        ),
      ],
      if (s.sites.length > 1)
        DropdownButton<String>(
          isExpanded: true,
          value: s.siteId,
          items: [
            for (final site in s.sites)
              DropdownMenuItem(value: site.id, child: Text(site.name)),
          ],
          onChanged: jira.busy
              ? null
              : (id) => id == null ? null : jira.selectSite(id),
        ),
      if (jira.hasBuildCredentials) _buildCredentialsNote(),
      _secondaryActions(signedIn: true),
    ];
  }

  /// "Cerrar" va siempre, en todos los estados del diálogo: el resto de botones son
  /// acciones y sin él no habría una salida evidente. No se desactiva con
  /// `jira.busy`: si el inicio de sesión espera al navegador, se puede cerrar el
  /// diálogo y la operación sigue en segundo plano.
  Widget _closeButton(BuildContext context) => TextButton(
    onPressed: () => Navigator.pop(context),
    child: const Text('Cerrar'),
  );

  List<Widget> _actions(BuildContext context) {
    if (_editing || !jira.configured) {
      return [
        _closeButton(context),
        if (jira.configured)
          TextButton(
            onPressed: () => setState(() => _editing = false),
            child: const Text('Cancelar'),
          ),
        FilledButton(
          onPressed: () async {
            if (_clientId.text.trim().isEmpty) return;
            await jira.saveCredentials(_clientId.text, _secret.text);
            if (!mounted) return;
            _secret.clear();
            setState(() => _editing = !jira.configured);
          },
          child: const Text('Guardar'),
        ),
      ];
    }
    return [
      _closeButton(context),
      if (jira.signedIn)
        FilledButton(
          onPressed: jira.busy ? null : () => jira.sync(widget.projects),
          child: const Text('Sincronizar'),
        )
      else
        FilledButton(
          onPressed: jira.busy ? null : jira.signIn,
          child: const Text('Iniciar sesión'),
        ),
    ];
  }
}
