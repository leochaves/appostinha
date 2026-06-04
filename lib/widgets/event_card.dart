import 'package:flutter/material.dart';
import '../models/event.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _primary = Color(0xFF00C851);
const _gold = Color(0xFFD4A017);
const _border = Color(0xFF30363D);
const _muted = Color(0xFF8B949E);

class EventCard extends StatelessWidget {
  final Event event;
  final String breadcrumb;
  final VoidCallback onTap;
  final bool voted;
  final String? votedOptionId;
  final VoidCallback? onBreadcrumbTap;

  const EventCard({
    super.key,
    required this.event,
    required this.breadcrumb,
    required this.onTap,
    this.voted = false,
    this.votedOptionId,
    this.onBreadcrumbTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = event.totalPredictions;
    final isResolved = event.status == 'resolved';
    final opts = [...event.options]
      ..sort((a, b) => b.predictionCount.compareTo(a.predictionCount));

    final borderColor = isResolved
        ? _gold.withValues(alpha: 0.3)
        : event.isOpen
            ? _primary.withValues(alpha: 0.25)
            : _border;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // breadcrumb + status dot + badge votei
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: isResolved ? _gold : event.isOpen ? _primary : _muted,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onBreadcrumbTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          breadcrumb.toUpperCase(),
                          style: TextStyle(
                              fontSize: 8, fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: onBreadcrumbTap != null ? _primary : _muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onBreadcrumbTap != null) ...[
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_forward_ios, size: 7, color: _primary.withValues(alpha: 0.7)),
                      ],
                    ],
                  ),
                ),
              ),
              if (voted) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_circle, color: _primary, size: 13),
              ],
            ]),
            const SizedBox(height: 6),
            Text(
              event.title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // opções com barra de progresso
            ...opts.take(4).toList().asMap().entries.map((entry) {
              final isWinner = event.winningOptionId == opts[entry.key].id;
              final o = entry.value;
              final isMyVote = votedOptionId == o.id;
              final pct = total > 0
                  ? (o.predictionCount / total * 100).round()
                  : 0;
              final leadPct = total > 0
                  ? (opts.first.predictionCount / total * 100).round()
                  : 0;
              final isLeading = pct > 0 && pct == leadPct;
              final fillColor = isWinner
                  ? _gold.withValues(alpha: 0.25)
                  : isMyVote
                      ? _primary.withValues(alpha: 0.3)
                      : isLeading
                          ? _primary.withValues(alpha: 0.22)
                          : _muted.withValues(alpha: 0.12);
              final textColor = isWinner ? _gold : isMyVote || isLeading ? _primary : _muted;

              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                height: 26,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _border.withValues(alpha: 0.7)),
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(children: [
                  if (total > 0)
                    FractionallySizedBox(
                      widthFactor: (pct / 100).clamp(0.0, 1.0),
                      child: Container(color: fillColor),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isMyVote) ...[
                          const Icon(Icons.how_to_vote, color: _primary, size: 11),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(o.title,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isMyVote ? FontWeight.w800 : FontWeight.w600,
                                  color: isMyVote ? _primary : Colors.white),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          total > 0 ? '$pct%' : '—',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: textColor),
                        ),
                      ],
                    ),
                  ),
                ]),
              );
            }),
            if (opts.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('+${opts.length - 4} mais',
                    style: const TextStyle(fontSize: 9, color: _muted)),
              ),
            const SizedBox(height: 8),
            // rodapé
            _buildFooter(opts),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(List opts) {
    final isResolved = event.status == 'resolved';
    final votedOption = votedOptionId != null
        ? event.options.where((o) => o.id == votedOptionId).firstOrNull
        : null;

    if (votedOption != null && !isResolved) {
      // já votou e ainda não resolvido
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: _primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: _primary, size: 11),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                votedOption.title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900,
                    letterSpacing: 0.8, color: _primary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // resolvido + usuário votou → mostrar acerto ou erro
    if (isResolved && votedOptionId != null) {
      final hit = votedOptionId == event.winningOptionId;
      final color = hit ? _primary : Colors.red;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hit ? Icons.check_circle : Icons.cancel, color: color, size: 12),
              const SizedBox(width: 5),
              Text(
                hit ? 'ACERTEI' : 'ERREI',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900,
                    letterSpacing: 1, color: color),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isResolved
            ? _gold.withValues(alpha: 0.08)
            : event.isOpen
                ? _primary.withValues(alpha: 0.12)
                : _muted.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isResolved
              ? _gold.withValues(alpha: 0.3)
              : event.isOpen
                  ? _primary.withValues(alpha: 0.3)
                  : _border,
        ),
      ),
      child: Center(
        child: Text(
          isResolved ? 'RESOLVIDO' : event.isOpen ? 'VOTAR' : 'FECHADO',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: isResolved ? _gold : event.isOpen ? _primary : _muted),
        ),
      ),
    );
  }
}
