import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../design/seline.dart';

/// Help, as on the canvas: a contents list beside short answers, with a
/// search that narrows the answers to the ones that mention what was typed.
///
/// Answers are written with **bold** for the words a person will see on
/// screen, so they can find the button being described.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _Topic {
  const _Topic(this.title, {this.paras = const [], this.steps = const [], this.note, this.table = false});

  final String title;
  final List<String> paras;
  final List<String> steps;
  final String? note;
  final bool table;

  String get text => [title, ...paras, ...steps, note ?? ''].join(' ').toLowerCase();
}

const _topics = [
  _Topic(
    'How Pillr works',
    paras: [
      'Every entry links a partner, an amount, an arm and a period. Staff record entries; a pastor approves them. Only approved giving counts toward totals, goals and the ranking, so the numbers on Overview are always numbers a pastor has checked.',
    ],
  ),
  _Topic(
    'Recording giving',
    steps: [
      "Choose **Record giving** on Overview, or on a partner's page.",
      'Find the partner by name, member ID or fellowship.',
      'Enter the amount, pick the arm, and check the date given.',
      "Save. A staff entry waits in the queue; a pastor's entry counts straight away.",
    ],
    paras: [
      'Bringing in a whole month at once? Use **Records › Bring in a sheet**. Pillr matches each row to a partner by member ID, including old IDs from before a merge.',
    ],
  ),
  _Topic(
    'Approving',
    paras: [
      'The queue lists what is waiting, oldest first. Select one or many and choose **Approve**. If something is wrong, **Decline** it with a reason; whoever recorded it sees your note and can fix and resend it.',
    ],
    note: 'Approved the wrong one? Open the entry and choose **Undo approval**. It goes back to the queue and the totals drop again.',
  ),
  _Topic(
    'Fixing a mistake',
    paras: [
      "**Waiting and sent-back entries** can be edited or deleted by a pastor, or by the staff member who recorded them. **Approved entries** can't be deleted; a pastor or admin can **void** one instead. A voided entry stays readable but counts toward nothing, and it can be restored from its page.",
    ],
  ),
  _Topic(
    'Duplicates and merging',
    paras: [
      'Every night Pillr compares partners by name, phone and member ID and lists possible duplicates under **Tools**. Making two records one person gives them a new member ID and keeps both old IDs, every phone and every email. If it was wrong, take a record back out by its old ID.',
    ],
  ),
  _Topic(
    'Goals',
    paras: [
      'A pastor sets a target for each arm in the active period. The bar fills as giving is approved, and the tick shows where the arm should be by today if giving keeps an even pace through the year.',
    ],
  ),
  _Topic('Who can do what', table: true),
  _Topic(
    'Periods and arms',
    paras: [
      'A **period** is the window giving is counted in, usually a year. Only one is active at a time, and every entry belongs to the period that was active when it was recorded. An **arm** is what the giving is toward, such as Tithe or Building. Your church turns on the arms it uses in Configuration.',
    ],
  ),
];

const _rights = [
  ('Record giving', 'Counts straight away', 'Waits for a pastor', 'No'),
  ('Approve, decline, void', 'Yes', 'Voids a duplicate from Tools', 'Voids and restores only'),
  ('Edit a partner', 'Yes', 'Yes, except closing a partner', 'No'),
  ('Periods, arms, people', 'Yes', 'No', 'Yes'),
];

class _HelpScreenState extends State<HelpScreen> {
  final _search = TextEditingController();
  final _keys = [for (final _ in _topics) GlobalKey()];
  int _at = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _at = i);
    final ctx = _keys[i].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (var i = 0; i < _topics.length; i++)
        if (q.isEmpty || _topics[i].text.contains(q) || (_topics[i].table && 'pastor staff admin'.contains(q))) i,
    ];

    final contents = SelCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _topics.length; i++)
            Material(
              color: _at == i ? Sel.skyTint : Colors.transparent,
              borderRadius: BorderRadius.circular(SelRadius.pill),
              child: InkWell(
                borderRadius: BorderRadius.circular(SelRadius.pill),
                onTap: () => _go(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    _topics[i].title,
                    style: SelType.bodySm.copyWith(
                      color: _at == i ? Sel.ink : Sel.warm,
                      fontWeight: _at == i ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final body = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 740),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Help', style: SelType.title),
          const SizedBox(height: SelSpace.x2),
          Text(
            "Short answers about recording and approving giving. If something here doesn't match what you see, ask your pastor.",
            style: SelType.body.copyWith(color: Sel.warm, fontSize: 16),
          ),
          const SizedBox(height: SelSpace.x4),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 480,
              child: SelField(
                controller: _search,
                hint: 'Search help, for example “send back”',
                prefixIcon: LucideIcons.search,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(height: SelSpace.x4),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SelSpace.x6),
              child: Text('Nothing in Help mentions “${_search.text.trim()}”.', style: SelType.bodyMuted),
            ),
          for (final i in shown) ...[
            const Divider(height: 1, color: Sel.border),
            Padding(
              key: _keys[i],
              padding: const EdgeInsets.symmetric(vertical: SelSpace.x6),
              child: _TopicView(topic: _topics[i]),
            ),
          ],
        ],
      ),
    );

    return SelPageBody(
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 860
              ? body
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 220, child: contents),
                    const SizedBox(width: SelSpace.x8),
                    Expanded(
                      child: Align(alignment: Alignment.topLeft, child: body),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TopicView extends StatelessWidget {
  const _TopicView({required this.topic});

  final _Topic topic;

  @override
  Widget build(BuildContext context) {
    final prose = SelType.body.copyWith(color: Sel.text, fontSize: 16, height: 1.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(topic.title, style: SelType.subtitle.copyWith(fontSize: 21)),
        const SizedBox(height: SelSpace.x3),
        for (var n = 0; n < topic.steps.length; n++)
          Padding(
            padding: const EdgeInsets.only(left: SelSpace.x2, bottom: SelSpace.x2),
            child: _Rich('${n + 1}.  ${topic.steps[n]}', style: prose),
          ),
        for (final p in topic.paras)
          Padding(
            padding: const EdgeInsets.only(bottom: SelSpace.x2),
            child: _Rich(p, style: prose),
          ),
        if (topic.note != null)
          Container(
            margin: const EdgeInsets.only(top: SelSpace.x2),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Sel.skyTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _Rich(topic.note!, style: SelType.bodySm.copyWith(color: Sel.ink, height: 1.6)),
          ),
        if (topic.table) const _Rights(),
      ],
    );
  }
}

class _Rights extends StatelessWidget {
  const _Rights();

  @override
  Widget build(BuildContext context) {
    Widget cell(String t, {bool head = false, bool label = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        t,
        style: head
            ? SelType.small
            : SelType.bodySm.copyWith(
                color: Sel.text,
                fontWeight: label ? FontWeight.w700 : FontWeight.w400,
              ),
      ),
    );
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1)},
      border: const TableBorder(horizontalInside: BorderSide(color: Sel.rowLine)),
      children: [
        TableRow(children: [cell('', head: true), cell('Pastor', head: true), cell('Staff', head: true), cell('Admin', head: true)]),
        for (final r in _rights)
          TableRow(children: [cell(r.$1, label: true), cell(r.$2), cell(r.$3), cell(r.$4)]),
      ],
    );
  }
}

/// Text with **bold** runs.
class _Rich extends StatelessWidget {
  const _Rich(this.source, {required this.style});

  final String source;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final parts = source.split('**');
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700, color: Sel.ink) : null,
            ),
        ],
      ),
    );
  }
}
