import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../brand/brand_mark.dart';
import '../state/app_state.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../widgets/collection_view.dart' show libraryViewKey;
import '../widgets/look_picker.dart';
import 'import_screen.dart';

/// First run (onboarding) — Orbit §8.9.
///
/// Four steps: the mark, the controller, the library look, and the games
/// folder. The screen sits outside the shell, so it has no OS bar or rail;
/// the planet limb and the dots are the only chrome.
///
/// It is shown once, only while the library is empty and the person has not
/// finished (or dismissed) first run. Answering either button on the last
/// step stores [completeKey], so a later empty library is still the normal
/// library, not onboarding again.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.state,
    this.initialStep = 0,
  });

  /// Persisted setting that records a finished first run.
  static const completeKey = 'onboardingComplete';

  /// First-run is due when there are no games yet and it was never finished.
  static bool shouldShow(AppState state) =>
      state.games.isEmpty && state.settings[completeKey] != true;

  final AppState state;

  /// Step to open on. The capture harness and widget tests use later steps;
  /// production always starts at the mark.
  final int initialStep;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 4;

  late int _step;
  late String _look;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep.clamp(0, _stepCount - 1).toInt();
    final stored = widget.state.settings[libraryViewKey];
    _look = defaultLibraryLook;
    for (final look in libraryLooks) {
      if (look.value == stored) _look = look.value;
    }
  }

  void _goTo(int step) {
    if (!mounted) return;
    setState(() => _step = step.clamp(0, _stepCount - 1));
  }

  Future<void> _continue() async {
    if (_step < 2) {
      _goTo(_step + 1);
      return;
    }
    if (_step == 2) {
      await widget.state.setSetting(libraryViewKey, _look);
      if (!mounted) return;
      _goTo(3);
    }
  }

  /// "Not now": the empty library is the next screen, and first run is done.
  Future<void> _notNow() async {
    await widget.state.setSetting(OnboardingScreen.completeKey, true);
  }

  /// "Choose a folder": open Import, and record first run as answered even
  /// if the person backs out of the importer. Push first — completing first
  /// rebuilds the app underneath and unmounts this context.
  void _chooseFolder() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportScreen(state: widget.state),
      ),
    );
    unawaited(widget.state.setSetting(OnboardingScreen.completeKey, true));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= Tokens.bpCompact;
    final motion =
        widget.state.settings['motion'] != false &&
        !MediaQuery.disableAnimationsOf(context);

    if (wide) {
      return Scaffold(
        backgroundColor: Tokens.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(
              child: CustomPaint(painter: _FirstRunBackdrop()),
            ),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(child: _centredContent(true, motion)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 64,
              child: Center(
                child: _StepDots(index: _step, count: _stepCount),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Tokens.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: CustomPaint(painter: _FirstRunBackdrop()),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _content(false, motion)),
              _phoneFooter(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _content(bool wide, bool motion) {
    if (_step == 2 && !wide) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 82, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pick a look for your collection',
                    style: _titleStyle(false),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Switch any time in Settings or from the library header.',
                    style: _bodyStyle(false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            LookPicker(
              selected: _look,
              onSelected: (look) => setState(() => _look = look),
              phone: true,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: _centredContent(wide, motion)),
        ),
      ),
    );
  }

  Widget _centredContent(bool wide, bool motion) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wide ? 1160 : 680),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            switch (_step) {
              0 => _welcome(wide, motion),
              1 => _controller(wide),
              2 => _looks(wide),
              _ => _folder(wide),
            },
            if (wide) ...[const SizedBox(height: 44), _actions(wide: true)],
          ],
        ),
      ),
    );
  }

  Widget _welcome(bool wide, bool motion) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SweepingMark(height: wide ? 176 : 120, motion: motion),
        SizedBox(height: wide ? 16 : 14),
        BrandWordmark(height: wide ? 46 : 34, color: Colors.white),
        SizedBox(height: wide ? 28 : 22),
        Text(
          Tokens.taglineMain,
          textAlign: TextAlign.center,
          style: Tokens.display(
            size: wide ? 15 : 13,
            weight: FontWeight.w500,
            ls: 0.34 * (wide ? 15 : 13),
            color: Tokens.muted,
          ),
        ),
      ],
    );
  }

  Widget _controller(bool wide) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              radius: 0.62,
              colors: [
                Tokens.accent.withValues(alpha: 0.25),
                Tokens.accent.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
            border: Border.all(color: Tokens.accent.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Tokens.accent.withValues(alpha: 0.16),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Symbols.sportsEsports,
            size: 64,
            fill: 1,
            color: Tokens.text,
          ),
        ),
        SizedBox(height: wide ? 34 : 28),
        Text(
          'Controller connected',
          textAlign: TextAlign.center,
          style: _titleStyle(wide),
        ),
        SizedBox(height: wide ? 16 : 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 620 : 340),
          child: Text(
            'Ready when you are. Everything in ezCORE works from here. '
            'A mouse, keyboard or touch screen works too, whenever you '
            'reach for one.',
            textAlign: TextAlign.center,
            style: _bodyStyle(wide),
          ),
        ),
      ],
    );
  }

  Widget _looks(bool wide) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pick a look for your collection',
          textAlign: TextAlign.center,
          style: _titleStyle(wide),
        ),
        SizedBox(height: wide ? 28 : 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 640 : 342),
          child: Text(
            wide
                ? 'Same games, five ways to browse them. Switch any time '
                      'with the View button or in Settings.'
                : 'Switch any time in Settings or from the library header.',
            textAlign: TextAlign.center,
            style: _bodyStyle(wide),
          ),
        ),
        SizedBox(height: wide ? 28 : 20),
        LookPicker(
          selected: _look,
          onSelected: (look) => setState(() => _look = look),
        ),
      ],
    );
  }

  Widget _folder(bool wide) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Where are your games?',
          textAlign: TextAlign.center,
          style: _titleStyle(wide),
        ),
        SizedBox(height: wide ? 16 : 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 640 : 340),
          child: Text(
            'Pick one folder and ezCORE keeps an eye on it. No account, '
            'no internet, nothing leaves this device.',
            textAlign: TextAlign.center,
            style: _bodyStyle(wide),
          ),
        ),
      ],
    );
  }

  Widget _phoneFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actions(wide: false),
          const SizedBox(height: 20),
          _StepDots(index: _step, count: _stepCount),
        ],
      ),
    );
  }

  Widget _actions({required bool wide}) {
    final primaryLabel = switch (_step) {
      0 => 'Get started',
      1 || 2 => 'Continue',
      _ => 'Choose a folder',
    };
    if (_step == 3) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (wide)
            _FirstRunButton(
              label: primaryLabel,
              height: 58,
              autofocus: true,
              onTap: _chooseFolder,
            )
          else
            Expanded(
              flex: 3,
              child: _FirstRunButton(
                label: primaryLabel,
                height: 56,
                autofocus: true,
                onTap: _chooseFolder,
              ),
            ),
          const SizedBox(width: 12),
          if (wide)
            _FirstRunButton(
              label: 'Not now',
              height: 58,
              primary: false,
              onTap: _notNow,
            )
          else
            Expanded(
              flex: 2,
              child: _FirstRunButton(
                label: 'Not now',
                height: 56,
                primary: false,
                onTap: _notNow,
              ),
            ),
        ],
      );
    }
    return SizedBox(
      width: wide ? null : double.infinity,
      child: _FirstRunButton(
        label: primaryLabel,
        height: wide ? 58 : 56,
        autofocus: true,
        onTap: _continue,
      ),
    );
  }

  TextStyle _titleStyle(bool wide) {
    final size = wide ? 48.0 : 30.0;
    return Tokens.display(
      size: size,
      weight: FontWeight.w600,
      ls: -0.03 * size,
      height: 1.05,
      color: Colors.white,
    );
  }

  TextStyle _bodyStyle(bool wide) => Tokens.body(
    size: wide ? 18 : 15,
    color: Tokens.muted,
    height: wide ? 1.55 : 1.6,
  );
}

