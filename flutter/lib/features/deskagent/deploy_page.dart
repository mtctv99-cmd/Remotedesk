import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

const double _kIconSize = 72;
const double _kTitleFontSize = 20;
const double _kContentFontSize = 15;
const Color _kAccentColor = MyTheme.accent;

// Skeleton deploy page for DeskAgent.
//
// Future wiring notes:
// - The platform already registers the `android_needs_deploy` event handler
//   in main.dart (~line 568) which opens showDeployPromptDialog(); this page
//   will reuse that flow and the existing dialog in
//   lib/mobile/widgets/deploy_dialog.dart.
// - Workspace-level kOption* keys for deploy state will be added to
//   lib/consts.dart at wiring time; this skeleton only uses local _k*
//   constants.
class DeployPage extends StatefulWidget {
  const DeployPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeployPageState();
}

class _DeployPageState extends State<DeployPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Deploy')),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: _kIconSize,
              color: _kAccentColor,
            ),
            const SizedBox(height: 8),
            Text(
              translate('Deploy'),
              style: TextStyle(fontSize: _kTitleFontSize),
            ),
            // Reuses the deploy tip key from deploy_dialog.dart.
            Text(
              translate('server_requires_deployment_tip'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: _kContentFontSize),
            ),
          ],
        ),
      ),
    );
  }
}
