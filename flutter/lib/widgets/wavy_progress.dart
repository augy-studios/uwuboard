// A progress bar as Material 3 Expressive draws one, the way Android's own updater and apps in
// Material You do: the part done as a wave in the theme's primary colour, drifting, then a gap and
// the rest of the way flat in its secondary container colour, with a dot at the end. With no
// telling how far it's got (value null), a wavy stretch sweeps across instead. The same as
// sgbus-timings' WavyProgressView.java, to the same measures: a 4 px line, waves 40 px long and
// 3 px high (half as long while sweeping), flat near the start and the end. Keeps still with
// animations turned off.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WavyProgress extends StatefulWidget {
  const WavyProgress({super.key, this.value, this.label});

  /// 0 to 1, or null while there's no telling.
  final double? value;

  /// What a screen reader says it is, such as "Downloading".
  final String? label;

  @override
  State<WavyProgress> createState() {
    return _WavyProgressState();
  }
}

class _WavyProgressState extends State<WavyProgress> with SingleTickerProviderStateMixin {
  // How long a wave takes to drift by its own length, and the sweep to cross once.
  static const _driftMilliseconds = 1000;
  static const _sweepMilliseconds = 1800;

  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  double _phase = 0;
  double _sweep = 0;
  // Shown, chasing widget.value a little each frame, so a download's many small steps glide.
  double _shown = 0;

  /// The widget's value, or 0 while there's no telling.
  double _valueOrZero() {
    final value = widget.value;
    if (value != null) {
      return value;
    } else {
      return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _shown = _valueOrZero();
  }

  /// Stops the animation when the device asks for no animations, and starts it again when
  /// that's turned off.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.maybeDisableAnimationsOf(context);
    final bool still;
    if (disableAnimations != null) {
      still = disableAnimations;
    } else {
      still = false;
    }
    if (still && _ticker.isActive) {
      _ticker.stop();
      _shown = _valueOrZero();
    } else if (!still && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(WavyProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null || oldWidget.value == null || !_ticker.isActive) {
      _shown = _valueOrZero();
    }
  }

  /// Runs every frame: moves the wave along, moves the sweep along, and brings the shown
  /// amount a little closer to the real one.
  void _tick(Duration elapsed) {
    final milliseconds = elapsed.inMilliseconds;
    final step = (elapsed - _lastTick).inMicroseconds / 1000;
    _lastTick = elapsed;
    setState(() {
      _phase = 2 * math.pi * (milliseconds % _driftMilliseconds) / _driftMilliseconds;
      _sweep = (milliseconds % _sweepMilliseconds) / _sweepMilliseconds;
      final target = widget.value;
      if (target != null) {
        // A fifth of the way there every 30 ms or so, whatever the frame rate.
        final easing = 1 - math.pow(0.8, step / 30).toDouble();
        _shown = _shown + (target - _shown) * easing.clamp(0, 1);
        if ((target - _shown).abs() < 0.001) {
          _shown = target;
        }
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final value = widget.value;
    String? spokenValue;
    double? progress;
    if (value == null) {
      spokenValue = null;
      progress = null;
    } else {
      spokenValue = '${(value * 100).round()}%';
      progress = _shown.clamp(0, 1);
    }
    return Semantics(
      label: widget.label,
      value: spokenValue,
      child: SizedBox(
        height: _WavePainter.thickness + 2 * _WavePainter.amplitude,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(
            progress: progress,
            phase: _phase,
            sweep: _sweep,
            active: colorScheme.primary,
            track: colorScheme.secondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Draws the bar itself: the wavy part done, the flat track after it and the stop dot, or,
/// with no progress known, a wavy stretch sweeping across.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.progress, required this.phase, required this.sweep, required this.active, required this.track});
  final double? progress;
  final double phase;
  final double sweep;
  final Color active;
  final Color track;

  static const thickness = 4.0;
  static const amplitude = 3.0;
  static const wavelength = 40.0;
  static const gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    const half = thickness / 2;
    const left = half;
    final right = size.width - half;
    final centerY = size.height / 2;
    if (right <= left) {
      return;
    }
    final width = right - left;

    /// A round-ended stroke of the bar's thickness in [color].
    Paint linePaint(Color color) {
      final paint = Paint();
      paint.color = color;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = thickness;
      paint.strokeCap = StrokeCap.round;
      paint.strokeJoin = StrokeJoin.round;
      return paint;
    }

    final trackPaint = linePaint(track);

    final progressValue = progress;
    if (progressValue == null) {
      // A stretch 40% as long as the bar, its front easing in from the left and out past the
      // right, with the track either side of it.
      final eased = 0.5 - math.cos(math.pi * sweep) / 2;
      final head = left + width * 1.4 * eased;
      final tail = head - width * 0.4;
      final from = math.max(left, tail);
      final to = math.min(right, head);
      if (to > from) {
        _wave(canvas, from, to, centerY, amplitude, wavelength / 2, linePaint(active));
      }
      if (from - gap - thickness > left) {
        canvas.drawLine(Offset(left, centerY), Offset(from - gap - thickness, centerY), trackPaint);
      }
      if (to + gap + thickness < right) {
        canvas.drawLine(Offset(to + gap + thickness, centerY), Offset(right, centerY), trackPaint);
      }
      return;
    }

    final end = left + width * progressValue;
    // Flat at the very start and as it finishes, as Material's does.
    final waveAmplitude = amplitude * math.min(progressValue / 0.1, (1 - progressValue) / 0.05).clamp(0.0, 1.0);
    if (end > left) {
      _wave(canvas, left, end, centerY, waveAmplitude, wavelength, linePaint(active));
    }
    final double trackFrom;
    if (progressValue > 0) {
      trackFrom = end + gap + thickness;
    } else {
      trackFrom = left;
    }
    if (trackFrom < right) {
      canvas.drawLine(Offset(trackFrom, centerY), Offset(right, centerY), trackPaint);
    }
    // The stop dot at the end, till the wave reaches it.
    if (progressValue < 1) {
      final dotPaint = Paint();
      dotPaint.color = active;
      canvas.drawCircle(Offset(right, centerY), half, dotPaint);
    }
  }

  // A wave from x `from` to `to`, its phase fixed to the bar so it drifts rather than slides.
  void _wave(Canvas canvas, double from, double to, double centerY, double waveAmplitude, double length, Paint paint) {
    final path = Path();
    final step = math.max(1.0, length / 24);
    for (var x = from;; x = math.min(to, x + step)) {
      final y = centerY + waveAmplitude * math.sin(2 * math.pi * x / length - phase);
      if (x == from) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      if (x >= to) {
        break;
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.sweep != sweep ||
        oldDelegate.active != active ||
        oldDelegate.track != track;
  }
}
