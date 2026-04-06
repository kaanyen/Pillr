import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Zendenta / Notion-style data table — white surface, grey header, row hover.
class PillrDataTable extends StatelessWidget {
  const PillrDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSelectAll,
    this.minWidth = 800,
  });

  final List<DataColumn2> columns;
  final List<DataRow> rows;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(bool? selected)? onSelectAll;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final styledColumns = columns
        .map(
          (c) => DataColumn2(
            label: DefaultTextStyle.merge(
              style: AppTypography.tableHeader,
              child: c.label,
            ),
            tooltip: c.tooltip,
            numeric: c.numeric,
            fixedWidth: c.fixedWidth,
            size: c.size,
            onSort: c.onSort,
          ),
        )
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.gray200),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: DataTable2(
        columnSpacing: AppSpacing.md,
        horizontalMargin: AppSpacing.md,
        minWidth: minWidth,
        headingRowHeight: 48,
        dataRowHeight: 56,
        headingRowDecoration: const BoxDecoration(
          color: AppColors.gray50,
          border: Border(
            bottom: BorderSide(color: AppColors.gray200),
          ),
        ),
        decoration: const BoxDecoration(),
        sortColumnIndex: sortColumnIndex,
        sortAscending: sortAscending,
        onSelectAll: onSelectAll,
        columns: styledColumns,
        rows: rows,
      ),
    );
  }
}