/// The primary / secondary buttons on first run.
class _FirstRunButton extends StatefulWidget {
  const _FirstRunButton({
    required this.label,
    required this.onTap,
    required this.height,
    this.primary = true,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onTap;
  final double height;
  final bool primary;
  final bool autofocus;

  @override
  State<_FirstRunButton> createState() => _FirstRunButtonState();
}

class _FirstRunButtonState extends State<_FirstRunButton> {
  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;

  OrbitButtonState get _state {
    if (_pressed) return OrbitButtonState.pressed;
    if (_hover || _focus) return OrbitButtonState.hover;
    return OrbitButtonState.rest;
  }

  void _activate() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        onShowFocusHighlight: (value) => setState(() => _focus = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _activate,
          child: AnimatedScale(
            scale: _pressed && !reduce ? Tokens.buttonPressScale : 1,
            duration: reduce ? Duration.zero : Tokens.instantDur,
            curve: Tokens.ease,
            child: AnimatedContainer(
              height: widget.height,
              duration: reduce ? Duration.zero : Tokens.fastDur,
              curve: Tokens.ease,
              padding: const EdgeInsets.symmetric(horizontal: 26),
              decoration: widget.primary
                  ? Tokens.primaryButton(state: _state)
                  : Tokens.secondaryButton(state: _state),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Transform.translate(
                      offset: const Offset(0, -2),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: 17,
                          weight: FontWeight.w600,
                          color: widget.primary ? Colors.white : Tokens.text,
                          height: null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Four dots; the current step is a 24 px pill (`§8.9`).
class _StepDots extends StatelessWidget {
  const _StepDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 2),
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AnimatedContainer(
                  key: Key('step-dot-$i'),
                  duration: reduce ? Duration.zero : Tokens.ambientDur,
                  curve: Tokens.ease,
                  width: i == index ? 24 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == index ? Tokens.accent : const Color(0x33DDE6F4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The brand mark with a light band travelling across it.
class _SweepingMark extends StatefulWidget {
  const _SweepingMark({required this.height, required this.motion});

  final double height;
  final bool motion;

  @override
  State<_SweepingMark> createState() => _SweepingMarkState();
}

class _SweepingMarkState extends State<_SweepingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.motion) _sweep.repeat();
  }

  @override
  void didUpdateWidget(_SweepingMark old) {
    super.didUpdateWidget(old);
    if (widget.motion == old.motion) return;
    if (widget.motion) {
      _sweep.repeat();
    } else {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, _) {
          final t = _sweep.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              BrandMark(height: widget.height, color: Colors.white),
              if (widget.motion)
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment(-1.8 + 3.6 * t, -0.9),
                    end: Alignment(-0.9 + 3.6 * t, 0.9),
                    colors: const [
                      Color(0x00BFD8FF),
                      Color(0x99BFD8FF),
                      Color(0x00BFD8FF),
                    ],
                    stops: const [0.38, 0.5, 0.62],
                  ).createShader(rect),
                  child: ExcludeSemantics(
                    child: BrandMark(
                      height: widget.height,
                      color: Colors.white,
                      light: false,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The onboarding scene: the planet body and its lit limb, no stars, so the
/// four steps own the screen.
class _FirstRunBackdrop extends CustomPainter {
  const _FirstRunBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final centre = Offset(w / 2, h * 1.624);
    final radius = h * 0.85;

    Path limb() {
      final path = Path();
      for (var i = 0; i <= 96; i++) {
        final x = w * i / 96;
        final dx = x - centre.dx;
        final dy = math.sqrt(math.max(0, radius * radius - dx * dx));
        final point = Offset(x, centre.dy - dy);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      return path;
    }

    final arc = limb();

    // Haze above the limb, then the flat planet surface.
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 44
        ..color = Tokens.planetRim.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = Tokens.planetRim.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(centre, radius, Paint()..color = Tokens.planetBody);

    // The lit band just under the limb stays inside the body.
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: centre, radius: radius)),
    );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..color = Tokens.planetRim.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Tokens.planetRim.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Tokens.planetRim.withValues(alpha: 0.82),
    );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Tokens.planetRimHi.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(_FirstRunBackdrop oldDelegate) => false;
}
