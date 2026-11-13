// The site's own icons (main-site/js/icons.js, and the ones drawn inline in index.html and
// script.js), as the same SVG paths: no emoji, no icon font. viewBox 0 0 24 24, stroked in the
// colour of the words around them.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _paths = <String, String>{
  'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/>',
  'moon': '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
  'close': '<path d="M18 6 6 18M6 6l12 12"/>',
  'clock': '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/>',
  'sync': '<path d="M20 11a8 8 0 0 0-14.3-4.9L4 8"/><path d="M4 3v5h5"/><path d="M4 13a8 8 0 0 0 14.3 4.9L20 16"/><path d="M20 21v-5h-5"/>',
  'help': '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6"/><path d="M12 17.2v.1"/>',
  'download': '<path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
  'upload': '<path d="M12 15V3"/><path d="m7 8 5-5 5 5"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
  'file-export': '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-4"/><path d="M18 9V7l-4-4"/><path d="M14 3v4h4"/><path d="M9 12h12"/><path d="m18 9 3 3-3 3"/>',
  'file-import': '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-4"/><path d="M18 9V7l-4-4"/><path d="M14 3v4h4"/><path d="M21 12H9"/><path d="m12 9-3 3 3 3"/>',
  'kanban': '<rect x="3" y="4" width="5" height="14" rx="1.5"/><rect x="9.5" y="4" width="5" height="10" rx="1.5"/><rect x="16" y="4" width="5" height="6" rx="1.5"/>',
  'timeline': '<path d="M3 4v16"/><rect x="5" y="5" width="8" height="3.5" rx="1.5"/><rect x="9" y="10.25" width="9" height="3.5" rx="1.5"/><rect x="14" y="15.5" width="7" height="3.5" rx="1.5"/>',
  'trash': '<path d="M4 7h16"/><path d="M10 11v6M14 11v6"/><path d="M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12"/><path d="M9 7V4h6v3"/>',
  // Drawn inline on the site.
  'menu': '<path d="M4 7h16M4 12h16M4 17h16"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'pencil': '<path d="M16 4.5l3.5 3.5L8 19.5H4.5V16L16 4.5z"/>',
  'dots': '<circle cx="12" cy="5" r="1.2" fill="currentColor"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><circle cx="12" cy="19" r="1.2" fill="currentColor"/>',
  'chevron-left': '<path d="m15 5-7 7 7 7"/>',
  'chevron-right': '<path d="m9 5 7 7-7 7"/>',
  'chevron-down': '<path d="m5 9 7 7 7-7"/>',
  'chevron-up': '<path d="m5 15 7-7 7 7"/>',
  'logout': '<path d="M9 3H5a1.5 1.5 0 0 0-1.5 1.5v15A1.5 1.5 0 0 0 5 21h4M15 16.5l4.5-4.5L15 7.5M19.5 12H9"/>',
  'coffee': '<path d="M18 8h1a4 4 0 0 1 0 8h-1"/><path d="M2 8h16v9a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4V8z"/><path d="M6 1v3M10 1v3M14 1v3"/>',
  'eye': '<path d="M1.5 12S5.25 4.5 12 4.5 22.5 12 22.5 12 18.75 19.5 12 19.5 1.5 12 1.5 12z"/><circle cx="12" cy="12" r="3"/>',
  'eye-off': '<path d="M1.5 12S5.25 4.5 12 4.5 22.5 12 22.5 12 18.75 19.5 12 19.5 1.5 12 1.5 12z"/><circle cx="12" cy="12" r="3"/><path d="M3 3l18 18"/>',
  'camera': '<rect x="2.5" y="7" width="19" height="13.5" rx="2.5"/><circle cx="12" cy="13.5" r="3.6"/><path d="M8.5 7 10 4.3h4L15.5 7"/>',
  'star': '<path d="M12 3l2.6 5.3 5.9.9-4.3 4.2 1 5.9L12 16.5l-5.2 2.8 1-5.9L3.5 9.2l5.9-.9z" fill="currentColor"/>',
  'reorder': '<path d="M3.5 5h13M3.5 12h13M3.5 19h13"/><path d="m19 2 2.5 3L19 8M19 16l2.5 3-2.5 3"/>',
  'image-add': '<path d="M12 16V4M7 9l5-5 5 5M3 19h18"/>',
  'check': '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  'search': '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.8-3.8"/>',
  'refresh': '<path d="M20 11a8 8 0 1 0-2.3 6.3"/><path d="M20 4v7h-7"/>',
  'link': '<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"/>',
  'screenshot': '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><circle cx="12" cy="12" r="3"/>',
  'screenshot-long': '<path d="M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M12 7v10M9 14l3 3 3-3"/>',
  'pin': '<path d="M9 3h6l-1 6 3 3v2H7v-2l3-3-1-6z"/><path d="M12 14v7"/>',
  'user': '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  'palette': '<path d="M12 3a9 9 0 1 0 0 18c1.5 0 2-1 2-2s-.6-1.6-.6-2.5c0-1 .8-1.5 1.8-1.5H17a4 4 0 0 0 4-4c0-4.4-4-8-9-8z"/><circle cx="7.5" cy="11.5" r="1" fill="currentColor"/><circle cx="10" cy="7.5" r="1" fill="currentColor"/><circle cx="15" cy="7.5" r="1" fill="currentColor"/>',
  'bell': '<path d="M6 9a6 6 0 1 1 12 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9z"/><path d="M10 20a2.2 2.2 0 0 0 4 0"/>',
  'widget': '<rect x="3" y="3" width="8" height="8" rx="2"/><rect x="13" y="3" width="8" height="5" rx="2"/><rect x="13" y="10" width="8" height="11" rx="2"/><rect x="3" y="13" width="8" height="8" rx="2"/>',
  'power': '<path d="M12 3v9"/><path d="M6.3 6.8a8 8 0 1 0 11.4 0"/>',
  'phone': '<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/>',
  'monitor': '<rect x="2.5" y="3.5" width="19" height="13" rx="2"/><path d="M8 21h8M12 16.5V21"/>',
  'globe': '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  'arrow-right': '<path d="M5 12h14M13 6l6 6-6 6"/>',
  'arrow-left': '<path d="M19 12H5M11 6l-6 6 6 6"/>',
  'minimise': '<path d="M5 12h14"/>',
  'maximise': '<rect x="5" y="5" width="14" height="14" rx="1"/>',
  'restore': '<rect x="4.5" y="8" width="11.5" height="11.5" rx="1"/><path d="M8 8V4.5h11.5V16H16"/>',
  'lock': '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7.5a4 4 0 0 1 8 0V11"/>',
};

bool hasIcon(String name) => _paths.containsKey(name);

/// The SVG of one icon, in a colour: for places that need the picture itself (the tray icon).
String iconSvg(String name, {String colour = '#000000', double stroke = 1.8}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="$colour" stroke-width="$stroke" '
    'stroke-linecap="round" stroke-linejoin="round">${(_paths[name] ?? '').replaceAll('currentColor', colour)}</svg>';

class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 20, this.color, this.stroke = 1.8});

  final String name;
  final double size;
  final Color? color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    final hex = '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    return Opacity(
      opacity: c.a,
      child: SvgPicture.string(
        iconSvg(name, colour: hex, stroke: stroke),
        width: size,
        height: size,
        excludeFromSemantics: true,
      ),
    );
  }
}
