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
  final List<String> votedOptionIds;
  final VoidCallback? onBreadcrumbTap;
  final bool isCoinMode;
  final String coinName;

  const EventCard({
    super.key,
    required this.event,
    required this.breadcrumb,
    required this.onTap,
    this.voted = false,
    this.votedOptionIds = const [],
    this.onBreadcrumbTap,
    this.isCoinMode = false,
    this.coinName = 'Ficha',
  });

  @override
  Widget build(BuildContext context) {
    final total = event.totalPredictions;
    final totalCoinPool = event.options.fold(0, (s, o) => s + o.coinPool);
    final isResolved = event.status == 'resolved';
    final opts = [...event.options]
      ..sort((a, b) => isCoinMode
          ? b.coinPool.compareTo(a.coinPool)
          : b.predictionCount.compareTo(a.predictionCount));

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
              final isMyVote = votedOptionIds.contains(o.id);

              // valores dependem do modo
              final double fillFactor;
              final String rightLabel;
              final bool isLeading;
              if (isCoinMode) {
                fillFactor = totalCoinPool > 0
                    ? (o.coinPool / totalCoinPool).clamp(0.0, 1.0)
                    : 0.0;
                final odd = totalCoinPool > 0 && o.coinPool > 0
                    ? totalCoinPool / o.coinPool
                    : 0.0;
                rightLabel = odd > 0
                    ? (odd == odd.truncateToDouble()
                        ? '${odd.toInt()}x'
                        : '${odd.toStringAsFixed(2)}x')
                    : '—';
                isLeading = entry.key == 0 && o.coinPool > 0;
              } else {
                final pct = total > 0
                    ? (o.predictionCount / total * 100).round()
                    : 0;
                final leadPct = total > 0
                    ? (opts.first.predictionCount / total * 100).round()
                    : 0;
                fillFactor = (pct / 100).clamp(0.0, 1.0);
                rightLabel = total > 0 ? '$pct%' : '—';
                isLeading = pct > 0 && pct == leadPct;
              }

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
                  if (fillFactor > 0)
                    FractionallySizedBox(
                      widthFactor: fillFactor,
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
                          rightLabel,
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
    final isClosed   = !event.isOpen && !isResolved;
    final votedOptions = event.options.where((o) => votedOptionIds.contains(o.id)).toList();
    final hasVote = votedOptions.isNotEmpty;

    // badge de estado do evento
    final Widget stateBadge;
    if (isResolved) {
      stateBadge = _pill(color: _gold,          icon: Icons.emoji_events_outlined, label: 'ENCERRADO');
    } else if (isClosed) {
      stateBadge = _pill(color: Colors.orange,  icon: Icons.lock_outline,          label: 'FECHADO');
    } else {
      stateBadge = _pill(color: _primary,       icon: Icons.radio_button_checked,  label: 'ABERTO');
    }

    // badge de participação do usuário
    final Widget userBadge;
    if (isResolved && hasVote) {
      final hit = votedOptionIds.contains(event.winningOptionId);
      userBadge = _pill(
        color: hit ? _primary : Colors.red,
        icon:  hit ? Icons.check_circle : Icons.cancel,
        label: hit ? 'ACERTEI' : 'ERREI',
      );
    } else if (hasVote) {
      final label = votedOptions.map((o) => o.title.toUpperCase()).join(' · ');
      userBadge = _pill(color: _primary, icon: Icons.how_to_vote, label: label);
    } else if (event.isOpen) {
      userBadge = _pill(color: _primary, icon: null, label: 'VOTAR', trailingArrow: true);
    } else {
      userBadge = _pill(color: _muted, icon: Icons.remove_circle_outline, label: 'SEM VOTO');
    }

    return Row(
      children: [
        stateBadge,
        const SizedBox(width: 6),
        Expanded(child: userBadge),
      ],
    );
  }

  Widget _pill({
    required Color color,
    required String label,
    IconData? icon,
    bool trailingArrow = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 11),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w900,
                  letterSpacing: 0.8, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailingArrow) ...[
            const SizedBox(width: 3),
            Icon(Icons.arrow_forward, color: color, size: 10),
          ],
        ],
      ),
    );
  }
}
