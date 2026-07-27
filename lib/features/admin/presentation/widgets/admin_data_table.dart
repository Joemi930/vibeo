import 'package:flutter/material.dart';

/// Définition d'une colonne pour [AdminDataTable].
class ColumnDef {
  const ColumnDef({
    required this.label,
    this.flex = 1.0,
    this.alignment = Alignment.centerLeft,
    this.headerAlignment = Alignment.centerLeft,
  });

  /// Titre affiché dans l'en-tête.
  final String label;

  /// Largeur relative de la colonne (1.0 = largeur de référence).
  final double flex;

  /// Alignement du contenu des cellules de cette colonne.
  final Alignment alignment;

  /// Alignement du titre de la colonne (par défaut, identique à [alignment]).
  final Alignment headerAlignment;
}

/// Tableau d'administration responsive.
///
/// Au-dessus de 900 px : grille avec en-tête fixe. En dessous : liste de
/// [Card], une par ligne, chaque colonne devient un libellé + valeur.
///
/// Chaque élément de [rows] doit avoir autant de widgets que [columns].
class AdminDataTable extends StatelessWidget {
  const AdminDataTable({
    required this.columns,
    required this.rows,
    this.emptyMessage,
    this.onRowTap,
    this.selectedIndex,
    super.key,
  });

  final List<ColumnDef> columns;
  final List<List<Widget>> rows;
  final String? emptyMessage;
  final void Function(int index)? onRowTap;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _buildEmpty(context);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return _buildTable(context);
        }
        return _buildCards(context);
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              emptyMessage ?? 'Aucun élément.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = Theme.of(context);
    final totalFlex = columns.fold<double>(0, (s, c) => s + c.flex);
    final flexInts = columns.map((c) {
      return ((c.flex / totalFlex) * 1000).round();
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // En-tête
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              children: [
                for (var i = 0; i < columns.length; i++)
                  Expanded(
                    flex: flexInts[i],
                    child: Align(
                      alignment: columns[i].headerAlignment,
                      child: Text(
                        columns[i].label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.04,
                          fontFamily: 'Space Mono',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // Lignes
          for (var i = 0; i < rows.length; i++)
            _TableRow(
              columns: columns,
              flexInts: flexInts,
              cells: rows[i],
              isSelected: i == selectedIndex,
              onTap: onRowTap != null ? () => onRowTap!(i) : null,
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildCards(BuildContext context) {
    return ListView.builder(
      itemCount: rows.length,
      itemExtent: null,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final isSelected = index == selectedIndex;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: InkWell(
            onTap: onRowTap != null ? () => onRowTap!(index) : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < columns.length; j++) ...[
                    if (j > 0) const SizedBox(height: 10),
                    Text(
                      columns[j].label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Space Mono',
                        fontSize: 10,
                        letterSpacing: 0.04,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: rows[index][j],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.columns,
    required this.flexInts,
    required this.cells,
    required this.isSelected,
    required this.showDivider,
    this.onTap,
  });

  final List<ColumnDef> columns;
  final List<int> flexInts;
  final List<Widget> cells;
  final bool isSelected;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withAlpha(80)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            for (var i = 0; i < columns.length; i++)
              Expanded(
                flex: flexInts[i],
                child: Align(alignment: columns[i].alignment, child: cells[i]),
              ),
          ],
        ),
      ),
    );
  }
}
